# Smart-Money Volume / Profile / VWAP Evidence Layer

**Implementation target:** `KLJ.mq5`  
**Build label:** v6.6.0  
**Status:** source integration and static regression checks are complete; MetaTrader compilation, in-indicator runtime tests, and an observed before/after performance run remain outstanding.

## 1. Scope and architecture

The new layer is an evidence consumer inside the existing indicator. It does not create setup state, replace a signal engine, submit orders, or own entry authority.

The closed-bar path is:

1. `OnCalculate()` normalizes the chart data into the existing chronological `g_buf_*` arrays and calls the existing `FillEMAAndVWAP()`.
2. Before candidate scoring, `MVP_EnsureDecisionSnapshot()` prepares/reuses the existing Master Volume Profile, then `SMF_UpdateSnapshot()` builds the closed-bar evidence snapshot. For non-visible modes it reuses the active MVP snapshot when valid; visible mode deliberately rebuilds a deterministic rolling as-of profile rather than trusting the mutable chart viewport.
3. `SMF_EvaluateCandidate()` evaluates that snapshot against the direction and causal events already selected by the core engine. It reuses the existing `MVP_BuildBars()` profile math and `BufVWAP[]`; it does not add another session, profile, or VWAP calculator.
4. Existing candidate-quality and entry-quality code consumes bounded subscore refinements. `SMF_RefreshDecisionView()` updates explanatory dashboard state after lifecycle ownership is settled.
5. At setup creation, evidence is copied into immutable setup facts and carried through the active setup, confirmed journal, and historical setup records. Later outcome updates do not rewrite those facts.

The evidence snapshot retains POC, VAH, VAL, up to four existing HVN and LVN prices, the profile fingerprint/source, VWAP value/source, total-volume ratio/source, event IDs, score-cluster decisions, and each source's availability time. HVN/LVN locations are now carried through scoring and immutable facts; touching one is explicitly **location context only**, with no directional score by itself.

## 2. Volume and order-flow disclosure

This indicator does **not** have reliable aggressor-side trades, bid/ask delta, footprint, or DOM data. The dashboard and evidence provenance therefore say **VOLUME PROXY** and **TRUE BID/ASK / AGGRESSOR FLOW: UNAVAILABLE**.

The available volume is terminal-provided real total volume when present, otherwise tick volume; a baseline may be mixed across real-volume and tick-volume bars and is labelled as such. `AnalyzeCandleIntelligence()` compares the closed bar with up to 20 prior closed bars and marks expansion at a ratio of at least 1.30. This is not signed order flow.

The existing MVP buy/sell split is also a proxy: it allocates each bar's volume using the close's location within that bar's range. It is not exchange bid-versus-ask volume. Likewise, the legacy compact-body/high-volume condition is called **effort/result proxy**, not institutional absorption. No display or score should be interpreted as true delta, true absorption, or proof of institutional activity.

## 3. Evidence rules and score integration

All numbers below are deterministic heuristic evidence scores, **not probabilities, win rates, or independent votes**.

### Profile / value area

`SMF_ProfileScore()` scores the candidate direction against the already-built profile:

| Closed-bar response | BUY-context score | SELL-context score |
|---|---:|---:|
| VAL sweep/reclaim or VAH sweep/rejection with the required close location | 95 | 95 |
| VAL/VAH touch without rejection | 42 | 42 |
| Close accepted beyond the opposing value boundary | 20 | 20 |
| Acceptance beyond the direction's value boundary | 76 | 76 |
| In-value side of POC | 64 | 64 |
| Other in-value/POC rotation context | 52 | 52 |
| Unavailable/neutral | 50 | 50 |

The response string distinguishes the actual BUY-side VAL response from the SELL-side VAH response and reports the boundary touched. HVN/LVN touches append a price-labelled `LOCATION (NON-DIRECTIONAL)` annotation; they do not change the score or by themselves create a rejection. A VAH/VAL/POC touch is tracked separately from an HVN/LVN touch so a neutral node does not accidentally suppress an unrelated flow subscore.

### VWAP

The layer reads the existing closed-bar `BufVWAP[]`. Candidate-relative VWAP evidence is scored as follows: reclaim 95; touch/rejection 88; three-bar acceptance on the candidate side 74; aligned close 62; close on the wrong side 25. Missing current/previous VWAP values make this evidence unavailable. VWAP context is not an entry trigger.

### Total-volume proxy

The directional volume proxy is zero unless total volume expands, the closed candle already confirms the candidate direction, and the direction-adjusted close location is above 0.50. Its bounded score is:

```text
v = clamp((volume_ratio - 1.30) / (2.50 - 1.30) * 100, 0, 100)
d = clamp((directional_close_location - 0.50) / 0.40 * 100, 0, 100)
flow_score = round(sqrt(v * d))
```

At the minimum 1.30 ratio the proxy score is zero; strong expansion and a directional close can approach 100. This is still only a candle/volume-total proxy.

### Existing score slots; no new entry authority

- The candle-intelligence composite remains the existing 0–100 composite (displacement +25, rejection +20, engulfing +20, liquidity rejection +15, raw expansion +10, follow-through +10, capped at 100). When SMF is enabled and expansion is present, `SMF_AdjustCandleScore()` **removes the legacy directionless +10 first** and replaces it with up to 10 scaled points only when the flow proxy is eligible and integrated. If direction does not match or a same-bar cluster suppresses flow, that raw spike credit is not retained.
- The existing liquidity/context slots are refined, not supplemented with a new outer factor: `0.85 * existing + 0.15 * SMF subscore`. The existing top-level score weights, gate thresholds, knapsack factors, and evidence-independence model are not expanded by an SMF vote.
- For a same-bar value-boundary rejection plus directional volume, the two are kept in the existing liquidity slot: `profile_integrated_score = 0.70 * profile_score + 0.30 * flow_score`; the separate flow slot is suppressed. A same-bar value-area/VWAP event suppresses the duplicate VWAP subscore. A same-bar VWAP/volume overlap retains the VWAP context and suppresses the separate flow subscore. HVN/LVN-only location does not trigger this boundary cluster rule.
- In `ComputeEntryQuality()`, the existing raw volume points are replaced by the causally valid, same-direction flow subscore only when appropriate. If the immutable setup facts mark the same event as already clustered in profile/VWAP, the separate volume points are zero. The existing 70/30 structural-versus-soft quality blend is unchanged.
- Conflicting profile/VWAP context or a supportive profile/VWAP opposed by HTF context disables SMF profile/VWAP score integration and is disclosed as `CONFLICT / WATCH`. This conflict is not silently averaged into the score. It is not a new core veto: the original entry authority remains the only trade authority.

The 85/15 and 70/30 figures are explicit bounded design blends, not empirically fitted parameters. They should be assessed on the project’s tester workflow before any claim of predictive improvement.

## 4. Precise status and BUY/SELL/WATCH/NO TRADE semantics

`SMF_ClassifyStatus()` applies these conditions in order:

1. Failed availability/replay validation → `CAUSALITY FAIL`.
2. Forming candle → `WATCH / WAIT CLOSED BAR`.
3. Conflicting context → `CONFLICT / WATCH`.
4. Core authority **and** structure, causal zone, later retest, and RR all pass → `EXECUTION READY (CORE AUTHORITY)` (a mirror of core state, not an SMF authorization).
5. Structure and causal zone exist but the retest/core gates are incomplete → `WAIT RETEST / CORE GATES`.
6. Profile rejection/location, directional volume proxy, VWAP alignment, and displacement all agree → `STRONG REACTION`.
7. A confirmed profile rejection at location → `REACTION`.
8. Location, flow, or VWAP context without the stronger sequence → `WATCH`.
9. No valid evidence → `NO DATA / WATCH`; valid data with no contextual response → `NO TRADE`.

The neutral dashboard view is deliberately non-directional: it may report a VAL/VAH reaction, VWAP location, HVN/LVN location, and missing structure/zone reasons, but it does not infer BUY or SELL from confluence.

**BUY/SELL are still emitted only by the existing core lifecycle/entry-authority path.** SMF cannot make a VAH/VAL/POC/VWAP touch, an HVN/LVN touch, or volume expansion satisfy the existing causal sweep → displacement → MSS/BOS/structure → causal zone → retest → RR/geometry → invalidation/lifecycle/execution checks. A `REACTION`, `STRONG REACTION`, `WATCH`, or `NO TRADE` from this evidence layer is not a core order decision. With the feature enabled, a failed causal/replay audit is fail-closed before candidate scoring; a mere context conflict suppresses the SMF score contributions but does not replace core gates.

## 5. Causality, replay, and provenance audit

- The decision bar is `rates_total - 2`; the forming bar is excluded. Evidence uses closed OHLC/volume, closed VWAP, and existing causal events only.
- The decision boundary is recorded as the next bar's timestamp. Profile bars must end no later than the decision bar, profile end time must not exceed that closed candle, and every recorded profile/VWAP/volume/event availability time must be `<= decision_time`.
- Historical profile construction is explicitly as-of. `SMF_BuildProfileAsOf(asof, ...)` selects the existing MVP period/session/window and calls `MVP_BuildBars()` only through `asof`; its deterministic visible-mode context uses a rolling bar window rather than the mutable chart viewport. `MVP_BaseRow()` uses the ATR at the profile's own as-of bar, not today's global ATR.
- The current replay check validates the current snapshot against a timestamp-keyed, idempotently updated ring (capacity 256) and its fingerprint; it does not rebuild a profile per candidate. On the default schedule, every 50 closed bars the bounded replay audit samples up to four historical decisions and rebuilds them as-of using the existing MVP builder. It checks timestamps, source/config, POC/VAH/VAL, row size, nodes via fingerprint, and repeat-build determinism. The initial attach can reconstruct selected historical samples when the ring has no records.
- Immutable setup facts carry the maximum source availability time and are revalidated before journal/history persistence. Their equality/digest checks include the profile fingerprint and HVN/LVN values, so later outcome writes cannot silently mutate entry-time evidence.
- Provenance includes profile mode/source and levels, VWAP source/value/response, volume source/ratio, relevant causal event IDs and availability, conflict/missing reasons, integration-cluster decisions, and replay status.

This is a bounded replay audit, not a full historical rebuild on every tick. As with other terminal-sourced indicators, corrected broker history can change a later rebuild; the audit is intended to surface that through a failed fingerprint/determinism check, not to claim immutable market data.

## 6. Deterministic regression coverage

The in-indicator `SMF_SelfTest()` now registers 17 deterministic checks, including VAL/VAH sweep reactions, no-rejection, VWAP context without structure, range-bound volume spike, effort/result proxy disclosure, availability rejection, forming-candle exclusion, unavailable true order flow, conflict/watch behavior, core-authority mirroring, HVN/LVN neutral scoring, synthetic as-of replay under future-bar mutation, and replacement (not stacking) of the legacy raw volume bonus. The existing MVP self-test remains in place.

`tests/test_smf_source_contract.py` adds 12 Python source-contract regressions for closed-bar ordering, as-of profile range, MVP/VWAP reuse, availability checks, immutable facts, score-overlap suppression, HVN/LVN propagation, proxy wording, and the registered scenarios. Run with:

```bash
python3 -m unittest discover -s tests -v
```

**Observed in this workspace:** all 12 Python tests passed; CRLF-aware `git diff --check` passed; a lexical delimiter and changed-function definition sanity check passed. These are not MetaTrader compile/runtime results. The 17 MQL self-tests have been added but have not been run here.

## 7. Performance comparison (static design comparison; runtime numbers pending)

| Path | SMF disabled | SMF enabled |
|---|---|---|
| Per-tick work | No SMF snapshot/scoring calls; legacy scores remain | Snapshot is keyed to the latest closed-bar timestamp and returns early on ordinary same-bar recalculations |
| Profile work | Existing MVP behavior only | Reuses the active `g_mvp` snapshot for eligible non-visible modes; visible mode uses the deterministic rolling as-of builder instead of viewport state (also used in non-visual tester paths where MVP drawing is skipped) |
| Evidence work | None | One candle-volume baseline scan of at most 20 prior bars, existing VWAP reads, fixed-size profile/node copies, and bounded event/node scoring per closed decision |
| Replay work | None | Current timestamp/ring/fingerprint check plus up to four sampled as-of rebuilds every 50 closed bars by default; no full-history per-tick rebuild |
| Chart objects | Existing indicator objects | Same existing dashboard/panel path; evidence is text/context, not a new per-bar object family |

No before/after MetaTrader timing was available in this environment, so no measured speedup or latency penalty is claimed. The code exposes the existing whole-`OnCalculate` EMA (`g_perf_calc_us`) plus SMF profile-build/cache-hit and snapshot timing counters in the expanded dashboard. A valid comparison should run identical symbol, timeframe, history, tester mode, visual mode, and draw settings with `InpUseSmartMoneyVolumeEvidence=false` and `true`; record the tester's total elapsed time and the same-period `g_perf_calc_us` distribution, then report the SMF build/cache/audit counters. The visible-profile mode and first attach should be measured separately from steady-state closed-bar operation.

## 8. Realistic examples

These examples illustrate evidence/status behavior; they are not trade recommendations.

### A. VAL sweep/reclaim, possible BUY context

Assume a closed candle wicks below VAL, closes back above it with close location 0.78, and total-volume ratio is 1.85. The profile response is `VAL SWEEP / RECLAIM` (95). If the existing candle confirms BUY, the flow proxy is approximately 57 (`v≈46`, `d=70`, `sqrt(v*d)≈57`). On a same-bar profile rejection, the liquidity subscore is approximately `0.70*95 + 0.30*57 = 83.6`; the separate flow slot is suppressed. With a base liquidity score of 70, the existing 85/15 refinement would be about 72.0. Without the required causal structure/zone/retest/RR/authority, this remains reaction/watch context—not BUY.

### B. VAH sweep/rejection, possible SELL context

Assume a high above VAH, a closed bearish rejection with close location 0.22, and total-volume ratio 2.00. Direction-adjusted close location is 0.78, giving flow proxy about 64; profile rejection remains 95; the single clustered liquidity subscore is about 85.7. If MSS/zone/retest/RR are absent, this is at most a SELL-side reaction/watch. SELL remains a core-engine decision after its existing lifecycle gates.

### C. VAL touch but no rejection

A candle overlaps VAL but closes below it without the required reclaim/close-location condition. The response is `VAL TOUCH / NO REJECTION` (42); it is not a confirmed sweep reaction. The status remains WATCH when this is the only location evidence, and missing structure/zone/retest reasons stay visible. No BUY is authorized.

### D. Large volume in a narrow range

A 2.0x volume ratio on a small-body, range-bound candle can still satisfy the legacy expansion boolean, but it is not displacement. If there is no direction-confirming candle, the directional flow proxy is zero and the raw +10 candle expansion credit is removed rather than retained as directionless confluence. With no other location/context it is `NO TRADE` at the SMF layer; if it touches a level it is, at most, WATCH.

### E. Conflicting profile and VWAP

If profile evidence supports the candidate direction at 70+ while VWAP scores 30 or less (or vice versa), the panel reports `CONFLICT / WATCH`; neither profile nor VWAP context is blended into its score slot. This is transparent disagreement, not an averaged “strong” score. The core engine's existing gates still decide whether a setup can publish.

### F. HVN/LVN touch without a boundary reaction

A closed candle through a stored HVN or LVN reports its node type and price as `LOCATION (NON-DIRECTIONAL)`. The node alone does not change the directional profile score or establish rejection. Any separate flow evidence is evaluated under the existing cluster rules; the node touch itself is not treated as a VAL/VAH rejection.

## 9. Validation still required

Before release, compile `KLJ.mq5` in MetaEditor, run the initialization `SMF_SelfTest()` and existing MVP/ZRE/RXN tests, check the Experts log for replay/self-test failures, and run the paired performance comparison above. No MQL compile, MetaTrader runtime, or trading/backtest performance result is asserted by this report.
