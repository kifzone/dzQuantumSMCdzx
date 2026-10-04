"""Source-contract regressions for the SMF layer.

These checks do not replace MetaEditor compilation or the in-indicator
SMF_SelfTest; they protect the causal wiring and high-risk contracts in CI.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path


SOURCE = (Path(__file__).resolve().parents[1] / "KLJ.mq5").read_text(encoding="utf-8")


def function_body(name: str) -> str:
    pattern = re.compile(r"(?m)^[A-Za-z_]\w*\s+" + re.escape(name) + r"\s*\(")
    for match in pattern.finditer(SOURCE):
        brace = SOURCE.find("{", match.end())
        semi = SOURCE.find(";", match.end())
        if brace < 0 or (semi >= 0 and semi < brace):
            continue
        depth = 0
        state = "code"
        i = brace
        while i < len(SOURCE):
            c = SOURCE[i]
            n = SOURCE[i + 1] if i + 1 < len(SOURCE) else ""
            if state == "code":
                if c == "/" and n == "/":
                    state = "line"
                    i += 2
                    continue
                if c == "/" and n == "*":
                    state = "block"
                    i += 2
                    continue
                if c == '"':
                    state = "string"
                    i += 1
                    continue
                if c == "'":
                    state = "char"
                    i += 1
                    continue
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        return SOURCE[brace : i + 1]
            elif state == "line":
                if c == "\n":
                    state = "code"
            elif state == "block":
                if c == "*" and n == "/":
                    state = "code"
                    i += 2
                    continue
            elif state in ("string", "char"):
                if c == "\\":
                    i += 2
                    continue
                if (state == "string" and c == '"') or (state == "char" and c == "'"):
                    state = "code"
            i += 1
    raise AssertionError(f"function definition not found: {name}")


class SmartMoneyEvidenceContracts(unittest.TestCase):
    def test_closed_bar_snapshot_precedes_scoring(self) -> None:
        oncalc = function_body("OnCalculate")
        ordered = [
            "FillEMAAndVWAP(",
            "MVP_EnsureDecisionSnapshot(",
            "SMF_UpdateSnapshot(",
            "CalculateAITradeSetup(",
            "SMF_RefreshDecisionView(",
        ]
        offsets = [oncalc.index(token) for token in ordered]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("int closed=rates_total-2", oncalc)
        self.assertIn("g_buf_t[closed+1]", function_body("SMF_UpdateSnapshot"))

    def test_profile_asof_builder_cannot_read_future_bars(self) -> None:
        builder = function_body("SMF_BuildProfileAsOf")
        self.assertIn("to<=asof", builder)
        self.assertIn("MVP_BuildBars(p,from,to", builder)
        self.assertIn('tag="VISIBLE-ROLL"', builder)
        self.assertNotIn("MVP_ViewSignature", builder)
        self.assertIn("g_atr_buf[closed]", function_body("MVP_BaseRow"))

    def test_existing_mvp_and_vwap_are_reused(self) -> None:
        builder = function_body("SMF_BuildProfileAsOf")
        snapshot = function_body("SMF_UpdateSnapshot")
        self.assertIn("MVP_FindPeriod", builder)
        self.assertIn("MVP_CollectSessionRuns", builder)
        self.assertIn("MVP_BuildBars", builder)
        self.assertIn("BufVWAP[closed]", snapshot)
        self.assertNotIn("ArrayResize(g_buf_", snapshot)

    def test_every_source_and_event_has_a_decision_time_check(self) -> None:
        self.assertIn("availability_time<=decision_time", function_body("SMF_CausalTimeValid"))
        self.assertIn("SMF_ProfileAsOfValid", function_body("SMF_EvaluateCandidate"))
        self.assertIn("SMF_AddEventProvenance", function_body("SMF_EvaluateCandidate"))
        facts_check = function_body("SMF_FactsCausalValid")
        self.assertIn("facts.availability_time>facts.decision_time", facts_check)
        self.assertIn("facts.volume_available_time>facts.decision_time", facts_check)

    def test_no_trade_authority_is_added_to_smf_functions(self) -> None:
        for name in ("SMF_EvaluateCandidate", "SMF_RefreshDecisionView", "SMF_ClassifyStatus"):
            body = function_body(name)
            self.assertNotIn("TryTransitionSignalState", body)
            self.assertNotIn("EntryMark", body)
        self.assertIn("EXECUTION READY (CORE AUTHORITY)", function_body("SMF_ClassifyStatus"))
        self.assertIn("authority_ok && structure_ok && zone_ok && retest_ok && rr_ok", function_body("SMF_ClassifyStatus"))

    def test_scores_refine_existing_slots_and_suppress_same_bar_duplicates(self) -> None:
        source = function_body("CalculateAITradeSetup")
        self.assertIn("0.85*base_liquidity+0.15*g_smf.profile_integrated_score", source)
        self.assertIn("0.85*base_htf+0.15*g_smf.vwap_score", source)
        self.assertIn("value-area/volume overlap: LIQUIDITY once; flow only blended on rejection", function_body("SMF_EvaluateCandidate"))
        self.assertIn("g_smf.integrate_vwap=false", function_body("SMF_EvaluateCandidate"))
        self.assertIn("adjusted=MathMax(0,score-10)", function_body("SMF_AdjustCandleScore"))

    def test_hvn_lvn_survive_snapshot_and_are_location_only(self) -> None:
        snapshot = function_body("SMF_UpdateSnapshot")
        candidate = function_body("SMF_EvaluateCandidate")
        facts = function_body("SMF_CopyToFacts")
        scorer = function_body("SMF_ProfileScore")
        self.assertIn("profile.hvn_px[i]", snapshot)
        self.assertIn("profile.lvn_px[i]", snapshot)
        self.assertIn("g_smf.profile_hvn[i]", candidate)
        self.assertIn("g_smf.profile_lvn[i]", candidate)
        self.assertIn("src.profile_hvn[i]", facts)
        self.assertIn("src.profile_lvn[i]", facts)
        self.assertIn("LOCATION (NON-DIRECTIONAL)", scorer)
        self.assertIn("touch=(boundary_touch || node_touch)", scorer)
        self.assertIn("T13 HVN/LVN preserve location without directional score", function_body("SMF_SelfTest"))
        self.assertIn("profile_boundary_touch &&", candidate)

    def test_raw_volume_expansion_credit_is_replaced_even_without_matching_flow(self) -> None:
        score_path = function_body("CalculateSetupQualityScore")
        quality = function_body("ComputeEntryQuality")
        self.assertIn("if(InpUseSmartMoneyVolumeEvidence)", score_path)
        self.assertIn("has_smf && smf_fact.causal_ok", quality)
        self.assertIn("smf_same_direction && smf_fact.integrate_flow", quality)
        self.assertIn("adjusted=MathMax(0,score-10)", function_body("SMF_AdjustCandleScore"))

    def test_proxy_is_never_described_as_true_delta(self) -> None:
        disclosure = function_body("SMF_OrderFlowDisclosure")
        self.assertIn("VOLUME PROXY ONLY", disclosure)
        self.assertIn("TRUE BID/ASK", disclosure)
        self.assertIn("UNAVAILABLE", disclosure)
        analyzer = function_body("AnalyzeCandleIntelligence")
        self.assertIn("prior closed-bar baseline", SOURCE)
        self.assertIn("not aggressor-side trades", analyzer)
        self.assertIn("not proof of", analyzer)
        self.assertIn("institutional absorption or order flow", analyzer)

    def test_immutable_facts_propagate_and_are_compared(self) -> None:
        for field in ("g_trade_setup.smf", "g_active_setup.smf", "g_history_setups[idx].smf", "g_confirmed_signal_journal[n].smf"):
            self.assertIn(field, SOURCE)
        self.assertIn("SMF_FactsEqual(g_confirmed_signal_journal[i].smf,setup.smf)", SOURCE)
        self.assertIn("SMF_FactsEqual(g_history_setups[i].smf,setup.smf)", SOURCE)
        self.assertIn("SMF_FactsDigest(g_confirmed_signal_journal[i].smf)", function_body("SMF_StateDigestString"))

    def test_historical_replay_rebuild_is_bounded_and_deterministic(self) -> None:
        audit = function_body("SMF_ReplayAuditRecent")
        self.assertIn("closed-sample*stride", audit)
        self.assertIn("SMF_BuildProfileAsOf(b", audit)
        self.assertIn("deterministic_checked", audit)
        self.assertIn("SMF_ProfileAsOfValid(replay.bar_end,b,available,decision)", audit)
        self.assertIn("SMF_AuditReplayRecord", audit)

    def test_required_deterministic_mql_scenarios_are_registered(self) -> None:
        test = function_body("SMF_SelfTest")
        for marker in (
            "T1 VAL sweep/reclaim BUY",
            "T2 VAH sweep/rejection SELL",
            "T3 VAL touch without rejection",
            "T4 VWAP reclaim without structure is WATCH",
            "T5 range-bound volume spike is not displacement",
            "T6 absorption/exhaustion remains a proxy",
            "T7 historical profile replay rejects future availability",
            "T8 forming candle cannot confirm",
            "T9 unavailable true order flow is explicitly disclosed",
            "T10 conflicting evidence stays contextual WATCH",
            "T11 execution-ready mirrors all core gates",
            "T12 flow score requires expansion beyond legacy threshold",
            "T13 HVN/LVN preserve location without directional score",
            "T14 synthetic historical profile replay ignores future-bar mutations",
            "T15 raw volume bonus is replaced, not stacked",
            "T7b immutable facts retain only available sources",
            "T7c immutable facts reject future volume availability",
        ):
            self.assertIn(marker, test)


if __name__ == "__main__":
    unittest.main()
