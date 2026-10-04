//+------------------------------------------------------------------+
//| QuantumSMC_AI_Pro_v5.7.3_Audited.mq5                             |
//| Premium SMC Analysis - v5.7.5 PRODUCTION AUDIT BUILD              |
//| Based on the v5.7.1/5.7.2 Institutional Market Maker source       |
//|                                                                    |
//| v5.7.3 FULL AUDIT (this build):                                   |
//| A1. Score engine: candle-context factor and the adaptive regime    |
//|     multiplier never reached final_score (aggregated before they   |
//|     were computed; regime fallback silently applied 0.97). The     |
//|     zone->regime->candle-context stage now runs before the single  |
//|     final aggregation, so all published weights are real.          |
//| A2. Hard causal gate moved ahead of zone/scoring work (same        |
//|     semantics, less wasted computation).                           |
//| A3. TP1/TP2 consumption of CONFIRMED setups is now tracked on      |
//|     closed bars (dashboard RESTING/CONSUMED reflects reality).     |
//| A4. Blacklist expiry uses a binary search instead of an O(bars)    |
//|     scan per entry per evaluation.                                 |
//| A5. Causal-graph prune no longer spams the journal every rebuild;  |
//|     prune logs are gated behind InpLogLifecycleTransitions.        |
//| A6. Judas swing: post-Asia scan no longer matches pre-Asia hours   |
//|     of the same local day (stale overnight bars).                  |
//| A7. g_last_bar_time is committed only after indicator data is      |
//|     available, so a failed CopyBuffer tick retries the new bar     |
//|     instead of silently skipping its events.                       |
//| A8. Dead code removed (SafeVal, AddOrMergeFVG_Simple,             |
//|     IsDuplicateLiquidity, IsDuplicateOB, BinarySearchNearestOB,    |
//|     DrawLevelText, unused locals).                                 |
//| A9. PDH/PDL/Pivot/Camarilla lines are skipped when D1 history is   |
//|     not yet available instead of being drawn at 0.0.               |
//| A10. Compact dashboard NEXT-state no longer reports WAIT ZONE      |
//|     while a causally valid zone exists; score-breakdown weights    |
//|     now display the actual aggregation weights.                    |
//| A11. Version strings unified to v5.7.3.                            |
//|                                                                    |
//| v5.7.4 DASHBOARD REDESIGN (this build):                            |
//| D1. Wire-up of dead features: BuildConfidenceBar() and             |
//|     BuildInstitutionalPatternChecklist() were fully implemented    |
//|     but never called; both now render in the dashboard.            |
//| D2. Grouped sections (STATUS/CAUSAL/SCORE/TRADE/ENGINE) with       |
//|     header separators and a state-tinted left border strip         |
//|     (green=CONFIRMED, watch colors, gray=WAIT).                    |
//| D3. Zero-context lines suppressed: score/breakdown render only     |
//|     when a structural anchor exists (no "score 0" clutter).        |
//|                                                                    |
//| v5.7.5 DASHBOARD SIZE + COLOR LEGEND (this build):                 |
//| D4. Size modes InpDashMode = MINI/COMPACT/FULL (default MINI,      |
//|     ~6 plain-word rows: STATE/WHY/SCORE/PLAN/TREND) replacing the  |
//|     InpCompactDashboard boolean; fixed 5-bucket color legend row   |
//|     (lime=BUY/OK, tomato=SELL/problem, aqua=watch/developing,      |
//|     gray=no setup, orange=blocked) drawn in MINI and COMPACT;      |
//|     one-off colors (goldenrod/khaki/dodger/mediumspring) removed   |
//|     so every visible color matches a legend bucket; engine         |
//|     internals now render in FULL mode only; legend row uses        |
//|     deterministic IDs DASH_LEG0..4 and is repositioned/deleted     |
//|     with the panel.                                                |
//|                                                                    |
//| FIXES v5.3.0 (Audit):                                             |
//| 1. Chronological arrays enforced via ArrayGetAsSeries()           |
//| 2. Structure/mitigations ONLY on closed bars (RETEST live only)    |
//| 3. Stable UID for OBs & Setups                                    |
//| 4. Master arrays NEVER sorted in-place; index tables used         |
//| 5. Blacklist prevents re-seeding INVALID setup                    |
//| 6. Fallback zone with min ATR height                              |
//| 7. ObjectsDeleteAll restricted to New Bar (delta)                 |
//| 8. ArrayResize with reserve + incremental EMA/VWAP                |
//|                                                                    |
//| UPGRADE v5.4.0 STABLE (P0/P1/P2):                                  |
//| P0.1 Guard total<3 / total-2, P0.2 Timeout+Distance invalidation  |
//| P0.3 Re-evaluate FVG after merge, P0.4 Enhanced SetupId+Blacklist |
//| P1.5 Incremental Detection, P1.6 Smart Object Mgmt, P1.7 Static   |
//|     price buffers, P1.8 Strict array caps (30/40/25/20)            |
//| P2.9 Sweep displacement/volume filter, P2.10 Synthetic zone       |
//|     quality, P2.11 Simplified Graph, P2.12 Lifecycle logs          |
//|                                                                    |
//| v5.6: exact pool ancestry; sweep->displacement->structure graph;   |
//| ranked causal OB/FVG anchors; deterministic Reliability; strict    |
//| target geometry/barriers; closed HTF replay; DST-aware sessions.   |
//| v5.6.1: exact-parent sweep confirmation; immutable first barrier;   |
//| strict displacement-generated FVG; explicit retest substates;      |
//| ancestry-safe graph pruning and incremental/full replay audits.     |
//| v5.6.2: HTF event availability time mapped to its actual closed     |
//| chart bar; Kill Zones separated from broad session windows.         |
//| v5.6.3: closed shift-1 cache keys; strict Sweep<Disp<Structure;     |
//| dynamic graph traversal; explicit event vs availability semantics.  |
//| v5.6.4: confirmed MTF; ranked causal ancestors; exact FVG source;   |
//| HTF close invariants; transactional setup/replay semantic closure.  |
//| v5.6.9: hop-level causal audit. Event PASS != causal PASS.          |
//| Dashboard shows SWEEP->DISP / DISP->MSS / MSS->ZONE fail reasons.   |
//| Quality score is diagnostic only and cannot authorize entry.        |
//| v5.7.0: directional opposite-scan + explicit BUY/SELL watch states;   |
//| invalidated setup releases ownership and next closed-bar scan may     |
//| promote the opposite institutional branch without bypassing retest.  |
//| v5.7.1: primary directional watch follows HTF/D1 bias; BOS may start  |
//| WATCH evidence, while MSS + causal path + retest remain mandatory.   |
//+------------------------------------------------------------------+
#property copyright "Quantum SMC AI Pro v5.7.3 Institutional Market Maker (Audited)"
#property version   "5.75"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_label1  "EMA Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  1
#property indicator_label2  "EMA Slow"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  2
#property indicator_label3  "VWAP"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrGold
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

double BufEmaFast[], BufEmaSlow[], BufVWAP[];
//--- Shared global indicator buffers (Rule 14 & Rule 21)
double g_atr_buf[], g_adx_buf[], g_rsi_buf[];

//====================================================================
// ENUMS
//====================================================================
enum ENUM_MIN_GRADE
{
   GRADE_D = 1,
   GRADE_C = 2,
   GRADE_B = 3,
   GRADE_A = 4,
   GRADE_APLUS = 5
};

enum ENUM_CAUSAL_EVENT_TYPE
{
   CE_LIQ_POOL=0,
   CE_LIQ_SWEEP,
   CE_DISPLACEMENT,
   CE_BOS,
   CE_CHOCH,
   CE_MSS,
   CE_ORDER_BLOCK,
   CE_FVG,
   CE_HTF_STRUCTURE,
   CE_SETUP,
   CE_TARGET
};

enum ENUM_BROKER_DST_RULE
{
   BROKER_DST_NONE=0,
   BROKER_DST_EU,
   BROKER_DST_US
};

enum ENUM_SESSION_ID
{
   SESSION_ASIA=0,
   SESSION_LONDON,
   SESSION_NEWYORK
};

// v6.0 MarketConflictEngine (master-prompt Sections 5 & 12).
// Classifies the relationship between the current chart's structural
// direction (the "LTF" from this engine's perspective) and the higher
// timeframe structural bias (g_htf_bias), so a lower-timeframe move against
// an intact higher-timeframe trend is labeled a retracement rather than
// blindly treated as a fresh signal in the opposite direction.
enum ENUM_MTF_CONFLICT_STATE
{
   MTF_NEUTRAL=0,       // HTF bias undetermined; no conflict claim possible
   MTF_ALIGNED,         // LTF direction matches HTF bias
   MTF_LTF_RETRACEMENT, // LTF direction opposes HTF bias, but HTF trend intact
   MTF_CONFLICT         // LTF MSS opposes an HTF bias independently confirmed by D1
};

//====================================================================
// INPUTS
//====================================================================
input group "====== EMA & VWAP ======"
input int InpEMAFast = 50;
input int InpEMASlow = 200;
input group "====== Oscillators ======"
input int InpATRPeriod = 14;
input int InpADXPeriod = 14;
input int InpRSIPeriod = 14;
input group "====== Structure (BOS/CHoCH/MSS) ======"
input int InpSwingFractalN = 3;
input int InpMaxStructureShown = 6;
input double InpDisplacementATR = 1.5;
input group "====== Order Blocks ======"
input int InpOBLookback = 20;
input int InpMaxStrongOB = 3;
input bool InpAutoRemoveMitigatedOB = true;
input int InpOBTransparency = 88;
input double InpOBMaxHeightATR = 3.0;
input group "====== Demand / Supply Zones ======"
input int InpZoneLookback = 150;
input int InpMaxZonesShown = 3;
input double InpZoneBaseBodyATR = 0.6;
input double InpZoneMaxHeightATR = 2.0;
input group "====== Breaker Blocks ======"
input bool InpShowBreakers = true;
input int InpMaxBreakersShown = 2;
input group "====== Fair Value Gaps ======"
input int InpFVGLookbackBars = 100;
input double InpFVGMinSizeATR = 0.3;
input int InpMaxFVGShown = 3;
input bool InpMergeFVG = true;
input bool InpHideFilledFVG = true;
input group "====== Liquidity ======"
input int InpLiquidityLookback = 100;
input int InpLiquidityFractalN = 2;
input double InpLiqToleranceATR = 0.15;
input double InpLiquidityTolerancePips = 5.0;
input int InpMaxLiquidityShown = 3;
input group "====== Premium Features ======"
input bool InpShowKillZones = true;
input bool InpShowSessionHL = true;
input group "====== Sessions & Levels ======"
input bool InpShowPivots = true;
input bool InpShowCamarilla = true;
input bool InpShowPDHPDL = true;
// Session hours are LOCAL market clocks in v5.6.
input int InpAsianStart = 9, InpAsianEnd = 18;      // Tokyo local session (09:00-18:00 JST = 00:00-09:00 UTC)
input int InpLondonStart = 8, InpLondonEnd = 16;   // London local session
input int InpNewYorkStart = 8, InpNewYorkEnd = 16; // New York local session
// Kill Zones are independent local-market windows; they are not derived from
// the first three session hours.
input int InpLondonKillZoneStart = 7, InpLondonKillZoneEnd = 10;   // London local
input int InpNewYorkKillZoneStart = 7, InpNewYorkKillZoneEnd = 10; // New York local
input group "====== Session Clock / DST ======"
input int InpBrokerUTCOffsetWinterMinutes = 120;
input ENUM_BROKER_DST_RULE InpBrokerDSTRule = BROKER_DST_EU;
input bool InpUseDSTSessions = true;
input group "====== Premium / Discount & OTE ======"
input bool InpShowPremiumDiscount = true;
input bool InpShowFibonacci = false;
input bool InpShowOTE = true;
input int InpSwingLookback = 120;
input int InpSwingRangeFractalN = 8;
input double InpOTEFibStart = 0.618;
input double InpOTEFibEnd = 0.79;
input int InpRangeBoxMaxBars = 60;
input group "====== v5.0 Algorithm Settings ======"
input bool InpUseBinarySearch = true;              // reserved: index search is linear today
input bool InpUseDynamicProg = true;
input bool InpUseKnapsack = true;
input bool InpUseBitMasking = true;
input bool InpUseMemoization = true;
input bool InpUseGraphTheory = true;
input group "====== QUALITY ENGINE - FLEXIBLE ======"
input bool InpRelaxedMode = true;
input bool InpRequireOB = false;
input bool InpRequireHTFBias = false;
input int InpMinSignalFactors = 2;
input bool InpAllowPartialFVG = true;
input bool InpShowQualityPanel = true;
input bool InpShowScoreBreakdown = true;
input int InpMinReliability = 80;
input ENUM_MIN_GRADE InpMinGrade = GRADE_B;
input bool InpBlockLowGrade = false;
input int InpMinEntryOBStrength = 3;
input double InpMaxOBDistATR = 8.0;
input bool InpAlertOnSetup = true;
input int InpMinConfidenceScore = 75;
input group "====== Panel Layout ======"
input bool InpASCIIBar = true;
input int InpPanelRightPad = 68;
input int InpPanelFontSize = 0;
input bool InpPanelAutoWidth = true;
input int InpPanelMaxReasons = 4;
input bool InpShowDebugCounts = false;
// D4 (v5.7.5 dashboard size modes): MINI = ~6 plain-word rows (default),
// COMPACT = grouped layout without engineering internals,
// FULL = everything including engine diagnostics.
// Replaces the old InpCompactDashboard boolean (FULL == old false,
// COMPACT == old true, MINI is new and is the default).
enum ENUM_DASH_MODE
  {
   DASH_MINI    = 0,   // Mini (recommended: ~6 rows)
   DASH_COMPACT = 1,   // Compact (grouped sections, no internals)
   DASH_FULL    = 2    // Full (all engineering details)
  };
input ENUM_DASH_MODE InpDashMode = DASH_MINI;   // Dashboard size: Mini / Compact / Full
input group "====== Clarity (1920x1080) ======"
input bool InpDeclutter = true;
input int InpPDTransparency = 97;
input group "====== AI Dashboard ======"
input bool InpShowAIDashboard = true;
input bool InpShowMTFPanel = true;
input bool InpShowTradeBox = true;
input group "====== Trade Levels (Pro) ======"
input bool InpDrawTradeLevels = true;
input bool InpUseMeanThreshold = true;
input bool InpSLBeyondSweep = true;
input double InpSLBufferATR = 0.2;
input bool InpSmartTargets = true;
input group "====== ICT Depth & Filters ======"
input ENUM_TIMEFRAMES InpHTFBiasTF = PERIOD_H4;
input bool InpUseHTFBias = true;
input int InpHTFStructureFractalN = 3;
input bool InpRequireD1StructureAgreement = true;
input bool InpDetectJudas = true;
input int InpMaxSpreadPts = 60;
input bool InpIgnoreSpreadOffHours = false;
input bool InpIgnoreSpreadInBacktest = true;
input int InpMaxStructureAge = 40;
input double InpADXChopLevel = 18.0;
input double InpADXTrendLevel = 25.0;
input group "====== Multi-Timeframe ======"
input ENUM_TIMEFRAMES InpMTF1 = PERIOD_MN1;
input ENUM_TIMEFRAMES InpMTF2 = PERIOD_W1;
input ENUM_TIMEFRAMES InpMTF3 = PERIOD_D1;
input ENUM_TIMEFRAMES InpMTF4 = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF5 = PERIOD_H1;
input group "====== Zone Colors ======"
input color InpColorOB = clrFireBrick;
input color InpColorOB_Bear = clrCrimson;
input color InpColorFVG = clrMediumOrchid;
input color InpColorDemand = clrSeaGreen;
input color InpColorSupply = clrDodgerBlue;
input color InpColorBreaker = clrGold;
input color InpColorPremium = clrIndianRed;
input color InpColorDiscount = clrForestGreen;
input color InpColorEQ = clrSilver;
input color InpColorFib = clrDarkGray;
input color InpColorOTE = clrAqua;
input group "====== DEBUGGING ======"
input bool InpShowDebugAlerts = false;
input bool InpLogSignalDetails = true;
input group "====== REAL-TIME MODE ======"
input bool InpRealTimeZones = true;
input bool InpUpdateEveryTick = true;
input bool InpRealTimeFractal = true; // draws provisional markers only; never feeds decisions
input bool InpShowEarlyZones = true;
input int InpEarlyZoneTransparency = 94;
input group "====== PREVIEW LATENCY (NON-AUTHORITATIVE) ======"
input int InpMinRightConfirmBars = 1; // preview only; confirmed fractals always use N right bars
input bool InpShowLatencyInPanel = false;
input bool InpShowEarlyBreakPreview = true; // non-authoritative live break preview
input double InpEarlyBreakBufferPoints = 0.0; // extra points required beyond structure price
input bool InpShowEarlyBreakTrigger = true; // show the same authoritative structure level before the break

input group "====== SETUP -> RETEST -> CONFIRMED (NEW v5.2.0) ======"
input bool InpUseRetestLifecycle = true;
input bool InpIntersectFVGZone = true;
input double InpInvalidateBufferATR = 0.3;
input bool InpAlertOnSetupReady = false;
input bool InpShowEntryPreview = true; // live entry preview on retest; non-authoritative
input bool InpAlertOnEntryPreview = true; // alert once per setup when live retest becomes directional
input bool InpInvalidateOnOppositeMSS = true; // closed opposite MSS cancels active setup and releases opposite scan
input group "====== MTF EXECUTION ENTRY (TACTICAL, NON-AUTHORITATIVE) ======"
input bool InpUseMTFExecutionEntry = true;
input bool InpAutoExecutionTF = true;
input ENUM_TIMEFRAMES InpExecutionTF = PERIOD_M5;
input double InpMTFEntryMaxDistanceATR = 1.0;
input bool InpAlertOnMTFExecutionEntry = true;
input bool InpShowMTFExecutionEntry = true;

input group "====== v5.4.0 Performance & Stability ======"
input bool   InpUseIncrementalDetection = true;
input int    InpMaxStructuresKeep      = 30;
input int    InpMaxLiquidityKeep       = 40;
input int    InpMaxFVGKeep             = 25;
input int    InpMaxZonesKeep           = 20;
input int    InpRetestTimeoutBars      = 25;
input double InpRetestMaxDistanceATR   = 2.5;
input bool   InpSmartObjectManagement  = true;
input bool   InpLogLifecycleTransitions = false;

input group "====== v5.6.6 RUNTIME / CAUSAL VALIDATION ======"
input bool InpRuntimeValidationMode = false;
input bool InpRuntimeCompareReplay = false;
input bool InpRuntimeNoLookaheadAudit = true;
input bool InpRuntimeHTFCausalityAudit = true;
input bool InpRuntimeGraphAudit = true;
input bool InpRuntimeEntryAudit = true;
input int  InpRuntimeAuditBars = 500;

input group "====== v5.6.6 ADVANCED CAUSAL SWEEP ENGINE ======"
input bool   InpUseAdvancedSweepEngine      = true;
input bool   InpSweepEntryAutoMode          = false;
input double InpSweepEntryMinScore          = 75.0;
input int    InpSweepEntryMaxBarsAfterSweep = 3;
input double InpSweepEntryMinRR             = 1.50;
input bool   InpUseMergeSortRanking         = true;
input bool   InpUseMemoizedDP               = true;
input bool   InpUseFibonacciDP              = true;
input bool   InpUseCausalGraphOptimizer      = true;
input bool   InpUseDijkstraPathSearch         = true;
input bool   InpUseBellmanFordValidation      = true;
input bool   InpUseBeamSearch                 = true;
input int    InpBeamWidth                     = 5;
input int    InpGraphMaxPathHops              = 8;
input double InpGraphTemporalPenaltyATR       = 0.04;
input double InpGraphConflictPenalty          = 2.50;
input double InpGraphCausalReward             = 3.00;
input bool   InpRejectGraphNegativeCycle      = true;
input bool   InpRequireGraphAgreement         = false;
input bool   InpUseCausalDPOptimizer           = true;

input group "====== v5.6.9 CAUSAL DIAGNOSTICS ======"
input bool   InpShowCausalAudit            = true;
input int    InpWatchMinQuality            = 75;
input bool   InpQualityScoreWithoutCausal  = true; // display-only; never authorizes entry

input group "====== v5.6.8 ALGORITHMIC CONFLUENCE ENGINE ======"
input bool   InpUseEvidenceIndependence      = true;
input bool   InpUseRegimeAdaptiveScoring     = true;
input bool   InpUseContextualCandleScoring   = true;
input bool   InpRequireContextualCandle      = false;
input double InpRegimeExpansionBonus         = 1.05;
input double InpRegimeTrendBonus             = 1.03;
input double InpRegimeRangePenalty           = 0.92;
input double InpRegimeCompressionPenalty     = 0.88;
input int    InpCandleRetestMinScore         = 55;

input group "====== v6.0 PRIME LEVEL ENGINE (diagnostic-only) ======"
// PrimeLevelEngine: prime-number-derived price levels as an OPTIONAL
// statistical/confluence feature. Per design, this must never gate or
// authorize entry -- it only ever contributes a small, capped bonus to the
// diagnostic score, exactly like the existing EMA/VWAP confluence bonus.
input bool   InpUsePrimeLevels           = true;
input int    InpPrimeLevelCount          = 25;    // how many prime-derived levels to generate per side
input double InpPrimeLevelToleranceATR   = 0.15;  // proximity tolerance, ATR-normalized
input double InpPrimeScoreMaxBonus       = 2.0;   // hard cap on final_score contribution (points)
input bool   InpUseRelationshipMatrix    = true;
input double InpRelationshipScoreMaxBonus = 2.0;  // hard cap on final_score contribution (points)
input bool   InpUseMarketConflictEngine  = true;
input double InpMTFConflictPenalty       = 4.0;   // hard cap on final_score penalty for MTF_CONFLICT (points)
input bool   InpShowInstitutionalPattern = true;

input group "====== v5.6.5 UNIVERSAL INSTRUMENT ADAPTER ======"
input bool InpUniversalInstrumentMode = true;
input bool InpUseExchangeTickSize      = true;
input bool InpUseBrokerStopsGeometry   = true;
input bool InpAutoInstrumentSession    = true;

input group "====== v5.6.3 Causal Institutional Sequence ======"
input bool   InpInstitutionalSequence       = true;
input bool   InpRequireLiquiditySweep       = true;
input int    InpSweepToStructureMaxBars     = 8;
input bool   InpRequireMSSAfterSweep         = true;
input bool   InpRequireInstitutionalZone     = true;
input bool   InpAllowFVGEntryZone            = true;
input int    InpOrderZonePreSweepBars        = 1;
input bool   InpBlockEquilibriumEntries      = true;
input double InpEquilibriumBufferATR         = 0.15;
input bool   InpUseEMAVWAPConfluence         = true;
input double InpMaxStopATR                   = 3.0;
input double InpMinRR1                       = 1.20;
input int    InpBlacklistExpiryBars          = 200;

input group "====== v5.6.3 Causal Event Graph ======"
input int    InpMaxCausalEventsKeep          = 160;
input int    InpAnchorSearchBars             = 60;
input double InpCausalDisplacementBodyATR    = 0.50;
input bool   InpRequireCausalFVGBody          = true;
input bool   InpPreferMSSAnchor               = true;
input bool   InpRejectTargetsBeyondBarrier   = true;  // legacy compatibility; institutional mode always enforces
input bool   InpEnableCausalInvariantChecks   = true;
input int    InpReplayAuditEveryBars          = 50;    // 0 disables incremental-vs-full audit

#define PFX "QSMC_"
#define MAX_CAUSAL_CHILDREN 8

//--- bit masking
#define BIT_MSS           (1<<0)
#define BIT_BOS           (1<<1)
#define BIT_CHOCH         (1<<2)
#define BIT_STRONG_OB     (1<<3)
#define BIT_LIQUIDITY     (1<<4)
#define BIT_FVG           (1<<5)
#define BIT_OTE           (1<<6)
#define BIT_HTF_BIAS      (1<<7)
#define BIT_KILLZONE      (1<<8)
#define BIT_DEMAND_ZONE   (1<<9)
#define BIT_JUDAS         (1<<10)
#define MAX_GRAPH_LINKS   16
#define MAX_CAUSAL_HOPS   6

//====================================================================
// GLOBALS
//====================================================================
datetime g_last_bar_time = 0;
int g_oncalc_seq=0;              // bumped once per OnCalculate call
int g_mtf_align_cache_seq=-1;    // MTFAlignmentPercent() per-tick cache key
int g_mtf_align_cache_value=0;   // MTFAlignmentPercent() per-tick cache value
int h_ema_fast, h_ema_slow, h_atr, h_adx, h_rsi;
int h_ema_mtf[5];
int g_signal_mask = 0;
double g_atr = 0.0;
double g_adx = 0.0;
long g_spread = 0;
int g_htf_bias = 0;
string g_htf_structure_state = "NEUTRAL";
string g_d1_structure_state  = "NEUTRAL";
int g_judas = 0, g_judas_bar = 0;
datetime g_htf_cache_time = 0;
datetime g_d1_cache_time = 0;
bool g_memo_hit = false;
datetime g_last_alert_bar = 0;
string g_last_confirmed_alert_id = "";
string g_last_entry_preview_id = "";
int g_dash_lines = 0;
int g_dash_width = 300;
int g_rates_total = 0;
bool g_is_backtest = false;
int g_signal_count = 0;
//--- perf & chronological helpers
double g_cum_pv=0.0, g_cum_v=0.0;
//--- Institutional real-time VWAP committed & forming candle state (Item 1)
double   g_committed_pv = 0.0, g_committed_v = 0.0;
double   g_cur_bar_pv   = 0.0, g_cur_bar_v   = 0.0;
datetime g_cur_bar_time = 0;
datetime g_vwap_anchor  = 0;

//--- Institutional Persistent Structure & OB State Machine (Item 2)
double g_struct_last_high          = 0.0;
double g_struct_last_low           = 0.0;
int    g_struct_trend              = 0;     // +1 bullish, -1 bearish, 0 neutral
int    g_struct_last_processed_bar = -1;    // last bar checked for structure break
int    g_struct_last_break_bar     = -1;    // last bar where BOS/CHOCH/MSS occurred
datetime g_last_ob_struct_time     = 0;     // stable OB processing cursor
double g_d1_high=0, g_d1_low=0, g_d1_close=0;
double g_htf_eq=0;
//--- P1.7 static price buffers (reuse, resize only when needed)
double g_buf_o[], g_buf_h[], g_buf_l[], g_buf_c[];
datetime g_buf_t[];
long g_buf_tv[];
int g_last_rates_total=0;
bool g_needs_full_rebuild=false;
//--- Non-authoritative live break preview (never feeds structure/causal decisions)
bool   g_early_break_preview=false;
bool   g_early_break_bull=false;
double g_early_break_price=0.0;
datetime g_early_break_time=0;
int    g_early_break_structure_idx=-1;
datetime g_early_break_structure_time=0;
string g_early_break_structure_type="";
string g_early_break_status=""; // PRE_BREAK / EARLY_BREAK / CLOSE_CONFIRMED / FAILED
datetime g_early_break_failed_time=0;
string g_mtf_entry_state="";
double g_mtf_entry_price=0.0;
datetime g_mtf_entry_time=0;
ENUM_TIMEFRAMES g_mtf_entry_tf=PERIOD_M5;
string g_last_mtf_entry_id="";
//--- P0.4 enhanced blacklist: store idea hash + zone center + tolerance
string g_blacklist_zone_type[]; // "BUY"/"SELL"
double g_blacklist_zone_center[];


//====================================================================
// v5.6.5 UNIVERSAL INSTRUMENT SPECIFICATION
// Broker/exchange metadata is the source of truth for price geometry.
// No asset-specific SMC logic is introduced here.
//====================================================================
struct SInstrumentSpec
{
   string symbol;
   ENUM_SYMBOL_CALC_MODE calc_mode;

   int    digits;
   double point;
   double tick_size;
   double tick_value;
   double contract_size;

   double volume_min;
   double volume_max;
   double volume_step;

   int    stops_level_points;
   int    freeze_level_points;

   bool   is_forex;
   bool   is_futures;
   bool   is_stock;
   bool   is_index;
   bool   is_metal;
   bool   is_crypto;
   bool   is_cfd;
   bool   is_exchange;

   bool   valid;
};

SInstrumentSpec g_instrument;

//--------------------------------------------------------------------
// Classify the current MT5 symbol from broker metadata/name only.
// This classification NEVER changes SMC semantics.
//--------------------------------------------------------------------
bool LoadInstrumentSpec()
{
   ZeroMemory(g_instrument);

   g_instrument.symbol=_Symbol;
   g_instrument.calc_mode=(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
   g_instrument.digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   g_instrument.point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   g_instrument.tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   g_instrument.tick_value=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   g_instrument.contract_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);

   g_instrument.volume_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   g_instrument.volume_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   g_instrument.volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   g_instrument.stops_level_points=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   g_instrument.freeze_level_points=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   if(g_instrument.point<=0.0)
      g_instrument.point=_Point;
   if(g_instrument.tick_size<=0.0)
      g_instrument.tick_size=g_instrument.point;

   int cm=(int)g_instrument.calc_mode;

   g_instrument.is_forex =
      (cm==(int)SYMBOL_CALC_MODE_FOREX ||
       cm==(int)SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE);

   g_instrument.is_futures =
      (cm==(int)SYMBOL_CALC_MODE_FUTURES ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_FUTURES ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS);

   g_instrument.is_stock =
      (cm==(int)SYMBOL_CALC_MODE_EXCH_STOCKS ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX);

   g_instrument.is_index =
      (cm==(int)SYMBOL_CALC_MODE_CFDINDEX);

   g_instrument.is_cfd =
      (cm==(int)SYMBOL_CALC_MODE_CFD ||
       cm==(int)SYMBOL_CALC_MODE_CFDINDEX ||
       cm==(int)SYMBOL_CALC_MODE_CFDLEVERAGE);

   g_instrument.is_exchange =
      (cm==(int)SYMBOL_CALC_MODE_EXCH_STOCKS ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_STOCKS_MOEX ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_FUTURES ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_BONDS ||
       cm==(int)SYMBOL_CALC_MODE_EXCH_BONDS_MOEX);

   // Metals/crypto cannot be inferred perfectly from MT5 calc mode because
   // brokers may publish them as CFD. Use conservative symbol-name hints only
   // for metadata classification; no trading decision depends on this flag.
   string s=_Symbol;
   StringToUpper(s);

   g_instrument.is_metal=
      (StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0 ||
       StringFind(s,"XAG")>=0 || StringFind(s,"SILVER")>=0);

   g_instrument.is_crypto=
      (StringFind(s,"BTC")>=0 || StringFind(s,"ETH")>=0 ||
       StringFind(s,"SOL")>=0 || StringFind(s,"XRP")>=0 ||
       StringFind(s,"DOGE")>=0 || StringFind(s,"LTC")>=0);

   g_instrument.valid=(g_instrument.point>0.0 && g_instrument.tick_size>0.0 &&
                       g_instrument.digits>=0);

   return g_instrument.valid;
}

//--------------------------------------------------------------------
// Price quantum: broker/exchange tick size, not merely _Digits.
//--------------------------------------------------------------------
double InstrumentTickSize()
{
   if(InpUniversalInstrumentMode && g_instrument.valid &&
      InpUseExchangeTickSize && g_instrument.tick_size>0.0)
      return g_instrument.tick_size;

   double t=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   return (t>0.0 ? t : _Point);
}

double NormalizePriceToTick(const double price)
{
   double tick=InstrumentTickSize();
   if(tick<=0.0) return NormalizeDouble(price,_Digits);

   double q=MathRound(price/tick);
   return NormalizeDouble(q*tick,_Digits);
}

double InstrumentMinStopDistance()
{
   if(!InpUseBrokerStopsGeometry || !g_instrument.valid)
      return 0.0;

   double p=(g_instrument.point>0.0 ? g_instrument.point : _Point);
   return MathMax(0.0,(double)g_instrument.stops_level_points*p);
}

double InstrumentFreezeDistance()
{
   if(!g_instrument.valid) return 0.0;
   double p=(g_instrument.point>0.0 ? g_instrument.point : _Point);
   return MathMax(0.0,(double)g_instrument.freeze_level_points*p);
}

double NormalizeVolumeToStep(const double requested)
{
   if(!g_instrument.valid || g_instrument.volume_step<=0.0)
      return requested;

   double v=MathMax(g_instrument.volume_min,
                    MathMin(g_instrument.volume_max,requested));
   double steps=MathFloor((v-g_instrument.volume_min)/g_instrument.volume_step+1e-9);
   double normalized=g_instrument.volume_min+steps*g_instrument.volume_step;

   if(normalized<g_instrument.volume_min) normalized=g_instrument.volume_min;
   if(normalized>g_instrument.volume_max) normalized=g_instrument.volume_max;

   return normalized;
}

string InstrumentClassName()
{
   if(g_instrument.is_futures) return "FUTURES";
   if(g_instrument.is_stock)   return "STOCK";
   if(g_instrument.is_forex)   return "FOREX";
   if(g_instrument.is_metal)   return "METAL";
   if(g_instrument.is_crypto)  return "CRYPTO";
   if(g_instrument.is_index)   return "INDEX";
   if(g_instrument.is_cfd)     return "CFD";
   return "OTHER";
}


//====================================================================
// v6.0 PRIME LEVEL ENGINE
// Purely statistical/optional feature (master-prompt Section 3.A).
// Prime-number-derived price levels are generated around a round-number
// anchor (a "century" level, i.e. price rounded to 100 pips -- a level
// class institutional/retail order flow already clusters around). Distance
// from the current decision price to the nearest such level is converted
// into a 0-100 proximity score.
//
// HARD DESIGN CONSTRAINT: this score is diagnostic-only.
//   - It NEVER participates in causal validation (Sections 3, 19 of the
//     institutional spec) and cannot gate, block, or authorize an entry.
//   - Its contribution to final_score is a small, explicitly capped bonus
//     (InpPrimeScoreMaxBonus), applied the same way the existing EMA/VWAP
//     confluence bonus is applied -- never as a weighted pillar.
//====================================================================
int g_primes[];

void BuildPrimeSieve(const int count)
{
   // Simple deterministic sieve: generate the first `count` primes.
   // count is bounded by an input (InpPrimeLevelCount), so this runs once
   // at OnInit and is never re-run per tick/bar.
   ArrayResize(g_primes,0,32);
   if(count<=0) return;
   int candidate=2;
   while(ArraySize(g_primes)<count)
   {
      bool is_prime=true;
      int limit=(int)MathSqrt((double)candidate);
      for(int p=0;p<ArraySize(g_primes) && g_primes[p]<=limit;p++)
         if(candidate%g_primes[p]==0){is_prime=false; break;}
      if(is_prime)
      {
         int n=ArraySize(g_primes);
         ArrayResize(g_primes,n+1,32);
         g_primes[n]=candidate;
      }
      candidate++;
   }
}

// Returns a 0-100 proximity score and, via nearest_label, a short description
// of the nearest prime-derived level (for dashboard/diagnostic display only).
double PrimeProximityScore(const double price,const double atr,string &nearest_label)
{
   nearest_label="";
   if(!InpUsePrimeLevels || ArraySize(g_primes)==0 || atr<=0.0) return 0.0;

   double pip=PipSize();
   if(pip<=0.0) return 0.0;

   // "Century" anchor: the round price level nearest to current price at a
   // 100-pip granularity. This mirrors a real, commonly cited institutional
   // clustering concept (round-number levels) rather than an arbitrary base.
   double century=pip*100.0;
   double anchor=MathRound(price/century)*century;

   double tolerance=atr*MathMax(0.01,InpPrimeLevelToleranceATR);
   double best_dist=DBL_MAX;
   double best_level=0.0;
   bool best_above=true;

   for(int i=0;i<ArraySize(g_primes);i++)
   {
      double offset=(double)g_primes[i]*pip;
      double lvl_up=anchor+offset;
      double lvl_dn=anchor-offset;
      double d_up=MathAbs(price-lvl_up);
      double d_dn=MathAbs(price-lvl_dn);
      if(d_up<best_dist){best_dist=d_up; best_level=lvl_up; best_above=(lvl_up>=price);}
      if(d_dn<best_dist){best_dist=d_dn; best_level=lvl_dn; best_above=(lvl_dn>=price);}
   }
   // Also consider the bare anchor itself (prime index 0 offset).
   double d_anchor=MathAbs(price-anchor);
   if(d_anchor<best_dist){best_dist=d_anchor; best_level=anchor; best_above=(anchor>=price);}

   if(best_dist>=tolerance) return 0.0;

   double score=100.0*(1.0-best_dist/tolerance);
   score=MathMax(0.0,MathMin(100.0,score));
   nearest_label=StringFormat("%s %s",best_above?"prime+":"prime-",
                              DoubleToString(best_level,_Digits));
   return score;
}


//====================================================================
// v6.0 INSTITUTIONAL RELATIONSHIP MATRIX (Floyd-Warshall)
// Master-prompt Section 13.
//
// This is DELIBERATELY distinct from the existing per-instance causal graph
// search (RunDijkstraCausalPath / RunBellmanFordCausalPath / RunBeamCausalPath
// in the ADVANCED CAUSAL SWEEP ENGINE below), which finds the best path
// between two specific EVENT INSTANCES on the live chart.
//
// This matrix instead encodes structural knowledge about how strongly one
// EVENT CATEGORY (Liquidity, Sweep, Displacement, MSS, BOS, CHoCH, FVG, OB,
// Retest, Volume, Session) relates to another, in general -- e.g. "how
// strong is a Liquidity->Sweep relationship compared to a Sweep->
// Displacement relationship". It is seeded with direct, one-hop confidences
// that mirror the documented causal hierarchy (Section 3 / 29 of the
// original spec: MSS stronger than BOS/CHoCH, etc.), then Floyd-Warshall
// computes the best (lowest-cost) TRANSITIVE relationship between every
// pair of categories -- exactly the "all-pairs shortest path" use case
// Floyd-Warshall is for.
//
// HARD DESIGN CONSTRAINT (explicit in the spec): "Use this to improve setup
// ranking. Do NOT use it as a blind prediction system." This matrix is
// static structural knowledge (built once, does not depend on live price
// data) and is used purely as a diagnostic/ranking-context signal. It never
// participates in causal validation and cannot gate or authorize an entry.
//====================================================================
enum ENUM_RELATION_NODE
{
   RN_LIQUIDITY=0,
   RN_SWEEP,
   RN_DISPLACEMENT,
   RN_MSS,
   RN_BOS,
   RN_CHOCH,
   RN_FVG,
   RN_OB,
   RN_RETEST,
   RN_VOLUME,
   RN_SESSION,
   RN_COUNT
};

#define RELATION_INF 1.0e6

double g_relation_cost[RN_COUNT][RN_COUNT];
double g_relation_strength[RN_COUNT][RN_COUNT]; // 0..100, higher = stronger

string RelationNodeName(const ENUM_RELATION_NODE n)
{
   switch(n)
   {
      case RN_LIQUIDITY:    return "Liquidity";
      case RN_SWEEP:        return "Sweep";
      case RN_DISPLACEMENT: return "Displacement";
      case RN_MSS:          return "MSS";
      case RN_BOS:          return "BOS";
      case RN_CHOCH:        return "CHoCH";
      case RN_FVG:          return "FVG";
      case RN_OB:           return "OB";
      case RN_RETEST:       return "Retest";
      case RN_VOLUME:       return "Volume";
      case RN_SESSION:      return "Session";
   }
   return "UNKNOWN";
}

void SeedRelationEdge(const ENUM_RELATION_NODE a,const ENUM_RELATION_NODE b,const double confidence)
{
   // Directed edge: cost = 1 - confidence. Lower cost = stronger relation.
   // Only keep the strongest (lowest-cost) edge if seeded more than once.
   double cost=MathMax(0.0,1.0-MathMax(0.0,MathMin(1.0,confidence)));
   if(cost<g_relation_cost[a][b]) g_relation_cost[a][b]=cost;
}

void BuildInstitutionalRelationshipMatrix()
{
   for(int i=0;i<RN_COUNT;i++)
      for(int j=0;j<RN_COUNT;j++)
         g_relation_cost[i][j]=(i==j)?0.0:RELATION_INF;

   // Seed one-hop confidences that mirror the documented causal hierarchy.
   // These are structural/definitional (Section 2/7 official terminology),
   // not fitted from live data -- e.g. MSS is explicitly stronger than
   // CHoCH which is explicitly stronger than plain BOS continuation.
   SeedRelationEdge(RN_LIQUIDITY,RN_SWEEP,0.91);
   SeedRelationEdge(RN_SWEEP,RN_DISPLACEMENT,0.88);
   SeedRelationEdge(RN_DISPLACEMENT,RN_MSS,0.86);
   SeedRelationEdge(RN_DISPLACEMENT,RN_CHOCH,0.70);
   SeedRelationEdge(RN_DISPLACEMENT,RN_BOS,0.65);
   SeedRelationEdge(RN_MSS,RN_FVG,0.83);
   SeedRelationEdge(RN_MSS,RN_OB,0.80);
   SeedRelationEdge(RN_CHOCH,RN_FVG,0.62);
   SeedRelationEdge(RN_CHOCH,RN_OB,0.60);
   SeedRelationEdge(RN_BOS,RN_FVG,0.58);
   SeedRelationEdge(RN_BOS,RN_OB,0.56);
   SeedRelationEdge(RN_FVG,RN_RETEST,0.79);
   SeedRelationEdge(RN_OB,RN_RETEST,0.78);
   // Volume and Session are context modifiers, not structural links in the
   // primary causal chain -- weaker, illustrative one-hop confidences only.
   SeedRelationEdge(RN_VOLUME,RN_SWEEP,0.55);
   SeedRelationEdge(RN_VOLUME,RN_DISPLACEMENT,0.60);
   SeedRelationEdge(RN_SESSION,RN_SWEEP,0.50);
   SeedRelationEdge(RN_SESSION,RN_DISPLACEMENT,0.52);

   // Classic Floyd-Warshall all-pairs shortest path over the category graph.
   // RN_COUNT is fixed and tiny (11), so this is O(11^3) and runs once.
   for(int k=0;k<RN_COUNT;k++)
      for(int i=0;i<RN_COUNT;i++)
      {
         if(g_relation_cost[i][k]>=RELATION_INF) continue;
         for(int j=0;j<RN_COUNT;j++)
         {
            if(g_relation_cost[k][j]>=RELATION_INF) continue;
            double via=g_relation_cost[i][k]+g_relation_cost[k][j];
            if(via<g_relation_cost[i][j]) g_relation_cost[i][j]=via;
         }
      }

   for(int i=0;i<RN_COUNT;i++)
      for(int j=0;j<RN_COUNT;j++)
      {
         double dist=g_relation_cost[i][j];
         g_relation_strength[i][j]=(dist<RELATION_INF*0.5) ?
            MathMax(0.0,MathMin(100.0,(1.0-dist)*100.0)) : 0.0;
      }
}

// Diagnostic/ranking-context accessor. Never used as a causal gate.
double InstitutionalRelationshipStrength(const ENUM_RELATION_NODE a,const ENUM_RELATION_NODE b)
{
   if(a<0 || a>=RN_COUNT || b<0 || b>=RN_COUNT) return 0.0;
   return g_relation_strength[a][b];
}


//====================================================================
// v6.0 MARKET CONFLICT ENGINE (master-prompt Sections 5 & 12)
//
// Section 5 (Divide and Conquer / MTF hierarchy) and Section 12
// (Bellman-Ford-style contradiction detection) both ask for the same real
// capability: when a lower timeframe move disagrees with the higher
// timeframe bias, the system must NOT collapse that into an immediate
// opposite-direction signal. It must instead recognize the hierarchy and
// label the situation -- e.g. "HTF BULLISH / LTF RETRACEMENT" -- rather
// than silently treating the LTF move as a fresh, equally-weighted signal.
//
// This reuses g_htf_bias (already a structural, causally-derived HTF bias
// from ComputeHTFBias/ComputeClosedStructureBias -- NOT a blind EMA cross)
// and g_d1_structure_state, so no new HTF computation is introduced.
//
// HARD DESIGN CONSTRAINT: this is a CLASSIFICATION/LABELING layer, not a
// new scoring pillar. ScoreHTF() already scores plain HTF alignment
// (0/50/100) and that is not duplicated here (avoids re-introducing the
// Section 17 double-counting issue). The only place this classification is
// allowed to affect final_score is the MTF_CONFLICT case specifically,
// where it captures a genuinely richer signal ScoreHTF cannot see on its
// own (an LTF MSS opposing an HTF bias that D1 independently confirms) --
// applied as a small, explicitly capped penalty, exactly like the existing
// ADX-chop penalty.
//====================================================================
ENUM_MTF_CONFLICT_STATE ClassifyMarketConflict(const bool is_buy,const string structure_type,
                                               string &label_out)
{
   label_out="";
   if(g_htf_bias==0)
   {
      label_out="HTF NEUTRAL";
      return MTF_NEUTRAL;
   }

   bool htf_bull=(g_htf_bias>0);
   if(htf_bull==is_buy)
   {
      label_out=StringFormat("HTF %s / ALIGNED",htf_bull?"BULLISH":"BEARISH");
      return MTF_ALIGNED;
   }

   // Disagreement: check whether D1 independently confirms the same HTF
   // direction AND the LTF anchor is a full MSS (the strongest possible LTF
   // structural claim). That specific combination is a genuine contradiction
   // (a decisively confirmed higher trend vs. the strongest opposite LTF
   // structural event) rather than an ordinary pullback.
   bool d1_confirms_htf=(htf_bull ? StringFind(g_d1_structure_state,"BULL")>=0
                                  : StringFind(g_d1_structure_state,"BEAR")>=0);
   if(structure_type=="MSS" && d1_confirms_htf)
   {
      label_out=StringFormat("CONFLICT: LTF MSS vs confirmed HTF %s",htf_bull?"BULLISH":"BEARISH");
      return MTF_CONFLICT;
   }

   label_out=StringFormat("HTF %s / LTF RETRACEMENT",htf_bull?"BULLISH":"BEARISH");
   return MTF_LTF_RETRACEMENT;
}


//====================================================================
// v6.0 INSTITUTIONAL PATTERN ENGINE (master-prompt Sections 8 & 22)
//
// "Detect sequences such as: Liquidity -> Sweep -> Displacement -> MSS ->
//  FVG -> Retest. The engine must track event order."
//
// The actual enforcement of this sequence (temporal causality, exact
// parent/child ancestry, chronological ordering) already exists and is
// audited elsewhere: BuildCausalEventGraph()/ResolveCausalPath() build and
// validate the real causal chain, and DiagnoseCausalChain() already derives
// a per-hop PASS/FAIL breakdown (g_causal_diag.hop_sweep_disp/hop_disp_mss/
// hop_mss_zone) plus the active setup's retest lifecycle state
// (g_active_setup.state). This engine does not re-implement or duplicate
// any of that -- it is a PURE DISPLAY-COMPOSITION layer that packages those
// already-computed, already-validated results into the single named
// checklist the master prompt's dashboard mockup (Section 22) asks for:
//
//   PATTERN <Bullish/Bearish> Institutional Reversal (n/5)
//   [v] SWEEP
//   [v] DISPLACEMENT
//   [v] MSS
//   [v] FVG   (or OB, whichever zone type the causal path actually selected)
//   [ ] RETEST
//
// It reads global diagnostic state only and writes nothing back into any
// causal/decision structure, so it cannot introduce a new gate, a new
// score contribution, or any repainting/look-ahead risk.
//====================================================================
void BuildInstitutionalPatternChecklist(string &out_lines[],int &out_count)
{
   out_count=0;
   ArrayResize(out_lines,7);

   bool is_buy=g_trade_setup.is_buy;
   if(g_causal_diag.decision_state=="SELL_WATCH")
      is_buy=false;
   else if(g_causal_diag.decision_state=="BUY_WATCH")
      is_buy=true;
   else if(g_causal_diag.zone_kind!="")
      is_buy=(StringFind(g_causal_diag.zone_kind,"BUY")>=0);

   bool sweep_ok=g_causal_diag.sweep_event_ok || g_causal_diag.hop_sweep_disp;
   bool disp_ok=g_causal_diag.disp_event_ok || g_causal_diag.hop_sweep_disp;
   bool mss_ok=g_causal_diag.hop_disp_mss || g_causal_diag.mss_event_ok;
   bool zone_ok=g_causal_diag.hop_mss_zone || g_causal_diag.zone_valid;
   string zone_label=(StringFind(g_causal_diag.zone_kind,"FVG")>=0) ? "FVG" :
                     (StringFind(g_causal_diag.zone_kind,"OB")>=0) ? "OB" : "ZONE";

   bool retest_confirmed=(g_active_setup.active &&
                          (g_active_setup.state=="RETEST_CONFIRMED" ||
                           g_active_setup.state=="CONFIRMED")) || g_trade_setup.valid;
   bool retest_active=(g_active_setup.active &&
                       (g_active_setup.state=="READY" ||
                        g_active_setup.state=="RETEST_PREVIEW" ||
                        g_active_setup.state=="RETEST_CONFIRMED" ||
                        g_active_setup.state=="CONFIRMED"));

   int done=0;
   if(sweep_ok) done++;
   if(disp_ok) done++;
   if(mss_ok) done++;
   if(zone_ok) done++;
   if(retest_confirmed) done++;

   out_lines[out_count++]=StringFormat("PATTERN %s Institutional Reversal (%d/5)",
                                       is_buy?"Bullish":"Bearish",done);
   out_lines[out_count++]=StringFormat("%s SWEEP",sweep_ok?"[v]":"[ ]");
   out_lines[out_count++]=StringFormat("%s DISPLACEMENT",disp_ok?"[v]":"[ ]");
   out_lines[out_count++]=StringFormat("%s MSS",mss_ok?"[v]":"[ ]");
   out_lines[out_count++]=StringFormat("%s %s",zone_ok?"[v]":"[ ]",zone_label);
   out_lines[out_count++]=StringFormat("%s RETEST%s",
                                       retest_confirmed?"[v]":"[ ]",
                                       (!retest_confirmed && retest_active)?" (pending)":"");
}


//====================================================================
// v5.6.6 ADVANCED CAUSAL SWEEP ENGINE
// Algorithms are deterministic search/ranking helpers.
// They never introduce future-bar information.
//====================================================================

struct SSweepCandidate
{
   int    liquidity_index;
   int    sweep_bar;
   int    displacement_bar;
   int    structure_bar;
   int    direction;
   double liquidity_price;
   double entry_price;
   double stop_price;
   double target_price;
   double rr;
   double score;
   int    structure_strength;
   string structure_type;
};

double FibDPValue(const int n)
{
   if(n<=0) return 0.0;
   if(n==1) return 1.0;
   double a=0.0,b=1.0,c=0.0;
   for(int i=2;i<=MathMin(n,20);i++)
   {
      c=a+b;
      a=b;
      b=c;
   }
   return b;
}

double AdvancedPathWeight(const int steps)
{
   int n=MathMax(1,MathMin(20,steps));
   if(!InpUseFibonacciDP) return 1.0/(double)n;
   return 1.0/MathMax(1.0,FibDPValue(n));
}

void MergeSweepCandidates(SSweepCandidate &a[],SSweepCandidate &tmp[],
                          const int left,const int right)
{
   if(left>=right) return;
   int mid=left+(right-left)/2;
   MergeSweepCandidates(a,tmp,left,mid);
   MergeSweepCandidates(a,tmp,mid+1,right);

   int i=left,j=mid+1,k=left;
   while(i<=mid && j<=right)
   {
      bool take_left=(a[i].score>a[j].score ||
                     (a[i].score==a[j].score && a[i].sweep_bar<a[j].sweep_bar));
      if(take_left) tmp[k++]=a[i++];
      else          tmp[k++]=a[j++];
   }
   while(i<=mid)  tmp[k++]=a[i++];
   while(j<=right)tmp[k++]=a[j++];
   for(int p=left;p<=right;p++) a[p]=tmp[p];
}

void SortSweepCandidates(SSweepCandidate &a[])
{
   int n=ArraySize(a);
   if(n<2) return;
   SSweepCandidate tmp[];
   ArrayResize(tmp,n);
   MergeSweepCandidates(a,tmp,0,n-1);
}

double MemoizedCausalPathScore(const int sweep_ok,const int displacement_ok,
                               const int structure_ok,const int anchor_ok,
                               const int retest_ok)
{
   static int memo_key=-1;
   static double memo_value=0.0;

   int key=sweep_ok |
           (displacement_ok<<1) |
           (structure_ok<<2) |
           (anchor_ok<<3) |
           (retest_ok<<4);

   if(InpUseMemoizedDP && key==memo_key)
      return memo_value;

   // Mandatory causal stages cannot be replaced by a high score.
   if(!sweep_ok || !displacement_ok || !structure_ok)
      return 0.0;

   double score=30.0;
   if(displacement_ok) score+=20.0;
   if(structure_ok)    score+=20.0;
   if(anchor_ok)       score+=15.0;
   if(retest_ok)       score+=15.0;

   memo_key=key;
   memo_value=score;
   return score;
}

double ScoreSweepCandidate(const SSweepCandidate &x,
                           const bool displacement_ok,
                           const bool structure_ok,
                           const bool anchor_ok,
                           const bool retest_ok)
{
   double causal=MemoizedCausalPathScore(
      1,displacement_ok?1:0,structure_ok?1:0,
      anchor_ok?1:0,retest_ok?1:0);

   if(causal<=0.0) return 0.0;

   double score=causal;
   if(x.displacement_bar>=x.sweep_bar) score+=5.0;
   if(x.structure_bar>=x.displacement_bar) score+=5.0;
   if(x.rr>=InpSweepEntryMinRR) score+=10.0;

   score+=20.0*AdvancedPathWeight(
      MathMax(1,x.structure_bar-x.sweep_bar+1));

   return MathMin(100.0,score);
}

bool BuildAdvancedSweepCandidate(const int liq_idx,const int sweep_bar,
                                 SSweepCandidate &x)
{
   if(liq_idx<0 || liq_idx>=ArraySize(g_liquidity)) return false;
   if(sweep_bar<0 || sweep_bar>=ArraySize(g_buf_c)) return false;

   SLiquidity pool=g_liquidity[liq_idx];
   if(!pool.swept || pool.availability_time<=0) return false;
   if(pool.availability_time>g_buf_t[sweep_bar]) return false;

   x.liquidity_index=liq_idx;
   x.sweep_bar=sweep_bar;
   x.displacement_bar=-1;
   x.structure_bar=-1;
   x.direction=0;
   x.liquidity_price=pool.price;
   x.entry_price=NormalizePriceToTick(g_buf_c[sweep_bar]);
   x.stop_price=0.0;
   x.target_price=0.0;
   x.rr=0.0;
   x.score=0.0;
   x.structure_strength=0;
   x.structure_type="";

   bool high_pool=(pool.type=="EQH");
   bool low_pool=(pool.type=="EQL");

   if(high_pool)
   {
      if(g_buf_h[sweep_bar]<=pool.price || g_buf_c[sweep_bar]>=pool.price)
         return false;
      x.direction=-1;
      x.stop_price=NormalizePriceToTick(g_buf_h[sweep_bar]);
   }
   else if(low_pool)
   {
      if(g_buf_l[sweep_bar]>=pool.price || g_buf_c[sweep_bar]<=pool.price)
         return false;
      x.direction=1;
      x.stop_price=NormalizePriceToTick(g_buf_l[sweep_bar]);
   }
   else return false;

   // Closed-bar boundary: never inspect the forming bar in candidate ranking.
   int closed_limit=MathMax(0,ArraySize(g_buf_c)-2);
   int last=MathMin(closed_limit,
                    sweep_bar+MathMax(1,InpSweepEntryMaxBarsAfterSweep));

   for(int b=sweep_bar+1;b<=last;b++)
   {
      double atr=(b<ArraySize(g_atr_buf) && g_atr_buf[b]>0.0)
                 ? g_atr_buf[b] : g_atr;
      if(atr<=0.0) continue;

      double body=MathAbs(g_buf_c[b]-g_buf_o[b]);
      if(body<0.50*atr) continue;

      if(x.direction<0 && g_buf_c[b]>=g_buf_o[b]) continue;
      if(x.direction>0 && g_buf_c[b]<=g_buf_o[b]) continue;

      x.displacement_bar=b;
      break;
   }

   if(x.displacement_bar<0) return false;

   // Real structure confirmation is mandatory for the advanced sweep path.
   // The previous implementation assigned structure_bar=displacement_bar,
   // which could score an unconfirmed displacement as a structure break.
   int structure_last=MathMin(closed_limit,
                              sweep_bar+MathMax(1,InpSweepEntryMaxBarsAfterSweep));
   int best_structure=-1;
   int best_strength=-1;
   string best_type="";
   for(int si=0;si<ArraySize(g_structures);si++)
   {
      SStructureBreak st=g_structures[si];
      if(st.type=="INIT") continue;
      if(st.bar<x.displacement_bar || st.bar>structure_last) continue;
      if((x.direction>0 && !st.bullish) || (x.direction<0 && st.bullish)) continue;
      if(InpRequireMSSAfterSweep && st.type!="MSS") continue;
      int type_strength=(st.type=="MSS" ? 30 : (st.type=="CHoCH" ? 20 : 12));
      type_strength+=MathMax(0,20-(st.bar-x.displacement_bar)*4);
      if(type_strength>best_strength ||
         (type_strength==best_strength && (best_structure<0 || st.bar<best_structure)))
      {
         best_structure=st.bar;
         best_strength=type_strength;
         best_type=st.type;
      }
   }
   if(best_structure<0) return false;
   x.structure_bar=best_structure;
   x.structure_strength=MathMax(0,best_strength);
   x.structure_type=best_type;

   double risk=(x.direction>0)
               ? x.entry_price-x.stop_price
               : x.stop_price-x.entry_price;
   if(risk<=InstrumentTickSize()) return false;

   x.target_price=NormalizePriceToTick(
      x.direction>0
      ? x.entry_price+risk*InpSweepEntryMinRR
      : x.entry_price-risk*InpSweepEntryMinRR);

   x.rr=(x.direction>0)
        ? (x.target_price-x.entry_price)/risk
        : (x.entry_price-x.target_price)/risk;

   bool structure_ok=(x.structure_bar>x.displacement_bar && x.structure_strength>0);
   x.score=ScoreSweepCandidate(x,true,structure_ok,false,false);
   return x.score>=InpSweepEntryMinScore;
}

bool GetBestAdvancedSweepCandidate(SSweepCandidate &best)
{
   if(!InpUseAdvancedSweepEngine) return false;

   SSweepCandidate candidates[];
   int count=ArraySize(g_liquidity);

   for(int i=0;i<count;i++)
   {
      if(!g_liquidity[i].swept) continue;
      int bar=g_liquidity[i].bar;
      if(bar<0 || bar>=ArraySize(g_buf_c)) continue;

      SSweepCandidate c;
      if(!BuildAdvancedSweepCandidate(i,bar,c)) continue;

      int n=ArraySize(candidates);
      ArrayResize(candidates,n+1,8);
      candidates[n]=c;
   }

   if(ArraySize(candidates)==0) return false;
   if(InpUseMergeSortRanking) SortSweepCandidates(candidates);

   best=candidates[0];
   return true;
}



//====================================================================
// STRUCTURES
//====================================================================
struct SStructureBreak
{
   int      bar;
   datetime time;
   double   price;
   bool     bullish;
   string   type;
   int      ob_bar;
   int      strength;
   int      priority;
};
struct SOrderBlock
{
   string   id; // STABLE UID
   int      bar;
   datetime time1,time2;
   double   top,bottom;
   bool     bullish;
   bool     mitigated;
   int      strength;
   string   state;
   double   distance_from_price;
   int      age;
   int      origin_struct_bar; // P1-3 Causal origin structure bar
   string   source_displacement_event_id;
   int      source_displacement_bar;
   datetime source_displacement_time;
   string   source_structure_event_id;
   datetime source_structure_time;
   string   closed_state;      // P2 Strictly confirmed closed state (<= total-2)
   string   live_preview;      // P2 Realtime preview state (total-1)
};
struct SFVG
{
   string   id; // stable raw-observation identity
   int      bar;       // compatibility alias: creation_bar
   datetime time1,time2;
   double   top,bottom;
   bool     bullish;
   bool     filled;
   string   state;
   double   mid_price;
   int      creation_bar;
   datetime creation_time;             // occurrence: completion-candle open
   int      availability_bar;           // authoritative closed decision bar
   datetime availability_time;          // actual next-open boundary
   int      source_displacement_bar;
   datetime source_displacement_time;
   string   source_displacement_event_id;
   int      source_structure_bar;
   datetime source_structure_time;
   string   source_structure_event_id;
};
struct SLiquidity
{
   string   id;
   int      bar;       // compatibility alias: availability_bar
   datetime time;      // compatibility alias: origin_time
   int      origin_bar;
   datetime origin_time;
   int      availability_bar;
   datetime availability_time;
   double   price;
   string   type;
   bool     swept;
   int      priority;
   int      parent_pool_bar; // compatibility alias: parent availability bar
   double   parent_level;
   string   parent_pool_id;
   int      parent_pool_origin_bar;
   datetime parent_pool_origin_time;
   int      parent_pool_availability_bar;
   datetime parent_pool_availability_time;
};
struct SKillZone
{
   datetime start,end;
   double   high,low;
   string   name;
   color    col;
};
struct SZone
{
   int      bar;
   datetime time1,time2;
   double   top,bottom;
   bool     bullish;
   string   state;
   int      touches;
   double   strength_score;
};
struct SBreaker
{
   int      bar;
   datetime time1,time2;
   double   top,bottom;
   bool     bullish;
   string   state;
};
struct SSignalFactor
{
   string name;
   int    value;
   int    weight;
   bool   active;
};
struct STradeSetup
{
   bool   valid;
   int    created_bar;
   datetime created_time;
   double zone_top,zone_bottom;
   bool   is_buy;
   double entry,sl,tp1,tp2,tp3;
   int    confidence;
   string reasons[14];
   int    reason_count;
   string blockers[10];
   int    blocker_count;
   int    knapsack_score;
   int    dp_optimal_score;
   int    weighted_score;
   int    reliability;
   string quality_grade;
   string institutional_grade;
   string risk_level;
   double risk_pips;
   double rr1,rr2,rr3;
   string tp1_type,tp2_type,tp3_type;
   string tp_source_event_id[3];
   int    tp_source_bar[3];
   bool   tp_consumed[3];
   bool   tp_barrier_bound[3];
   double immutable_target_barrier;
   string immutable_target_barrier_type;
   string immutable_target_barrier_event_id;
   int    immutable_target_barrier_bar;
   int    max_factor_value;
   int    ob_index; // cached index for rendering (resolved via UID)
   string ob_uid;   // STABLE UID
   double ob_dist_atr;
   string zone_source;
   int    sweep_bar;
   double sweep_price;
   string sweep_event_id;
   string displacement_event_id;
   string structure_event_id;
   string zone_event_id;
   string setup_event_id;
   double causal_path_score;
   double graph_path_cost;
   double graph_path_score;
   string graph_optimizer;
   int    graph_path_hops;
   bool   graph_agreement;
   int    candle_context_score;
   int    evidence_independence_score;
   string market_regime;
   int    prime_proximity_score; // PrimeLevelEngine diagnostic (0-100, low-influence only)
   string prime_nearest_label;
   int    relationship_score;    // InstitutionalRelationshipMatrix diagnostic (0-100)
   string relationship_label;
   string mtf_conflict_label;    // MarketConflictEngine classification label
};
struct SScoreBreakdown
{
   double structure;
   double liquidity;
   double orderblock;
   double fvg;
   double session;
   double htf;
   double algo;
   double candle_context;
   double evidence_independence;
   double regime;
   double prime; // PrimeLevelEngine diagnostic pillar; intentionally NOT weighted into final_score
   double relationship; // InstitutionalRelationshipMatrix diagnostic pillar; NOT weighted into final_score
   double final_score;
};

// v5.6.9: hop-level causal audit. Event gates are existence flags.
// They MUST NOT be OR-ed into causal_valid.
struct SCausalHopReport
{
   bool   sweep_event_ok;
   bool   disp_event_ok;
   bool   mss_event_ok;
   bool   align_ok;
   bool   hop_sweep_disp;
   bool   hop_disp_mss;
   bool   hop_mss_zone;
   bool   causal_valid;
   bool   zone_valid;
   bool   watch;
   int    quality_score;
   int    mtf_align_pct;
   int    sweep_age_bars;
   int    candidate_structure_bar;
   string candidate_structure_type;
   string zone_kind;
   string path_text;
   string hop_sweep_disp_reason;
   string hop_disp_mss_reason;
   string hop_mss_zone_reason;
   string causal_fail_reason;
   // v5.7.0 directional opposite-branch diagnostics. These are advisory
   // until the normal causal + retest lifecycle authorizes a trade.
   bool   opposite_available;
   bool   opposite_sweep_ok;
   bool   opposite_disp_ok;
   bool   opposite_mss_ok;
   bool   opposite_zone_ok;
   bool   opposite_retest_ok;
   bool   opposite_is_buy;
   int    opposite_score;
   int    opposite_structure_bar;
   string opposite_structure_type;
   string opposite_zone_kind;
   string opposite_reason;
   // v5.7.1 primary directional watch: follows the actual HTF/D1 bias,
   // not merely the opposite of the latest local structure. Advisory only.
   bool   directional_watch_available;
   bool   directional_watch_sweep_ok;
   bool   directional_watch_disp_ok;
   bool   directional_watch_mss_ok;
   bool   directional_watch_zone_ok;
   bool   directional_watch_is_buy;
   int    directional_watch_score;
   int    directional_watch_structure_bar;
   string directional_watch_structure_type;
   string directional_watch_zone_kind;
   string directional_watch_reason;
   string decision_state; // WAIT | BUY_WATCH | SELL_WATCH | EARLY | CONFIRMED
   // v5.7.3: recorded hop chain (SWEEP -> DISP -> STRUCT -> ZONE) for the
   // dashboard causal audit line; reset by ResetCausalHopReport().
   int    hop_count;
   string types[MAX_CAUSAL_HOPS];
   string ids[MAX_CAUSAL_HOPS];
   int    event_bars[MAX_CAUSAL_HOPS];
   int    age_bars[MAX_CAUSAL_HOPS];
   double strengths[MAX_CAUSAL_HOPS];
};
struct SActiveSetup
{
   bool     active;
   string   id; // STABLE SETUP ID
   string   state; // READY | RETEST_PREVIEW | RETEST_CONFIRMED | CONFIRMED | INVALID
   bool     is_buy;
   int      created_bar; // for reference only
   datetime created_time; // IMMUTABLE anchor
   double   zone_top, zone_bottom;
   string   ob_uid; // STABLE
   int      ob_index_cache; // resolved each tick
   string   quality_grade;
   string   institutional_grade;
   int      confidence;
   int      reliability;
   double   entry,sl,tp1,tp2,tp3;
   string   tp1_type,tp2_type,tp3_type;
   string   tp_source_event_id[3];
   int      tp_source_bar[3];
   bool     tp_consumed[3];
   bool     tp_barrier_bound[3];
   double   immutable_target_barrier;
   string   immutable_target_barrier_type;
   string   immutable_target_barrier_event_id;
   int      immutable_target_barrier_bar;
   double   rr1,rr2,rr3;
   string   risk_level;
   double   risk_pips;
   string   zone_source;
   int      sweep_bar;
   double   sweep_price;
   string   sweep_event_id;
   string   displacement_event_id;
   string   structure_event_id;
   string   zone_event_id;
   string   setup_event_id;
   double   causal_path_score;
   int      retest_bar;
   datetime retest_time;
   int      confirmed_bar;
   datetime confirmed_time;
   bool     alert_fired;
};
struct SDealingRange
{
   bool     valid;
   int      bar_high,bar_low;
   datetime time_high,time_low;
   double   high,low,eq;
   bool     bullish_leg;
};
struct SGraphNode
{
   string type;
   double price;
   int    strength;
   int    links[MAX_GRAPH_LINKS];
   int    link_count;
   bool   visited;
};
struct STarget
{
   double price;
   int    priority;
   string type;
   int    source_bar;
   int    event_index;
   bool   consumed;
   double score;
};

struct SCausalEvent
{
   string   id;
   ENUM_CAUSAL_EVENT_TYPE type;
   int      event_bar;
   datetime event_time;
   int      availability_bar;
   datetime availability_time;
   bool     bullish;
   double   price;
   double   top;
   double   bottom;
   int      parent_primary;
   int      parent_secondary;
   int      children[MAX_CAUSAL_CHILDREN];
   int      child_count;
   double   strength;
   bool     confirmed;
   bool     invalidated;
   int      age;
   int      source_index;
};

//====================================================================
// COLLECTIONS (chronological masters + index tables)
//====================================================================
SStructureBreak g_structures[];
SOrderBlock     g_order_blocks[];
SFVG            g_fvgs[];
SLiquidity      g_liquidity[];
SKillZone       g_kill_zones[];
SZone           g_zones[];
SBreaker        g_breakers[];
SGraphNode      g_market_graph[]; // legacy proximity graph; flexible mode only
SCausalEvent    g_causal_events[];
int             g_selected_sweep_event=-1;
int             g_selected_displacement_event=-1;
int             g_selected_structure_event=-1;
int             g_selected_zone_event=-1;
datetime        g_htf_last_event_time=0;
datetime        g_htf_last_availability_time=0;
datetime        g_d1_last_event_time=0;
datetime        g_d1_last_availability_time=0;
bool            g_causal_invariants_ok=true;
bool            g_replay_audit_pending=false;
bool            g_replay_equivalence_ok=true;
datetime        g_replay_expected_time=0;
ulong           g_replay_expected_hash=0;
string          g_replay_audit_status="NOT RUN";
STradeSetup     g_trade_setup;
SActiveSetup    g_active_setup;
SDealingRange   g_range;
SScoreBreakdown g_score;
SCausalHopReport g_causal_diag;
// Dashboard diagnostic state (recomputed each closed bar; display only)
string g_directional_watch_text="";
color  g_directional_watch_color=clrDarkGray;
string g_causal_chain_text="";
color  g_causal_chain_color=clrDarkGray;
string g_decision_state="WAIT";      // WAIT | BUY_WATCH | SELL_WATCH | EARLY | CONFIRMED
int g_ob_price_idx[];
int g_ob_strength_idx[];
int g_liq_priority_idx[];
//--- MTF panel (MN/W1/D1/H4/H1): bias per TF from CLOSED HTF candles only
#define MTF_TF_COUNT 5
int      g_mtf_aligned[MTF_TF_COUNT];     // +1 bull, -1 bear, 0 unknown
int      g_mtf_self_index=-1;             // row matching chart TF (if any)
datetime g_mtf_event_time[MTF_TF_COUNT];  // last confirmed HTF structure event
datetime g_mtf_avail_time[MTF_TF_COUNT];  // when that event became known
string   g_mtf_note[MTF_TF_COUNT];        // "EMA200 x" style note per row
int      g_mtf_panel_tick=0;              // per-tick fetch throttle for the panel
//--- blacklist for terminal setups
string g_setup_blacklist[];
datetime g_blacklist_time[];

//====================================================================
// FORWARD DECLARATIONS (100% Signature & Array Compatible)
//====================================================================
string GenerateOBId(const datetime t,const double top,const double bottom,const bool bullish);
string GenerateLiquidityId(const string type,const datetime origin_time,const datetime availability_time,const double price);
string GenerateFVGId(const bool bullish,const datetime displacement_time,const datetime creation_time,
                     const double top,const double bottom);
string GenerateSetupId(const bool is_buy,const datetime ct,const double top,const double bottom);
int FindOBIndexByUID(const string uid);
bool IsBlacklistEntryActive(const datetime entry_time);
bool IsBlacklisted(const string id);
void BlacklistSetup(const string id,const datetime t);
void LogLifecycle(const string msg);
bool IsSameIdeaAsBlacklisted(const bool is_buy, const double zt, const double zb);
void EnforceArrayLimits();
void ReevaluateFVGStateIncremental(SFVG &fvg, const int check_bar, const double &h[], const double &l[]);
void ReevaluateFVGStateFull(SFVG &fvg, const int total, const double &h[], const double &l[]);
bool SweepHasDisplacementOrVolume(const int sweep_bar, const bool is_high, const double level, const double atr, const double &h[], const double &l[], const double &o[], const double &c[], const long &tv[]);
void SmartObjectCleanup(const bool isNewBar);
void PrepareDynamicRedraw();
void RepositionDashboard();
bool GetBestAdvancedSweepCandidate(SSweepCandidate &best);
double FibDPValue(const int n);
double AdvancedPathWeight(const int steps);
double MemoizedCausalPathScore(const int sweep_ok,const int displacement_ok,
                               const int structure_ok,const int anchor_ok,
                               const int retest_ok);
bool BuildAdvancedSweepCandidate(const int liq_idx,const int sweep_bar,
                                 SSweepCandidate &x);
void SortSweepCandidates(SSweepCandidate &a[]);

// v5.6.9 Causal Graph Optimization
struct SCausalPathResult
{
   bool valid;
   bool negative_cycle;
   double cost;
   double score;
   int hops;
   int start_event;
   int target_event;
   string algorithm;
   bool agreement;
   int nodes[16];
};
void ResetCausalPathResult(SCausalPathResult &r);
double CausalEdgeCost(const int from,const int to);
double CausalEdgeSignedWeight(const int from,const int to);
bool RunDijkstraCausalPath(const int start_event,const int target_event,SCausalPathResult &out);
bool RunBellmanFordCausalPath(const int start_event,const int target_event,SCausalPathResult &out);
bool RunBeamCausalPath(const int start_event,const int target_event,SCausalPathResult &out);
bool OptimizeCausalGraphPath(const int start_event,const int target_event,SCausalPathResult &out);
bool ValidateCausalPathAgreement(const SCausalPathResult &a,const SCausalPathResult &b);
int CausalEvidenceDP(SSignalFactor &factors[],const int max_weight);

void RunRuntimeCausalValidation();
bool LoadInstrumentSpec();
double InstrumentTickSize();
double NormalizePriceToTick(const double price);
double InstrumentMinStopDistance();
double InstrumentFreezeDistance();
double NormalizeVolumeToStep(const double requested);
string InstrumentClassName();
void BuildPrimeSieve(const int count);
double PrimeProximityScore(const double price,const double atr,string &nearest_label);
void BuildInstitutionalRelationshipMatrix();
double InstitutionalRelationshipStrength(const ENUM_RELATION_NODE a,const ENUM_RELATION_NODE b);
string RelationNodeName(const ENUM_RELATION_NODE n);
ENUM_MTF_CONFLICT_STATE ClassifyMarketConflict(const bool is_buy,const string structure_type,
                                               string &label_out);
void BuildInstitutionalPatternChecklist(string &out_lines[],int &out_count);
double PipSize();
double OBMid(const int i);
void BuildOBPriceIndex();
void BuildOBStrengthIndex();
void BuildLiquidityPriorityIndex();
void UpdateSignalMask(const int total,const double &c[]);
bool CheckSignalPattern(const int required_mask);
void AddGraphNode(const string type,const double price,const int strength);
void ConnectGraphNodes();
void BuildMarketGraph();
double GraphConfluenceScore(const double price);
string CausalTypeName(const ENUM_CAUSAL_EVENT_TYPE type);
int AddCausalEvent(const string id,const ENUM_CAUSAL_EVENT_TYPE type,const int bar,const datetime tm,
                   const bool bullish,const double price,const double top,const double bottom,
                   const int parent_primary,const int parent_secondary,const double strength,
                   const bool confirmed,const bool invalidated,const int source_index);
void LinkCausalEvents(const int parent,const int child);
void RebuildCausalChildren();
void RollbackCausalGraphToSize(const int size);
int FindCausalEventById(const string id);
int FindCausalEventBySource(const ENUM_CAUSAL_EVENT_TYPE type,const int source_index);
int FindNearestCausalAncestor(const int child,const ENUM_CAUSAL_EVENT_TYPE type,
                              const string exact_event_id="");
int FindParentEventOfType(const int child,const ENUM_CAUSAL_EVENT_TYPE type);
bool IsCausallyConnected(const int ancestor,const int descendant);
bool ValidateDisplacementLeg(const int sweep_bar,const int structure_bar,const bool bullish,
                             const double break_price,const double &o[],const double &h[],
                             const double &l[],const double &c[],int &impulse_bar);
bool ValidateCausalOB(const int ob_index,const int sweep_bar,const int displacement_bar,
                      const int structure_bar,const bool bullish,const double &o[],const double &c[]);
bool ValidateCausalFVG(const int fvg_index,const int sweep_bar,const int structure_bar,
                       const int displacement_bar,const bool bullish,const double &o[],
                       const double &h[],const double &l[],const double &c[]);
void BuildCausalEventGraph(const int total,const double &o[],const double &h[],const double &l[],
                           const double &c[],const datetime &t[]);
void MarkCausalAncestors(const int event_index,bool &keep[]);
void PruneCausalEventGraph(const int max_events);
bool ValidateHTFAvailability(const ENUM_TIMEFRAMES tf,const datetime event_time,
                             const datetime availability_time,string &reason);
bool ValidateCausalGraphInvariants(string &reason);
ulong CausalGraphFingerprint();
void RunCausalGraphChecks(const datetime closed_time);

bool ResolveCausalPath(const int structure_source,int &sweep_event,int &displacement_event,
                       int &structure_event,int &ob_event,int &fvg_event);
double CausalPathScore(const int sweep_event,const int displacement_event,const int structure_event,
                       const int ob_event,const int fvg_event);
int SelectBestStructureAnchor(const int total,const double &c[],int &sweep_event,
                              int &displacement_event,int &structure_event,int &ob_event,int &fvg_event,
                              const int direction_filter=0);
int KnapsackOptimizeSignals(SSignalFactor &factors[],const int max_weight);
int DynamicProgrammingConfidence(SSignalFactor &factors[]);
double ScoreStructure(const int total,const bool is_buy);
double ScoreLiquidity(const bool is_buy,const int anchor_bar=-1);
double ScoreOrderBlock(const int ob_index,const double price,const double atr,const int anchor_bar=-1);
double ScoreFVG(const bool is_buy,const double price,const int anchor_bar=-1);
double ScoreSession();
double ScoreHTF(const bool is_buy);
double ScoreAlgo(const int knap,const int dp,const int max_possible,const double price);
string DetectMarketRegime(const int closed,const double atr);
double RegimeScoreMultiplier(const string regime);
int IndependentEvidenceScore(SSignalFactor &factors[]);
int MaxPossibleValue(SSignalFactor &f[]);
int CalculateReliability(const int conf,const int knap,const int dp,const int maxp);
string CalculateQualityGrade(const int conf,const int reliability);
int GradeRank(const string g);
string GetInstitutionalGrade(const int conf,const int knap,const int dp,const int maxp);
string CalculateRiskLevel(const double entry,const double sl,const double atr,const long spread_pts,double &risk_pips_out);
string BuildConfidenceBar(const int pct,const int cells=10);
int SelectEntryOB(const double price,const bool is_buy,const double atr,const int anchor_bar=-1,const int sweep_bar=-1);
int SelectEntryFVG(const double price,const bool is_buy,const double atr,const int anchor_bar,const int sweep_bar);
int FindAlignedLiquiditySweep(const bool is_buy,const int structure_bar,const int max_bars,double &price_out);
bool IsInstitutionalLocation(const bool is_buy,const double zone_top,const double zone_bottom,const double atr,string &why);
void PushTarget(STarget &arr[],STarget &t);
double GreedyFindBestTarget(const double from,const bool is_buy,const double min_dist,string &type_out);
bool GetClosedCurrentDayHighLow(double &day_high,double &day_low);
double DirectionalRR(const bool is_buy,const double entry,const double sl,const double target);
bool ValidateTargetGeometry(const bool is_buy,const double entry,const double sl,
                            const double tp1,const double tp2,const double tp3);
double NearestOpposingBarrier(const double from,const bool is_buy,string &type_out,
                               string &source_event_id,int &source_bar);
double FindInstitutionalTarget(const double from,const double entry,const double sl,const bool is_buy,
                               const double min_dist,const double min_rr,const int stage,
                               const double hard_barrier,string &type_out,string &source_event_id,
                               int &source_bar,bool &consumed,bool &barrier_bound);
void AddReason(const string r);
void AddBlocker(const string b);
bool CreateSetupBranchTransactional(const string setup_event_id,const int closed,
                                    const datetime decision_time,const bool is_buy,
                                    const double entry,const double zone_top,const double zone_bottom,
                                    const double tp1,const double tp2,const double tp3);
void ResetCausalHopReport();
string GateTxt(const bool ok);
void DashPushWrapped(string &L[],int &ln,const string s,const int width);
int MTFAlignmentPercent();
void DiagnoseDirectionalWatch(const int total,const double &o[],const double &h[],
                              const double &l[],const double &c[]);

void DiagnoseCausalChain(const int total,const double &o[],const double &h[],const double &l[],
                         const double &c[],const datetime &t[]);
void ApplyCausalDecisionState();

void CalculateAITradeSetup(const int total,const double &o[],const double &h[],const double &l[],const double &c[]);

//====================================================================
// v5.6.7 CAUSAL CANDLE INTELLIGENCE
// Closed-bar only. Candle patterns are confirmation evidence, never a
// standalone trade trigger. No future-bar data is read here.
//====================================================================
struct SCandleIntel
{
   bool   valid;
   bool   bullish;
   bool   bearish;
   int    score;
   string pattern;
   double body_ratio;
   double close_location;
};

SCandleIntel AnalyzeClosedCandle(const int closed,const double &o[],const double &h[],
                                 const double &l[],const double &c[],const double atr)
{
   SCandleIntel x;
   x.valid=false; x.bullish=false; x.bearish=false; x.score=0;
   x.pattern="NONE"; x.body_ratio=0.0; x.close_location=0.5;

   if(closed<2 || closed>=ArraySize(o) || closed>=ArraySize(h) ||
      closed>=ArraySize(l) || closed>=ArraySize(c)) return x;

   double range=h[closed]-l[closed];
   if(range<=_Point) return x;
   double body=MathAbs(c[closed]-o[closed]);
   double upper=h[closed]-MathMax(o[closed],c[closed]);
   double lower=MathMin(o[closed],c[closed])-l[closed];
   double prev_body=MathAbs(c[closed-1]-o[closed-1]);
   double prev_range=h[closed-1]-l[closed-1];
   if(prev_range<=_Point) prev_range=range;

   x.body_ratio=body/range;
   x.close_location=(c[closed]-l[closed])/range;
   bool up=(c[closed]>o[closed]);
   bool dn=(c[closed]<o[closed]);
   bool strong_body=(x.body_ratio>=0.55 || (atr>0.0 && body>=0.50*atr));
   bool doji=(x.body_ratio<=0.12);

   // Engulfing: the current closed candle must contain the previous body.
   bool bull_engulf=up && c[closed]>=o[closed-1] && o[closed]<=c[closed-1] &&
                    c[closed]>c[closed-1] && body>=prev_body*0.90;
   bool bear_engulf=dn && o[closed]>=c[closed-1] && c[closed]<=o[closed-1] &&
                    c[closed]<c[closed-1] && body>=prev_body*0.90;

   // Hammer / shooting-star geometry. These are stronger when the close is
   // near the rejection extreme and the body is not excessively large.
   bool hammer=(lower>=body*2.0 && upper<=MathMax(body*0.75,_Point*2.0) &&
                x.close_location>=0.62);
   bool shooting=(upper>=body*2.0 && lower<=MathMax(body*0.75,_Point*2.0) &&
                 x.close_location<=0.38);

   // Three-bar reversal patterns. Only bars [closed-2..closed] are used.
   double b2=MathAbs(c[closed-2]-o[closed-2]);
   double r2=h[closed-2]-l[closed-2];
   bool b2_dn=(c[closed-2]<o[closed-2]);
   bool b2_up=(c[closed-2]>o[closed-2]);
   bool middle_small=(prev_range>_Point && prev_body<=prev_range*0.35);
   bool morning=b2_dn && middle_small && up && strong_body &&
                c[closed]>(o[closed-2]+c[closed-2])*0.5;
   bool evening=b2_up && middle_small && dn && strong_body &&
                c[closed]<(o[closed-2]+c[closed-2])*0.5;

   // Piercing / dark-cloud style rejection.
   bool piercing=(c[closed-1]<o[closed-1] && up &&
                  c[closed]>o[closed-1] && c[closed]<(o[closed-1]+c[closed-1])*0.5);
   bool dark_cloud=(c[closed-1]>o[closed-1] && dn &&
                    c[closed]<o[closed-1] && c[closed]>(o[closed-1]+c[closed-1])*0.5);

   if(bull_engulf){x.pattern="BULLISH_ENGULFING"; x.bullish=true; x.score=85;}
   else if(bear_engulf){x.pattern="BEARISH_ENGULFING"; x.bearish=true; x.score=85;}
   else if(morning){x.pattern="MORNING_STAR"; x.bullish=true; x.score=88;}
   else if(evening){x.pattern="EVENING_STAR"; x.bearish=true; x.score=88;}
   else if(hammer){x.pattern="HAMMER"; x.bullish=true; x.score=72;}
   else if(shooting){x.pattern="SHOOTING_STAR"; x.bearish=true; x.score=72;}
   else if(piercing){x.pattern="PIERCING"; x.bullish=true; x.score=65;}
   else if(dark_cloud){x.pattern="DARK_CLOUD"; x.bearish=true; x.score=65;}
   else if(doji){x.pattern="DOJI"; x.score=30;}
   else
   {
      // No named pattern: still expose candle quality for diagnostics, but
      // do not treat an ordinary candle as reversal evidence.
      if(strong_body && x.close_location>=0.80 && up)
      {x.pattern="BULLISH_DISPLACEMENT_CANDLE"; x.bullish=true; x.score=55;}
      else if(strong_body && x.close_location<=0.20 && dn)
      {x.pattern="BEARISH_DISPLACEMENT_CANDLE"; x.bearish=true; x.score=55;}
   }

   x.valid=(x.score>0);
   return x;
}

bool CandleConfirmsDirection(const SCandleIntel &x,const bool is_buy)
{
   return x.valid && ((is_buy && x.bullish) || (!is_buy && x.bearish));
}
int ContextualCandleScore(const SCandleIntel &candle,const bool is_buy,const double price,
                          const double zone_top,const double zone_bottom,const double atr,
                          const bool sweep_ok,const bool structure_ok,const bool zone_ok,
                          const string regime);
void ManageSetupLifecycle(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool is_new_bar);
void FireSetupAlert(const datetime bar_time);
void FillEMAAndVWAP(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const long &tv[],const bool is_new_bar);
datetime DayAnchor(const datetime t);
datetime LastSundayUTC(const int year,const int month,const int hour);
datetime NthSundayUTC(const int year,const int month,const int nth,const int hour);
bool IsEuropeDSTUTC(const datetime utc);
bool IsUSDSTUTC(const datetime utc);
int BrokerUTCOffsetSecondsAt(const datetime server_time);
datetime ServerToUTC(const datetime server_time);
datetime SessionLocalTime(const datetime server_time,const ENUM_SESSION_ID session_id);
int DateKey(const datetime t);
bool HourInWindow(const int hour,const int start_hour,const int end_hour);
bool IsInSession(const datetime server_time,const ENUM_SESSION_ID session_id);
bool IsInKillZone(const datetime server_time,const ENUM_SESSION_ID session_id);
int ChartEventBarAtTime(const datetime &chart_time[],const int total,const datetime event_time);
int ChartClosedBarAtTime(const datetime &chart_time[],const int total,const datetime availability_time);
void DetectStructure(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false);
int FractalRightBars(const int n);
int PreviewFractalRightBars(const int n);
bool IsPreviewFractalHigh(const double &h[],const int i,const int n,const int total);
bool IsPreviewFractalLow(const double &l[],const int i,const int n,const int total);
//====================================================================
// FAST MTF EXECUTION ENTRY - TACTICAL ONLY
// Does not mutate g_trade_setup.valid or bypass institutional confirmation.
//====================================================================
ENUM_TIMEFRAMES SelectExecutionTF()
{
   if(!InpAutoExecutionTF) return InpExecutionTF;
   int sec=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   if(sec<=PeriodSeconds(PERIOD_M5))  return PERIOD_M1;
   if(sec<=PeriodSeconds(PERIOD_M30)) return PERIOD_M5;
   return PERIOD_M15;
}
void ClearMTFExecutionEntry()
{
   g_mtf_entry_state=""; g_mtf_entry_price=0.0; g_mtf_entry_time=0;
   ObjectDelete(0,PFX+"MTF_ENTRY"); ObjectDelete(0,PFX+"MTF_ENTRY_TX");
}
void UpdateMTFExecutionEntry()
{
   if(!InpUseMTFExecutionEntry){ ClearMTFExecutionEntry(); return; }
   bool have_dir=false,bull=false; double trigger=0.0; datetime trigger_time=0;
   if(g_early_break_structure_idx>=0 && g_early_break_price>0.0 &&
      (g_early_break_status=="EARLY_BREAK" || g_early_break_status=="CLOSE_CONFIRMED"))
   { have_dir=true; bull=g_early_break_bull; trigger=g_early_break_price; trigger_time=g_early_break_structure_time; }
   else if(g_active_setup.active)
   { have_dir=true; bull=g_active_setup.is_buy; trigger=g_active_setup.entry; trigger_time=g_active_setup.created_time; }
   else if(g_htf_bias==1 || g_htf_bias==-1)
   {
      have_dir=true; bull=(g_htf_bias>0);
      for(int i=ArraySize(g_structures)-1;i>=0;i--)
      { if(g_structures[i].type=="INIT" || g_structures[i].bullish!=bull) continue; trigger=g_structures[i].price; trigger_time=g_structures[i].time; break; }
   }
   if(!have_dir || trigger<=0.0){ ClearMTFExecutionEntry(); return; }
   if(InpUseHTFBias && g_htf_bias!=(bull?1:-1)){ ClearMTFExecutionEntry(); return; }
   ENUM_TIMEFRAMES etf=SelectExecutionTF(); g_mtf_entry_tf=etf;
   double atr=g_atr; if(atr<=0.0) atr=MathMax(100.0*_Point,10.0*_Point);
   double maxdist=atr*MathMax(0.1,InpMTFEntryMaxDistanceATR);
   double lh=iHigh(_Symbol,etf,0), ll=iLow(_Symbol,etf,0), lo=iOpen(_Symbol,etf,0), lc=iClose(_Symbol,etf,0);
   double ch=iHigh(_Symbol,etf,1), cl=iLow(_Symbol,etf,1), co=iOpen(_Symbol,etf,1), cc=iClose(_Symbol,etf,1);
   datetime lt=iTime(_Symbol,etf,0), ct=iTime(_Symbol,etf,1);
   if(lt<=0 || ct<=0){ ClearMTFExecutionEntry(); return; }
   double lp=(lc>0.0?lc:(bull?lh:ll));
   if(MathAbs(lp-trigger)>maxdist){ ClearMTFExecutionEntry(); return; }
   bool live_cross=bull ? (lh>=trigger && lc>=lo) : (ll<=trigger && lc<=lo);
   bool closed_confirm=bull ? (ch>=trigger && cc>co && cc>=trigger) : (cl<=trigger && cc<co && cc<=trigger);
   if(trigger_time>0 && ct<trigger_time) return;
   if(!live_cross && !closed_confirm) return;
   string state=closed_confirm?"CONFIRMED":"PREVIEW";
   double ep=closed_confirm?cc:lc; datetime et=closed_confirm?ct:lt;
   string id=StringFormat("%s|%d|%I64d|%s|%.5f",_Symbol,(int)etf,(long)trigger_time,bull?"B":"S",trigger);
   g_mtf_entry_state=state; g_mtf_entry_price=ep; g_mtf_entry_time=et;
   if(InpShowMTFExecutionEntry)
   {
      string line=PFX+"MTF_ENTRY";
      if(ObjectFind(0,line)<0) ObjectCreate(0,line,OBJ_HLINE,0,0,ep);
      ObjectSetDouble(0,line,OBJPROP_PRICE,ep);
      ObjectSetInteger(0,line,OBJPROP_COLOR,closed_confirm?(bull?clrLime:clrTomato):clrAqua);
      ObjectSetInteger(0,line,OBJPROP_STYLE,closed_confirm?STYLE_SOLID:STYLE_DASH);
      ObjectSetInteger(0,line,OBJPROP_WIDTH,2); ObjectSetInteger(0,line,OBJPROP_SELECTABLE,false);
      DrawTextLabel(PFX+"MTF_ENTRY_TX",et,ep,StringFormat("MTF %s ENTRY %s @ %.2f | %s",bull?"BUY":"SELL",state,ep,TFName(etf)),closed_confirm?(bull?clrLime:clrTomato):clrAqua,!bull,9);
   }
   if(InpAlertOnMTFExecutionEntry)
   {
      string key=id+"|"+state;
      if(key!=g_last_mtf_entry_id)
      { g_last_mtf_entry_id=key; Alert(StringFormat("%s %s | MTF %s ENTRY %s @ %.2f | execution %s | institutional confirmation separate",_Symbol,TFName((ENUM_TIMEFRAMES)_Period),bull?"BUY":"SELL",state,ep,TFName(etf))); }
   }
}

void DrawProvisionalFractals(const int total,const datetime &t[],const double &h[],const double &l[]);
void UpdateEarlyBreakPreview(const int total,const datetime &t[],const double &h[],const double &l[],const double &c[]);
void UpdateMTFExecutionEntry();
bool IsFractalHigh(const double &h[],const int i,const int n,const int total);
bool IsFractalLow(const double &l[],const int i,const int n,const int total);
int FindLastBearishOB(const double &o[],const double &c[],const int from,const int lookback);
int FindLastBullishOB(const double &o[],const double &c[],const int from,const int lookback);
void DetectOrderBlocks(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false);
void AddBreakerBlock(const double &h[],const double &l[],const double &c[],const datetime &t[],const int break_bar,const double top,const double bottom,const bool bullish,const int total);
void DetectZones(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false);
void DetectFVG(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false);
void AddOrMergeFVG(SFVG &fvg, const int total, const double &h[], const double &l[]);
void DetectLiquidity(const int total,const double &h[],const double &l[],const double &c[],const double &o[],const long &tv[],const datetime &t[],const bool incremental);
void DetectDealingRange(const int total,const double &h[],const double &l[],const datetime &t[],const bool incremental=false);
bool GetOTEZone(double &ote_top,double &ote_bottom,bool &ote_is_buy);
int ComputeClosedStructureBias(const ENUM_TIMEFRAMES tf,const int lookback,const int fractal_n,
                               double &eq_out,string &state_out,datetime &last_event_time,
                               datetime &last_availability_time);
void ComputeHTFBias();
void DetectJudasSwing(const int total,const datetime &t[],const double &h[],const double &l[],const double &c[]);
void DetectKillZones(const int total,const datetime &t[],const double &h[],const double &l[]);
void DrawZones();
void DrawPremiumDiscount(const int total,const datetime &t[]);
void DrawBreakerZones();
void DrawStructureAndOB();
void DrawFVGZones();
void DrawLiquidityMarkers();
void DrawKillZones();
void DrawQuantumDashboard(const int total,const double &c[]);
string L_Trim(const string s);
void DrawMTFPanel();
void DrawSetupZone(const int total,const datetime &t[]);
void DrawTradeBox();
void DrawTradeLevels(const int total,const datetime &t[]);
void DrawPDHPDL();
void DrawPivotPoints();
void DrawCamarilla();
void DrawSessionHighLow(const int total,const datetime &t[],const double &h[],const double &l[]);
void DrawHLine(const string name,const double price,const color col,const string label,const int width=1);
void DrawTextLabel(const string name,const datetime tm,const double price,const string text,const color col,const bool above,const int font_size=8);
void DrawFibLine(const string name,const datetime t1,const datetime t2,const double price,const color col,const int style=STYLE_DOT,const int width=1);
void DrawZoneBox(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color col,const string label,const int transparency=88);
color GradeColor(const string g);
color PctColor(const int p);
color BlendColor(const color col,const int pct);
string NormText(const string s);
string TFName(const ENUM_TIMEFRAMES tf);
string IntegerToBinary(const int num);
//====================================================================
// HELPERS - Stable IDs & Blacklist
//====================================================================
string GenerateOBId(const datetime t,const double top,const double bottom,const bool bullish)
{
   return StringFormat("OB_%s_%I64d_%s_%s_%s",_Symbol,(long)t,
                       DoubleToString(top,_Digits),DoubleToString(bottom,_Digits),
                       bullish?"B":"S");
}
string GenerateLiquidityId(const string type,const datetime origin_time,const datetime availability_time,const double price)
{
   return StringFormat("LQ_%s_%s_%I64d_%I64d_%s",_Symbol,type,(long)origin_time,
                       (long)availability_time,DoubleToString(price,_Digits));
}
string GenerateFVGId(const bool bullish,const datetime displacement_time,const datetime creation_time,
                     const double top,const double bottom)
{
   // Geometry may later be consolidated, so it is deliberately excluded from
   // identity.  One closed three-candle gap maps to one displacement event.
   return StringFormat("FVG_%s_%s_%I64d_%I64d",_Symbol,bullish?"B":"S",
                       (long)displacement_time,(long)creation_time);
}
string GenerateSetupId(const bool is_buy,const datetime ct,const double top,const double bottom)
{
   // P0.4 Enhanced: normalize to PipSize*0.5 to avoid floating noise, include symbol+TF+dir+time+zone
   double pip=PipSize();
   double step=(pip>0 ? pip*0.5 : _Point);
   double nTop  = (step>0? MathRound(top/step)*step : top);
   double nBottom = (step>0? MathRound(bottom/step)*step : bottom);
   // also include ATR bucket to differentiate ideas on same zone but different volatility regime (optional)
   return StringFormat("SETUP_%s_%s_%s_%I64d_%s_%s",_Symbol,
                       TFName((ENUM_TIMEFRAMES)_Period),is_buy?"BUY":"SELL",(long)ct,
                       DoubleToString(nTop,_Digits),DoubleToString(nBottom,_Digits));
}
int FindOBIndexByUID(const string uid)
{
   if(uid=="") return -1;
   int n=ArraySize(g_order_blocks);
   for(int i=0;i<n;i++) if(g_order_blocks[i].id==uid) return i;
   return -1;
}
// v5.7.3 FIX (A4): expiry evaluation used to count matching bars with a full
// forward scan over chart history per blacklist entry per evaluation
// (O(entries x bars) per setup candidate). The count "bars with time >=
// entry_time" is now resolved with one binary search over the
// chronological time buffer. Semantics are identical, including the
// predates-retained-history rule.
bool IsBlacklistEntryActive(const datetime entry_time)
{
   if(InpBlacklistExpiryBars<=0) return true;
   int closed=g_rates_total-2;
   if(entry_time<=0 || closed<0 || closed>=ArraySize(g_buf_t)) return true;
   // Binary search for the first chronological bar at/after entry_time.
   int lo=0,hi=closed,first=-1;
   while(lo<=hi)
   {
      int mid=lo+(hi-lo)/2;
      if(g_buf_t[mid]>=entry_time){first=mid; hi=mid-1;}
      else lo=mid+1;
   }
   if(first<0)
   {
      // No retained bar is at/after entry_time: active only if the entry
      // timestamp is not older than the retained history.
      return (entry_time<g_buf_t[0] ? false : true);
   }
   int bars=closed-first+1;
   return (bars<=InpBlacklistExpiryBars);
}
bool IsBlacklisted(const string id)
{
   int n=ArraySize(g_setup_blacklist);
   for(int i=0;i<n;i++)
      if(g_setup_blacklist[i]==id && i<ArraySize(g_blacklist_time) &&
         IsBlacklistEntryActive(g_blacklist_time[i])) return true;
   return false;
}
void BlacklistSetup(const string id,const datetime t)
{
   if(id=="" || IsBlacklisted(id)) return;
   int n=ArraySize(g_setup_blacklist);
   ArrayResize(g_setup_blacklist,n+1,32);
   ArrayResize(g_blacklist_time,n+1,32);
   ArrayResize(g_blacklist_zone_center,n+1,32);
   ArrayResize(g_blacklist_zone_type,n+1,32);
   g_setup_blacklist[n]=id;
   g_blacklist_time[n]=t;
   // P0.4 store center/dir for fuzzy same-idea check
   string dir="BUY";
   if(StringFind(id,"_SELL_")>=0) dir="SELL";
   else if(StringFind(id,"_BUY_")>=0) dir="BUY";
   g_blacklist_zone_type[n]=dir;
   double center=0;
   // parse last two prices from id tail: ..._top_bottom
   string parts[]; int cnt=StringSplit(id, (ushort)'_', parts);
   if(cnt>=2)
   {
      double top=StringToDouble(parts[cnt-2]);
      double bot=StringToDouble(parts[cnt-1]);
      if(top>0 && bot>0) center=(top+bot)*0.5;
   }
   g_blacklist_zone_center[n]=center;
   // prune old (>64 keep 32)
   if(n+1>64)
   {
      int keep=32;
      int newSize=n+1-keep;
      string tmp[]; datetime tmpt[]; string tmpT[]; double tmpC[];
      ArrayResize(tmp,newSize,32); ArrayResize(tmpt,newSize,32); ArrayResize(tmpT,newSize,32); ArrayResize(tmpC,newSize,32);
      for(int i=0;i<newSize;i++){ tmp[i]=g_setup_blacklist[i+keep]; tmpt[i]=g_blacklist_time[i+keep]; tmpT[i]=g_blacklist_zone_type[i+keep]; tmpC[i]=g_blacklist_zone_center[i+keep];}
      ArrayResize(g_setup_blacklist,newSize,32); ArrayResize(g_blacklist_time,newSize,32);
      ArrayResize(g_blacklist_zone_type,newSize,32); ArrayResize(g_blacklist_zone_center,newSize,32);
      for(int i=0;i<newSize;i++){ g_setup_blacklist[i]=tmp[i]; g_blacklist_time[i]=tmpt[i]; g_blacklist_zone_type[i]=tmpT[i]; g_blacklist_zone_center[i]=tmpC[i];}
   }
}
//--- v5.4.0 helpers
void LogLifecycle(const string msg)
{
   if(!InpLogLifecycleTransitions) return;
   Print("[Lifecycle] ",msg);
}
bool IsSameIdeaAsBlacklisted(const bool is_buy, const double zt, const double zb)
{
   // P0.4 fuzzy check: same direction + zone center within ATR*0.3 ~ same idea
   int n=ArraySize(g_setup_blacklist);
   if(n==0) return false;
   double center=(zt+zb)*0.5;
   double tol=(g_atr>0? g_atr*0.30 : 8*PipSize());
   string dir=is_buy?"BUY":"SELL";
   for(int i=0;i<n;i++)
   {
      if(i>=ArraySize(g_blacklist_time) ||
         !IsBlacklistEntryActive(g_blacklist_time[i])) continue;
      // quick direction filter via substring
      if(StringFind(g_setup_blacklist[i],dir)<0) continue;
      // compare stored center if available
      if(i<ArraySize(g_blacklist_zone_center))
      {
         if(MathAbs(g_blacklist_zone_center[i]-center)<=tol && g_blacklist_zone_type[i]==dir)
            return true;
      }
      // fallback: try parse center from id? exact match already handled by IsBlacklisted
   }
   return false;
}
void EnforceArrayLimits()
{
   // P1.8 strict caps - delete oldest (chronological 0)
   if(InpMaxStructuresKeep>0 && ArraySize(g_structures)>InpMaxStructuresKeep)
   {
      int excess=ArraySize(g_structures)-InpMaxStructuresKeep;
      for(int i=0;i<ArraySize(g_structures)-excess;i++) g_structures[i]=g_structures[i+excess];
      ArrayResize(g_structures, InpMaxStructuresKeep, 32);
   }
   if(InpMaxLiquidityKeep>0 && ArraySize(g_liquidity)>InpMaxLiquidityKeep)
   {
      // An exact sweep may never survive without its exact pool ancestor.
      // Select newest records backwards, accounting for a sweep+pool pair as
      // one atomic retention unit, then restore chronological order.
      int n=ArraySize(g_liquidity);
      bool keep[]; ArrayResize(keep,n); ArrayInitialize(keep,false);
      int kept=0;
      for(int i=n-1;i>=0 && kept<InpMaxLiquidityKeep;i--)
      {
         if(keep[i]) continue;
         bool is_sweep=(g_liquidity[i].type=="BSL TAKEN" ||
                        g_liquidity[i].type=="SSL TAKEN");
         int parent=-1;
         if(is_sweep && g_liquidity[i].parent_pool_id!="")
            for(int p=0;p<n;p++)
               if(g_liquidity[p].id==g_liquidity[i].parent_pool_id)
               { parent=p; break; }
         int cost=1+((parent>=0 && !keep[parent]) ? 1 : 0);
         if(kept+cost>InpMaxLiquidityKeep) continue;
         keep[i]=true; kept++;
         if(parent>=0 && !keep[parent]){keep[parent]=true; kept++;}
      }
      SLiquidity compact[]; ArrayResize(compact,kept,32);
      int out=0;
      for(int i=0;i<n;i++) if(keep[i]) compact[out++]=g_liquidity[i];
      ArrayResize(g_liquidity,kept,32);
      for(int i=0;i<kept;i++) g_liquidity[i]=compact[i];
      BuildLiquidityPriorityIndex();
   }
   if(InpMaxFVGKeep>0 && ArraySize(g_fvgs)>InpMaxFVGKeep)
   {
      int excess=ArraySize(g_fvgs)-InpMaxFVGKeep;
      for(int i=0;i<ArraySize(g_fvgs)-excess;i++) g_fvgs[i]=g_fvgs[i+excess];
      ArrayResize(g_fvgs, InpMaxFVGKeep, 32);
   }
   if(InpMaxZonesKeep>0 && ArraySize(g_zones)>InpMaxZonesKeep)
   {
      int excess=ArraySize(g_zones)-InpMaxZonesKeep;
      for(int i=0;i<ArraySize(g_zones)-excess;i++) g_zones[i]=g_zones[i+excess];
      ArrayResize(g_zones, InpMaxZonesKeep, 32);
   }
   // OrderBlocks capped via InpMaxStrongOB*2 already, but also enforce absolute
   int obHardCap = MathMax(InpMaxStrongOB*4, 12);
   if(ArraySize(g_order_blocks)>obHardCap)
   {
      BuildOBStrengthIndex();
      // keep strongest obHardCap
      SOrderBlock tmp[]; ArrayResize(tmp, obHardCap, 32);
      for(int i=0;i<obHardCap;i++) tmp[i]=g_order_blocks[g_ob_strength_idx[i]];
      // restore chrono order
      for(int i=1;i<obHardCap;i++){ SOrderBlock key=tmp[i]; int j=i-1; while(j>=0 && tmp[j].bar>key.bar){tmp[j+1]=tmp[j]; j--;} tmp[j+1]=key; }
      ArrayResize(g_order_blocks, obHardCap, 32);
      for(int i=0;i<obHardCap;i++) g_order_blocks[i]=tmp[i];
      BuildOBPriceIndex(); BuildOBStrengthIndex();
   }
}
void ReevaluateFVGStateIncremental(SFVG &fvg, const int check_bar, const double &h[], const double &l[])
{
   if(fvg.filled || fvg.state=="FILLED" || check_bar <= fvg.bar) return;
   if(fvg.bullish)
   {
      if(l[check_bar]<=fvg.bottom){ fvg.filled=true; fvg.state="FILLED"; }
      else if(l[check_bar]<fvg.top){ double fp=(fvg.top-l[check_bar])/(fvg.top-fvg.bottom)*100; if(fp>50) fvg.state="PARTIAL"; }
   }
   else
   {
      if(h[check_bar]>=fvg.top){ fvg.filled=true; fvg.state="FILLED"; }
      else if(h[check_bar]>fvg.bottom){ double fp=(h[check_bar]-fvg.bottom)/(fvg.top-fvg.bottom)*100; if(fp>50) fvg.state="PARTIAL"; }
   }
}

void ReevaluateFVGStateFull(SFVG &fvg, const int total, const double &h[], const double &l[])
{
   if(total<3) return;
   int lastClosed=total-2;
   if(lastClosed<0 || lastClosed>=total) return;
   for(int k=fvg.bar+1;k<=lastClosed;k++)
   {
      ReevaluateFVGStateIncremental(fvg, k, h, l);
      if(fvg.filled) break;
   }
}
bool SweepHasDisplacementOrVolume(const int sweep_bar, const bool is_high, const double level, const double atr, const double &h[], const double &l[], const double &o[], const double &c[], const long &tv[])
{
   // P2.9: sweep must have displacement or relative volume
   if(sweep_bar<0 || sweep_bar>=ArraySize(h)) return false;
   double body=MathAbs(c[sweep_bar]-o[sweep_bar]);
   double range=h[sweep_bar]-l[sweep_bar];
   bool disp = (atr>0 && (body>=atr*0.40 || range>=atr*0.75));
   // volume filter: compare to avg of last 20
   if(!disp && ArraySize(tv)>20)
   {
      long sum=0; int cnt=0;
      for(int k=MathMax(0,sweep_bar-20);k<sweep_bar;k++){ sum+=(long)tv[k]; cnt++; }
      double avg=(cnt>0? (double)sum/cnt : 0);
      if(avg>0 && tv[sweep_bar]>=avg*1.6) disp=true;
   }
   // also require close beyond level (already checked) + wick beyond tolerance
   double beyond = is_high ? (h[sweep_bar]-level) : (level - l[sweep_bar]);
   if(beyond < (atr>0? atr*0.15 : 3*PipSize())) disp=false;
   return disp;
}
void SmartObjectCleanup(const bool isNewBar)
{
   if(!InpSmartObjectManagement) return;

   if(!g_active_setup.active)
   {
      ObjectDelete(0,PFX+"SETUPZONE");
      ObjectDelete(0,PFX+"SETUPZONE_L");
   }

   if(!g_trade_setup.valid)
   {
      ObjectDelete(0,PFX+"ENTRY");
      ObjectDelete(0,PFX+"SL");
      ObjectDelete(0,PFX+"TP1");
      ObjectDelete(0,PFX+"TP2");
      ObjectDelete(0,PFX+"TP3");
      ObjectDelete(0,PFX+"ENTRY_ARROW");
      ObjectDelete(0,PFX+"CONNECT");
      ObjectDelete(0,PFX+"TRADE_BOX_BG");
      for(int i=0;i<10;i++) ObjectDelete(0,PFX+"TBOX_"+IntegerToString(i));
   }
}

void PrepareDynamicRedraw()
{
   // Index-based names become stale after array pruning.  Delete only the
   // dynamic categories, and only on a new bar, then redraw from masters.
   ObjectsDeleteAll(0,PFX+"ZN_");
   ObjectsDeleteAll(0,PFX+"STR_");
   ObjectsDeleteAll(0,PFX+"OB_");
   ObjectsDeleteAll(0,PFX+"BRK_");
   ObjectsDeleteAll(0,PFX+"FVG");
   ObjectsDeleteAll(0,PFX+"LIQ_");
   ObjectsDeleteAll(0,PFX+"KZ_");
   ObjectsDeleteAll(0,PFX+"PREM");
   ObjectsDeleteAll(0,PFX+"DISC");
   ObjectsDeleteAll(0,PFX+"OTE");
   ObjectsDeleteAll(0,PFX+"FIB_");
   ObjectsDeleteAll(0,PFX+"PFR_");
   ObjectDelete(0,PFX+"JUDAS");
}

//====================================================================
// INIT / DEINIT / EVENTS
//====================================================================
int OnInit()
{
   if(!LoadInstrumentSpec())
   {
      Print("[InstrumentAdapter] Invalid symbol specification: ",_Symbol);
      return INIT_FAILED;
   }
   BuildPrimeSieve(MathMax(1,InpPrimeLevelCount));
   BuildInstitutionalRelationshipMatrix();
   Print("[InstrumentAdapter] ",_Symbol,
         " class=",InstrumentClassName(),
         " digits=",g_instrument.digits,
         " point=",DoubleToString(g_instrument.point,g_instrument.digits),
         " tick=",DoubleToString(g_instrument.tick_size,g_instrument.digits),
         " contract=",DoubleToString(g_instrument.contract_size,2),
         " vol=",DoubleToString(g_instrument.volume_min,8),"/",
         DoubleToString(g_instrument.volume_step,8),"/",
         DoubleToString(g_instrument.volume_max,8));

   if(InpEMAFast<1 || InpEMASlow<2 || InpATRPeriod<1 || InpADXPeriod<1 ||
      InpSwingFractalN<1 || InpLiquidityFractalN<1 || InpMaxStrongOB<1 ||
      InpMaxStructuresKeep<1 || InpMaxLiquidityKeep<1 || InpMaxFVGKeep<1 ||
      InpMaxZonesKeep<1 || InpSweepToStructureMaxBars<1 || InpMinRightConfirmBars<1 ||
      InpMaxStopATR<=0.0 || InpMinRR1<=0.0 || InpHTFStructureFractalN<1 ||
      InpMaxCausalEventsKeep<32 || InpAnchorSearchBars<1 || InpCausalDisplacementBodyATR<=0.0 ||
      InpReplayAuditEveryBars<0 || InpEquilibriumBufferATR<0.0 || InpRetestMaxDistanceATR<0.0 || InpSLBufferATR<0.0 ||
      InpAsianStart<0 || InpAsianStart>23 || InpAsianEnd<0 || InpAsianEnd>23 ||
      InpLondonStart<0 || InpLondonStart>23 || InpLondonEnd<0 || InpLondonEnd>23 ||
      InpNewYorkStart<0 || InpNewYorkStart>23 || InpNewYorkEnd<0 || InpNewYorkEnd>23 ||
      InpLondonKillZoneStart<0 || InpLondonKillZoneStart>23 ||
      InpLondonKillZoneEnd<0 || InpLondonKillZoneEnd>23 ||
      InpNewYorkKillZoneStart<0 || InpNewYorkKillZoneStart>23 ||
      InpNewYorkKillZoneEnd<0 || InpNewYorkKillZoneEnd>23 ||
      InpLondonKillZoneStart==InpLondonKillZoneEnd ||
      InpNewYorkKillZoneStart==InpNewYorkKillZoneEnd)
   {
      Print("Invalid Quantum SMC input parameters");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, BufEmaFast, INDICATOR_DATA);
   SetIndexBuffer(1, BufEmaSlow, INDICATOR_DATA);
   SetIndexBuffer(2, BufVWAP, INDICATOR_DATA);
   // enforce chronological (0=oldest) for indicator buffers
   ArraySetAsSeries(BufEmaFast,false);
   ArraySetAsSeries(BufEmaSlow,false);
   ArraySetAsSeries(BufVWAP,false);

   h_ema_fast = iMA(_Symbol, PERIOD_CURRENT, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(_Symbol, PERIOD_CURRENT, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   h_atr = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   h_adx = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);
   h_rsi = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   ENUM_TIMEFRAMES mtf_list[] = {InpMTF1, InpMTF2, InpMTF3, InpMTF4, InpMTF5};
   for(int i=0;i<5;i++)
      h_ema_mtf[i] = iMA(_Symbol, mtf_list[i], InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   if(h_ema_fast==INVALID_HANDLE || h_ema_slow==INVALID_HANDLE ||
      h_atr==INVALID_HANDLE || h_adx==INVALID_HANDLE || h_rsi==INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   for(int i=0;i<5;i++) if(h_ema_mtf[i]==INVALID_HANDLE) Print("MTF handle ",i," failed");

   ArrayResize(g_structures,0,32);
   ArrayResize(g_order_blocks,0,32);
   ArrayResize(g_fvgs,0,32);
   ArrayResize(g_liquidity,0,32);
   ArrayResize(g_kill_zones,0,8);
   ArrayResize(g_zones,0,32);
   ArrayResize(g_breakers,0,8);
   ArrayResize(g_market_graph,0,32);
   ArrayResize(g_causal_events,0,64);
   ArrayResize(g_ob_price_idx,0,32);
   ArrayResize(g_ob_strength_idx,0,32);
   ArrayResize(g_liq_priority_idx,0,32);
   ArrayResize(g_setup_blacklist,0,32);
   ArrayResize(g_blacklist_time,0,32);
   ArrayResize(g_blacklist_zone_center,0,32);
   ArrayResize(g_blacklist_zone_type,0,32);
   ArrayResize(g_buf_o,0,32); ArrayResize(g_buf_h,0,32); ArrayResize(g_buf_l,0,32); ArrayResize(g_buf_c,0,32);
   ArrayResize(g_buf_t,0,32); ArrayResize(g_buf_tv,0,32);
   ArrayResize(g_atr_buf,0,32); ArrayResize(g_adx_buf,0,32); ArrayResize(g_rsi_buf,0,32);
   g_last_rates_total=0; g_needs_full_rebuild=true;

   g_trade_setup.valid=false; g_trade_setup.ob_uid=""; g_trade_setup.ob_index=-1;
   g_active_setup.active=false; g_active_setup.state="NONE"; g_active_setup.id="";
   g_active_setup.created_bar=-1; g_active_setup.retest_bar=-1; g_active_setup.confirmed_bar=-1; g_active_setup.alert_fired=false;
   g_active_setup.ob_uid=""; g_active_setup.ob_index_cache=-1;
   g_active_setup.sweep_event_id=""; g_active_setup.displacement_event_id="";
   g_active_setup.structure_event_id=""; g_active_setup.zone_event_id="";
   g_active_setup.setup_event_id="";
   g_active_setup.immutable_target_barrier=0.0;
   g_active_setup.immutable_target_barrier_type="";
   g_active_setup.immutable_target_barrier_event_id="";
   g_active_setup.immutable_target_barrier_bar=-1;
   for(int ti=0;ti<3;ti++)
   {
      g_active_setup.tp_source_event_id[ti]="";
      g_active_setup.tp_source_bar[ti]=-1;
      g_active_setup.tp_consumed[ti]=false;
      g_active_setup.tp_barrier_bound[ti]=false;
   }
   g_range.valid=false;
   g_dash_lines=0;
   g_signal_count=0;
   g_is_backtest = (MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_VISUAL_MODE));
   g_cum_pv=0; g_cum_v=0; g_vwap_anchor=0;
   g_committed_pv=0; g_committed_v=0; g_cur_bar_pv=0; g_cur_bar_v=0; g_cur_bar_time=0;
   g_struct_last_high=0; g_struct_last_low=0; g_struct_trend=0;
   g_struct_last_processed_bar=-1; g_struct_last_break_bar=-1;
   g_last_ob_struct_time=0;
   g_d1_cache_time=0; g_htf_cache_time=0; g_last_confirmed_alert_id=""; g_last_entry_preview_id="";
   g_htf_structure_state="NEUTRAL"; g_d1_structure_state="NEUTRAL";
   g_htf_last_event_time=0; g_htf_last_availability_time=0;
   g_d1_last_event_time=0; g_d1_last_availability_time=0;
   g_selected_sweep_event=g_selected_displacement_event=-1;
   g_selected_structure_event=g_selected_zone_event=-1;
   g_causal_invariants_ok=true;
   g_replay_audit_pending=false;
   g_replay_equivalence_ok=true;
   g_replay_expected_time=0;
   g_replay_expected_hash=0;
   g_replay_audit_status="NOT RUN";
   ResetCausalHopReport();

   Print("======================================================");
   Print(" Quantum SMC AI v5.7.3 AUDITED BUILD");
   Print("======================================================");
   Print(" Symbol: ",_Symbol," | Digits: ",(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   Print(" Point: ",DoubleToString(_Point,5)," | PipSize: ",DoubleToString(PipSize(),5));
   Print(" Mode: ",g_is_backtest ? "BACKTEST" : "LIVE TRADING");
   Print("------------------------------------------------------");
   Print(" LATENCY SETTINGS:");
   Print(" - Swing Fractal N: ",InpSwingFractalN);
   Print(" - Liquidity Fractal N: ",InpLiquidityFractalN);
   Print(" - Displacement ATR: ",DoubleToString(InpDisplacementATR,2));
   Print(" - Confirmed fractal: symmetric ",InpSwingFractalN,"L/",InpSwingFractalN,"R");
   Print(" - Preview-only right bars: ",PreviewFractalRightBars(InpSwingFractalN),
         " (never used by Structure/Liquidity/Range)");
   Print(" - HTF structure fractal N: ",InpHTFStructureFractalN,
         " | D1 agreement: ",InpRequireD1StructureAgreement?"YES":"NO");
   Print(" - Causal graph: max ",InpMaxCausalEventsKeep," | anchor search ",InpAnchorSearchBars," bars");
   Print(" - Session clock: local market time + DST | broker winter UTC minutes ",
         InpBrokerUTCOffsetWinterMinutes," | rule ",EnumToString(InpBrokerDSTRule));
   Print(" - Independent KZ windows: London ",InpLondonKillZoneStart,"-",InpLondonKillZoneEnd,
         " local | New York ",InpNewYorkKillZoneStart,"-",InpNewYorkKillZoneEnd," local");
   Print(" - RealTime Zones: ",InpRealTimeZones ? "ON (Tick)" : "OFF (Confirmed)");
   Print(" - Update Every Tick: ",InpUpdateEveryTick ? "YES" : "NO (Bar Close)");
   Print(" - Incremental: ", InpUseIncrementalDetection ? "ON" : "OFF");
   Print(" - Caps: Struct ",InpMaxStructuresKeep," Liq ",InpMaxLiquidityKeep," FVG ",InpMaxFVGKeep," Zones ",InpMaxZonesKeep);
   Print(" - RetestTimeout: ",InpRetestTimeoutBars," bars / ",DoubleToString(InpRetestMaxDistanceATR,1)," ATR");
   Print(" - Institutional sequence: ",InpInstitutionalSequence?"ON":"OFF");
   Print(" - Mandatory: sweep=",InpRequireLiquiditySweep," MSS=",InpRequireMSSAfterSweep,
         " zone=",InpRequireInstitutionalZone," discount/premium=",InpBlockEquilibriumEntries);
   Print("======================================================");
   if(InpRealTimeZones)
      Print(">>> REALTIME MODE ACTIVE: zones/signals on closed bars only; RETEST allowed live.");
   Print(">>> v5.7.3 audit: scoring pipeline order fixed; TP tracking; binary blacklist; gated prune logs");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   IndicatorRelease(h_ema_fast); IndicatorRelease(h_ema_slow);
   IndicatorRelease(h_atr); IndicatorRelease(h_adx); IndicatorRelease(h_rsi);
   for(int i=0;i<5;i++) IndicatorRelease(h_ema_mtf[i]);
   // A deinitialized indicator must never leave owned chart objects behind.
   ObjectsDeleteAll(0,PFX);
   Print("=========================================");
   Print(" Quantum SMC v5.7.3 Stopped");
   Print(" Total Signals Generated: ",g_signal_count);
   Print("=========================================");
}
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      if(InpShowAIDashboard) RepositionDashboard();
      ChartRedraw(0);
   }
   if(id==CHARTEVENT_CUSTOM)
   {
      g_last_bar_time=0;
      if(InpShowDebugAlerts) Print(">>> Custom event triggered - Will recalculate on next tick");
   }
}
void RepositionDashboard()
{
   int chart_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   if(chart_w<=0) return;
   int bg_x=chart_w - InpPanelRightPad - g_dash_width;
   if(bg_x<5) bg_x=5;
   int txt_x=bg_x+8;
   string bg=PFX+"DASH_BG";
   if(ObjectFind(0,bg)>=0) ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,bg_x);
   for(int i=0;i<g_dash_lines;i++)
   {
      string name=PFX+"DASH_"+IntegerToString(i);
      if(ObjectFind(0,name)>=0) ObjectSetInteger(0,name,OBJPROP_XDISTANCE,txt_x);
   }
   for(int k=0;k<5;k++)
   {
      string lname=PFX+"DASH_LEG"+IntegerToString(k);
      if(ObjectFind(0,lname)>=0) ObjectSetInteger(0,lname,OBJPROP_XDISTANCE,txt_x);
   }
}

//====================================================================
// MAIN - OnCalculate with chronological enforcement & delta rendering
//====================================================================
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   g_oncalc_seq++;
   // v5.7.3 PERF: instrument metadata is immutable per chart symbol; load it
   // once (and on symbol change) instead of on every tick.
   if(InpUniversalInstrumentMode)
   {
      static string g_instrument_loaded_for="";
      if(g_instrument_loaded_for!=_Symbol)
      {
         LoadInstrumentSpec();
         g_instrument_loaded_for=_Symbol;
      }
   }

   if(rates_total<3) return 0;
   if(rates_total<InpEMASlow+50) return 0;

   bool is_series=ArrayGetAsSeries(time);
   datetime cur=is_series ? time[0] : time[rates_total-1];
   bool is_new_bar=(g_last_bar_time==0 || cur!=g_last_bar_time);

   // Keep the shared execution-context globals truthful even when the tick
   // body is skipped: dashboards and risk labels read them between ticks.
   g_rates_total=rates_total;
   int closed_src_early=is_series ? 1 : rates_total-2;
   g_spread=(closed_src_early>=0 && closed_src_early<ArraySize(spread)) ?
            (long)MathMax(0,spread[closed_src_early]) : 0;

   if(!is_new_bar && prev_calculated>0 && !InpUpdateEveryTick)
      return rates_total;

   // Quality and setup gates consume the canonical closed bar's recorded
   // spread, never the mutable live SymbolInfo spread.
   int closed_src=closed_src_early;
   g_spread=(closed_src>=0 && closed_src<ArraySize(spread)) ?
            (long)MathMax(0,spread[closed_src]) : 0;

   bool needResize=(ArraySize(g_buf_o)!=rates_total);
   bool first_run=(prev_calculated==0 || g_last_rates_total==0 || g_needs_full_rebuild);
   bool useIncremental=(InpUseIncrementalDetection && !first_run && is_new_bar &&
                        rates_total==g_last_rates_total+1);
   bool intra_tick=(!is_new_bar && prev_calculated>0 && rates_total==g_last_rates_total);
   bool full_detection=(is_new_bar && !useIncremental);
   bool detection_updated=false;

   if(needResize)
   {
      ArrayResize(g_buf_o,rates_total,64);
      ArrayResize(g_buf_h,rates_total,64);
      ArrayResize(g_buf_l,rates_total,64);
      ArrayResize(g_buf_c,rates_total,64);
      ArrayResize(g_buf_t,rates_total,64);
      ArrayResize(g_buf_tv,rates_total,64);
      ArrayResize(g_atr_buf,rates_total,64);
      ArrayResize(g_adx_buf,rates_total,64);
      ArrayResize(g_rsi_buf,rates_total,64);
   }

   // Canonical arrays are always chronological: zero is oldest, total-1 is live.
   if(intra_tick && !needResize)
   {
      int k=rates_total-1;
      int src=is_series ? 0 : k;
      g_buf_o[k]=open[src]; g_buf_h[k]=high[src]; g_buf_l[k]=low[src]; g_buf_c[k]=close[src];
      g_buf_t[k]=time[src]; g_buf_tv[k]=tick_volume[src];
   }
   else if(useIncremental)
   {
      for(int k=MathMax(0,rates_total-3);k<rates_total;k++)
      {
         int src=is_series ? rates_total-1-k : k;
         g_buf_o[k]=open[src]; g_buf_h[k]=high[src]; g_buf_l[k]=low[src]; g_buf_c[k]=close[src];
         g_buf_t[k]=time[src]; g_buf_tv[k]=tick_volume[src];
      }
   }
   else
   {
      for(int k=0;k<rates_total;k++)
      {
         int src=is_series ? rates_total-1-k : k;
         g_buf_o[k]=open[src]; g_buf_h[k]=high[src]; g_buf_l[k]=low[src]; g_buf_c[k]=close[src];
         g_buf_t[k]=time[src]; g_buf_tv[k]=tick_volume[src];
      }
   }

   // Indicator data: full history only for a rebuild; otherwise copy the live tail.
   bool full_indicators=(first_run || full_detection);
   if(full_indicators)
   {
      int na=CopyBuffer(h_atr,0,0,rates_total,g_atr_buf);
      int nd=CopyBuffer(h_adx,0,0,rates_total,g_adx_buf);
      CopyBuffer(h_rsi,0,0,rates_total,g_rsi_buf);
      if(na<=0 || nd<=0) return prev_calculated;
   }
   else
   {
      int count=MathMin(3,rates_total);
      double ta[],td[],tr[];
      if(CopyBuffer(h_atr,0,0,count,ta)==count)
         for(int k=0;k<count;k++) g_atr_buf[rates_total-count+k]=ta[k];
      if(CopyBuffer(h_adx,0,0,count,td)==count)
         for(int k=0;k<count;k++) g_adx_buf[rates_total-count+k]=td[k];
      if(CopyBuffer(h_rsi,0,0,count,tr)==count)
         for(int k=0;k<count;k++) g_rsi_buf[rates_total-count+k]=tr[k];
   }

   // v5.7.3 FIX (A7): the new-bar identity is committed only after indicator
   // data is known to be available. Previously a failed CopyBuffer on the
   // first tick of a new bar consumed is_new_bar and silently skipped that
   // bar's closed-bar detection until the NEXT bar closed.
   if(is_new_bar) g_last_bar_time=cur;

   int closed=rates_total-2;
   // Trading decisions use the last CLOSED ATR/ADX, never the forming values.
   g_atr=(closed>=0 && closed<ArraySize(g_atr_buf)) ? g_atr_buf[closed] : 0.0;
   g_adx=(closed>=0 && closed<ArraySize(g_adx_buf)) ? g_adx_buf[closed] : 0.0;

   FillEMAAndVWAP(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,g_buf_tv,full_indicators);

   if(useIncremental)
   {
      // Closed-state transitions are processed once for the newly closed candle.
      for(int i=0;i<ArraySize(g_fvgs);i++)
         ReevaluateFVGStateIncremental(g_fvgs[i],closed,g_buf_h,g_buf_l);

      for(int i=0;i<ArraySize(g_order_blocks);i++)
      {
         if(g_order_blocks[i].state=="MITIGATED") continue;
         bool bull=g_order_blocks[i].bullish;
         bool overlap=(g_buf_l[closed]<=g_order_blocks[i].top &&
                       g_buf_h[closed]>=g_order_blocks[i].bottom);
         if(overlap)
         {
            g_order_blocks[i].state="TOUCHED";
            g_order_blocks[i].closed_state="TOUCHED";
         }
         if(bull && g_buf_c[closed]<g_order_blocks[i].bottom)
         {
            AddBreakerBlock(g_buf_h,g_buf_l,g_buf_c,g_buf_t,closed,
                            g_order_blocks[i].top,g_order_blocks[i].bottom,false,rates_total);
            g_order_blocks[i].mitigated=true;
            g_order_blocks[i].state="MITIGATED";
            g_order_blocks[i].closed_state="MITIGATED";
         }
         if(!bull && g_buf_c[closed]>g_order_blocks[i].top)
         {
            AddBreakerBlock(g_buf_h,g_buf_l,g_buf_c,g_buf_t,closed,
                            g_order_blocks[i].top,g_order_blocks[i].bottom,true,rates_total);
            g_order_blocks[i].mitigated=true;
            g_order_blocks[i].state="MITIGATED";
            g_order_blocks[i].closed_state="MITIGATED";
         }
      }

      for(int i=0;i<ArraySize(g_zones);i++)
      {
         if(g_zones[i].state=="MITIGATED") continue;
         bool overlap=(g_buf_l[closed]<=g_zones[i].top && g_buf_h[closed]>=g_zones[i].bottom);
         if(overlap){g_zones[i].touches++; g_zones[i].state="MITIGATION";}
         if(g_zones[i].bullish && g_buf_c[closed]<g_zones[i].bottom) g_zones[i].state="MITIGATED";
         if(!g_zones[i].bullish && g_buf_c[closed]>g_zones[i].top) g_zones[i].state="MITIGATED";
      }

      DetectStructure(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,true);
      DetectLiquidity(rates_total,g_buf_h,g_buf_l,g_buf_c,g_buf_o,g_buf_tv,g_buf_t,true);
      DetectOrderBlocks(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,true);
      DetectZones(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,true);
      DetectFVG(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,true);
      DetectDealingRange(rates_total,g_buf_h,g_buf_l,g_buf_t,true);
      ComputeHTFBias();
      if(InpDetectJudas) DetectJudasSwing(rates_total,g_buf_t,g_buf_h,g_buf_l,g_buf_c);
      if(InpShowKillZones) DetectKillZones(rates_total,g_buf_t,g_buf_h,g_buf_l);

      BuildOBPriceIndex();
      BuildOBStrengthIndex();
      BuildLiquidityPriorityIndex();
      EnforceArrayLimits();
      UpdateSignalMask(rates_total,g_buf_c);
      BuildCausalEventGraph(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t);
      if(InpUseGraphTheory && !InpInstitutionalSequence) BuildMarketGraph();
      detection_updated=true;
      LogLifecycle(StringFormat("Incremental closed=%d struct=%d OB=%d FVG=%d LQ=%d",
                   closed,ArraySize(g_structures),ArraySize(g_order_blocks),ArraySize(g_fvgs),ArraySize(g_liquidity)));
   }
   else if(full_detection || first_run)
   {
      ArrayResize(g_structures,0,32);
      ArrayResize(g_order_blocks,0,32);
      ArrayResize(g_fvgs,0,32);
      ArrayResize(g_liquidity,0,32);
      ArrayResize(g_kill_zones,0,8);
      ArrayResize(g_zones,0,32);
      ArrayResize(g_breakers,0,8);
      ArrayResize(g_market_graph,0,32);
      ArrayResize(g_ob_price_idx,0,32);
      ArrayResize(g_ob_strength_idx,0,32);
      ArrayResize(g_liq_priority_idx,0,32);
      g_signal_mask=0;
      g_last_ob_struct_time=0;

      DetectStructure(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,false);
      DetectLiquidity(rates_total,g_buf_h,g_buf_l,g_buf_c,g_buf_o,g_buf_tv,g_buf_t,false);
      DetectOrderBlocks(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,false);
      BuildOBPriceIndex();
      BuildOBStrengthIndex();
      DetectZones(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,false);
      DetectFVG(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,false);
      BuildLiquidityPriorityIndex();
      DetectDealingRange(rates_total,g_buf_h,g_buf_l,g_buf_t,false);
      ComputeHTFBias();
      if(InpDetectJudas) DetectJudasSwing(rates_total,g_buf_t,g_buf_h,g_buf_l,g_buf_c);
      if(InpShowKillZones) DetectKillZones(rates_total,g_buf_t,g_buf_h,g_buf_l);
      EnforceArrayLimits();
      BuildOBPriceIndex();
      BuildOBStrengthIndex();
      BuildLiquidityPriorityIndex();
      UpdateSignalMask(rates_total,g_buf_c);
      BuildCausalEventGraph(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t);
      if(InpUseGraphTheory && !InpInstitutionalSequence) BuildMarketGraph();
      detection_updated=true;
      g_needs_full_rebuild=false;
   }

   // Complete a pending same-bar replay comparison before any decision can
   // consume a graph that differs from the incremental result.
   if(g_replay_audit_pending && first_run)
   {
      if(g_replay_expected_time==g_buf_t[closed])
      {
         ulong rebuilt_hash=CausalGraphFingerprint();
         if(rebuilt_hash!=g_replay_expected_hash)
         {
            g_replay_equivalence_ok=false;
            g_causal_invariants_ok=false;
            g_replay_audit_status="MISMATCH";
            Print("[CausalReplay] FAIL ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period),
                  " incremental/full mismatch @ ",TimeToString(g_buf_t[closed]));
         }
         else
         {
            g_replay_audit_status="PASS";
            Print("[CausalReplay] PASS ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period),
                  " @ ",TimeToString(g_buf_t[closed]));
         }
      }
      else
         g_replay_audit_status="SKIPPED (no same-bar tick)";
      g_replay_audit_pending=false;
   }

   g_last_rates_total=rates_total;

   // Existing immutable setups get first ownership of the newly closed bar.
   // This prevents a recalculated candidate from replacing the very retest
   // candle that should confirm or invalidate the previous setup.
   bool had_active=g_active_setup.active;
   if(!had_active && InpUseRetestLifecycle && is_new_bar)
      g_trade_setup.valid=false;
   if(had_active)
      ManageSetupLifecycle(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,is_new_bar);

   if(detection_updated &&
      (!InpUseRetestLifecycle || (!g_active_setup.active && !g_trade_setup.valid)))
      CalculateAITradeSetup(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c);

   // A setup seeded above may use only the forming candle as a RETEST preview.
   if(!had_active && g_active_setup.active)
      ManageSetupLifecycle(rates_total,g_buf_o,g_buf_h,g_buf_l,g_buf_c,g_buf_t,is_new_bar);

   // Periodically snapshot the incremental market-event graph and force a
   // same-bar full replay on the next tick.
   if(InpEnableCausalInvariantChecks && InpReplayAuditEveryBars>0 && useIncremental &&
      detection_updated && !g_replay_audit_pending &&
      (closed%InpReplayAuditEveryBars)==0)
   {
      g_replay_expected_time=g_buf_t[closed];
      g_replay_expected_hash=CausalGraphFingerprint();
      g_replay_audit_pending=true;
      g_replay_audit_status="PENDING FULL REPLAY";
      g_needs_full_rebuild=true;
   }

   if(InpSmartObjectManagement) SmartObjectCleanup(is_new_bar);

   bool needs_full_redraw=(is_new_bar || prev_calculated==0);
   if(needs_full_redraw)
   {
      if(InpSmartObjectManagement) PrepareDynamicRedraw();
      else ObjectsDeleteAll(0,PFX);

      if(InpShowPremiumDiscount || InpShowFibonacci || InpShowOTE)
         DrawPremiumDiscount(rates_total,g_buf_t);
      DrawZones();
      DrawStructureAndOB();
      if(InpShowBreakers) DrawBreakerZones();
      DrawFVGZones();
      DrawLiquidityMarkers();
      DrawProvisionalFractals(rates_total,g_buf_t,g_buf_h,g_buf_l);
      if(InpShowKillZones) DrawKillZones();
      if(InpDetectJudas && g_judas!=0)
         DrawTextLabel(PFX+"JUDAS",g_buf_t[g_judas_bar],
                       g_judas==1 ? g_buf_l[g_judas_bar] : g_buf_h[g_judas_bar],
                       g_judas==1 ? "JUDAS UP" : "JUDAS DN",
                       g_judas==1 ? clrLime : clrRed,g_judas!=1,9);
      if(InpShowPDHPDL) DrawPDHPDL();
      if(InpShowPivots) DrawPivotPoints();
      if(InpShowCamarilla) DrawCamarilla();
      if(InpShowSessionHL) DrawSessionHighLow(rates_total,g_buf_t,g_buf_h,g_buf_l);
   }

   // Live preview is evaluated on every tick. It is visual only and never
   // mutates confirmed structure, causal events, or trade validity.
   UpdateEarlyBreakPreview(rates_total,g_buf_t,g_buf_h,g_buf_l,g_buf_c);
   UpdateMTFExecutionEntry();

   if(InpShowAIDashboard) DrawQuantumDashboard(rates_total,g_buf_c);
   if(InpShowMTFPanel) DrawMTFPanel();

   if(InpUseRetestLifecycle && g_active_setup.active &&
      (g_active_setup.state=="READY" || g_active_setup.state=="RETEST_PREVIEW" ||
       g_active_setup.state=="RETEST_CONFIRMED"))
   {
      if(needs_full_redraw) DrawSetupZone(rates_total,g_buf_t);
      else
      {
         string name=PFX+"SETUPZONE";
         if(ObjectFind(0,name)>=0)
         {
            datetime t2=g_buf_t[rates_total-1]+(datetime)(PeriodSeconds()*15);
            ObjectMove(0,name,1,t2,g_active_setup.zone_bottom);
         }
      }
   }

   // Explicit live entry marker: visually distinct from the authoritative
   // CONFIRMED trade signal and tied to the immutable setup entry price.
   if(InpShowEntryPreview && InpUseRetestLifecycle && g_active_setup.active &&
      g_active_setup.state=="RETEST_PREVIEW")
   {
      string epname=PFX+"ENTRY_PREVIEW";
      double ep=g_active_setup.entry;
      if(ObjectFind(0,epname)<0)
         ObjectCreate(0,epname,OBJ_HLINE,0,0,ep);
      ObjectSetDouble(0,epname,OBJPROP_PRICE,ep);
      ObjectSetInteger(0,epname,OBJPROP_COLOR,clrAqua);
      ObjectSetInteger(0,epname,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetInteger(0,epname,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,epname,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,epname,OBJPROP_BACK,true);
   }
   else
   {
      string epname=PFX+"ENTRY_PREVIEW";
      if(ObjectFind(0,epname)>=0) ObjectDelete(0,epname);
   }

   if(InpShowTradeBox && g_trade_setup.valid) DrawTradeBox();
   if(InpDrawTradeLevels && g_trade_setup.valid) DrawTradeLevels(rates_total,g_buf_t);
   FireSetupAlert(cur);
   RunRuntimeCausalValidation();
   return rates_total;
}

//====================================================================
//====================================================================
// RUNTIME CAUSAL VALIDATION
// Lightweight post-calculation integrity check.
// This function is intentionally observational: it never creates,
// modifies, or invalidates a trade setup.
//====================================================================
void RunRuntimeCausalValidation()
{
   // Validate only the current finalized setup state.
   // Keep this side-effect free so runtime diagnostics cannot alter
   // signal generation or introduce look-ahead behavior.
   if(!g_trade_setup.valid)
      return;

   if(!MathIsValidNumber(g_trade_setup.entry) ||
      !MathIsValidNumber(g_trade_setup.sl) ||
      !MathIsValidNumber(g_trade_setup.tp1) ||
      !MathIsValidNumber(g_trade_setup.tp2) ||
      !MathIsValidNumber(g_trade_setup.tp3))
      return;

   // Basic directional price sanity. STradeSetup uses is_buy + tp1/tp2/tp3.
   if(g_trade_setup.is_buy)
   {
      if(g_trade_setup.sl>=g_trade_setup.entry ||
         g_trade_setup.tp1<=g_trade_setup.entry)
         return;
   }
   else
   {
      if(g_trade_setup.sl<=g_trade_setup.entry ||
         g_trade_setup.tp1>=g_trade_setup.entry)
         return;
   }
}

//====================================================================
// SYMBOL-AWARE PIP SIZE
//====================================================================
double PipSize()
{
   // Forex retains conventional pip semantics for 3/5 digit quotes.
   // All other instruments use broker/exchange tick size as the atomic price unit.
   if(g_instrument.valid && g_instrument.is_forex)
   {
      int d=g_instrument.digits;
      if(d==5 || d==3)
         return g_instrument.point*10.0;
   }

   return InstrumentTickSize();
}

//====================================================================
// ALGORITHMS
//====================================================================
double OBMid(const int i)
{
   if(i<0 || i>=ArraySize(g_order_blocks)) return 0;
   return (g_order_blocks[i].top + g_order_blocks[i].bottom)*0.5;
}
void BuildOBPriceIndex()
{
   int n=ArraySize(g_order_blocks);
   ArrayResize(g_ob_price_idx,n,32);
   for(int i=0;i<n;i++) g_ob_price_idx[i]=i;
   for(int i=1;i<n;i++)
   {
      int key=g_ob_price_idx[i];
      double kp=OBMid(key);
      int j=i-1;
      while(j>=0 && OBMid(g_ob_price_idx[j])>kp)
      { g_ob_price_idx[j+1]=g_ob_price_idx[j]; j--; }
      g_ob_price_idx[j+1]=key;
   }
}
void BuildOBStrengthIndex()
{
   int n=ArraySize(g_order_blocks);
   ArrayResize(g_ob_strength_idx,n,32);
   for(int i=0;i<n;i++) g_ob_strength_idx[i]=i;
   // insertion sort descending strength, stable - does not mutate master
   for(int i=1;i<n;i++)
   {
      int key=g_ob_strength_idx[i];
      int ks=g_order_blocks[key].strength;
      int j=i-1;
      while(j>=0 && g_order_blocks[g_ob_strength_idx[j]].strength < ks)
      { g_ob_strength_idx[j+1]=g_ob_strength_idx[j]; j--; }
      g_ob_strength_idx[j+1]=key;
   }
}
void BuildLiquidityPriorityIndex()
{
   int n=ArraySize(g_liquidity);
   ArrayResize(g_liq_priority_idx,n,32);
   for(int i=0;i<n;i++) g_liq_priority_idx[i]=i;
   // assign priorities
   for(int i=0;i<n;i++)
   {
      if(g_liquidity[i].swept && StringFind(g_liquidity[i].type,"TAKEN")>=0) g_liquidity[i].priority=10;
      else if(g_liquidity[i].swept) g_liquidity[i].priority=2;
      else if(g_liquidity[i].type=="EQH" || g_liquidity[i].type=="EQL") g_liquidity[i].priority=5;
      else g_liquidity[i].priority=1;
   }
   // sort index by priority descending
   for(int i=1;i<n;i++)
   {
      int key=g_liq_priority_idx[i];
      int kp=g_liquidity[key].priority;
      int j=i-1;
      while(j>=0 && g_liquidity[g_liq_priority_idx[j]].priority < kp)
      { g_liq_priority_idx[j+1]=g_liq_priority_idx[j]; j--; }
      g_liq_priority_idx[j+1]=key;
   }
}
void UpdateSignalMask(const int total,const double &c[])
{
   g_signal_mask=0;
   if(total<3) return;
   int closed=total-2;
   double price=c[closed];
   int ns=ArraySize(g_structures);
   if(ns>0)
   {
      string ty=g_structures[ns-1].type;
      if(ty=="MSS") g_signal_mask|=BIT_MSS;
      else if(ty=="BOS") g_signal_mask|=BIT_BOS;
      else if(ty=="CHoCH") g_signal_mask|=BIT_CHOCH;
   }
   for(int i=0;i<ArraySize(g_order_blocks);i++)
      if(g_order_blocks[i].strength>=4 && g_order_blocks[i].state!="MITIGATED")
      {g_signal_mask|=BIT_STRONG_OB; break;}
   for(int i=ArraySize(g_liquidity)-1;i>=MathMax(0,ArraySize(g_liquidity)-3);i--)
      if(g_liquidity[i].swept){g_signal_mask|=BIT_LIQUIDITY; break;}
   for(int i=0;i<ArraySize(g_fvgs);i++)
      if(g_fvgs[i].state=="OPEN"){g_signal_mask|=BIT_FVG; break;}
   if(g_range.valid)
   {
      double ot=0,ob=0; bool ib=false;
      if(GetOTEZone(ot,ob,ib))
         if(price<=ot && price>=ob) g_signal_mask|=BIT_OTE;
   }
   if(g_htf_bias!=0) g_signal_mask|=BIT_HTF_BIAS;
   // Session membership is evaluated at the closed bar's availability
   // boundary.  Only the next-open timestamp is used; no forming OHLC leaks.
   datetime now=(closed+1<ArraySize(g_buf_t)) ? g_buf_t[closed+1] : 0;
   if(IsInKillZone(now,SESSION_LONDON) || IsInKillZone(now,SESSION_NEWYORK))
      g_signal_mask|=BIT_KILLZONE;
   for(int i=0;i<ArraySize(g_zones);i++)
      if(g_zones[i].bullish && g_zones[i].state!="MITIGATED")
         if(price<=g_zones[i].top && price>=g_zones[i].bottom)
         {g_signal_mask|=BIT_DEMAND_ZONE; break;}
   if(g_judas!=0) g_signal_mask|=BIT_JUDAS;
}
bool CheckSignalPattern(const int required_mask)
{
   return (g_signal_mask & required_mask)==required_mask;
}
void AddGraphNode(const string type,const double price,const int strength)
{
   int idx=ArraySize(g_market_graph);
   ArrayResize(g_market_graph,idx+1,32);
   g_market_graph[idx].type=type;
   g_market_graph[idx].price=price;
   g_market_graph[idx].strength=strength;
   g_market_graph[idx].link_count=0;
   g_market_graph[idx].visited=false;
}
void ConnectGraphNodes()
{
   int n=ArraySize(g_market_graph);
   double max_distance=(g_atr>0)? g_atr*0.75 : 200*_Point;
   for(int i=0;i<n;i++)
      for(int j=i+1;j<n;j++)
      {
         if(MathAbs(g_market_graph[i].price-g_market_graph[j].price)>max_distance) continue;
         if(g_market_graph[i].link_count<MAX_GRAPH_LINKS) g_market_graph[i].links[g_market_graph[i].link_count++]=j;
         if(g_market_graph[j].link_count<MAX_GRAPH_LINKS) g_market_graph[j].links[g_market_graph[j].link_count++]=i;
      }
}
void BuildMarketGraph()
{
   // P2.11 Simplified: cap nodes, reduce links for performance
   ArrayResize(g_market_graph,0,32);
   int maxNodes=14;
   int cnt=0;
   // limit OBs to strongest 6
   BuildOBStrengthIndex();
   for(int k=0;k<MathMin(6, ArraySize(g_order_blocks)) && cnt<maxNodes;k++)
   {
      int i=g_ob_strength_idx[k];
      if(i<0 || i>=ArraySize(g_order_blocks)) continue;
      AddGraphNode("OB",OBMid(i),g_order_blocks[i].strength); cnt++;
   }
   for(int i=0;i<ArraySize(g_fvgs) && cnt<maxNodes;i++) if(g_fvgs[i].state!="FILLED"){ AddGraphNode("FVG",(g_fvgs[i].top+g_fvgs[i].bottom)*0.5,3); cnt++; }
   for(int i=0;i<ArraySize(g_liquidity) && cnt<maxNodes;i++) if(g_liquidity[i].swept){ AddGraphNode("LIQ",g_liquidity[i].price,5); cnt++; if(cnt>=maxNodes) break; }
   // reduced connect radius and max links already limited to 6 via MAX_GRAPH_LINKS
   ConnectGraphNodes();
}
double GraphConfluenceScore(const double price)
{
   int n=ArraySize(g_market_graph);
   if(n==0) return 0.0;
   double band=(g_atr>0)? g_atr*2.0 : 300*_Point;
   double best=0.0;
   for(int i=0;i<n;i++)
   {
      if(MathAbs(g_market_graph[i].price-price)>band) continue;
      double v=10.0*(1+g_market_graph[i].link_count)+g_market_graph[i].strength*4.0;
      best=MathMax(best,v);
   }
   return MathMin(100.0,best);
}
string CausalTypeName(const ENUM_CAUSAL_EVENT_TYPE type)
{
   switch(type)
   {
      case CE_LIQ_POOL:      return "LIQ_POOL";
      case CE_LIQ_SWEEP:     return "LIQ_SWEEP";
      case CE_DISPLACEMENT:  return "DISPLACEMENT";
      case CE_BOS:           return "BOS";
      case CE_CHOCH:         return "CHOCH";
      case CE_MSS:           return "MSS";
      case CE_ORDER_BLOCK:   return "ORDER_BLOCK";
      case CE_FVG:           return "FVG";
      case CE_HTF_STRUCTURE: return "HTF_STRUCTURE";
      case CE_SETUP:         return "SETUP";
      case CE_TARGET:        return "TARGET";
   }
   return "UNKNOWN";
}

int FindCausalEventById(const string id)
{
   if(id=="") return -1;
   for(int i=0;i<ArraySize(g_causal_events);i++)
      if(g_causal_events[i].id==id) return i;
   return -1;
}

void LinkCausalEvents(const int parent,const int child)
{
   if(parent<0 || child<0 || parent>=ArraySize(g_causal_events) || child>=ArraySize(g_causal_events)) return;
   for(int i=0;i<g_causal_events[parent].child_count;i++)
      if(g_causal_events[parent].children[i]==child) return;
   if(g_causal_events[parent].child_count<MAX_CAUSAL_CHILDREN)
      g_causal_events[parent].children[g_causal_events[parent].child_count++]=child;
}

void RebuildCausalChildren()
{
   int n=ArraySize(g_causal_events);
   for(int i=0;i<n;i++)
   {
      g_causal_events[i].child_count=0;
      for(int c=0;c<MAX_CAUSAL_CHILDREN;c++) g_causal_events[i].children[c]=-1;
   }
   for(int i=0;i<n;i++)
   {
      LinkCausalEvents(g_causal_events[i].parent_primary,i);
      if(g_causal_events[i].parent_secondary!=g_causal_events[i].parent_primary)
         LinkCausalEvents(g_causal_events[i].parent_secondary,i);
   }
}

void RollbackCausalGraphToSize(const int size)
{
   int keep=MathMax(0,MathMin(size,ArraySize(g_causal_events)));
   ArrayResize(g_causal_events,keep,64);
   for(int i=0;i<keep;i++)
   {
      if(g_causal_events[i].parent_primary>=keep) g_causal_events[i].parent_primary=-1;
      if(g_causal_events[i].parent_secondary>=keep) g_causal_events[i].parent_secondary=-1;
   }
   RebuildCausalChildren();
}

int AddCausalEvent(const string id,const ENUM_CAUSAL_EVENT_TYPE type,const int bar,const datetime tm,
                   const bool bullish,const double price,const double top,const double bottom,
                   const int parent_primary,const int parent_secondary,const double strength,
                   const bool confirmed,const bool invalidated,const int source_index)
{
   int existing=FindCausalEventById(id);
   if(existing>=0) return existing;

   int p1=parent_primary;
   int p2=parent_secondary;
   bool temporal_invalid=invalidated;
   int current_size=ArraySize(g_causal_events);

   // An edge exists only when its parent was available no later than the
   // child's actual event timestamp.  Delaying child availability cannot cure
   // an acausal edge, so illegal parents are rejected rather than retained.
   if(p1>=0)
   {
      if(p1>=current_size || g_causal_events[p1].availability_time<=0 ||
         g_causal_events[p1].availability_time>tm)
      { p1=-1; temporal_invalid=true; }
   }
   if(p2>=0)
   {
      if(p2>=current_size || g_causal_events[p2].availability_time<=0 ||
         g_causal_events[p2].availability_time>tm)
      { p2=-1; temporal_invalid=true; }
   }

   int idx=ArraySize(g_causal_events);
   ArrayResize(g_causal_events,idx+1,64);
   g_causal_events[idx].id=id;
   g_causal_events[idx].type=type;
   g_causal_events[idx].event_bar=bar;
   g_causal_events[idx].event_time=tm;

   // Native chart-derived events become available at the actual next candle
   // open.  Decision-boundary events pass that next-open as tm, making event
   // and availability timestamps equal without PeriodSeconds assumptions.
   int availability_bar=bar;
   datetime availability_time=tm;
   if(bar>=0 && bar+1<ArraySize(g_buf_t) && tm<=g_buf_t[bar])
      availability_time=g_buf_t[bar+1];
   g_causal_events[idx].availability_bar=availability_bar;
   g_causal_events[idx].availability_time=availability_time;
   g_causal_events[idx].bullish=bullish;
   g_causal_events[idx].price=price;
   g_causal_events[idx].top=top;
   g_causal_events[idx].bottom=bottom;
   g_causal_events[idx].parent_primary=p1;
   g_causal_events[idx].parent_secondary=p2;
   g_causal_events[idx].child_count=0;
   g_causal_events[idx].strength=strength;
   g_causal_events[idx].confirmed=confirmed;
   g_causal_events[idx].invalidated=temporal_invalid;
   g_causal_events[idx].age=(g_rates_total>0 ?
                             MathMax(0,g_rates_total-2-availability_bar) : 0);
   g_causal_events[idx].source_index=source_index;
   LinkCausalEvents(p1,idx);
   if(p2!=p1) LinkCausalEvents(p2,idx);
   return idx;
}

int FindCausalEventBySource(const ENUM_CAUSAL_EVENT_TYPE type,const int source_index)
{
   for(int i=0;i<ArraySize(g_causal_events);i++)
      if(g_causal_events[i].type==type && g_causal_events[i].source_index==source_index) return i;
   return -1;
}

int FindNearestCausalAncestor(const int child,const ENUM_CAUSAL_EVENT_TYPE type,
                              const string exact_event_id)
{
   int n=ArraySize(g_causal_events);
   if(child<0 || child>=n) return -1;
   datetime decision_time=g_causal_events[child].event_time;
   if(decision_time<=0) return -1;

   int queue[]; ArrayResize(queue,MathMax(4,n*2+4));
   bool seen[]; ArrayResize(seen,n); ArrayInitialize(seen,false);
   int head=0,tail=0;
   int p1=g_causal_events[child].parent_primary;
   int p2=g_causal_events[child].parent_secondary;
   if(p1>=0) queue[tail++]=p1;
   if(p2>=0 && p2!=p1) queue[tail++]=p2;

   int best=-1;
   long best_distance=0;
   bool best_exact=false;
   double best_strength=-DBL_MAX;
   datetime best_event_time=0;
   string best_id="";

   while(head<tail)
   {
      int cur=queue[head++];
      if(cur<0 || cur>=n || seen[cur]) continue;
      seen[cur]=true;
      SCausalEvent ev=g_causal_events[cur];

      // Connectivity is exact because only explicit parent links are traversed.
      // Temporal validity uses parent availability against the child's actual
      // decision/event time; an unavailable ancestor is never rankable.
      bool direction_valid=(ev.bullish==g_causal_events[child].bullish);
      bool historical_pool=(ev.type==CE_LIQ_POOL && ev.confirmed);
      bool valid=(ev.type==type && ev.confirmed && (!ev.invalidated || historical_pool) &&
                  direction_valid && ev.event_time>0 && ev.event_time<=decision_time &&
                  ev.availability_time>0 && ev.availability_time<=decision_time);
      if(valid)
      {
         long distance=(long)(decision_time-ev.availability_time);
         bool exact=(exact_event_id!="" && ev.id==exact_event_id);
         bool better=(best<0 || distance<best_distance ||
                     (distance==best_distance && exact && !best_exact) ||
                     (distance==best_distance && exact==best_exact &&
                      ev.strength>best_strength+1e-9) ||
                     (distance==best_distance && exact==best_exact &&
                      MathAbs(ev.strength-best_strength)<=1e-9 &&
                      ev.event_time>best_event_time) ||
                     (distance==best_distance && exact==best_exact &&
                      MathAbs(ev.strength-best_strength)<=1e-9 &&
                      ev.event_time==best_event_time &&
                      (best_id=="" || StringCompare(ev.id,best_id)<0)));
         if(better)
         {
            best=cur; best_distance=distance; best_exact=exact;
            best_strength=ev.strength; best_event_time=ev.event_time;
            best_id=ev.id;
         }
      }

      int a=ev.parent_primary;
      int b=ev.parent_secondary;
      if(a>=0 && tail<ArraySize(queue)) queue[tail++]=a;
      if(b>=0 && b!=a && tail<ArraySize(queue)) queue[tail++]=b;
   }
   return best;
}

int FindParentEventOfType(const int child,const ENUM_CAUSAL_EVENT_TYPE type)
{
   // Compatibility wrapper: all existing callers now receive the deterministic
   // nearest valid ancestor rather than the first insertion-order BFS match.
   return FindNearestCausalAncestor(child,type,"");
}

bool IsCausallyConnected(const int ancestor,const int descendant)
{
   int n=ArraySize(g_causal_events);
   if(ancestor<0 || descendant<0 || ancestor>=n || descendant>=n) return false;
   if(ancestor==descendant) return true;
   int queue[]; ArrayResize(queue,MathMax(2,n*2+2));
   bool seen[]; ArrayResize(seen,n); ArrayInitialize(seen,false);
   int head=0,tail=0; queue[tail++]=descendant;
   while(head<tail)
   {
      int cur=queue[head++];
      if(cur<0 || cur>=n || seen[cur]) continue;
      seen[cur]=true;
      int p1=g_causal_events[cur].parent_primary;
      int p2=g_causal_events[cur].parent_secondary;
      if(p1==ancestor || p2==ancestor) return true;
      if(p1>=0) queue[tail++]=p1;
      if(p2>=0 && p2!=p1) queue[tail++]=p2;
   }
   return false;
}

bool ValidateDisplacementLeg(const int sweep_bar,const int structure_bar,const bool bullish,
                             const double break_price,const double &o[],const double &h[],
                             const double &l[],const double &c[],int &impulse_bar)
{
   impulse_bar=-1;
   int total=ArraySize(c);
   // Institutional chronology is strict: Sweep < Displacement < Structure.
   // Therefore the leg must contain at least one fully closed bar between its
   // sweep and structure endpoints.
   if(sweep_bar<0 || structure_bar<=sweep_bar+1 || structure_bar>=total) return false;
   double atr=(structure_bar<ArraySize(g_atr_buf) ? g_atr_buf[structure_bar] : g_atr);
   if(atr<=0.0) return false;
   if(bullish && c[structure_bar]<=break_price) return false;
   if(!bullish && c[structure_bar]>=break_price) return false;
   double net=bullish ? c[structure_bar]-l[sweep_bar] : h[sweep_bar]-c[structure_bar];
   if(net<atr*InpDisplacementATR) return false;

   // Bind the displacement event to the strongest qualifying directional
   // candle in the proven sweep->structure leg.  FVG ancestry is later tied
   // to this exact candle rather than to any imbalance somewhere in the leg.
   double best_ratio=0.0;
   for(int k=sweep_bar+1;k<structure_bar;k++)
   {
      double ak=(k<ArraySize(g_atr_buf) && g_atr_buf[k]>0.0) ? g_atr_buf[k] : atr;
      if(ak<=0.0) continue;
      double signed_body=bullish ? c[k]-o[k] : o[k]-c[k];
      double ratio=signed_body/ak;
      if(ratio>=InpCausalDisplacementBodyATR && ratio>best_ratio)
      {
         best_ratio=ratio;
         impulse_bar=k;
      }
   }
   return (impulse_bar>sweep_bar && impulse_bar<structure_bar);
}

bool ValidateCausalOB(const int ob_index,const int sweep_bar,const int displacement_bar,
                      const int structure_bar,const bool bullish,const double &o[],const double &c[])
{
   if(ob_index<0 || ob_index>=ArraySize(g_order_blocks)) return false;
   SOrderBlock ob=g_order_blocks[ob_index];
   if(ob.bullish!=bullish || ob.state=="MITIGATED") return false;
   int leg_start=MathMax(0,sweep_bar-MathMax(0,InpOrderZonePreSweepBars));
   if(displacement_bar<=sweep_bar || displacement_bar>=structure_bar) return false;
   if(ob.bar<leg_start || ob.bar>=displacement_bar) return false;

   // The causal OB is the final opposing candle before the exact impulse,
   // never merely the final opposing candle before a later structure break.
   int last_opposing=-1;
   for(int k=displacement_bar-1;k>=leg_start;k--)
   {
      if((bullish && c[k]<o[k]) || (!bullish && c[k]>o[k]))
      {last_opposing=k; break;}
   }
   if(last_opposing!=ob.bar) return false;
   for(int k=ob.bar+1;k<structure_bar;k++)
   {
      if(bullish && c[k]<ob.bottom) return false;
      if(!bullish && c[k]>ob.top) return false;
   }
   return true;
}

bool ValidateCausalFVG(const int fvg_index,const int sweep_bar,const int structure_bar,
                       const int displacement_bar,const bool bullish,const double &o[],
                       const double &h[],const double &l[],const double &c[])
{
   if(fvg_index<0 || fvg_index>=ArraySize(g_fvgs)) return false;
   SFVG f=g_fvgs[fvg_index];
   if(f.bullish!=bullish || f.state=="FILLED") return false;
   int C=f.creation_bar,A=C-2,B=C-1;
   if(A<0 || B<0 || C>=ArraySize(c)) return false;
   if(f.id=="" || f.bar!=f.creation_bar ||
      f.source_displacement_bar!=displacement_bar || B!=displacement_bar) return false;
   int leg_start=MathMax(0,sweep_bar-MathMax(0,InpOrderZonePreSweepBars));
   // DetectFVG records C as f.bar and B=C-1 as the actual displacement
   // source.  The raw gap must be fully available before the later structure
   // candle occurs: B(displacement) < C(formation) < structure.
   if(A<leg_start || C>=structure_bar || structure_bar>=ArraySize(g_buf_t)) return false;
   if(f.availability_time<=0 || f.availability_time>g_buf_t[structure_bar]) return false;

   // The middle candle that generated the three-candle imbalance must be the
   // exact candle represented by CE_DISPLACEMENT.
   if(displacement_bar<0 || B!=displacement_bar) return false;
   if(InpRequireCausalFVGBody)
   {
      double atr=(B<ArraySize(g_atr_buf) && g_atr_buf[B]>0.0) ? g_atr_buf[B] : g_atr;
      if(atr<=0.0) return false;
      double body=c[B]-o[B];
      if((bullish && body<atr*InpCausalDisplacementBodyATR) ||
         (!bullish && -body<atr*InpCausalDisplacementBodyATR)) return false;
   }
   double leg_high=-DBL_MAX,leg_low=DBL_MAX;
   for(int k=sweep_bar;k<=MathMin(structure_bar+1,ArraySize(c)-1);k++)
   {leg_high=MathMax(leg_high,h[k]); leg_low=MathMin(leg_low,l[k]);}
   return (f.top<=leg_high+_Point && f.bottom>=leg_low-_Point);
}

void BuildCausalEventGraph(const int total,const double &o[],const double &h[],const double &l[],
                           const double &c[],const datetime &t[])
{
   ArrayResize(g_causal_events,0,64);
   g_selected_sweep_event=g_selected_displacement_event=-1;
   g_selected_structure_event=g_selected_zone_event=-1;
   int closed=total-2;

   // 1) Confirmed liquidity pools and their explicit sweep children.
   // Pool occurrence and confirmation are intentionally separate.
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      SLiquidity q=g_liquidity[i];
      bool is_pool=(q.type=="EQH" || q.type=="EQL");
      if(!is_pool || q.id=="") continue;
      bool bull=(q.type=="EQL");
      string id="CE_POOL_"+q.id;
      int pev=AddCausalEvent(id,CE_LIQ_POOL,q.origin_bar,q.origin_time,bull,
                             q.price,q.price,q.price,-1,-1,q.priority*10.0,
                             true,q.swept,i);
      if(pev>=0)
      {
         g_causal_events[pev].availability_bar=q.availability_bar;
         g_causal_events[pev].availability_time=q.availability_time;
         g_causal_events[pev].age=MathMax(0,g_rates_total-2-q.availability_bar);
      }
   }
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      SLiquidity q=g_liquidity[i];
      bool bsl=(q.type=="BSL TAKEN");
      bool ssl=(q.type=="SSL TAKEN");
      if((!bsl && !ssl) || q.id=="") continue;
      bool bull=ssl;
      int parent=FindCausalEventById("CE_POOL_"+q.parent_pool_id);
      bool exact_parent=(parent>=0 &&
                         g_causal_events[parent].source_index>=0 &&
                         g_causal_events[parent].source_index<ArraySize(g_liquidity) &&
                         g_liquidity[g_causal_events[parent].source_index].id==q.parent_pool_id &&
                         g_causal_events[parent].availability_time<=q.origin_time);
      if(!exact_parent) parent=-1;

      string id="CE_SWEEP_"+q.id;
      int sev=AddCausalEvent(id,CE_LIQ_SWEEP,q.origin_bar,q.origin_time,bull,
                             q.price,q.price,q.price,parent,-1,q.priority*10.0,
                             parent>=0,parent<0,i);
      if(sev>=0)
      {
         g_causal_events[sev].availability_bar=q.availability_bar;
         g_causal_events[sev].availability_time=q.availability_time;
         g_causal_events[sev].age=MathMax(0,g_rates_total-2-q.availability_bar);
      }
   }

   // 2) Sweep -> displacement -> structure -> causally bound zones.
   // Clear derived structure bindings before each deterministic graph rebuild.
   for(int fi=0;fi<ArraySize(g_fvgs);fi++)
   {
      g_fvgs[fi].source_structure_bar=-1;
      g_fvgs[fi].source_structure_time=0;
      g_fvgs[fi].source_structure_event_id="";
   }

   for(int si=0;si<ArraySize(g_structures);si++)
   {
      SStructureBreak st=g_structures[si];
      // INIT establishes state only and cannot become an anchor or OB source.
      if(st.type=="INIT") continue;

      int sweep=-1;
      int impulse_bar=-1;
      int best_sweep_bar=-1;
      string best_sweep_id="";
      for(int e=0;e<ArraySize(g_causal_events);e++)
      {
         if(g_causal_events[e].type!=CE_LIQ_SWEEP || g_causal_events[e].invalidated ||
            !g_causal_events[e].confirmed || g_causal_events[e].bullish!=st.bullish) continue;
         int age=st.bar-g_causal_events[e].event_bar;
         if(age<0 || (InpSweepToStructureMaxBars>0 && age>InpSweepToStructureMaxBars)) continue;

         int candidate_impulse=-1;
         if(!ValidateDisplacementLeg(g_causal_events[e].event_bar,st.bar,st.bullish,
                                     st.price,o,h,l,c,candidate_impulse)) continue;
         // The sweep must have been confirmed before the displacement candle
         // occurred, not merely before the later structure became available.
         if(g_causal_events[e].availability_time>t[candidate_impulse]) continue;

         int sb=g_causal_events[e].event_bar;
         string eid=g_causal_events[e].id;
         if(sb>best_sweep_bar || (sb==best_sweep_bar &&
            (best_sweep_id=="" || StringCompare(eid,best_sweep_id)<0)))
         {
            sweep=e;
            impulse_bar=candidate_impulse;
            best_sweep_bar=sb;
            best_sweep_id=eid;
         }
      }

      bool valid_disp=(sweep>=0 && impulse_bar>g_causal_events[sweep].event_bar &&
                       impulse_bar<st.bar);
      int disp=-1;
      string did="";
      if(valid_disp)
      {
         did=StringFormat("CE_DISP_%s_%s_%I64d",_Symbol,st.bullish?"B":"S",
                          (long)t[impulse_bar]);
         disp=AddCausalEvent(did,CE_DISPLACEMENT,impulse_bar,t[impulse_bar],st.bullish,
                             c[impulse_bar],h[impulse_bar],l[impulse_bar],sweep,-1,
                             st.strength*20.0,true,false,si);
         valid_disp=(disp>=0 && !g_causal_events[disp].invalidated &&
                     g_causal_events[disp].parent_primary==sweep);
      }

      ENUM_CAUSAL_EVENT_TYPE et=(st.type=="MSS" ? CE_MSS :
                                  (st.type=="CHoCH" ? CE_CHOCH : CE_BOS));
      string sid=StringFormat("CE_%s_%s_%I64d_%s",CausalTypeName(et),_Symbol,
                              (long)t[st.bar],st.bullish?"B":"S");
      int sev=AddCausalEvent(sid,et,st.bar,t[st.bar],st.bullish,st.price,
                             st.price,st.price,valid_disp?disp:-1,
                             valid_disp?sweep:-1,st.strength*20.0,true,
                             !valid_disp,si);
      if(!valid_disp || sev<0 || g_causal_events[sev].invalidated) continue;

      datetime structure_boundary=t[st.bar+1];
      for(int oi=0;oi<ArraySize(g_order_blocks);oi++)
      {
         if(g_order_blocks[oi].origin_struct_bar!=st.bar) continue;
         if(g_order_blocks[oi].source_displacement_bar!=impulse_bar) continue;
         if(!ValidateCausalOB(oi,g_causal_events[sweep].event_bar,impulse_bar,
                              st.bar,st.bullish,o,c)) continue;

         g_order_blocks[oi].source_displacement_event_id=did;
         g_order_blocks[oi].source_structure_event_id=sid;
         SOrderBlock ob=g_order_blocks[oi];
         string oid="CE_ORDER_BLOCK_"+ob.id;
         AddCausalEvent(oid,CE_ORDER_BLOCK,st.bar,structure_boundary,ob.bullish,
                        (ob.top+ob.bottom)*0.5,ob.top,ob.bottom,sev,disp,
                        ob.strength*20.0,true,ob.state=="MITIGATED",oi);
      }

      for(int fi=0;fi<ArraySize(g_fvgs);fi++)
      {
         if(g_fvgs[fi].source_structure_event_id!="") continue;
         if(g_fvgs[fi].source_displacement_bar!=impulse_bar) continue;
         if(!ValidateCausalFVG(fi,g_causal_events[sweep].event_bar,st.bar,
                               impulse_bar,st.bullish,o,h,l,c)) continue;

         g_fvgs[fi].source_displacement_event_id=did;
         g_fvgs[fi].source_structure_bar=st.bar;
         g_fvgs[fi].source_structure_time=t[st.bar];
         g_fvgs[fi].source_structure_event_id=sid;
         SFVG f=g_fvgs[fi];
         int zone_bar=MathMax(f.availability_bar,st.bar);
         datetime zone_time=(f.availability_time>structure_boundary ?
                             f.availability_time : structure_boundary);
         string fid="CE_"+f.id;
         AddCausalEvent(fid,CE_FVG,zone_bar,zone_time,f.bullish,f.mid_price,
                        f.top,f.bottom,disp,sev,(f.state=="OPEN"?85.0:65.0),
                        true,f.state=="FILLED",fi);
      }
   }

   if(g_htf_last_event_time>0 && g_htf_last_availability_time>0 && g_htf_bias!=0)
   {
      int htf_event_bar=ChartEventBarAtTime(t,total,g_htf_last_event_time);
      int htf_availability_bar=ChartClosedBarAtTime(t,total,g_htf_last_availability_time);
      if(htf_event_bar>=0 && htf_availability_bar>=0)
      {
         string id=StringFormat("CE_HTF_%s_%I64d_%I64d_%s",_Symbol,
                                (long)g_htf_last_event_time,
                                (long)g_htf_last_availability_time,
                                g_htf_bias>0?"B":"S");
         int hev=AddCausalEvent(id,CE_HTF_STRUCTURE,htf_event_bar,g_htf_last_event_time,
                                g_htf_bias>0,g_htf_eq,g_htf_eq,g_htf_eq,-1,-1,
                                80.0,true,false,-1);
         if(hev>=0)
         {
            g_causal_events[hev].availability_bar=htf_availability_bar;
            g_causal_events[hev].availability_time=g_htf_last_availability_time;
            g_causal_events[hev].age=MathMax(0,g_rates_total-2-htf_availability_bar);
         }
      }
      else if(InpLogSignalDetails)
         Print("[HTFEvent] event/availability mapping failed: event=",
               TimeToString(g_htf_last_event_time)," available=",
               TimeToString(g_htf_last_availability_time));
   }

   // Rehydrate the immutable setup branch after each graph rebuild.
   if(g_active_setup.active && g_active_setup.setup_event_id!="")
   {
      int zone=FindCausalEventById(g_active_setup.zone_event_id);
      int structure=FindCausalEventById(g_active_setup.structure_event_id);
      int setup_bar=ChartClosedBarAtTime(t,total,g_active_setup.created_time);
      if(zone>=0 && structure>=0 && setup_bar>=0)
      {
         g_active_setup.created_bar=setup_bar;
         int setup=AddCausalEvent(g_active_setup.setup_event_id,CE_SETUP,
                                  setup_bar,g_active_setup.created_time,
                                  g_active_setup.is_buy,g_active_setup.entry,
                                  g_active_setup.zone_top,g_active_setup.zone_bottom,
                                  zone,structure,g_active_setup.reliability,true,false,-1);
         int src1=FindCausalEventById(g_active_setup.tp_source_event_id[0]);
         int src2=FindCausalEventById(g_active_setup.tp_source_event_id[1]);
         int src3=FindCausalEventById(g_active_setup.tp_source_event_id[2]);
         AddCausalEvent(StringFormat("CE_TP1_%s_%I64d_%s",_Symbol,(long)g_active_setup.created_time,
                                     DoubleToString(g_active_setup.tp1,_Digits)),
                        CE_TARGET,g_active_setup.created_bar,g_active_setup.created_time,g_active_setup.is_buy,g_active_setup.tp1,
                        g_active_setup.tp1,g_active_setup.tp1,src1>=0?src1:zone,setup,90.0,true,
                        g_active_setup.tp_consumed[0],g_active_setup.tp_source_bar[0]);
         AddCausalEvent(StringFormat("CE_TP2_%s_%I64d_%s",_Symbol,(long)g_active_setup.created_time,
                                     DoubleToString(g_active_setup.tp2,_Digits)),
                        CE_TARGET,g_active_setup.created_bar,g_active_setup.created_time,g_active_setup.is_buy,g_active_setup.tp2,
                        g_active_setup.tp2,g_active_setup.tp2,src2>=0?src2:zone,setup,75.0,true,
                        g_active_setup.tp_consumed[1],g_active_setup.tp_source_bar[1]);
         AddCausalEvent(StringFormat("CE_TP3_%s_%I64d_%s",_Symbol,(long)g_active_setup.created_time,
                                     DoubleToString(g_active_setup.tp3,_Digits)),
                        CE_TARGET,g_active_setup.created_bar,g_active_setup.created_time,g_active_setup.is_buy,g_active_setup.tp3,
                        g_active_setup.tp3,g_active_setup.tp3,src3>=0?src3:zone,setup,60.0,true,
                        g_active_setup.tp_consumed[2],g_active_setup.tp_source_bar[2]);
      }
   }
   else if(!InpUseRetestLifecycle && g_trade_setup.valid &&
           g_trade_setup.setup_event_id!="" && g_trade_setup.created_time>0)
   {
      int zone=FindCausalEventById(g_trade_setup.zone_event_id);
      int structure=FindCausalEventById(g_trade_setup.structure_event_id);
      int setup_bar=ChartClosedBarAtTime(t,total,g_trade_setup.created_time);
      if(zone>=0 && structure>=0 && setup_bar>=0)
      {
         g_trade_setup.created_bar=setup_bar;
         int setup=AddCausalEvent(g_trade_setup.setup_event_id,CE_SETUP,
                                  setup_bar,g_trade_setup.created_time,
                                  g_trade_setup.is_buy,g_trade_setup.entry,
                                  g_trade_setup.zone_top,g_trade_setup.zone_bottom,
                                  zone,structure,g_trade_setup.reliability,true,false,-1);
         double targets[3]; targets[0]=g_trade_setup.tp1;
         targets[1]=g_trade_setup.tp2; targets[2]=g_trade_setup.tp3;
         double strengths[3]; strengths[0]=90.0; strengths[1]=75.0; strengths[2]=60.0;
         for(int ti=0;ti<3;ti++)
         {
            int src=FindCausalEventById(g_trade_setup.tp_source_event_id[ti]);
            if(src<0) src=zone;
            AddCausalEvent(StringFormat("CE_TP%d_%s_%I64d_%s",ti+1,_Symbol,
                                        (long)g_trade_setup.created_time,
                                        DoubleToString(targets[ti],_Digits)),
                           CE_TARGET,g_trade_setup.created_bar,g_trade_setup.created_time,
                           g_trade_setup.is_buy,targets[ti],targets[ti],targets[ti],
                           src,setup,strengths[ti],true,g_trade_setup.tp_consumed[ti],
                           g_trade_setup.tp_source_bar[ti]);
         }
      }
   }
   if(InpMaxCausalEventsKeep>0 && ArraySize(g_causal_events)>InpMaxCausalEventsKeep)
      PruneCausalEventGraph(InpMaxCausalEventsKeep);
   RunCausalGraphChecks(t[closed]);
}

void MarkCausalAncestors(const int event_index,bool &keep[])
{
   int n=ArraySize(g_causal_events);
   if(event_index<0 || event_index>=n || ArraySize(keep)!=n) return;
   int queue[]; ArrayResize(queue,MathMax(1,n*2)); int head=0,tail=0;
   queue[tail++]=event_index;
   while(head<tail)
   {
      int cur=queue[head++];
      if(cur<0 || cur>=n || keep[cur]) continue;
      keep[cur]=true;
      int p1=g_causal_events[cur].parent_primary;
      int p2=g_causal_events[cur].parent_secondary;
      if(p1>=0 && tail<ArraySize(queue)) queue[tail++]=p1;
      if(p2>=0 && p2!=p1 && tail<ArraySize(queue)) queue[tail++]=p2;
   }
}

void PruneCausalEventGraph(const int max_events)
{
   int n=ArraySize(g_causal_events);
   if(max_events<=0 || n<=max_events) return;

   bool keep[]; ArrayResize(keep,n); ArrayInitialize(keep,false);

   // The active setup component has absolute priority: setup, targets and all
   // transitive ancestors survive before recent-history branches are considered.
   string protected_setup_id=(g_active_setup.active ? g_active_setup.setup_event_id :
                              g_trade_setup.setup_event_id);
   int active_setup=FindCausalEventById(protected_setup_id);
   if(active_setup>=0)
   {
      MarkCausalAncestors(active_setup,keep);
      for(int i=0;i<n;i++)
      {
         if(g_causal_events[i].type!=CE_TARGET) continue;
         if(g_causal_events[i].parent_primary==active_setup ||
            g_causal_events[i].parent_secondary==active_setup)
            MarkCausalAncestors(i,keep);
      }
      string barrier_id=(g_active_setup.active ?
                         g_active_setup.immutable_target_barrier_event_id :
                         g_trade_setup.immutable_target_barrier_event_id);
      int barrier_event=FindCausalEventById(barrier_id);
      if(barrier_event>=0) MarkCausalAncestors(barrier_event,keep);
   }

   int order[]; ArrayResize(order,n);
   for(int i=0;i<n;i++) order[i]=i;
   for(int i=1;i<n;i++)
   {
      int key=order[i],j=i-1;
      while(j>=0)
      {
         int a=order[j];
         bool older=(g_causal_events[a].availability_time<g_causal_events[key].availability_time ||
                    (g_causal_events[a].availability_time==g_causal_events[key].availability_time &&
                     StringCompare(g_causal_events[a].id,g_causal_events[key].id)>0));
         if(!older) break;
         order[j+1]=order[j]; j--;
      }
      order[j+1]=key;
   }

   int kept=0;
   for(int i=0;i<n;i++) if(keep[i]) kept++;
   for(int oi=0;oi<n && kept<max_events;oi++)
   {
      int idx=order[oi];
      if(keep[idx] || g_causal_events[idx].invalidated) continue;
      if(g_causal_events[idx].type==CE_LIQ_SWEEP && !g_causal_events[idx].confirmed) continue;

      bool trial[]; ArrayResize(trial,n); ArrayCopy(trial,keep);
      MarkCausalAncestors(idx,trial);
      int trial_count=0;
      for(int k=0;k<n;k++) if(trial[k]) trial_count++;
      if(trial_count<=max_events)
      {
         ArrayCopy(keep,trial);
         kept=trial_count;
      }
   }

   if(kept>max_events)
   {
      // v5.7.3 FIX (A5): configuration warning only fires when the operator
      // asked for it; it repeated on every rebuild before.
      if(InpLogLifecycleTransitions)
         Print("[CausalGraph] Active component exceeds configured cap; preserving ancestry: ",kept);
   }

   int map[]; ArrayResize(map,n); ArrayInitialize(map,-1);
   SCausalEvent compact[]; ArrayResize(compact,kept,64);
   int out=0;
   for(int i=0;i<n;i++)
   {
      if(!keep[i]) continue;
      map[i]=out;
      compact[out]=g_causal_events[i];
      compact[out].child_count=0;
      for(int c=0;c<MAX_CAUSAL_CHILDREN;c++) compact[out].children[c]=-1;
      out++;
   }
   for(int i=0;i<kept;i++)
   {
      int p1=compact[i].parent_primary;
      int p2=compact[i].parent_secondary;
      compact[i].parent_primary=(p1>=0 && p1<n ? map[p1] : -1);
      compact[i].parent_secondary=(p2>=0 && p2<n ? map[p2] : -1);
   }

   g_selected_sweep_event=(g_selected_sweep_event>=0 && g_selected_sweep_event<n ?
                           map[g_selected_sweep_event] : -1);
   g_selected_displacement_event=(g_selected_displacement_event>=0 && g_selected_displacement_event<n ?
                                  map[g_selected_displacement_event] : -1);
   g_selected_structure_event=(g_selected_structure_event>=0 && g_selected_structure_event<n ?
                               map[g_selected_structure_event] : -1);
   g_selected_zone_event=(g_selected_zone_event>=0 && g_selected_zone_event<n ?
                          map[g_selected_zone_event] : -1);

   ArrayResize(g_causal_events,kept,64);
   for(int i=0;i<kept;i++) g_causal_events[i]=compact[i];
   for(int i=0;i<kept;i++)
   {
      LinkCausalEvents(g_causal_events[i].parent_primary,i);
      if(g_causal_events[i].parent_secondary!=g_causal_events[i].parent_primary)
         LinkCausalEvents(g_causal_events[i].parent_secondary,i);
   }
   // v5.7.3 FIX (A5): this printed on EVERY rebuild once the cap was reached,
   // flooding the journal during normal operation. It is now lifecycle-gated.
   if(InpLogLifecycleTransitions)
      Print("[CausalGraph] ancestry-safe prune ",n," -> ",kept);
}

bool ValidateHTFAvailability(const ENUM_TIMEFRAMES tf,const datetime event_time,
                             const datetime availability_time,string &reason)
{
   reason="";
   if(event_time<=0 || availability_time<=0)
   {reason="missing HTF event/availability timestamp"; return false;}
   int source_shift=iBarShift(_Symbol,tf,event_time,false);
   // shift 0 is still forming and therefore cannot be a confirmed source.
   if(source_shift<=0)
   {reason="HTF source candle is forming or unavailable"; return false;}
   datetime source_open=iTime(_Symbol,tf,source_shift);
   datetime source_close=iTime(_Symbol,tf,source_shift-1);
   if(source_open<=0 || source_close<=source_open)
   {reason="HTF source close boundary unavailable"; return false;}
   if(event_time<source_open || event_time>=source_close)
   {reason="HTF event timestamp outside source candle"; return false;}
   if(availability_time<source_close)
   {reason="HTF event leaked before source candle close"; return false;}
   return true;
}

bool ValidateCausalGraphInvariants(string &reason)
{
   reason="";
   int n=ArraySize(g_causal_events);
   for(int i=0;i<n;i++)
   {
      SCausalEvent ev=g_causal_events[i];
      if(ev.parent_primary>=n || ev.parent_secondary>=n ||
         ev.parent_primary==i || ev.parent_secondary==i)
      {reason="Invalid/self parent at "+ev.id; return false;}
      if(ev.event_bar<0 || ev.availability_bar<ev.event_bar ||
         ev.availability_time<ev.event_time)
      {reason="Event availability precedes event origin: "+ev.id; return false;}
      if((ev.parent_primary>=0 &&
          g_causal_events[ev.parent_primary].availability_time>ev.event_time) ||
         (ev.parent_secondary>=0 &&
          g_causal_events[ev.parent_secondary].availability_time>ev.event_time))
      {reason="Parent unavailable at child event time: "+ev.id; return false;}
      for(int j=i+1;j<n;j++)
         if(g_causal_events[j].id==ev.id)
         {reason="Duplicate causal event identity: "+ev.id; return false;}
      int parents[2]; parents[0]=ev.parent_primary; parents[1]=ev.parent_secondary;
      for(int pi=0;pi<2;pi++)
      {
         int p=parents[pi];
         if(p<0 || (pi==1 && p==parents[0])) continue;
         bool reciprocal=false;
         for(int ci=0;ci<g_causal_events[p].child_count;ci++)
            if(g_causal_events[p].children[ci]==i){reciprocal=true; break;}
         if(!reciprocal){reason="Parent/child adjacency mismatch: "+ev.id; return false;}
      }

      // Both parent dimensions must terminate; detect any ancestry cycle.
      bool seen[]; ArrayResize(seen,n); ArrayInitialize(seen,false);
      int queue[]; ArrayResize(queue,MathMax(1,n*2)); int head=0,tail=0;
      if(ev.parent_primary>=0) queue[tail++]=ev.parent_primary;
      if(ev.parent_secondary>=0 && ev.parent_secondary!=ev.parent_primary) queue[tail++]=ev.parent_secondary;
      while(head<tail)
      {
         int cur=queue[head++];
         if(cur==i){reason="Causal parent cycle at "+ev.id; return false;}
         if(cur<0 || cur>=n || seen[cur]) continue;
         seen[cur]=true;
         int p1=g_causal_events[cur].parent_primary;
         int p2=g_causal_events[cur].parent_secondary;
         if(p1>=0 && tail<ArraySize(queue)) queue[tail++]=p1;
         if(p2>=0 && p2!=p1 && tail<ArraySize(queue)) queue[tail++]=p2;
      }

      if(ev.type==CE_LIQ_POOL)
      {
         if(ev.source_index<0 || ev.source_index>=ArraySize(g_liquidity))
         {reason="Pool source index invalid: "+ev.id; return false;}
         SLiquidity q=g_liquidity[ev.source_index];
         if(q.id=="" || ev.id!="CE_POOL_"+q.id || ev.event_bar!=q.origin_bar ||
            ev.event_time!=q.origin_time || ev.availability_bar!=q.availability_bar ||
            ev.availability_time!=q.availability_time || q.availability_time<q.origin_time)
         {reason="Pool origin/availability identity mismatch: "+ev.id; return false;}
      }
      if(ev.invalidated || !ev.confirmed) continue;
      if(ev.type==CE_LIQ_SWEEP)
      {
         if(ev.source_index<0 || ev.source_index>=ArraySize(g_liquidity))
         {reason="Sweep source index invalid: "+ev.id; return false;}
         SLiquidity q=g_liquidity[ev.source_index];
         int pool=FindNearestCausalAncestor(i,CE_LIQ_POOL,"CE_POOL_"+q.parent_pool_id);
         if(pool<0){reason="Confirmed sweep lacks exact pool parent: "+ev.id; return false;}
         int pool_source=g_causal_events[pool].source_index;
         if(pool_source<0 || pool_source>=ArraySize(g_liquidity) ||
            q.parent_pool_id=="" || q.parent_pool_id!=g_liquidity[pool_source].id ||
            g_liquidity[pool_source].availability_time>q.origin_time)
         {reason="Sweep/pool exact identity or availability mismatch: "+ev.id; return false;}
      }
      else if(ev.type==CE_DISPLACEMENT)
      {
         if(ev.event_bar<0 || ev.event_bar+1>=ArraySize(g_buf_t) ||
            ev.availability_bar!=ev.event_bar ||
            ev.availability_time!=g_buf_t[ev.event_bar+1])
         {reason="Displacement not available at its own close: "+ev.id; return false;}
         int sw=FindParentEventOfType(i,CE_LIQ_SWEEP);
         int pool=(sw>=0 ? FindParentEventOfType(sw,CE_LIQ_POOL) : -1);
         if(sw<0 || pool<0 || !g_causal_events[sw].confirmed)
         {reason="Displacement lacks pool->sweep ancestry: "+ev.id; return false;}
      }
      else if(ev.type==CE_BOS || ev.type==CE_CHOCH || ev.type==CE_MSS)
      {
         if(ev.event_bar<0 || ev.event_bar+1>=ArraySize(g_buf_t) ||
            ev.availability_bar!=ev.event_bar ||
            ev.availability_time!=g_buf_t[ev.event_bar+1])
         {reason="Structure not available at its closed decision boundary: "+ev.id; return false;}
         int dp=FindParentEventOfType(i,CE_DISPLACEMENT);
         int sw=FindParentEventOfType(i,CE_LIQ_SWEEP);
         int pool=(sw>=0 ? FindParentEventOfType(sw,CE_LIQ_POOL) : -1);
         if(dp<0 || sw<0 || pool<0)
         {reason="Structure ancestry incomplete: "+ev.id; return false;}
         if(!(g_causal_events[pool].event_time<g_causal_events[sw].event_time &&
              g_causal_events[sw].event_time<g_causal_events[dp].event_time &&
              g_causal_events[dp].event_time<ev.event_time))
         {reason="Structure event chronology invalid: "+ev.id; return false;}
         if(!(g_causal_events[pool].availability_time<=g_causal_events[sw].availability_time &&
              g_causal_events[sw].availability_time<=g_causal_events[dp].availability_time &&
              g_causal_events[dp].availability_time<=ev.availability_time))
         {reason="Structure availability chronology invalid: "+ev.id; return false;}
      }
      else if(ev.type==CE_ORDER_BLOCK || ev.type==CE_FVG)
      {
         int st=FindParentEventOfType(i,CE_MSS);
         if(st<0) st=FindParentEventOfType(i,CE_CHOCH);
         if(st<0) st=FindParentEventOfType(i,CE_BOS);
         int dp=FindParentEventOfType(i,CE_DISPLACEMENT);
         int sw=FindParentEventOfType(i,CE_LIQ_SWEEP);
         int pool=(sw>=0 ? FindParentEventOfType(sw,CE_LIQ_POOL) : -1);
         if(st<0 || dp<0 || sw<0 || pool<0)
         {reason="Zone ancestry incomplete: "+ev.id; return false;}
         if(ev.type==CE_FVG)
         {
            if(ev.source_index<0 || ev.source_index>=ArraySize(g_fvgs) ||
               g_fvgs[ev.source_index].id=="" ||
               g_fvgs[ev.source_index].availability_time<g_fvgs[ev.source_index].creation_time ||
               g_fvgs[ev.source_index].source_displacement_time>=g_fvgs[ev.source_index].creation_time ||
               g_fvgs[ev.source_index].availability_time>g_causal_events[st].event_time ||
               g_fvgs[ev.source_index].source_displacement_bar!=g_causal_events[dp].event_bar ||
               g_fvgs[ev.source_index].source_displacement_time!=g_causal_events[dp].event_time ||
               g_fvgs[ev.source_index].source_displacement_event_id!=g_causal_events[dp].id ||
               g_fvgs[ev.source_index].source_structure_time!=g_causal_events[st].event_time ||
               g_fvgs[ev.source_index].source_structure_event_id!=g_causal_events[st].id)
            {reason="FVG exact displacement/structure binding mismatch: "+ev.id; return false;}
         }
         else
         {
            if(ev.source_index<0 || ev.source_index>=ArraySize(g_order_blocks) ||
               g_order_blocks[ev.source_index].source_displacement_bar!=g_causal_events[dp].event_bar ||
               g_order_blocks[ev.source_index].source_displacement_time!=g_causal_events[dp].event_time ||
               g_order_blocks[ev.source_index].source_displacement_event_id!=g_causal_events[dp].id ||
               g_order_blocks[ev.source_index].source_structure_time!=g_causal_events[st].event_time ||
               g_order_blocks[ev.source_index].source_structure_event_id!=g_causal_events[st].id)
            {reason="OB exact displacement/structure binding mismatch: "+ev.id; return false;}
         }
      }
      else if(ev.type==CE_HTF_STRUCTURE)
      {
         string htf_reason="";
         if(!ValidateHTFAvailability(InpHTFBiasTF,ev.event_time,
                                     ev.availability_time,htf_reason))
         {reason="HTF availability invariant: "+htf_reason+" | "+ev.id; return false;}
         if(ev.event_bar<0 || ev.event_bar+1>=ArraySize(g_buf_t) ||
            ev.availability_bar<0 || ev.availability_bar+1>=ArraySize(g_buf_t) ||
            !(g_buf_t[ev.event_bar]<=ev.event_time &&
              ev.event_time<g_buf_t[ev.event_bar+1]) ||
            !(g_buf_t[ev.availability_bar]<ev.availability_time &&
              ev.availability_time<=g_buf_t[ev.availability_bar+1]) ||
            ev.event_time>=ev.availability_time ||
            ev.event_bar>ev.availability_bar)
         {reason="HTF event/availability mapping mismatch: "+ev.id; return false;}
      }
      else if(ev.type==CE_SETUP)
      {
         if(ev.event_bar<0 || ev.event_bar+1>=ArraySize(g_buf_t) ||
            ev.event_time!=g_buf_t[ev.event_bar+1] ||
            ev.availability_time!=ev.event_time)
         {reason="Setup timestamp is not the decision boundary: "+ev.id; return false;}
         int sw=FindParentEventOfType(i,CE_LIQ_SWEEP);
         int pool=(sw>=0 ? FindParentEventOfType(sw,CE_LIQ_POOL) : -1);
         int dp=FindParentEventOfType(i,CE_DISPLACEMENT);
         int st=FindParentEventOfType(i,CE_MSS);
         if(st<0) st=FindParentEventOfType(i,CE_CHOCH);
         if(st<0) st=FindParentEventOfType(i,CE_BOS);
         if(pool<0 || sw<0 || dp<0 || st<0)
         {reason="Setup ancestry incomplete: "+ev.id; return false;}
         if(!(g_causal_events[pool].availability_time<=g_causal_events[sw].availability_time &&
              g_causal_events[sw].availability_time<=g_causal_events[dp].availability_time &&
              g_causal_events[dp].availability_time<=g_causal_events[st].availability_time &&
              g_causal_events[st].availability_time<=ev.event_time &&
              g_causal_events[st].event_time<ev.event_time))
         {reason="Setup causal availability chain invalid: "+ev.id; return false;}
      }
      else if(ev.type==CE_TARGET)
      {
         if(ev.event_bar<0 || ev.event_bar+1>=ArraySize(g_buf_t) ||
            ev.event_time!=g_buf_t[ev.event_bar+1] ||
            ev.availability_time!=ev.event_time)
         {reason="Target timestamp is not the setup decision boundary: "+ev.id; return false;}
         int setup=FindParentEventOfType(i,CE_SETUP);
         if(setup<0){reason="Target lacks setup parent: "+ev.id; return false;}
      }
   }

   // Immutable lifecycle geometry: once a setup exists, direction, target
   // ordering, stored RR, and the entry-time opposing barrier must agree.
   if(g_active_setup.active)
   {
      bool creation_ok=false;
      for(int cb=0;cb+1<ArraySize(g_buf_t);cb++)
         if(g_active_setup.created_time==g_buf_t[cb+1])
         {creation_ok=true; break;}
      bool geometry=g_active_setup.is_buy ?
         (g_active_setup.sl<g_active_setup.entry && g_active_setup.entry<g_active_setup.tp1 &&
          g_active_setup.tp1<g_active_setup.tp2 && g_active_setup.tp2<g_active_setup.tp3) :
         (g_active_setup.sl>g_active_setup.entry && g_active_setup.entry>g_active_setup.tp1 &&
          g_active_setup.tp1>g_active_setup.tp2 && g_active_setup.tp2>g_active_setup.tp3);
      double risk=MathAbs(g_active_setup.entry-g_active_setup.sl);
      double rr1=(risk>_Point ? MathAbs(g_active_setup.tp1-g_active_setup.entry)/risk : -1.0);
      double rr2=(risk>_Point ? MathAbs(g_active_setup.tp2-g_active_setup.entry)/risk : -1.0);
      double rr3=(risk>_Point ? MathAbs(g_active_setup.tp3-g_active_setup.entry)/risk : -1.0);
      bool rr_ok=(MathAbs(rr1-g_active_setup.rr1)<=1e-6 &&
                  MathAbs(rr2-g_active_setup.rr2)<=1e-6 &&
                  MathAbs(rr3-g_active_setup.rr3)<=1e-6);
      bool barrier_ok=true;
      bool barrier_source_ok=true;
      if(g_active_setup.immutable_target_barrier>0.0)
      {
         barrier_ok=g_active_setup.is_buy ?
            (g_active_setup.tp1<=g_active_setup.immutable_target_barrier+_Point &&
             g_active_setup.tp2<=g_active_setup.immutable_target_barrier+_Point &&
             g_active_setup.tp3<=g_active_setup.immutable_target_barrier+_Point) :
            (g_active_setup.tp1>=g_active_setup.immutable_target_barrier-_Point &&
             g_active_setup.tp2>=g_active_setup.immutable_target_barrier-_Point &&
             g_active_setup.tp3>=g_active_setup.immutable_target_barrier-_Point);
         int barrier_event=FindCausalEventById(g_active_setup.immutable_target_barrier_event_id);
         if(barrier_event<0) barrier_source_ok=false;
         else
         {
            double reconstructed=g_active_setup.is_buy ? g_causal_events[barrier_event].bottom
                                                       : g_causal_events[barrier_event].top;
            barrier_source_ok=(MathAbs(reconstructed-
                               g_active_setup.immutable_target_barrier)<=_Point);
         }
      }
      if(!creation_ok || !geometry || !rr_ok || !barrier_ok || !barrier_source_ok)
      {reason="Active setup immutable timestamp/geometry/barrier mismatch"; return false;}
   }
   return true;
}

ulong CausalGraphFingerprint()
{
   int n=ArraySize(g_causal_events);
   int order[]; ArrayResize(order,n);
   for(int i=0;i<n;i++) order[i]=i;
   for(int i=1;i<n;i++)
   {
      int key=order[i],j=i-1;
      while(j>=0 && StringCompare(g_causal_events[order[j]].id,g_causal_events[key].id)>0)
      {order[j+1]=order[j]; j--;}
      order[j+1]=key;
   }

   ulong hash=1469598103934665603;
   for(int oi=0;oi<n;oi++)
   {
      int i=order[oi];
      string p1=(g_causal_events[i].parent_primary>=0 ?
                 g_causal_events[g_causal_events[i].parent_primary].id : "ROOT");
      string p2=(g_causal_events[i].parent_secondary>=0 ?
                 g_causal_events[g_causal_events[i].parent_secondary].id : "ROOT");
      string source_key="NONE";
      int source=g_causal_events[i].source_index;
      if((g_causal_events[i].type==CE_LIQ_POOL || g_causal_events[i].type==CE_LIQ_SWEEP) &&
         source>=0 && source<ArraySize(g_liquidity)) source_key=g_liquidity[source].id;
      else if(g_causal_events[i].type==CE_ORDER_BLOCK &&
              source>=0 && source<ArraySize(g_order_blocks)) source_key=g_order_blocks[source].id;
      else if(g_causal_events[i].type==CE_FVG &&
              source>=0 && source<ArraySize(g_fvgs)) source_key=g_fvgs[source].id;
      else if((g_causal_events[i].type==CE_BOS || g_causal_events[i].type==CE_CHOCH ||
               g_causal_events[i].type==CE_MSS || g_causal_events[i].type==CE_DISPLACEMENT) &&
              source>=0 && source<ArraySize(g_structures))
         source_key=StringFormat("STRUCT_%I64d_%s",(long)g_structures[source].time,
                                 g_structures[source].type);
      else if(source>=0) source_key="BAR_"+IntegerToString(source);
      string row=StringFormat("%s|%d|%d|%I64d|%d|%I64d|%s|%s|%d|%d|%s|%d|%s|%s|%s|%s",
                 g_causal_events[i].id,(int)g_causal_events[i].type,
                 g_causal_events[i].event_bar,(long)g_causal_events[i].event_time,
                 g_causal_events[i].availability_bar,(long)g_causal_events[i].availability_time,
                 p1,p2,g_causal_events[i].confirmed?1:0,
                 g_causal_events[i].invalidated?1:0,source_key,
                 g_causal_events[i].bullish?1:0,
                 DoubleToString(g_causal_events[i].price,_Digits),
                 DoubleToString(g_causal_events[i].top,_Digits),
                 DoubleToString(g_causal_events[i].bottom,_Digits),
                 DoubleToString(g_causal_events[i].strength,6));
      for(int k=0;k<StringLen(row);k++)
      {
         hash^=(ulong)StringGetCharacter(row,k);
         hash*=1099511628211;
      }
   }
   string setup_row="NO_SETUP";
   if(g_active_setup.active)
      setup_row=StringFormat("ACTIVE|%s|%s|%I64d|%d|%s|%s|%s|%s|%s|%s|%s|%s|%d",
         g_active_setup.id,g_active_setup.state,(long)g_active_setup.created_time,
         g_active_setup.is_buy?1:0,DoubleToString(g_active_setup.entry,_Digits),
         DoubleToString(g_active_setup.sl,_Digits),DoubleToString(g_active_setup.tp1,_Digits),
         DoubleToString(g_active_setup.tp2,_Digits),DoubleToString(g_active_setup.tp3,_Digits),
         DoubleToString(g_active_setup.rr1,6),DoubleToString(g_active_setup.rr2,6),
         DoubleToString(g_active_setup.rr3,6),
         DoubleToString(g_active_setup.immutable_target_barrier,_Digits),
         g_active_setup.reliability);
   else if(!InpUseRetestLifecycle && g_trade_setup.valid)
      setup_row=StringFormat("INSTANT|%s|%I64d|%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d",
         g_trade_setup.setup_event_id,(long)g_trade_setup.created_time,
         g_trade_setup.is_buy?1:0,DoubleToString(g_trade_setup.entry,_Digits),
         DoubleToString(g_trade_setup.sl,_Digits),DoubleToString(g_trade_setup.tp1,_Digits),
         DoubleToString(g_trade_setup.tp2,_Digits),DoubleToString(g_trade_setup.tp3,_Digits),
         DoubleToString(g_trade_setup.rr1,6),DoubleToString(g_trade_setup.rr2,6),
         DoubleToString(g_trade_setup.rr3,6),
         DoubleToString(g_trade_setup.immutable_target_barrier,_Digits),
         g_trade_setup.zone_event_id,g_trade_setup.reliability);
   for(int k=0;k<StringLen(setup_row);k++)
   {
      hash^=(ulong)StringGetCharacter(setup_row,k);
      hash*=1099511628211;
   }
   string selected_sweep=(g_active_setup.active ? g_active_setup.sweep_event_id :
                          g_trade_setup.sweep_event_id);
   string selected_disp=(g_active_setup.active ? g_active_setup.displacement_event_id :
                         g_trade_setup.displacement_event_id);
   string selected_structure=(g_active_setup.active ? g_active_setup.structure_event_id :
                              g_trade_setup.structure_event_id);
   string selected_zone=(g_active_setup.active ? g_active_setup.zone_event_id :
                         g_trade_setup.zone_event_id);
   if(selected_sweep=="") selected_sweep="NONE";
   if(selected_disp=="") selected_disp="NONE";
   if(selected_structure=="") selected_structure="NONE";
   if(selected_zone=="") selected_zone="NONE";
   string state_row=StringFormat("STATE|%d|%s|%s|%d|%s|%s|%I64d|%I64d|%s|%s|%s|%s|%d|%d|%d",
      g_struct_trend,DoubleToString(g_struct_last_high,_Digits),
      DoubleToString(g_struct_last_low,_Digits),g_htf_bias,g_htf_structure_state,
      g_d1_structure_state,(long)g_htf_last_event_time,
      (long)g_htf_last_availability_time,selected_sweep,selected_disp,
      selected_structure,selected_zone,g_signal_mask,g_trade_setup.confidence,
      g_trade_setup.reliability);
   for(int k=0;k<StringLen(state_row);k++)
   {
      hash^=(ulong)StringGetCharacter(state_row,k);
      hash*=1099511628211;
   }
   return hash;
}

void RunCausalGraphChecks(const datetime closed_time)
{
   if(!InpEnableCausalInvariantChecks)
   {
      g_causal_invariants_ok=true;
      return;
   }
   string reason="";
   g_causal_invariants_ok=ValidateCausalGraphInvariants(reason);
   if(!g_causal_invariants_ok)
   {
      g_replay_audit_status="INVARIANT FAIL";
      Print("[CausalInvariant] FAIL ",_Symbol," ",EnumToString((ENUM_TIMEFRAMES)_Period),
            " @ ",TimeToString(closed_time)," | ",reason);
   }
}

bool ResolveCausalPath(const int structure_source,int &sweep_event,int &displacement_event,
                       int &structure_event,int &ob_event,int &fvg_event)
{
   sweep_event=displacement_event=structure_event=ob_event=fvg_event=-1;
   for(int e=0;e<ArraySize(g_causal_events);e++)
   {
      ENUM_CAUSAL_EVENT_TYPE ty=g_causal_events[e].type;
      if((ty==CE_MSS || ty==CE_BOS || ty==CE_CHOCH) &&
         g_causal_events[e].source_index==structure_source)
      {structure_event=e; break;}
   }
   if(structure_event<0 || g_causal_events[structure_event].invalidated) return false;
   displacement_event=FindParentEventOfType(structure_event,CE_DISPLACEMENT);
   if(displacement_event<0 || g_causal_events[displacement_event].invalidated) return false;
   sweep_event=FindParentEventOfType(displacement_event,CE_LIQ_SWEEP);
   if(sweep_event<0 || g_causal_events[sweep_event].invalidated ||
      !g_causal_events[sweep_event].confirmed) return false;
   int pool_event=FindParentEventOfType(sweep_event,CE_LIQ_POOL);
   // A swept pool is consumed as a target, but remains a valid historical
   // ancestor; therefore confirmation/identity, not its consumed flag, governs ancestry.
   if(pool_event<0 || !g_causal_events[pool_event].confirmed ||
      !IsCausallyConnected(pool_event,sweep_event)) return false;

   double best_ob=-DBL_MAX,best_fvg=-DBL_MAX;
   string best_ob_id="",best_fvg_id="";
   for(int e=0;e<ArraySize(g_causal_events);e++)
   {
      if(g_causal_events[e].invalidated || !g_causal_events[e].confirmed) continue;
      if(g_causal_events[e].type==CE_ORDER_BLOCK && IsCausallyConnected(structure_event,e) &&
         (g_causal_events[e].strength>best_ob+1e-9 ||
          (MathAbs(g_causal_events[e].strength-best_ob)<=1e-9 &&
           (best_ob_id=="" || StringCompare(g_causal_events[e].id,best_ob_id)<0))))
      {best_ob=g_causal_events[e].strength; best_ob_id=g_causal_events[e].id; ob_event=e;}
      if(g_causal_events[e].type==CE_FVG && IsCausallyConnected(displacement_event,e) &&
         (g_causal_events[e].strength>best_fvg+1e-9 ||
          (MathAbs(g_causal_events[e].strength-best_fvg)<=1e-9 &&
           (best_fvg_id=="" || StringCompare(g_causal_events[e].id,best_fvg_id)<0))))
      {best_fvg=g_causal_events[e].strength; best_fvg_id=g_causal_events[e].id; fvg_event=e;}
   }
   return (ob_event>=0 || fvg_event>=0);
}

double CausalPathScore(const int sweep_event,const int displacement_event,const int structure_event,
                       const int ob_event,const int fvg_event)
{
   if(sweep_event<0 || displacement_event<0 || structure_event<0) return 0.0;
   int pool_event=FindParentEventOfType(sweep_event,CE_LIQ_POOL);
   if(pool_event<0 || !g_causal_events[sweep_event].confirmed ||
      !IsCausallyConnected(pool_event,sweep_event) ||
      !IsCausallyConnected(sweep_event,displacement_event) ||
      !IsCausallyConnected(displacement_event,structure_event)) return 0.0;
   double score=55.0;
   ENUM_CAUSAL_EVENT_TYPE st=g_causal_events[structure_event].type;
   score+=(st==CE_MSS ? 20.0 : (st==CE_CHOCH ? 12.0 : 8.0));
   if(ob_event>=0 && IsCausallyConnected(structure_event,ob_event)) score+=15.0;
   if(fvg_event>=0 && IsCausallyConnected(displacement_event,fvg_event)) score+=10.0;
   if(ob_event>=0 && fvg_event>=0) score+=5.0;
   return MathMin(100.0,score);
}

int SelectBestStructureAnchor(const int total,const double &c[],int &sweep_event,
                              int &displacement_event,int &structure_event,int &ob_event,int &fvg_event,
                              const int direction_filter)
{
   sweep_event=displacement_event=structure_event=ob_event=fvg_event=-1;
   datetime decision_time=(total>=2 && total-1<ArraySize(g_buf_t)) ? g_buf_t[total-1] : 0;
   if(decision_time<=0) return -1;
   int best=-1; double best_score=-DBL_MAX;
   string best_event_id="";
   for(int si=0;si<ArraySize(g_structures);si++)
   {
      SStructureBreak st=g_structures[si];
      if(st.type=="INIT") continue;
      if(direction_filter>0 && !st.bullish) continue;
      if(direction_filter<0 && st.bullish) continue;
      int age=(total-2)-st.bar;
      if(age<0 || (InpAnchorSearchBars>0 && age>InpAnchorSearchBars)) continue;
      if(InpRequireMSSAfterSweep && st.type!="MSS") continue;
      int sw=-1,dp=-1,se=-1,ob=-1,fv=-1;
      if(!ResolveCausalPath(si,sw,dp,se,ob,fv)) continue;
      if(sw<0 || dp<0 || se<0 ||
         !g_causal_events[sw].confirmed || !g_causal_events[dp].confirmed ||
         !g_causal_events[se].confirmed ||
         g_causal_events[sw].availability_time>decision_time ||
         g_causal_events[dp].availability_time>decision_time ||
         g_causal_events[se].availability_time>decision_time) continue;
      if(ob>=0 && (!g_causal_events[ob].confirmed ||
                   g_causal_events[ob].availability_time>decision_time ||
                   !IsCausallyConnected(se,ob))) ob=-1;
      if(fv>=0 && (!g_causal_events[fv].confirmed ||
                   g_causal_events[fv].availability_time>decision_time ||
                   !IsCausallyConnected(dp,fv) || !IsCausallyConnected(se,fv))) fv=-1;
      string location_reason="";
      if(ob>=0 && !IsInstitutionalLocation(st.bullish,g_causal_events[ob].top,
                                            g_causal_events[ob].bottom,g_atr,location_reason)) ob=-1;
      location_reason="";
      if(fv>=0 && !IsInstitutionalLocation(st.bullish,g_causal_events[fv].top,
                                            g_causal_events[fv].bottom,g_atr,location_reason)) fv=-1;
      if(ob<0 && fv<0) continue;
      double score=CausalPathScore(sw,dp,se,ob,fv);
      score+=MathMax(0.0,20.0-(double)age*20.0/MathMax(1,InpAnchorSearchBars));
      if(InpPreferMSSAnchor && st.type=="MSS") score+=12.0;
      if(g_htf_bias==(st.bullish?1:-1)) score+=8.0;
      if(ob>=0 && fv>=0) score+=5.0;
      string candidate_id=(se>=0 ? g_causal_events[se].id : "");
      if(score>best_score+1e-9 ||
         (MathAbs(score-best_score)<=1e-9 &&
          (best_event_id=="" || StringCompare(candidate_id,best_event_id)<0)))
      {
         best_score=score; best=si; best_event_id=candidate_id;
         sweep_event=sw; displacement_event=dp; structure_event=se; ob_event=ob; fvg_event=fv;
      }
   }
   return best;
}

int KnapsackOptimizeSignals(SSignalFactor &factors[],const int max_weight)
{
   if(!InpUseKnapsack || max_weight<=0) return 0;
   int n=ArraySize(factors);
   int dp[]; ArrayResize(dp,max_weight+1); ArrayInitialize(dp,0);
   for(int i=0;i<n;i++)
   {
      if(!factors[i].active) continue;
      int w=factors[i].weight; int v=factors[i].value;
      if(w<=0 || w>max_weight) continue;
      for(int cap=max_weight;cap>=w;cap--) dp[cap]=MathMax(dp[cap],dp[cap-w]+v);
   }
   return dp[max_weight];
}
int DynamicProgrammingConfidence(SSignalFactor &factors[])
{
   if(!InpUseDynamicProg) return 0;
   int n=ArraySize(factors);
   int dp[]; ArrayResize(dp,101); ArrayInitialize(dp,0);
   for(int i=0;i<n;i++)
   {
      if(!factors[i].active) continue;
      int w=factors[i].weight;
      if(w<=0 || w>100) continue;
      for(int j=100;j>=w;j--) dp[j]=MathMax(dp[j],dp[j-w]+factors[i].value);
   }
   return dp[100];
}

//====================================================================
// QUALITY ENGINE - 7 WEIGHTED PILLARS
//====================================================================
double ScoreStructure(const int total,const bool is_buy)
{
   int n=ArraySize(g_structures);
   if(n==0) return 0.0;
   int idx=n-1;
   if(InpInstitutionalSequence && g_selected_structure_event>=0 &&
      g_selected_structure_event<ArraySize(g_causal_events))
      idx=g_causal_events[g_selected_structure_event].source_index;
   if(idx<0 || idx>=n) return 0.0;
   SStructureBreak s=g_structures[idx];
   if(s.type=="INIT") return 0.0;
   if(s.bullish!=is_buy) return 0.0;
   double base=(s.type=="MSS")?100.0:(s.type=="BOS"?78.0:60.0);
   int age=(total-2)-s.bar;
   if(InpMaxStructureAge>0)
   {
      double decay=1.0-(double)age/(double)(InpMaxStructureAge*3);
      base*=MathMax(0.50,MathMin(1.0,decay));
   }
   return base;
}
double ScoreLiquidity(const bool is_buy,const int anchor_bar)
{
   int n=ArraySize(g_liquidity);
   double best=0.0;
   int scanned=0;
   for(int i=n-1;i>=0 && scanned<15;i--,scanned++)
   {
      if(anchor_bar > 0 && MathAbs(g_liquidity[i].bar - anchor_bar) > 40) continue;
      if(g_liquidity[i].swept && StringFind(g_liquidity[i].type,"TAKEN")>=0)
      {
         bool aligned=(is_buy && StringFind(g_liquidity[i].type,"SSL")>=0) ||
                      (!is_buy && StringFind(g_liquidity[i].type,"BSL")>=0);
         best=MathMax(best,aligned?100.0:40.0);
      }
      else if(!g_liquidity[i].swept && (g_liquidity[i].type=="EQH" || g_liquidity[i].type=="EQL"))
         best=MathMax(best,50.0);
   }
   return best;
}
double ScoreOrderBlock(const int ob_index,const double price,const double atr,const int anchor_bar)
{
   if(ob_index<0 || ob_index>=ArraySize(g_order_blocks)) return 0.0;
   if(g_order_blocks[ob_index].closed_state=="MITIGATED" || g_order_blocks[ob_index].state=="MITIGATED") return 0.0;
   if(anchor_bar > 0 && g_order_blocks[ob_index].origin_struct_bar != anchor_bar) return 20.0;
   double s=(g_order_blocks[ob_index].strength>=5)?100.0:(g_order_blocks[ob_index].strength>=4)?85.0:65.0;
   if(g_order_blocks[ob_index].closed_state=="TOUCHED" || g_order_blocks[ob_index].state=="TOUCHED") s*=(InpRelaxedMode?0.92:0.85);
   double dist=MathAbs(price-OBMid(ob_index));
   if(atr>0) s*=MathMax(0.40,1.0-(dist/(atr*8.0)));
   return MathMin(100.0,s);
}
double ScoreFVG(const bool is_buy,const double price,const int anchor_bar)
{
   double best=0.0;
   int fvg_count=0;
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].state=="FILLED") continue;
      if(g_fvgs[i].bullish!=is_buy) continue;
      if(InpInstitutionalSequence && anchor_bar>0 &&
         g_fvgs[i].source_structure_bar!=anchor_bar) continue;
      if(!InpInstitutionalSequence && anchor_bar > 0 &&
         (g_fvgs[i].bar < anchor_bar - 30 || g_fvgs[i].bar > anchor_bar)) continue;
      fvg_count++;
      double v=(g_fvgs[i].state=="OPEN")?80.0:(InpAllowPartialFVG?65.0:50.0);
      if(price<=g_fvgs[i].top && price>=g_fvgs[i].bottom) v=100.0;
      best=MathMax(best,v);
   }
   if(InpLogSignalDetails && fvg_count>0)
      Print(StringFormat(">>> FVG Score: %.1f (%d FVGs)",best,fvg_count));
   return best;
}
double ScoreSession()
{
   int closed=g_rates_total-2;
   datetime now=(closed>=0 && closed+1<ArraySize(g_buf_t)) ? g_buf_t[closed+1] : 0;
   if(IsInKillZone(now,SESSION_LONDON) || IsInKillZone(now,SESSION_NEWYORK)) return 100.0;
   if(IsInSession(now,SESSION_LONDON) || IsInSession(now,SESSION_NEWYORK)) return 75.0;
   if(IsInSession(now,SESSION_ASIA)) return 40.0;
   return 30.0;
}
double ScoreHTF(const bool is_buy)
{
   if(!InpUseHTFBias) return 50.0;
   if(g_htf_bias==0) return 50.0;
   return (g_htf_bias==(is_buy?1:-1))?100.0:0.0;
}
double ScoreAlgo(const int knap,const int dp,const int max_possible,const double price)
{
   if(InpInstitutionalSequence)
      return g_trade_setup.causal_path_score;
   double a=(max_possible>0)?100.0*knap/max_possible:0.0;
   double b=(max_possible>0)?100.0*dp/max_possible:0.0;
   double base=MathMax(a,b);
   double conf=(InpUseGraphTheory && !InpInstitutionalSequence)?GraphConfluenceScore(price):0.0;
   return MathMin(100.0,base*0.70+conf*0.30);
}
string DetectMarketRegime(const int closed,const double atr)
{
   if(!InpUseRegimeAdaptiveScoring) return "NEUTRAL";
   double avg_atr=0.0; int n=0;
   int start=MathMax(0,closed-20);
   for(int i=start;i<closed && i<ArraySize(g_atr_buf);i++)
   {
      if(g_atr_buf[i]>0.0){avg_atr+=g_atr_buf[i]; n++;}
   }
   if(n<=0 || atr<=0.0) return "NEUTRAL";
   avg_atr/=n;
   double vol_ratio=atr/MathMax(avg_atr,_Point);
   if(g_adx>=InpADXTrendLevel && vol_ratio>=1.08) return "EXPANSION";
   if(g_adx>=InpADXTrendLevel) return "TREND";
   if(g_adx<=InpADXChopLevel && vol_ratio<=0.94) return "COMPRESSION";
   if(g_adx<=InpADXChopLevel) return "RANGE";
   return "TRANSITION";
}

double RegimeScoreMultiplier(const string regime)
{
   if(!InpUseRegimeAdaptiveScoring) return 1.0;
   if(regime=="EXPANSION") return InpRegimeExpansionBonus;
   if(regime=="TREND") return InpRegimeTrendBonus;
   if(regime=="RANGE") return InpRegimeRangePenalty;
   if(regime=="COMPRESSION") return InpRegimeCompressionPenalty;
   return 0.97;
}

int ContextualCandleScore(const SCandleIntel &candle,const bool is_buy,const double price,
                          const double zone_top,const double zone_bottom,const double atr,
                          const bool sweep_ok,const bool structure_ok,const bool zone_ok,
                          const string regime)
{
   if(!InpUseContextualCandleScoring || !candle.valid) return 0;
   if(!CandleConfirmsDirection(candle,is_buy)) return 0;
   double score=(double)candle.score*0.45;
   double zone_mid=(zone_top+zone_bottom)*0.5;
   bool candle_in_zone=(price<=zone_top+MathMax(_Point,atr*0.15) &&
                        price>=zone_bottom-MathMax(_Point,atr*0.15));
   if(zone_ok) score+=12.0;
   if(candle_in_zone) score+=8.0;
   if(sweep_ok) score+=10.0;
   if(structure_ok) score+=10.0;
   if(candle.close_location>=0.80 || candle.close_location<=0.20) score+=6.0;
   if(candle.body_ratio>=0.55) score+=4.0;
   if(regime=="EXPANSION" || regime=="TREND") score+=4.0;
   if(regime=="COMPRESSION") score-=4.0;
   if(candle.pattern=="DOJI") score-=20.0;
   return (int)MathMax(0,MathMin(100,MathRound(score)));
}

int IndependentEvidenceScore(SSignalFactor &factors[])
{
   if(!InpUseEvidenceIndependence) return 0;
   // Cluster evidence so causal derivatives are not counted as independent
   // votes. MSS/CHOCH/BOS share one structure cluster; OB/FVG share one zone
   // cluster; session/kill-zone/Judas share one timing cluster.
   int structure=0,zone=0,liquidity=0,context=0,timing=0,candle=0;
   for(int i=0;i<ArraySize(factors);i++)
   {
      if(!factors[i].active) continue;
      string n=factors[i].name;
      if(n=="MSS") structure=MathMax(structure,30);
      else if(n=="CHoCH") structure=MathMax(structure,24);
      else if(n=="BOS") structure=MathMax(structure,20);
      else if(n=="Aligned Sweep") liquidity=MathMax(liquidity,25);
      else if(n=="Causal OB") zone=MathMax(zone,15);
      else if(n=="Causal FVG") zone=MathMax(zone,10);
      else if(n=="OTE Zone" || n=="PD Context") context=MathMax(context,10);
      else if(n=="HTF Bias") context=MathMax(context,10);
      else if(n=="Kill Zone" || n=="Judas Swing") timing=MathMax(timing,10);
      else if(n=="Candle Confirmation") candle=MathMax(candle,15);
   }
   int total=structure+zone+liquidity+context+timing+candle;
   return MathMin(100,total);
}

int MaxPossibleValue(SSignalFactor &f[])
{
   int sum=0;
   for(int i=0;i<ArraySize(f);i++) sum+=f[i].value;
   return MathMax(1,sum);
}
int CalculateReliability(const int conf,const int knap,const int dp,const int maxp)
{
   // Reliability is a deterministic, explainable 0..100 quality index.
   // It is NOT P(win), contains no statistical calibration, and does not use
   // DP/Knapsack as evidence of predictive power in institutional mode.
   if(InpInstitutionalSequence)
   {
      double zone=MathMax(g_score.orderblock,g_score.fvg);
      double htf=(g_htf_bias==(g_trade_setup.is_buy?1:-1) ? 100.0 : (g_htf_bias==0 ? 50.0 : 0.0));
      double recency=50.0;
      if(g_selected_structure_event>=0 && g_selected_structure_event<ArraySize(g_causal_events))
      {
         int age=g_causal_events[g_selected_structure_event].age;
         recency=MathMax(0.0,100.0-(double)age*100.0/MathMax(1,InpAnchorSearchBars));
      }
      double market=50.0;
      if(g_adx>=InpADXTrendLevel) market=100.0;
      else if(g_adx>0.0 && g_adx<InpADXChopLevel) market=20.0;
      // Live spread is an execution gate, not replay-stable quality evidence.
      double rel=g_trade_setup.causal_path_score*0.40+
                 g_score.structure*0.15+zone*0.15+htf*0.10+
                 g_score.session*0.05+recency*0.10+market*0.05;
      return (int)MathMax(0,MathMin(100,MathRound(rel)));
   }
   // Flexible legacy mode retains a heuristic quality index, never a statistical likelihood.
   double kn=(maxp>0)?100.0*knap/maxp:0.0;
   double dn=(maxp>0)?100.0*dp/maxp:0.0;
   double rel=conf*0.50+kn*0.30+dn*0.20;
   if(g_htf_bias==(g_trade_setup.is_buy?1:-1)) rel+=4;
   if(CheckSignalPattern(BIT_KILLZONE)) rel+=3;
   return (int)MathMax(0,MathMin(100,MathRound(rel)));
}
string CalculateQualityGrade(const int conf,const int reliability)
{
   int s=(int)MathRound(conf*0.60+reliability*0.40);
   bool perfect=InpInstitutionalSequence
                ? (g_trade_setup.sweep_bar>=0 && g_trade_setup.zone_source!="")
                : CheckSignalPattern(BIT_MSS|BIT_STRONG_OB|BIT_LIQUIDITY|BIT_OTE);
   if(s>=90 && perfect) return "A+";
   if(s>=85) return "A";
   if(s>=72) return "B";
   if(s>=60) return "C";
   return "D";
}
int GradeRank(const string g)
{
   if(g=="A+") return 5;
   if(g=="A") return 4;
   if(g=="B") return 3;
   if(g=="C") return 2;
   return 1;
}
string GetInstitutionalGrade(const int conf,const int knap,const int dp,const int maxp)
{
   int t=0;
   if(InpInstitutionalSequence)
      t=(int)MathRound(conf*0.30+g_trade_setup.reliability*0.30+
                       g_trade_setup.causal_path_score*0.40);
   else
   {
      double kn=(maxp>0)?100.0*knap/maxp:0.0;
      double dn=(maxp>0)?100.0*dp/maxp:0.0;
      t=(int)MathRound((conf+kn+dn)/3.0);
   }
   if(t>=85) return "Institutional";
   if(t>=68) return "Professional";
   return "Retail";
}
string CalculateRiskLevel(const double entry,const double sl,const double atr,const long spread_pts,double &risk_pips_out)
{
   double pip=PipSize();
   double risk=MathAbs(entry-sl);
   risk_pips_out=(pip>0)?risk/pip:0.0;
   double atr_mult=(atr>0)?risk/atr:99.0;
   double sp_ratio=(risk>0)?(spread_pts*_Point)/risk:1.0;
   int pts=0;
   if(atr_mult<=1.20) pts+=2; else if(atr_mult<=2.00) pts+=1;
   if(sp_ratio<=0.08) pts+=2; else if(sp_ratio<=0.15) pts+=1;
   if(spread_pts<=InpMaxSpreadPts/2) pts+=1;
   if(pts>=4) return "LOW";
   if(pts>=2) return "MEDIUM";
   return "HIGH";
}
string BuildConfidenceBar(const int pct,const int cells)
{
   int filled=(int)MathRound((double)pct/100.0*cells);
   filled=MathMax(0,MathMin(cells,filled));
   string full=InpASCIIBar?"#":"█";
   string empt=InpASCIIBar?"-":"░";
   string bar="";
   for(int i=0;i<filled;i++) bar+=full;
   for(int i=filled;i<cells;i++) bar+=empt;
   return bar;
}
//--------------------------------------------------------------------
int FindAlignedLiquiditySweep(const bool is_buy,const int structure_bar,const int max_bars,double &price_out)
{
   price_out=0.0;
   int best=-1;
   int best_bar=-1;
   string best_id="";
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(!g_liquidity[i].swept) continue;
      bool aligned=is_buy ? (StringFind(g_liquidity[i].type,"SSL")>=0)
                          : (StringFind(g_liquidity[i].type,"BSL")>=0);
      if(!aligned) continue;
      int age=structure_bar-g_liquidity[i].origin_bar;
      if(age<0) continue;                       // sweep must precede the break
      if(max_bars>0 && age>max_bars) continue;
      if(g_liquidity[i].origin_bar>best_bar ||
         (g_liquidity[i].origin_bar==best_bar &&
          (best_id=="" || StringCompare(g_liquidity[i].id,best_id)<0)))
      {
         best=i;
         best_bar=g_liquidity[i].origin_bar;
         best_id=g_liquidity[i].id;
         price_out=g_liquidity[i].price;
      }
   }
   return best;
}

int SelectEntryOB(const double price,const bool is_buy,const double atr,const int anchor_bar,const int sweep_bar)
{
   int n=ArraySize(g_order_blocks);
   if(n==0) return -1;

   double a=(atr>0.0 ? atr : _Point*100.0);
   double max_dist=a*(InpInstitutionalSequence ? InpMaxOBDistATR
                                               : (InpRelaxedMode ? 12.0 : InpMaxOBDistATR));
   int best=-1;
   double best_score=-DBL_MAX;
   string best_uid="";
   int candidates=0;

   for(int i=0;i<n;i++)
   {
      SOrderBlock ob=g_order_blocks[i];
      if(ob.bullish!=is_buy) continue;
      if(ob.state=="MITIGATED" || ob.closed_state=="MITIGATED") continue;
      if(ob.strength<InpMinEntryOBStrength) continue;

      if(InpInstitutionalSequence)
      {
         if(anchor_bar>=0 && ob.origin_struct_bar!=anchor_bar) continue;
         if(sweep_bar>=0 && ob.bar<sweep_bar-MathMax(0,InpOrderZonePreSweepBars)) continue;
      }

      double mid=(ob.top+ob.bottom)*0.5;
      double dist=MathAbs(price-mid);
      if(dist>max_dist) continue;
      // A buy zone should normally be below price; a sell zone above it.
      if(InpInstitutionalSequence)
      {
         if(is_buy && mid>price+a*0.25) continue;
         if(!is_buy && mid<price-a*0.25) continue;
      }
      else if(!InpRelaxedMode)
      {
         if(is_buy && mid>price+a*0.5) continue;
         if(!is_buy && mid<price-a*0.5) continue;
      }

      candidates++;
      double distance_score=MathMax(0.0,100.0-(dist/a)*12.0);
      double score=ob.strength*18.0+distance_score;
      if(ob.closed_state=="TOUCHED" || ob.state=="TOUCHED") score*=0.82;
      if(score>best_score+1e-9 ||
         (MathAbs(score-best_score)<=1e-9 &&
          (best_uid=="" || StringCompare(ob.id,best_uid)<0)))
      {best_score=score; best_uid=ob.id; best=i;}
   }

   if(InpShowDebugAlerts || InpLogSignalDetails)
      Print(StringFormat(">>> Institutional OB %s: candidates=%d selected=%d",
                         is_buy?"BUY":"SELL",candidates,best));
   return best;
}

int SelectEntryFVG(const double price,const bool is_buy,const double atr,const int anchor_bar,const int sweep_bar)
{
   if(!InpAllowFVGEntryZone) return -1;
   double a=(atr>0.0 ? atr : _Point*100.0);
   int best=-1;
   double best_score=DBL_MAX;
   string best_id="";
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      SFVG f=g_fvgs[i];
      if(f.bullish!=is_buy || f.state=="FILLED") continue;
      if(!InpAllowPartialFVG && f.state=="PARTIAL") continue;
      if(InpInstitutionalSequence)
      {
         if(f.source_displacement_event_id=="" || f.source_structure_event_id=="") continue;
         if(sweep_bar>=0 && f.source_displacement_bar<=sweep_bar) continue;
         if(anchor_bar>=0 && f.source_structure_bar!=anchor_bar) continue;
      }
      double mid=(f.top+f.bottom)*0.5;
      double dist=MathAbs(price-mid);
      if(dist>a*InpMaxOBDistATR) continue;
      if(InpInstitutionalSequence)
      {
         if(is_buy && mid>price+a*0.25) continue;
         if(!is_buy && mid<price-a*0.25) continue;
      }
      double height=MathAbs(f.top-f.bottom);
      double score=dist+height*0.35+(f.state=="PARTIAL" ? a*0.35 : 0.0);
      if(score<best_score-1e-9 ||
         (MathAbs(score-best_score)<=1e-9 &&
          (best_id=="" || StringCompare(f.id,best_id)<0)))
      {best_score=score; best_id=f.id; best=i;}
   }
   return best;
}

bool IsInstitutionalLocation(const bool is_buy,const double zone_top,const double zone_bottom,
                             const double atr,string &why)
{
   why="";
   if(!InpInstitutionalSequence || !InpBlockEquilibriumEntries) return true;
   double eq=(g_range.valid ? g_range.eq : g_htf_eq);
   if(eq<=0.0)
   {
      why="No dealing-range equilibrium";
      return false;
   }
   double mid=(zone_top+zone_bottom)*0.5;
   double buffer=(atr>0.0 ? atr*InpEquilibriumBufferATR : 0.0);
   if(is_buy && mid>=eq-buffer)
   {
      why="BUY zone is not in discount";
      return false;
   }
   if(!is_buy && mid<=eq+buffer)
   {
      why="SELL zone is not in premium";
      return false;
   }
   return true;
}

//--------------------------------------------------------------------
void PushTarget(STarget &arr[],STarget &t)
{
   int i=ArraySize(arr); ArrayResize(arr,i+1,16); arr[i]=t;
}
bool GetClosedCurrentDayHighLow(double &day_high,double &day_low)
{
   day_high=-DBL_MAX; day_low=DBL_MAX;
   int closed=g_rates_total-2;
   if(closed<0 || closed>=ArraySize(g_buf_t) || closed>=ArraySize(g_buf_h) ||
      closed>=ArraySize(g_buf_l)) return false;
   // Shift 0 is used only for the current D1 candle's OPEN boundary; no
   // forming D1 OHLC value is consumed.  This respects broker day boundaries.
   datetime anchor=iTime(_Symbol,PERIOD_D1,0);
   if(anchor<=0 || anchor>g_buf_t[closed]) anchor=DayAnchor(g_buf_t[closed]);
   bool found=false;
   for(int i=closed;i>=0;i--)
   {
      if(g_buf_t[i]<anchor) break;
      day_high=MathMax(day_high,g_buf_h[i]);
      day_low=MathMin(day_low,g_buf_l[i]);
      found=true;
   }
   return (found && day_high>=day_low);
}
double GreedyFindBestTarget(const double from,const bool is_buy,const double min_dist,string &type_out)
{
   type_out="ATR Projection";
   STarget tg[]; ArrayResize(tg,0,16);
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      // Targets are resting liquidity, never liquidity that was already taken.
      if(g_liquidity[i].swept) continue;
      if(is_buy && g_liquidity[i].type!="EQH") continue;
      if(!is_buy && g_liquidity[i].type!="EQL") continue;
      double p=g_liquidity[i].price;
      if(!((is_buy && p>from+min_dist) || (!is_buy && p<from-min_dist))) continue;
      STarget t; t.price=p; t.priority=10; t.type=g_liquidity[i].type+" Pool";
      PushTarget(tg,t);
   }
   for(int i=0;i<ArraySize(g_order_blocks);i++)
   {
      if(g_order_blocks[i].bullish==is_buy) continue;
      double p=is_buy?g_order_blocks[i].bottom:g_order_blocks[i].top;
      if(!((is_buy && p>from+min_dist) || (!is_buy && p<from-min_dist))) continue;
      STarget t; t.price=p; t.priority=7; t.type="Opposing OB"; PushTarget(tg,t);
   }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].state=="FILLED") continue;
      double p=is_buy?g_fvgs[i].bottom:g_fvgs[i].top;
      if(!((is_buy && p>from+min_dist) || (!is_buy && p<from-min_dist))) continue;
      STarget t; t.price=p; t.priority=6; t.type="FVG Edge"; PushTarget(tg,t);
   }
   double mag[4]; string mn[4];
   // Previous-day values are closed shift 1. Current-day extrema are rebuilt
   // only from chart bars through total-2, never from the forming D1 candle.
   double closed_day_high=0.0,closed_day_low=0.0;
   bool have_closed_day=GetClosedCurrentDayHighLow(closed_day_high,closed_day_low);
   mag[0]=(g_d1_high>0? g_d1_high : iHigh(_Symbol,PERIOD_D1,1)); mn[0]="PDH";
   mag[1]=(g_d1_low>0?  g_d1_low  : iLow(_Symbol,PERIOD_D1,1)); mn[1]="PDL";
   mag[2]=(have_closed_day?closed_day_high:0.0); mn[2]="Closed-day High";
   mag[3]=(have_closed_day?closed_day_low:0.0); mn[3]="Closed-day Low";
   for(int k=0;k<4;k++)
   {
      double p=mag[k]; if(p<=0) continue;
      if(!((is_buy && p>from+min_dist) || (!is_buy && p<from-min_dist))) continue;
      STarget t; t.price=p; t.priority=(k<2)?5:4; t.type=mn[k]; PushTarget(tg,t);
   }
   if(ArraySize(tg)==0) return 0.0;
   int best=0;
   for(int i=1;i<ArraySize(tg);i++)
   {
      if(tg[i].priority>tg[best].priority){best=i; continue;}
      if(tg[i].priority==tg[best].priority)
      {
         if(is_buy && tg[i].price<tg[best].price) best=i;
         if(!is_buy && tg[i].price>tg[best].price) best=i;
      }
   }
   type_out=tg[best].type;
   return tg[best].price;
}

double DirectionalRR(const bool is_buy,const double entry,const double sl,const double target)
{
   double risk=is_buy ? entry-sl : sl-entry;
   if(risk<=_Point) return -1.0;
   double reward=is_buy ? target-entry : entry-target;
   if(reward<=0.0) return -1.0;
   return reward/risk;
}

bool ValidateTargetGeometry(const bool is_buy,const double entry,const double sl,
                            const double tp1,const double tp2,const double tp3)
{
   if(is_buy)
      return (sl<entry && entry<tp1 && tp1<tp2 && tp2<tp3);
   return (sl>entry && entry>tp1 && tp1>tp2 && tp2>tp3);
}

double NearestOpposingBarrier(const double from,const bool is_buy,string &type_out,
                               string &source_event_id,int &source_bar)
{
   type_out=""; source_event_id=""; source_bar=-1;
   double best=0.0,best_dist=DBL_MAX;
   string best_key="";
   for(int i=0;i<ArraySize(g_order_blocks);i++)
   {
      SOrderBlock ob=g_order_blocks[i];
      if(ob.bullish==is_buy || ob.state=="MITIGATED" || ob.closed_state=="MITIGATED") continue;
      int cev=FindCausalEventBySource(CE_ORDER_BLOCK,i);
      if(InpInstitutionalSequence && (cev<0 || g_causal_events[cev].invalidated || !g_causal_events[cev].confirmed)) continue;
      double p=is_buy ? ob.bottom : ob.top;
      if((is_buy && p<=from) || (!is_buy && p>=from)) continue;
      double d=MathAbs(p-from);
      string key=(cev>=0 ? g_causal_events[cev].id : ob.id);
      if(d<best_dist-1e-9 ||
         (MathAbs(d-best_dist)<=1e-9 && (best_key=="" || StringCompare(key,best_key)<0)))
      {
         best_dist=d; best=p; best_key=key; type_out="Opposing OB";
         source_event_id=(cev>=0 ? g_causal_events[cev].id : ""); source_bar=ob.bar;
      }
   }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      SFVG f=g_fvgs[i];
      if(f.bullish==is_buy || f.state=="FILLED") continue;
      int cev=FindCausalEventBySource(CE_FVG,i);
      if(InpInstitutionalSequence && (cev<0 || g_causal_events[cev].invalidated || !g_causal_events[cev].confirmed)) continue;
      double p=is_buy ? f.bottom : f.top;
      if((is_buy && p<=from) || (!is_buy && p>=from)) continue;
      double d=MathAbs(p-from);
      string key=(cev>=0 ? g_causal_events[cev].id : f.id);
      if(d<best_dist-1e-9 ||
         (MathAbs(d-best_dist)<=1e-9 && (best_key=="" || StringCompare(key,best_key)<0)))
      {
         best_dist=d; best=p; best_key=key; type_out="Opposing FVG";
         source_event_id=(cev>=0 ? g_causal_events[cev].id : ""); source_bar=f.bar;
      }
   }
   return best;
}

double FindInstitutionalTarget(const double from,const double entry,const double sl,const bool is_buy,
                               const double min_dist,const double min_rr,const int stage,
                               const double hard_barrier,string &type_out,string &source_event_id,
                               int &source_bar,bool &consumed,bool &barrier_bound)
{
   type_out=""; source_event_id=""; source_bar=-1; consumed=false; barrier_bound=false;
   STarget candidates[]; ArrayResize(candidates,0,16);
   double barrier=hard_barrier;
   // All TP stages share one immutable barrier discovered from Entry.  The
   // ceiling/floor is never recalculated from TP1 or TP2.

   // Resting external liquidity: consumed pools are never targets.
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      SLiquidity q=g_liquidity[i];
      if(q.swept) continue;
      if(is_buy && q.type!="EQH") continue;
      if(!is_buy && q.type!="EQL") continue;
      int cev=FindCausalEventBySource(CE_LIQ_POOL,i);
      if(InpInstitutionalSequence && (cev<0 || g_causal_events[cev].invalidated || !g_causal_events[cev].confirmed)) continue;
      double p=q.price;
      if((is_buy && p<=from+min_dist) || (!is_buy && p>=from-min_dist)) continue;
      STarget t; t.price=p; t.priority=100; t.type=q.type+" RESTING";
      t.source_bar=q.bar; t.event_index=cev; t.consumed=false; t.score=0.0;
      PushTarget(candidates,t);
   }

   // First opposing order-flow barriers are valid objectives themselves.
   for(int i=0;i<ArraySize(g_order_blocks);i++)
   {
      SOrderBlock ob=g_order_blocks[i];
      if(ob.bullish==is_buy || ob.state=="MITIGATED" || ob.closed_state=="MITIGATED") continue;
      int cev=FindCausalEventBySource(CE_ORDER_BLOCK,i);
      if(InpInstitutionalSequence && (cev<0 || g_causal_events[cev].invalidated || !g_causal_events[cev].confirmed)) continue;
      double p=is_buy ? ob.bottom : ob.top;
      if((is_buy && p<=from+min_dist) || (!is_buy && p>=from-min_dist)) continue;
      STarget t; t.price=p; t.priority=(ob.state=="TOUCHED"?65:80); t.type="Opposing OB edge";
      t.source_bar=ob.bar; t.event_index=cev; t.consumed=false; t.score=0.0;
      PushTarget(candidates,t);
   }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      SFVG f=g_fvgs[i];
      if(f.bullish==is_buy || f.state=="FILLED") continue;
      int cev=FindCausalEventBySource(CE_FVG,i);
      if(InpInstitutionalSequence && (cev<0 || g_causal_events[cev].invalidated || !g_causal_events[cev].confirmed)) continue;
      double p=is_buy ? f.bottom : f.top;
      if((is_buy && p<=from+min_dist) || (!is_buy && p>=from-min_dist)) continue;
      STarget t; t.price=p; t.priority=(f.state=="OPEN"?72:55); t.type="Opposing FVG edge";
      t.source_bar=f.bar; t.event_index=cev; t.consumed=false; t.score=0.0;
      PushTarget(candidates,t);
   }

   // Previous-day external liquidity, only while not already consumed today.
   double pdh=(g_d1_high>0.0 ? g_d1_high : iHigh(_Symbol,PERIOD_D1,1));
   double pdl=(g_d1_low>0.0 ? g_d1_low : iLow(_Symbol,PERIOD_D1,1));
   double cur_high=0.0,cur_low=0.0;
   bool have_closed_day=GetClosedCurrentDayHighLow(cur_high,cur_low);
   if(have_closed_day && is_buy && pdh>from+min_dist && cur_high<pdh-_Point)
   {
      STarget t; t.price=pdh; t.priority=92; t.type="PDH liquidity"; t.source_bar=-1;
      t.event_index=-1; t.consumed=false; t.score=0.0; PushTarget(candidates,t);
   }
   if(have_closed_day && !is_buy && pdl<from-min_dist && cur_low>pdl+_Point)
   {
      STarget t; t.price=pdl; t.priority=92; t.type="PDL liquidity"; t.source_bar=-1;
      t.event_index=-1; t.consumed=false; t.score=0.0; PushTarget(candidates,t);
   }

   int best=-1; double best_score=-DBL_MAX;
   string best_key="";
   double atr=(g_atr>0.0 ? g_atr : 100.0*_Point);
   double distance_weight=(stage<=1 ? 15.0 : (stage==2 ? 8.0 : 4.0));
   for(int i=0;i<ArraySize(candidates);i++)
   {
      double p=candidates[i].price;
      double rr=DirectionalRR(is_buy,entry,sl,p);
      if(rr<min_rr) continue;
      if(barrier>0.0)
      {
         bool beyond=is_buy ? (p>barrier+_Point) : (p<barrier-_Point);
         if(beyond) continue;
      }
      double dist=MathAbs(p-from)/atr;
      double score=candidates[i].priority*10.0-dist*distance_weight;
      candidates[i].score=score;
      string key=(candidates[i].event_index>=0 && candidates[i].event_index<ArraySize(g_causal_events)) ?
                  g_causal_events[candidates[i].event_index].id :
                  StringFormat("%s_%d_%s",candidates[i].type,candidates[i].source_bar,
                               DoubleToString(candidates[i].price,_Digits));
      if(score>best_score+1e-9 ||
         (MathAbs(score-best_score)<=1e-9 &&
          (best_key=="" || StringCompare(key,best_key)<0)))
      {best_score=score; best_key=key; best=i;}
   }
   if(best<0) return 0.0;
   type_out=candidates[best].type;
   source_bar=candidates[best].source_bar;
   consumed=candidates[best].consumed;
   if(candidates[best].event_index>=0 && candidates[best].event_index<ArraySize(g_causal_events))
      source_event_id=g_causal_events[candidates[best].event_index].id;
   else
      source_event_id=StringFormat("LEVEL_%s_%s",_Symbol,candidates[best].type);
   barrier_bound=(barrier>0.0 && MathAbs(candidates[best].price-barrier)<=_Point);
   return candidates[best].price;
}

void AddReason(const string reason)
{
   if(reason=="") return;
   if(g_trade_setup.reason_count>=14) return;
   for(int i=0;i<g_trade_setup.reason_count;i++)
      if(g_trade_setup.reasons[i]==reason) return;
   g_trade_setup.reasons[g_trade_setup.reason_count++]=reason;
}
void AddBlocker(const string reason)
{
   if(reason=="") return;
   if(g_trade_setup.blocker_count>=10) return;
   for(int i=0;i<g_trade_setup.blocker_count;i++)
      if(g_trade_setup.blockers[i]==reason) return;
   g_trade_setup.blockers[g_trade_setup.blocker_count++]=reason;
}

bool CreateSetupBranchTransactional(const string setup_event_id,const int closed,
                                    const datetime decision_time,const bool is_buy,
                                    const double entry,const double zone_top,const double zone_bottom,
                                    const double tp1,const double tp2,const double tp3)
{
   // All-or-nothing CE_SETUP + CE_TARGET insertion.  Every child cites its
   // own evidence source as primary parent so target replay stays possible
   // after the setup is removed.
   if(!InpEnableCausalInvariantChecks)
   {
      int zone=FindCausalEventById(g_trade_setup.zone_event_id);
      int structure=FindCausalEventById(g_trade_setup.structure_event_id);
      if(zone<0 || structure<0) return false;
      int setup=AddCausalEvent(setup_event_id,CE_SETUP,closed,decision_time,is_buy,
                               entry,zone_top,zone_bottom,zone,structure,
                               g_trade_setup.reliability,true,false,-1);
      if(setup<0) return false;
      double targets[3]; targets[0]=tp1; targets[1]=tp2; targets[2]=tp3;
      double strengths[3]; strengths[0]=90.0; strengths[1]=75.0; strengths[2]=60.0;
      for(int ti=0;ti<3;ti++)
      {
         int src=FindCausalEventById(g_trade_setup.tp_source_event_id[ti]);
         if(src<0) src=zone;
         AddCausalEvent(StringFormat("CE_TP%d_%s_%I64d_%s",ti+1,_Symbol,
                                     (long)decision_time,
                                     DoubleToString(targets[ti],_Digits)),
                        CE_TARGET,closed,decision_time,is_buy,targets[ti],
                        targets[ti],targets[ti],src,setup,strengths[ti],true,false,
                        g_trade_setup.tp_source_bar[ti]);
      }
      return true;
   }

   int size_before=ArraySize(g_causal_events);
   int zone=FindCausalEventById(g_trade_setup.zone_event_id);
   int structure=FindCausalEventById(g_trade_setup.structure_event_id);
   if(zone<0 || structure<0) return false;
   int setup=AddCausalEvent(setup_event_id,CE_SETUP,closed,decision_time,is_buy,
                            entry,zone_top,zone_bottom,zone,structure,
                            g_trade_setup.reliability,true,false,-1);
   if(setup>=0)
   {
      double targets[3]; targets[0]=tp1; targets[1]=tp2; targets[2]=tp3;
      double strengths[3]; strengths[0]=90.0; strengths[1]=75.0; strengths[2]=60.0;
      for(int ti=0;ti<3;ti++)
      {
         int src=FindCausalEventById(g_trade_setup.tp_source_event_id[ti]);
         if(src<0) src=zone;
         AddCausalEvent(StringFormat("CE_TP%d_%s_%I64d_%s",ti+1,_Symbol,
                                     (long)decision_time,
                                     DoubleToString(targets[ti],_Digits)),
                        CE_TARGET,closed,decision_time,is_buy,targets[ti],
                        targets[ti],targets[ti],src,setup,strengths[ti],true,false,
                        g_trade_setup.tp_source_bar[ti]);
      }
   }

   string fail_reason="";
   if(setup<0 || !ValidateCausalGraphInvariants(fail_reason))
   {
      RollbackCausalGraphToSize(size_before);
      g_replay_audit_status="INVARIANT FAIL";
      Print("[CausalBranch] ROLLBACK ",setup_event_id," | ",
            (fail_reason==""?"setup event rejected":fail_reason));
      return false;
   }
   if(InpLogLifecycleTransitions)
      Print("[CausalBranch] setup branch created: ",setup_event_id);
   return true;
}

void ResetCausalHopReport()
{
   g_causal_diag.hop_count=0;
   for(int i=0;i<MAX_CAUSAL_HOPS;i++)
   {
      g_causal_diag.types[i]="";
      g_causal_diag.ids[i]="";
      g_causal_diag.event_bars[i]=-1;
      g_causal_diag.age_bars[i]=-1;
      g_causal_diag.strengths[i]=0.0;
   }
}

void RecordCausalHop(const string hop_type,const string hop_id,const int hop_bar,
                     const int hop_age,const double hop_strength)
{
   if(g_causal_diag.hop_count>=MAX_CAUSAL_HOPS) return;
   int i=g_causal_diag.hop_count;
   g_causal_diag.types[i]=hop_type;
   g_causal_diag.ids[i]=hop_id;
   g_causal_diag.event_bars[i]=hop_bar;
   g_causal_diag.age_bars[i]=hop_age;
   g_causal_diag.strengths[i]=hop_strength;
   g_causal_diag.hop_count++;
}

void DashPushWrapped(string &L[],int &ln,const string s,const int width)
{
   // Pure text helper: word-wraps s into L[] at ln. The dashboard printer
   // owns all object creation; this only prepares display lines.
   int max_chars=MathMax(10,width);
   int len=StringLen(s);
   if(len<=max_chars)
   {
      int n=ArraySize(L);
      ArrayResize(L,n+1,32);
      L[n]=s;
      ln++;
      return;
   }
   string cur="";
   string word="";
   for(int i=0;i<=len;i++)
   {
      ushort ch=(i<len ? StringGetCharacter(s,i) : ' ');
      if(ch==' ' || i==len)
      {
         string trial=(cur=="" ? word : cur+" "+word);
         if(StringLen(trial)>max_chars && cur!="")
         {
            int n=ArraySize(L);
            ArrayResize(L,n+1,32);
            L[n]=cur;
            ln++;
            cur=word;
         }
         else
            cur=trial;
         word="";
      }
      else
         word+=ShortToString(ch);
   }
   if(cur!="")
   {
      int n=ArraySize(L);
      ArrayResize(L,n+1,32);
      L[n]=cur;
      ln++;
   }
}

string GateTxt(const bool ok)
{
   return ok?"[v] ":"[ ] ";
}
string NormText(const string s)
{
   return s;
}
string TFName(const ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return EnumToString(tf);
}
string IntegerToBinary(const int num)
{
   // Compact mask visualisation: lowest 12 bits cover every defined BIT_*.
   string s="";
   for(int i=11;i>=0;i--)
      s+=(((num>>i)&1)==1)?"1":"0";
   return s;
}
color ColorLerp(const color c1,const color c2,const double t)
{
   double f=MathMax(0.0,MathMin(1.0,t)); // const param: blend via local factor
   int r1=(c1&0xFF),g1=((c1>>8)&0xFF),b1=((c1>>16)&0xFF);
   int r2=(c2&0xFF),g2=((c2>>8)&0xFF),b2=((c2>>16)&0xFF);
   int r=(int)MathRound(r1+(r2-r1)*f);
   int g=(int)MathRound(g1+(g2-g1)*f);
   int b=(int)MathRound(b1+(b2-b1)*f);
   return (color)((b<<16)|(g<<8)|r);
}
color ColorWithAlpha(const color base,const uchar alpha)
{
   return (color)(((uint)alpha<<24)|((uint)base&0x00FFFFFF));
}

int MTFAlignmentPercent()
{
   // P3.2: cached on the OnCalculate sequence number.  Called from
   // CalculateAITradeSetup AND DrawMTFPanel; without the cache the same
   // aggregation ran twice per bar (2x dead weight in every draw).
   if(g_mtf_align_cache_seq==g_oncalc_seq && g_mtf_align_cache_seq>0)
      return g_mtf_align_cache_value;
   if(g_mtf_self_index<0)
   {
      // derive the self row from the configured panel even before the first
      // panel draw, so the chart TF is never double-counted
      ENUM_TIMEFRAMES cur=(ENUM_TIMEFRAMES)_Period;
      if(cur==InpMTF1) g_mtf_self_index=0;
      else if(cur==InpMTF2) g_mtf_self_index=1;
      else if(cur==InpMTF3) g_mtf_self_index=2;
      else if(cur==InpMTF4) g_mtf_self_index=3;
      else if(cur==InpMTF5) g_mtf_self_index=4;
   }
   int score=0;
   int checked=0;
   int closed=g_rates_total-2;
   double closed_price=(closed>=0 && closed<ArraySize(g_buf_c) ? g_buf_c[closed] : 0.0);
   for(int i=0;i<MTF_TF_COUNT;i++)
   {
      if(i==g_mtf_self_index) continue;
      if(g_mtf_aligned[i]!=0){score+=(g_mtf_aligned[i]>0?1:0); checked++;}
      else checked++;
   }
   int pct=(checked>0)?(int)MathRound(100.0*score/checked):-1;
   g_mtf_align_cache_seq=g_oncalc_seq;
   g_mtf_align_cache_value=pct;
   return pct;
}

int OppositeBiasPotential(const bool is_buy,const double price,const double atr)
{
   // Measures how close the market is to the opposite branch's trigger, so
   // the dashboard can warn when both branches are near-simultaneously valid.
   if(atr<=0.0) return 0;
   int n=ArraySize(g_structures);
   if(n==0) return 0;
   double last_level=g_structures[n-1].price;
   double distance=MathAbs(price-last_level);
   int proximity=(int)MathMax(0,MathMin(100,100.0*(1.0-MathMin(1.0,distance/(atr*4.0)))));
   bool opposite_broken=false;
   for(int i=n-1;i>=0 && i>=n-3;i--)
      if(g_structures[i].bullish!=is_buy){opposite_broken=true; break;}
   int potential=proximity;
   if(opposite_broken) potential=MathMin(100,potential+25);
   return potential;
}

int DirectionalWatchScore(const bool is_buy,const double price,const double atr)
{
   // Pure indicator diagnostics; never uses prices that did not exist at
   // the closed bar boundary.
   if(atr<=0.0) return 0;
   int score=0;
   int closed=g_rates_total-2;
   if(closed<0) return 0;
   bool htf_ok=(g_htf_bias==0)||(g_htf_bias==(is_buy?1:-1));
   if(htf_ok) score+=30;
   if(g_d1_structure_state==(is_buy?"BULLISH":"BEARISH"))
      score+=15;
   if(g_struct_trend==(is_buy?1:-1)) score+=20;
   if(ScoreSession()>=75.0) score+=15;
   double structure_score=ScoreStructure(g_rates_total,is_buy);
   if(structure_score>=60.0) score+=20;
   return MathMin(100,score);
}

void DiagnoseDirectionalWatch(const int total,const double &o[],const double &h[],
                              const double &l[],const double &c[])
{
   // Diagnostics of the direction that is NOT currently published, so the
   // dashboard can explain what the opposite branch is still missing.
   bool opposite_buy=!g_trade_setup.valid ? true : !g_trade_setup.is_buy;
   if(g_trade_setup.valid) opposite_buy=!g_trade_setup.is_buy;
   int closed=total-2;
   if(closed<1 || closed>=ArraySize(c)) 
   {
      g_directional_watch_text="DIAGNOSTICS UNAVAILABLE";
      g_directional_watch_color=clrDarkGray;
      return;
   }
   double price=c[closed];
   double atr=(closed<ArraySize(g_atr_buf) ? g_atr_buf[closed] : g_atr);
   if(atr<=0.0)
   {
      g_directional_watch_text="ATR UNAVAILABLE";
      g_directional_watch_color=clrDarkGray;
      return;
   }
   int score=DirectionalWatchScore(opposite_buy,price,atr);
   string why="";
   bool htf_ok=(g_htf_bias==0)||(g_htf_bias==(opposite_buy?1:-1));
   if(!htf_ok) why="HTF bias opposes";
   else if(g_struct_trend!=(opposite_buy?1:-1)) why="structure trend opposes";
   else if(score<60) why="evidence weight low";
   else why="awaiting confirmed zone+retest";
   g_directional_watch_text=StringFormat("%s WATCH %d/100 (%s)",
                          opposite_buy?"BUY":"SELL",score,why);
   g_directional_watch_color=score>=60 ? clrGoldenrod : clrDarkGray;
}

void DiagnoseCausalChain(const int total,const double &o[],const double &h[],const double &l[],
                         const double &c[],const datetime &t[])
{
   if(g_causal_diag.hop_count<=0)
   {
      g_causal_chain_text="NO CAUSAL CHAIN";
      g_causal_chain_color=clrDarkGray;
      return;
   }
   string chain="";
   for(int i=0;i<g_causal_diag.hop_count && i<MAX_CAUSAL_HOPS;i++)
   {
      if(i>0) chain+=" -> ";
      chain+=g_causal_diag.types[i];
   }
   int age=g_causal_diag.age_bars[g_causal_diag.hop_count-1];
   g_causal_chain_text=StringFormat("%s | age %d bars",chain,MathMax(0,age));
   g_causal_chain_color=(g_causal_diag.hop_count>=5?clrMediumSpringGreen:clrGoldenrod);
}

void ApplyCausalDecisionState()
{
   // Single source of truth for the dashboard decision state.
   // v5.7.3 FIX (A10): while a causally valid zone exists the state must
   // never degrade to "WAIT ZONE"; the watch state reflects the actual gate
   // that remains (retest/confirmation), not a zone search.
   bool confirmed=g_trade_setup.valid ||
                  (InpUseRetestLifecycle && g_active_setup.active &&
                   (g_active_setup.state=="RETEST_CONFIRMED" ||
                    g_active_setup.state=="CONFIRMED"));
   bool early=(g_early_break_status=="EARLY_BREAK" ||
               g_early_break_status=="CLOSE_CONFIRMED") && !confirmed;
   bool zone_valid=g_causal_diag.causal_valid && g_causal_diag.zone_valid;

   if(confirmed)
      g_decision_state="CONFIRMED";
   else if(early)
      g_decision_state=g_early_break_bull?"EARLY BUY":"EARLY SELL";
   else if(zone_valid)
   {
      if(g_causal_diag.directional_watch_available)
         g_decision_state=g_causal_diag.directional_watch_is_buy?"BUY_WATCH":"SELL_WATCH";
      else
         g_decision_state=(g_causal_diag.candidate_structure_bar>=0 ?
                           (g_decision_state=="SELL_WATCH"?"SELL_WATCH":"BUY_WATCH") : "WAIT");
   }
   else if(g_causal_diag.directional_watch_available &&
           g_causal_diag.directional_watch_score>=InpWatchMinQuality)
      g_decision_state=g_causal_diag.directional_watch_is_buy?"BUY_WATCH":"SELL_WATCH";
   else
      g_decision_state="WAIT";

   g_causal_diag.decision_state=g_decision_state;
}

//====================================================================
// AI TRADE SETUP - v5.7.3
// Institutional pipeline (default): POOL -> SWEEP -> DISPLACEMENT ->
// MSS/BOS -> CAUSAL ZONE -> (RETEST) -> TARGETS.  A1 fix: the zone ->
// regime -> candle-context stage runs BEFORE the single final
// aggregation, so every factor actually reaches final_score.
//====================================================================
void CalculateAITradeSetup(const int total,const double &o[],const double &h[],const double &l[],const double &c[])
{
   ResetCausalHopReport();
   g_trade_setup.reason_count=0;
   g_trade_setup.blocker_count=0;
   if(InpUseRetestLifecycle && g_active_setup.active)
   {
      // An immutable setup owns the chart until it confirms or invalidates.
      g_causal_diag.watch=true;
      return;
   }
   if(total<50) return;

   int closed=total-2;
   if(closed<2 || closed>=ArraySize(c)) return;
   double price=c[closed];
   double atr=(closed<ArraySize(g_atr_buf) && g_atr_buf[closed]>0.0) ? g_atr_buf[closed] : g_atr;
   if(atr<=0.0) return;

   UpdateSignalMask(total,c);

   //--- live execution environment gates (closed-bar recorded spread)
   bool spread_ok=true;
   if(!(g_is_backtest && InpIgnoreSpreadInBacktest) && !InpIgnoreSpreadOffHours)
      spread_ok=(g_spread<=(long)InpMaxSpreadPts);
   else if(!(g_is_backtest && InpIgnoreSpreadInBacktest))
      spread_ok=(g_spread<=(long)InpMaxSpreadPts);

   //--- candle intelligence (closed bar only)
   SCandleIntel candle=AnalyzeClosedCandle(closed,o,h,l,c,atr);
   string regime=DetectMarketRegime(closed,atr);
   double regime_mult=RegimeScoreMultiplier(regime);
   g_score.regime=regime_mult*100.0;

   //--- directional candidate evaluation
   //    v5.7.x semantics: directional preference follows HTF/D1 bias.  A
   //    candidate that opposes an explicit HTF bias is evaluated only to
   //    feed the opposite-branch diagnostics and can never publish.
   int dir_order[2]; dir_order[0]=1; dir_order[1]=-1;
   if(g_htf_bias<0){dir_order[0]=-1; dir_order[1]=1;}

   int    best_dir=0;
   int    best_anchor=-1;
   int    best_sw=-1,best_dp=-1,best_se=-1,best_ob=-1,best_fv=-1;
   double best_rank=-DBL_MAX;

   // opposite-branch diagnostics (best of the non-preferred direction)
   int opp_dir=0,opp_anchor=-1,opp_sw=-1,opp_dp=-1,opp_se=-1,opp_ob=-1,opp_fv=-1;
   double opp_rank=-DBL_MAX;

   for(int d=0;d<2;d++)
   {
      bool is_buy=(dir_order[d]>0);
      int sw=-1,dp=-1,se=-1,ob=-1,fv=-1;
      int anchor=SelectBestStructureAnchor(total,c,sw,dp,se,ob,fv,dir_order[d]);
      if(anchor<0) continue;
      double rank=(double)se;
      if(ob>=0) rank+=5.0;
      if(fv>=0) rank+=3.0;
      bool preferred=(g_htf_bias==0)||(g_htf_bias==dir_order[d]);
      if(preferred) rank+=100.0;
      if(is_buy==(dir_order[0]>0)) rank+=1.0;   // stable bias-order tiebreak

      if(preferred)
      {
         if(rank>best_rank)
         {
            best_rank=rank; best_dir=dir_order[d]; best_anchor=anchor;
            best_sw=sw; best_dp=dp; best_se=se; best_ob=ob; best_fv=fv;
         }
      }
      else
      {
         if(rank>opp_rank)
         {
            opp_rank=rank; opp_dir=dir_order[d]; opp_anchor=anchor;
            opp_sw=sw; opp_dp=dp; opp_se=se; opp_ob=ob; opp_fv=fv;
         }
      }
   }

   //--- hop report from the preferred candidate (or its absence)
   g_causal_diag.sweep_event_ok=(best_sw>=0);
   g_causal_diag.disp_event_ok=(best_dp>=0);
   g_causal_diag.mss_event_ok=(best_se>=0);
   g_causal_diag.hop_sweep_disp=(best_sw>=0 && best_dp>=0 &&
                                 IsCausallyConnected(best_sw,best_dp));
   g_causal_diag.hop_disp_mss=(best_dp>=0 && best_se>=0 &&
                               IsCausallyConnected(best_dp,best_se));
   g_causal_diag.candidate_structure_bar=(best_se>=0 ?
        g_causal_events[best_se].event_bar : -1);
   g_causal_diag.candidate_structure_type=(best_se>=0 ?
        CausalTypeName(g_causal_events[best_se].type) : "");
   if(best_sw>=0) g_causal_diag.sweep_age_bars=g_causal_events[best_sw].age;

   if(best_anchor<0 || best_dir==0)
   {
      g_causal_diag.causal_valid=false;
      g_causal_diag.zone_valid=false;
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason="no causally valid structure anchor";
      g_causal_diag.path_text="";
      if(opp_anchor>=0)
      {
         g_causal_diag.opposite_available=true;
         g_causal_diag.opposite_is_buy=(opp_dir>0);
         g_causal_diag.opposite_structure_bar=g_causal_events[opp_se].event_bar;
         g_causal_diag.opposite_structure_type=CausalTypeName(g_causal_events[opp_se].type);
         g_causal_diag.opposite_reason="opposite branch has a causal anchor";
      }
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   bool is_buy=(best_dir>0);
   g_causal_diag.hop_mss_zone=(best_ob>=0 || best_fv>=0);
   g_causal_diag.zone_kind=(best_ob>=0?"CAUSAL OB":(best_fv>=0?"CAUSAL FVG":""));
   g_causal_diag.path_text=StringFormat("%s -> %s -> %s -> %s",
        (best_sw>=0?"SWEEP":"-"),(best_dp>=0?"DISP":"-"),
        (best_se>=0?CausalTypeName(g_causal_events[best_se].type):"-"),
        g_causal_diag.zone_kind==""?"-":g_causal_diag.zone_kind);
   // record the hop chain for the dashboard causal audit line
   if(best_sw>=0)
      RecordCausalHop("SWEEP",g_causal_events[best_sw].id,
                      g_causal_events[best_sw].event_bar,
                      g_causal_events[best_sw].age,
                      g_causal_events[best_sw].strength);
   if(best_dp>=0)
      RecordCausalHop("DISP",g_causal_events[best_dp].id,
                      g_causal_events[best_dp].event_bar,
                      g_causal_events[best_dp].age,
                      g_causal_events[best_dp].strength);
   if(best_se>=0)
      RecordCausalHop(CausalTypeName(g_causal_events[best_se].type),
                      g_causal_events[best_se].id,
                      g_causal_events[best_se].event_bar,
                      g_causal_events[best_se].age,
                      g_causal_events[best_se].strength);
   if(best_ob>=0)
      RecordCausalHop("OB",g_causal_events[best_ob].id,
                      g_causal_events[best_ob].event_bar,
                      g_causal_events[best_ob].age,
                      g_causal_events[best_ob].strength);
   if(best_fv>=0)
      RecordCausalHop("FVG",g_causal_events[best_fv].id,
                      g_causal_events[best_fv].event_bar,
                      g_causal_events[best_fv].age,
                      g_causal_events[best_fv].strength);
   g_causal_diag.causal_valid=(best_sw>=0 && best_dp>=0 && best_se>=0 &&
                               g_causal_diag.hop_sweep_disp && g_causal_diag.hop_disp_mss);

   //--- zone geometry from the causal events themselves
   double zone_top=0.0,zone_bottom=0.0;
   string zone_source="";
   int    zone_event=-1;
   if(best_ob>=0)
   {
      zone_event=best_ob;
      zone_top=g_causal_events[best_ob].top;
      zone_bottom=g_causal_events[best_ob].bottom;
      zone_source="CAUSAL_OB";
      g_score.orderblock=ScoreOrderBlock(g_causal_events[best_ob].source_index,price,atr,
                                         g_causal_events[best_se].event_bar);
      g_score.fvg=(best_fv>=0 ? ScoreFVG(is_buy,price,g_causal_events[best_se].event_bar) : 0.0);
   }
   else if(best_fv>=0)
   {
      zone_event=best_fv;
      zone_top=g_causal_events[best_fv].top;
      zone_bottom=g_causal_events[best_fv].bottom;
      zone_source="CAUSAL_FVG";
      g_score.orderblock=0.0;
      g_score.fvg=ScoreFVG(is_buy,price,g_causal_events[best_se].event_bar);
   }
   g_causal_diag.zone_valid=(zone_event>=0);
   g_selected_sweep_event=best_sw;
   g_selected_displacement_event=best_dp;
   g_selected_structure_event=best_se;
   g_selected_zone_event=zone_event;

   //--- blocked before scoring: institutional location + blacklist + spread
   if(!g_causal_diag.causal_valid || !g_causal_diag.zone_valid)
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason="incomplete causal chain";
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }
   string loc_why="";
   if(!IsInstitutionalLocation(is_buy,zone_top,zone_bottom,atr,loc_why))
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=loc_why;
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }
   string zone_id=(g_causal_events[zone_event].type==CE_ORDER_BLOCK ?
                   g_order_blocks[g_causal_events[zone_event].source_index].id :
                   g_fvgs[g_causal_events[zone_event].source_index].id);
   if(IsBlacklisted(zone_id) || IsSameIdeaAsBlacklisted(is_buy,zone_top,zone_bottom))
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason="setup idea blacklisted (recently invalidated)";
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }
   if(!spread_ok)
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=StringFormat("spread %d pts > max %d",
                                                    (int)g_spread,InpMaxSpreadPts);
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   //--- entry / stop geometry (fixed at decision time; never re-anchored)
   double entry=(is_buy ? zone_top : zone_bottom);
   int sweep_bar=g_causal_events[best_sw].event_bar;
   double sweep_price=g_causal_events[best_sw].price;
   double sl;
   if(InpSLBeyondSweep)
      sl=(is_buy ? MathMin(g_buf_l[sweep_bar],zone_bottom)
                 : MathMax(g_buf_h[sweep_bar],zone_top));
   else
      sl=(is_buy ? zone_bottom : zone_top);
   sl+=(is_buy ? -1.0 : 1.0)*InpSLBufferATR*atr;
   sl=NormalizePriceToTick(sl);
   entry=NormalizePriceToTick(entry);
   double risk=MathAbs(entry-sl);
   if(risk<=_Point || risk>atr*InpMaxStopATR)
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=StringFormat("stop geometry out of range (%.1f ATR)",
                                                    risk/MathMax(atr,_Point));
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   //--- immutable opposing barrier discovered from ENTRY (never re-derived)
   string barrier_type="",barrier_event_id="";
   int barrier_bar=-1;
   double barrier=NearestOpposingBarrier(entry,is_buy,barrier_type,barrier_event_id,barrier_bar);

   //--- ordered targets from immutable barrier logic
   double tp1=0,tp2=0,tp3=0;
   string t1s="",t2s="",t3s="",ev1="",ev2="",ev3="";
   int b1=-1,b2=-1,b3=-1; bool cons1=false,cons2=false,cons3=false,bb1=false,bb2=false,bb3=false;
   double min_dist=MathMax(atr*0.50,InstrumentMinStopDistance());
   double from=entry;
   tp1=FindInstitutionalTarget(from,entry,sl,is_buy,min_dist,InpMinRR1,1,barrier,
                               t1s,ev1,b1,cons1,bb1);
   if(tp1>0.0){from=tp1;
      tp2=FindInstitutionalTarget(from,entry,sl,is_buy,min_dist,InpMinRR1,2,barrier,
                                  t2s,ev2,b2,cons2,bb2);}
   if(tp2>0.0){from=tp2;
      tp3=FindInstitutionalTarget(from,entry,sl,is_buy,min_dist,InpMinRR1,3,barrier,
                                  t3s,ev3,b3,cons3,bb3);}
   // ATR projections capped by the barrier keep all three objectives ordered.
   if(tp1<=0.0)
   {
      tp1=(is_buy ? entry+atr*1.5 : entry-atr*1.5);
      if(barrier>0.0 && ((is_buy && tp1>barrier) || (!is_buy && tp1<barrier)))
         tp1=barrier;
      tp1=NormalizePriceToTick(tp1); t1s="ATR Projection";
   }
   if(tp2<=0.0)
   {
      tp2=(is_buy ? entry+atr*2.5 : entry-atr*2.5);
      if(barrier>0.0 && ((is_buy && tp2>barrier) || (!is_buy && tp2<barrier)))
         tp2=barrier;
      tp2=NormalizePriceToTick(tp2); t2s="ATR Projection";
   }
   if(tp3<=0.0)
   {
      tp3=(is_buy ? entry+atr*4.0 : entry-atr*4.0);
      if(barrier>0.0 && ((is_buy && tp3>barrier) || (!is_buy && tp3<barrier)))
         tp3=barrier;
      tp3=NormalizePriceToTick(tp3); t3s="ATR Projection";
   }
   tp1=NormalizePriceToTick(tp1); tp2=NormalizePriceToTick(tp2); tp3=NormalizePriceToTick(tp3);
   if(!ValidateTargetGeometry(is_buy,entry,sl,tp1,tp2,tp3))
   {
      // Collapse to a single objective rather than publish crossed targets.
      tp2=tp1; tp3=tp1; t2s=t1s; t3s=t1s; ev2=ev1; ev3=ev1; b2=b1; b3=b1;
      cons2=cons1; cons3=cons1; bb2=bb1; bb3=bb1;
      if(!ValidateTargetGeometry(is_buy,entry,sl,tp1,tp2,tp3))
      {
         g_causal_diag.watch=true;
         g_causal_diag.causal_fail_reason="target geometry could not be ordered";
         ApplyCausalDecisionState();
         DiagnoseDirectionalWatch(total,o,h,l,c);
         DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
         return;
      }
   }

   //--- v5.7.3 FIX (A1): zone -> regime -> candle-context stage runs BEFORE
   //    the single final aggregation, so candle context and the adaptive
   //    regime multiplier genuinely reach final_score.
   g_score.structure=ScoreStructure(total,is_buy);
   g_score.liquidity=ScoreLiquidity(is_buy,g_causal_events[best_se].event_bar);
   g_score.session=ScoreSession();
   g_score.htf=ScoreHTF(is_buy);
   double causal_path=CausalPathScore(best_sw,best_dp,best_se,best_ob,best_fv);
   g_score.algo=causal_path;
   g_score.candle_context=(double)ContextualCandleScore(candle,is_buy,price,
                            zone_top,zone_bottom,atr,
                            true /*sweep ok by construction*/,
                            g_causal_diag.mss_event_ok,
                            g_causal_diag.zone_valid,regime);
   SSignalFactor factors[12];
   for(int i=0;i<12;i++){factors[i].name=""; factors[i].value=0; factors[i].weight=0; factors[i].active=false;}
   int fc=0;
   factors[fc].name="MSS";        factors[fc].value=30; factors[fc].weight=12;
   factors[fc].active=(g_causal_events[best_se].type==CE_MSS); fc++;
   factors[fc].name="CHoCH";      factors[fc].value=24; factors[fc].weight=10;
   factors[fc].active=(g_causal_events[best_se].type==CE_CHOCH); fc++;
   factors[fc].name="BOS";        factors[fc].value=20; factors[fc].weight=8;
   factors[fc].active=(g_causal_events[best_se].type==CE_BOS); fc++;
   factors[fc].name="Aligned Sweep"; factors[fc].value=25; factors[fc].weight=10;
   factors[fc].active=true; fc++;
   factors[fc].name="Causal OB";  factors[fc].value=15; factors[fc].weight=8;
   factors[fc].active=(best_ob>=0); fc++;
   factors[fc].name="Causal FVG"; factors[fc].value=10; factors[fc].weight=6;
   factors[fc].active=(best_fv>=0); fc++;
   factors[fc].name="OTE Zone";   factors[fc].value=10; factors[fc].weight=4;
   factors[fc].active=((g_signal_mask&BIT_OTE)!=0); fc++;
   factors[fc].name="HTF Bias";   factors[fc].value=10; factors[fc].weight=6;
   factors[fc].active=(g_htf_bias==best_dir); fc++;
   factors[fc].name="Kill Zone";  factors[fc].value=10; factors[fc].weight=4;
   factors[fc].active=((g_signal_mask&BIT_KILLZONE)!=0); fc++;
   factors[fc].name="Judas Swing"; factors[fc].value=10; factors[fc].weight=4;
   factors[fc].active=(g_judas!=0); fc++;
   factors[fc].name="Candle Confirmation"; factors[fc].value=15; factors[fc].weight=8;
   factors[fc].active=CandleConfirmsDirection(candle,is_buy); fc++;
   factors[fc].name="PD Context"; factors[fc].value=10; factors[fc].weight=4;
   // v5.7.3 note: in institutional mode premium/discount location is already
   // a HARD gate (IsInstitutionalLocation), so paying it again here would
   // double-count the same evidence. The factor stays defined for flexible
   // mode but is inactive in institutional sequence mode.
   factors[fc].active=!InpInstitutionalSequence &&
                      ((g_signal_mask&BIT_DEMAND_ZONE)!=0 ||
                       (g_signal_mask&BIT_OTE)!=0);
   fc++;

   int knap=KnapsackOptimizeSignals(factors,60);
   int dpv=DynamicProgrammingConfidence(factors);
   int maxp=MaxPossibleValue(factors);
   int independence=IndependentEvidenceScore(factors);
   g_score.evidence_independence=(double)independence;

   //--- single final aggregation (A1)
   string conflict_label="";
   ENUM_MTF_CONFLICT_STATE conflict=ClassifyMarketConflict(is_buy,
        g_causal_diag.candidate_structure_type,conflict_label);
   double prime_score=0.0; string prime_label="";
   if(InpUsePrimeLevels && !InpInstitutionalSequence)
      prime_score=PrimeProximityScore(price,atr,prime_label);
   double rel_score=0.0; string rel_label="";
   if(InpUseRelationshipMatrix && !InpInstitutionalSequence)
   {
      rel_score=InstitutionalRelationshipStrength(RN_MSS,RN_OB)*100.0;
      rel_label=RelationNodeName(RN_OB);
   }
   double final_score=0.0;
   if(InpInstitutionalSequence)
   {
      // Evidence-cluster weighted aggregation of the seven pillars.
      final_score=0.22*g_score.structure+
                  0.14*g_score.liquidity+
                  0.16*MathMax(g_score.orderblock,g_score.fvg)+
                  0.10*g_score.session+
                  0.10*g_score.htf+
                  0.18*g_score.algo+
                  0.10*g_score.candle_context+
                  0.05*(double)MathMax(knap,dpv)*(100.0/MathMax(1,maxp))+
                  0.05*g_score.evidence_independence;
      final_score*=regime_mult;                       // adaptive regime multiplier
      if(g_score.candle_context>0.0) final_score+=2.0; // explicit context bonus
      if(conflict==MTF_CONFLICT) final_score-=MathMin(InpMTFConflictPenalty,
                                                      MathAbs(final_score)*0.10);
      final_score=MathMax(0.0,MathMin(100.0,final_score));
   }
   else
   {
      final_score=0.18*g_score.structure+0.12*g_score.liquidity+
                  0.14*g_score.orderblock+0.10*g_score.fvg+
                  0.08*g_score.session+0.12*g_score.htf+
                  0.16*g_score.algo+0.10*g_score.candle_context+
                  (double)MathMax(knap,dpv)*(100.0/MathMax(1,maxp))*0.10;
      final_score*=regime_mult;
      final_score+=MathMin(InpPrimeScoreMaxBonus,prime_score*0.02*InpPrimeScoreMaxBonus);
      final_score+=MathMin(InpRelationshipScoreMaxBonus,rel_score*0.02*InpRelationshipScoreMaxBonus);
      if(conflict==MTF_CONFLICT) final_score-=MathMin(InpMTFConflictPenalty,
                                                      MathAbs(final_score)*0.10);
      final_score=MathMax(0.0,MathMin(100.0,final_score));
   }
   g_score.prime=prime_score;
   g_score.relationship=rel_score;
   g_score.final_score=final_score;
   int conf=(int)MathRound(final_score);
   if(conf<InpMinConfidenceScore)
   {
      g_causal_diag.watch=true;
      g_causal_diag.quality_score=conf;
      g_causal_diag.causal_fail_reason=StringFormat("confidence %d < min %d",
                                                    conf,InpMinConfidenceScore);
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   //--- EMA/VWAP confluence evidence (closed-bar values only)
   bool ema_ok=true;
   if(InpUseEMAVWAPConfluence && closed<ArraySize(BufEmaFast) &&
      closed<ArraySize(BufEmaSlow) && closed<ArraySize(BufVWAP) &&
      BufEmaFast[closed]!=EMPTY_VALUE && BufEmaSlow[closed]!=EMPTY_VALUE &&
      BufVWAP[closed]!=EMPTY_VALUE && BufVWAP[closed]!=0.0)
   {
      ema_ok=is_buy ? (price>BufEmaSlow[closed] || price>BufVWAP[closed])
                    : (price<BufEmaSlow[closed] || price<BufVWAP[closed]);
      if(!ema_ok && InpInstitutionalSequence)
      {
         g_causal_diag.watch=true;
         g_causal_diag.causal_fail_reason="EMA200/VWAP confluence opposes";
         ApplyCausalDecisionState();
         DiagnoseDirectionalWatch(total,o,h,l,c);
         DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
         return;
      }
   }

   //--- publish
   g_trade_setup.valid=false;
   g_trade_setup.created_bar=closed;
   g_trade_setup.created_time=g_buf_t[closed+1]; // decision boundary = next open
   g_trade_setup.zone_top=zone_top;
   g_trade_setup.zone_bottom=zone_bottom;
   g_trade_setup.is_buy=is_buy;
   g_trade_setup.entry=entry;
   g_trade_setup.sl=sl;
   g_trade_setup.tp1=tp1; g_trade_setup.tp2=tp2; g_trade_setup.tp3=tp3;
   g_trade_setup.tp1_type=t1s; g_trade_setup.tp2_type=t2s; g_trade_setup.tp3_type=t3s;
   g_trade_setup.tp_source_event_id[0]=ev1;
   g_trade_setup.tp_source_event_id[1]=ev2;
   g_trade_setup.tp_source_event_id[2]=ev3;
   g_trade_setup.tp_source_bar[0]=b1;
   g_trade_setup.tp_source_bar[1]=b2;
   g_trade_setup.tp_source_bar[2]=b3;
   g_trade_setup.tp_consumed[0]=cons1;
   g_trade_setup.tp_consumed[1]=cons2;
   g_trade_setup.tp_consumed[2]=cons3;
   g_trade_setup.tp_barrier_bound[0]=bb1;
   g_trade_setup.tp_barrier_bound[1]=bb2;
   g_trade_setup.tp_barrier_bound[2]=bb3;
   g_trade_setup.immutable_target_barrier=barrier;
   g_trade_setup.immutable_target_barrier_type=barrier_type;
   g_trade_setup.immutable_target_barrier_event_id=barrier_event_id;
   g_trade_setup.immutable_target_barrier_bar=barrier_bar;
   g_trade_setup.ob_index=(best_ob>=0 ? g_causal_events[best_ob].source_index : -1);
   g_trade_setup.ob_uid=(g_trade_setup.ob_index>=0 ?
                         g_order_blocks[g_trade_setup.ob_index].id : "");
   g_trade_setup.ob_dist_atr=(g_trade_setup.ob_index>=0 ?
                              MathAbs(price-OBMid(g_trade_setup.ob_index))/atr : 0.0);
   g_trade_setup.zone_source=zone_source;
   g_trade_setup.sweep_bar=sweep_bar;
   g_trade_setup.sweep_price=sweep_price;
   g_trade_setup.sweep_event_id=g_causal_events[best_sw].id;
   g_trade_setup.displacement_event_id=g_causal_events[best_dp].id;
   g_trade_setup.structure_event_id=g_causal_events[best_se].id;
   g_trade_setup.zone_event_id=g_causal_events[zone_event].id;
   g_trade_setup.causal_path_score=causal_path;
   g_trade_setup.confidence=conf;
   g_trade_setup.knapsack_score=knap;
   g_trade_setup.dp_optimal_score=dpv;
   g_trade_setup.max_factor_value=maxp;
   g_trade_setup.candle_context_score=(int)MathRound(g_score.candle_context);
   g_trade_setup.evidence_independence_score=independence;
   g_trade_setup.market_regime=regime;
   g_trade_setup.prime_proximity_score=(int)MathRound(prime_score);
   g_trade_setup.prime_nearest_label=prime_label;
   g_trade_setup.relationship_score=(int)MathRound(rel_score);
   g_trade_setup.relationship_label=rel_label;
   g_trade_setup.mtf_conflict_label=conflict_label;

   double rr1=DirectionalRR(is_buy,entry,sl,tp1);
   double rr2=DirectionalRR(is_buy,entry,sl,tp2);
   double rr3=DirectionalRR(is_buy,entry,sl,tp3);
   if(rr1<InpMinRR1)
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=StringFormat("RR1 %.2f < min %.2f",rr1,InpMinRR1);
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }
   g_trade_setup.rr1=rr1; g_trade_setup.rr2=rr2; g_trade_setup.rr3=rr3;

   //--- reasons / blockers (for the panel)
   AddReason(g_causal_events[best_sw].id);
   AddReason(g_causal_events[best_dp].id);
   AddReason(CausalTypeName(g_causal_events[best_se].type));
   AddReason(zone_source);
   if(best_fv>=0 && best_ob>=0) AddReason("OB+FVG confluence");
   if((g_signal_mask&BIT_KILLZONE)!=0) AddReason("KILL ZONE");
   if(CandleConfirmsDirection(candle,is_buy))
      AddReason(StringFormat("candle %s",candle.pattern));
   if(conflict==MTF_CONFLICT) AddBlocker(conflict_label);

   //--- quality indices AFTER the setup struct is populated
   int reliability=CalculateReliability(conf,knap,dpv,maxp);
   g_trade_setup.reliability=reliability;
   g_trade_setup.quality_grade=CalculateQualityGrade(conf,reliability);
   g_trade_setup.institutional_grade=GetInstitutionalGrade(conf,knap,dpv,maxp);
   g_trade_setup.risk_level=CalculateRiskLevel(entry,sl,atr,g_spread,g_trade_setup.risk_pips);
   g_causal_diag.quality_score=conf;
   g_causal_diag.mtf_align_pct=MTFAlignmentPercent();

   if(InpBlockLowGrade && GradeRank(g_trade_setup.quality_grade)<GradeRank(
        (InpMinGrade==GRADE_APLUS?"A+":(InpMinGrade==GRADE_A?"A":
        (InpMinGrade==GRADE_B?"B":"C")))))
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=StringFormat("grade %s below minimum",
                                                    g_trade_setup.quality_grade);
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }
   if(reliability<InpMinReliability)
   {
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason=StringFormat("reliability %d < min %d",
                                                    reliability,InpMinReliability);
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   //--- causal-graph branch (all-or-nothing)
   string setup_id=GenerateSetupId(is_buy,g_trade_setup.created_time,zone_top,zone_bottom);
   g_trade_setup.setup_event_id=setup_id;
   g_signal_count++;
   if(!CreateSetupBranchTransactional(setup_id,closed,g_trade_setup.created_time,is_buy,
                                      entry,zone_top,zone_bottom,tp1,tp2,tp3))
   {
      g_trade_setup.valid=false;
      g_causal_diag.watch=true;
      g_causal_diag.causal_fail_reason="causal branch rejected/rolled back";
      ApplyCausalDecisionState();
      DiagnoseDirectionalWatch(total,o,h,l,c);
      DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
      return;
   }

   if(InpUseRetestLifecycle)
   {
      // Seed the immutable setup; confirmation happens on a later CLOSED bar
      // through ManageSetupLifecycle.  The setup itself is already causal.
      g_active_setup.active=true;
      g_active_setup.id=setup_id;
      g_active_setup.state="READY";
      g_active_setup.is_buy=is_buy;
      g_active_setup.created_bar=closed;
      g_active_setup.created_time=g_trade_setup.created_time;
      g_active_setup.zone_top=zone_top;
      g_active_setup.zone_bottom=zone_bottom;
      g_active_setup.ob_uid=g_trade_setup.ob_uid;
      g_active_setup.ob_index_cache=g_trade_setup.ob_index;
      g_active_setup.quality_grade=g_trade_setup.quality_grade;
      g_active_setup.institutional_grade=g_trade_setup.institutional_grade;
      g_active_setup.confidence=conf;
      g_active_setup.reliability=reliability;
      g_active_setup.entry=entry;
      g_active_setup.sl=sl;
      g_active_setup.tp1=tp1; g_active_setup.tp2=tp2; g_active_setup.tp3=tp3;
      g_active_setup.tp1_type=t1s; g_active_setup.tp2_type=t2s; g_active_setup.tp3_type=t3s;
      g_active_setup.tp_source_event_id[0]=ev1;
      g_active_setup.tp_source_event_id[1]=ev2;
      g_active_setup.tp_source_event_id[2]=ev3;
      g_active_setup.tp_source_bar[0]=b1;
      g_active_setup.tp_source_bar[1]=b2;
      g_active_setup.tp_source_bar[2]=b3;
      g_active_setup.tp_consumed[0]=false;
      g_active_setup.tp_consumed[1]=false;
      g_active_setup.tp_consumed[2]=false;
      g_active_setup.tp_barrier_bound[0]=bb1;
      g_active_setup.tp_barrier_bound[1]=bb2;
      g_active_setup.tp_barrier_bound[2]=bb3;
      g_active_setup.immutable_target_barrier=barrier;
      g_active_setup.immutable_target_barrier_type=barrier_type;
      g_active_setup.immutable_target_barrier_event_id=barrier_event_id;
      g_active_setup.immutable_target_barrier_bar=barrier_bar;
      g_active_setup.rr1=rr1; g_active_setup.rr2=rr2; g_active_setup.rr3=rr3;
      g_active_setup.risk_level=g_trade_setup.risk_level;
      g_active_setup.risk_pips=g_trade_setup.risk_pips;
      g_active_setup.zone_source=zone_source;
      g_active_setup.sweep_bar=sweep_bar;
      g_active_setup.sweep_price=sweep_price;
      g_active_setup.sweep_event_id=g_trade_setup.sweep_event_id;
      g_active_setup.displacement_event_id=g_trade_setup.displacement_event_id;
      g_active_setup.structure_event_id=g_trade_setup.structure_event_id;
      g_active_setup.zone_event_id=g_trade_setup.zone_event_id;
      g_active_setup.setup_event_id=setup_id;
      g_active_setup.causal_path_score=causal_path;
      g_active_setup.retest_bar=-1;
      g_active_setup.retest_time=0;
      g_active_setup.confirmed_bar=-1;
      g_active_setup.confirmed_time=0;
      g_active_setup.alert_fired=false;
      if(InpLogLifecycleTransitions)
         LogLifecycle(StringFormat("SEEDED %s %s @ %s",is_buy?"BUY":"SELL",
                                    setup_id,DoubleToString(entry,_Digits)));
      if(InpAlertOnSetupReady)
         Alert(StringFormat("%s %s | %s SETUP READY %s | zone %s-%s | awaiting retest (not an entry signal)",
               _Symbol,TFName((ENUM_TIMEFRAMES)_Period),is_buy?"BUY":"SELL",
               g_trade_setup.quality_grade,
               DoubleToString(zone_bottom,_Digits),DoubleToString(zone_top,_Digits)));
   }
   else
   {
      g_trade_setup.valid=true;
   }

   g_causal_diag.watch=false;
   ApplyCausalDecisionState();
   DiagnoseDirectionalWatch(total,o,h,l,c);
   DiagnoseCausalChain(total,o,h,l,c,g_buf_t);
   if(InpLogSignalDetails)
      Print(StringFormat("[Setup] %s %s conf=%d rel=%d grade=%s path=%.0f RR1=%.2f barrier=%s",
            is_buy?"BUY":"SELL",setup_id,conf,reliability,
            g_trade_setup.quality_grade,causal_path,rr1,
            DoubleToString(barrier,_Digits)));
}


void LifecycleInvalidateActive(const string why,const datetime bl_time)
{
   // Shared invalidation path: blacklist the idea, release ownership, and
   // drop the published mirror so the opposite branch can be promoted only
   // through the normal causal pipeline.
   BlacklistSetup(g_active_setup.id,bl_time);
   if(InpLogLifecycleTransitions)
      LogLifecycle(StringFormat("INVALIDATED %s (%s)",g_active_setup.id,why));
   g_active_setup.active=false;
   g_active_setup.state="INVALID";
   g_trade_setup.valid=false;
   ObjectDelete(0,PFX+"TRADEBOX");
   ObjectDelete(0,PFX+"TL_E");
   ObjectDelete(0,PFX+"TL_SL");
   ObjectDelete(0,PFX+"TL_TP1");
   ObjectDelete(0,PFX+"TL_TP2");
   ObjectDelete(0,PFX+"TL_TP3");
   ObjectDelete(0,PFX+"ENTRY_PREVIEW");
   ObjectDelete(0,PFX+"SETUPZONE");
}

//====================================================================
// SETUP LIFECYCLE  (READY -> RETEST_PREVIEW -> RETEST_CONFIRMED ->
//                    CONFIRMED -> (TP consumption) -> RELEASED)
//                    or INVALID at any pre-confirmation stage.
// All decisions are evaluated on CLOSED bars only.  TP1/TP2/TP3
// consumption of CONFIRMED setups is likewise closed-bar based
// (v5.7.3 FIX A3), so the dashboard reflects reality.
//====================================================================
void ManageSetupLifecycle(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool is_new_bar)
{
   if(!InpUseRetestLifecycle || !g_active_setup.active) return;
   int closed=total-2;
   if(closed<1 || closed>=ArraySize(c)) return;
   double atr=(closed<ArraySize(g_atr_buf) && g_atr_buf[closed]>0.0) ? g_atr_buf[closed] : g_atr;
   if(atr<=0.0) return;

   int age=closed-g_active_setup.created_bar;

   //--- CONFIRMED stage: manage SL and sequential TP consumption on closed bars
   if(g_active_setup.state=="CONFIRMED" || g_active_setup.state=="RETEST_CONFIRMED")
   {
      bool is_buy=g_active_setup.is_buy;
      // Close-beyond-SL invalidates (wick spikes do not).
      bool sl_hit=is_buy ? (c[closed]<=g_active_setup.sl)
                         : (c[closed]>=g_active_setup.sl);
      if(sl_hit)
      {
         LifecycleInvalidateActive("SL close-beyond",t[closed]);
         return;
      }
      // Sequential TP consumption preserves the TP1<TP2<TP3 order.
      if(is_buy)
      {
         if(!g_active_setup.tp_consumed[0] && h[closed]>=g_active_setup.tp1)
            g_active_setup.tp_consumed[0]=true;
         if(g_active_setup.tp_consumed[0] && !g_active_setup.tp_consumed[1] &&
            h[closed]>=g_active_setup.tp2)
            g_active_setup.tp_consumed[1]=true;
         if(g_active_setup.tp_consumed[1] && !g_active_setup.tp_consumed[2] &&
            h[closed]>=g_active_setup.tp3)
            g_active_setup.tp_consumed[2]=true;
      }
      else
      {
         if(!g_active_setup.tp_consumed[0] && l[closed]<=g_active_setup.tp1)
            g_active_setup.tp_consumed[0]=true;
         if(g_active_setup.tp_consumed[0] && !g_active_setup.tp_consumed[1] &&
            l[closed]<=g_active_setup.tp2)
            g_active_setup.tp_consumed[1]=true;
         if(g_active_setup.tp_consumed[1] && !g_active_setup.tp_consumed[2] &&
            l[closed]<=g_active_setup.tp3)
            g_active_setup.tp_consumed[2]=true;
      }
      // Keep the published mirror in sync with consumption state.
      g_trade_setup.tp_consumed[0]=g_active_setup.tp_consumed[0];
      g_trade_setup.tp_consumed[1]=g_active_setup.tp_consumed[1];
      g_trade_setup.tp_consumed[2]=g_active_setup.tp_consumed[2];
      if(g_active_setup.tp_consumed[0] && g_active_setup.tp_consumed[1] &&
         g_active_setup.tp_consumed[2])
      {
         if(InpLogLifecycleTransitions)
            LogLifecycle(StringFormat("COMPLETE %s (all targets consumed)",
                                      g_active_setup.id));
         g_active_setup.active=false;
         g_active_setup.state="COMPLETE";
         g_trade_setup.valid=false;
         ObjectDelete(0,PFX+"TRADEBOX");
         ObjectDelete(0,PFX+"TL_E");
         ObjectDelete(0,PFX+"TL_SL");
         ObjectDelete(0,PFX+"TL_TP1");
         ObjectDelete(0,PFX+"TL_TP2");
         ObjectDelete(0,PFX+"TL_TP3");
         ObjectDelete(0,PFX+"ENTRY_PREVIEW");
         ObjectDelete(0,PFX+"SETUPZONE");
      }
      return;
   }

   //--- pre-confirmation stages: evaluate once per closed bar
   if(!is_new_bar) 
   {
      // still allow the live forming-candle retest PREVIEW to update
      if(g_active_setup.state=="READY" || g_active_setup.state=="RETEST_PREVIEW")
      {
         double cur_low=l[total-1],cur_high=h[total-1];
         bool preview_hit=g_active_setup.is_buy ?
            (cur_low<=g_active_setup.zone_top && cur_low>=g_active_setup.zone_bottom-InpInvalidateBufferATR*atr) :
            (cur_high>=g_active_setup.zone_bottom && cur_high<=g_active_setup.zone_top+InpInvalidateBufferATR*atr);
         if(preview_hit && g_active_setup.state=="READY")
         {
            g_active_setup.state="RETEST_PREVIEW";
            // one entry-preview alert per setup idea
            string preview_id=g_active_setup.id+"|PREVIEW";
            if(InpAlertOnEntryPreview && g_last_entry_preview_id!=preview_id)
            {
               g_last_entry_preview_id=preview_id;
               Alert(StringFormat("%s %s | %s ENTRY PREVIEW (live retest into zone, NON-AUTHORITATIVE) entry %.2f",
                     _Symbol,TFName((ENUM_TIMEFRAMES)_Period),
                     g_active_setup.is_buy?"BUY":"SELL",g_active_setup.entry));
            }
         }
      }
      return;
   }

   //--- opposite closed MSS invalidates a waiting setup
   if(InpInvalidateOnOppositeMSS &&
      g_struct_last_break_bar>g_active_setup.created_bar &&
      g_struct_last_break_bar<=closed &&
      ArraySize(g_structures)>0)
   {
      SStructureBreak last=g_structures[ArraySize(g_structures)-1];
      if(last.type=="MSS" && last.bullish!=g_active_setup.is_buy)
      {
         LifecycleInvalidateActive("opposite closed MSS",t[closed]);
         return;
      }
   }

   //--- retest timeout
   if(InpRetestTimeoutBars>0 && age>InpRetestTimeoutBars)
   {
      LifecycleInvalidateActive("retest timeout",t[closed]);
      return;
   }

   //--- hard zone invalidation: a CLOSED bar beyond the far zone edge
   bool invalidated=g_active_setup.is_buy ?
      (c[closed]<g_active_setup.zone_bottom-InpInvalidateBufferATR*atr) :
      (c[closed]>g_active_setup.zone_top+InpInvalidateBufferATR*atr);
   if(invalidated)
   {
      LifecycleInvalidateActive("closed beyond invalidation buffer",t[closed]);
      return;
   }

   //--- retest test on the just-closed bar
   bool retest=false;
   if(g_active_setup.is_buy)
   {
      bool wicked_in=(l[closed]<=g_active_setup.zone_top &&
                      l[closed]>=g_active_setup.zone_bottom-InpInvalidateBufferATR*atr);
      bool close_holds=(c[closed]>g_active_setup.zone_bottom);
      bool max_dist_ok=(InpRetestMaxDistanceATR<=0.0 ||
                        (g_active_setup.zone_top-l[closed])<=InpRetestMaxDistanceATR*atr);
      retest=(wicked_in && close_holds && max_dist_ok);
   }
   else
   {
      bool wicked_in=(h[closed]>=g_active_setup.zone_bottom &&
                      h[closed]<=g_active_setup.zone_top+InpInvalidateBufferATR*atr);
      bool close_holds=(c[closed]<g_active_setup.zone_top);
      bool max_dist_ok=(InpRetestMaxDistanceATR<=0.0 ||
                        (h[closed]-g_active_setup.zone_bottom)<=InpRetestMaxDistanceATR*atr);
      retest=(wicked_in && close_holds && max_dist_ok);
   }

   if(retest && (g_active_setup.state=="READY" || g_active_setup.state=="RETEST_PREVIEW"))
   {
      // v5.7.x: MSS + causal path + retest all mandatory. A retest publishes
      // the CONFIRMED trade; it never bypasses the causal gates that seeded
      // the setup, and invalidated setups release ownership only through
      // this lifecycle (no opposite-branch bypass of retest).
      g_active_setup.state="CONFIRMED";
      g_active_setup.retest_bar=closed;
      g_active_setup.retest_time=t[closed];
      g_active_setup.confirmed_bar=closed;
      g_active_setup.confirmed_time=t[closed];

      g_trade_setup.valid=true;
      g_trade_setup.created_bar=g_active_setup.created_bar;
      g_trade_setup.created_time=g_active_setup.created_time;
      g_trade_setup.zone_top=g_active_setup.zone_top;
      g_trade_setup.zone_bottom=g_active_setup.zone_bottom;
      g_trade_setup.is_buy=g_active_setup.is_buy;
      g_trade_setup.entry=g_active_setup.entry;
      g_trade_setup.sl=g_active_setup.sl;
      g_trade_setup.tp1=g_active_setup.tp1;
      g_trade_setup.tp2=g_active_setup.tp2;
      g_trade_setup.tp3=g_active_setup.tp3;
      g_trade_setup.rr1=g_active_setup.rr1;
      g_trade_setup.rr2=g_active_setup.rr2;
      g_trade_setup.rr3=g_active_setup.rr3;
      g_trade_setup.confidence=g_active_setup.confidence;
      g_trade_setup.reliability=g_active_setup.reliability;
      g_trade_setup.quality_grade=g_active_setup.quality_grade;
      g_trade_setup.institutional_grade=g_active_setup.institutional_grade;
      g_trade_setup.risk_level=g_active_setup.risk_level;
      g_trade_setup.risk_pips=g_active_setup.risk_pips;
      g_trade_setup.setup_event_id=g_active_setup.setup_event_id;
      g_trade_setup.zone_event_id=g_active_setup.zone_event_id;
      g_trade_setup.structure_event_id=g_active_setup.structure_event_id;
      g_trade_setup.sweep_event_id=g_active_setup.sweep_event_id;
      g_trade_setup.displacement_event_id=g_active_setup.displacement_event_id;
      g_trade_setup.zone_source=g_active_setup.zone_source;
      g_trade_setup.sweep_bar=g_active_setup.sweep_bar;
      g_trade_setup.sweep_price=g_active_setup.sweep_price;
      g_trade_setup.immutable_target_barrier=g_active_setup.immutable_target_barrier;
      g_trade_setup.immutable_target_barrier_type=g_active_setup.immutable_target_barrier_type;
      g_trade_setup.immutable_target_barrier_event_id=g_active_setup.immutable_target_barrier_event_id;
      g_trade_setup.immutable_target_barrier_bar=g_active_setup.immutable_target_barrier_bar;
      g_trade_setup.causal_path_score=g_active_setup.causal_path_score;
      if(InpLogLifecycleTransitions)
         LogLifecycle(StringFormat("CONFIRMED %s (retest bar %d)",
                                   g_active_setup.id,closed));
   }
}

//====================================================================
// ALERTS - one per confirmed event, no per-tick repeats
//====================================================================
void FireSetupAlert(const datetime bar_time)
{
   if(!InpAlertOnSetup) return;
   if(!g_trade_setup.valid) return;
   if(g_last_confirmed_alert_id==g_trade_setup.setup_event_id) return;
   if(bar_time<=g_last_alert_bar && g_last_alert_bar>0) return;

   g_last_confirmed_alert_id=g_trade_setup.setup_event_id;
   g_last_alert_bar=bar_time;
   Alert(StringFormat("%s %s | MSS CONFIRMED %s SETUP | entry %.2f SL %.2f TP1 %.2f TP2 %.2f TP3 %.2f | zone %s-%s | grade %s | %s",
         _Symbol,TFName((ENUM_TIMEFRAMES)_Period),
         g_trade_setup.is_buy?"BUY":"SELL",
         g_trade_setup.entry,g_trade_setup.sl,
         g_trade_setup.tp1,g_trade_setup.tp2,g_trade_setup.tp3,
         DoubleToString(g_trade_setup.zone_bottom,_Digits),
         DoubleToString(g_trade_setup.zone_top,_Digits),
         g_trade_setup.quality_grade,
         TimeToString(bar_time,TIME_DATE|TIME_MINUTES)));
}

//====================================================================
// EMA + INSTITUTIONAL VWAP
// EMA comes from the indicator handles.  VWAP is session-anchored:
// committed totals cover CLOSED bars only; the forming bar contributes
// a provisional value that is committed exactly once when it closes.
//====================================================================
void FillEMAAndVWAP(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const long &tv[],const bool is_new_bar)
{
   if(total<2) return;

   if(total>ArraySize(BufVWAP)) return; // terminal not ready yet

   if(is_new_bar) // full pass: rebuild committed history deterministically
   {
      int na=CopyBuffer(h_ema_fast,0,0,total,BufEmaFast);
      int ns=CopyBuffer(h_ema_slow,0,0,total,BufEmaSlow);
      if(na<total || ns<total)
      {
         // partial data: clear the tail so stale values never persist
         for(int k=0;k<total;k++)
         {
            if(k>=na) BufEmaFast[k]=EMPTY_VALUE;
            if(k>=ns) BufEmaSlow[k]=EMPTY_VALUE;
         }
      }

      g_committed_pv=0.0; g_committed_v=0.0;
      g_cur_bar_pv=0.0;   g_cur_bar_v=0.0;
      datetime anchor=DayAnchor(t[0]);
      g_vwap_anchor=anchor;
      for(int k=0;k<total;k++)
      {
         if(t[k]>=anchor+86400)
         {
            anchor=DayAnchor(t[k]);
            g_vwap_anchor=anchor;
            g_committed_pv=0.0; g_committed_v=0.0;
         }
         double typical=(h[k]+l[k]+c[k])/3.0;
         double v=(double)MathMax(1,tv[k]);
         if(k<total-1)
         {
            g_committed_pv+=typical*v;
            g_committed_v+=v;
            BufVWAP[k]=(g_committed_v>0 ? g_committed_pv/g_committed_v : typical);
         }
         else
         {
            g_cur_bar_pv=typical*v;
            g_cur_bar_v=v;
            g_cur_bar_time=t[k];
            BufVWAP[k]=(g_committed_v+g_cur_bar_v>0 ?
                        (g_committed_pv+g_cur_bar_pv)/(g_committed_v+g_cur_bar_v) : typical);
         }
      }
      return;
   }

   //--- incremental pass
   int last=total-1;
   double ef[3],es[3];
   if(CopyBuffer(h_ema_fast,0,0,3,ef)==3)
      for(int k=0;k<3;k++) BufEmaFast[total-3+k]=ef[k];
   if(CopyBuffer(h_ema_slow,0,0,3,es)==3)
      for(int k=0;k<3;k++) BufEmaSlow[total-3+k]=es[k];

   // forming bar rolled over -> commit the previous forming contribution
   if(t[last]!=g_cur_bar_time && g_cur_bar_time>0)
   {
      g_committed_pv+=g_cur_bar_pv;
      g_committed_v+=g_cur_bar_v;
      g_cur_bar_pv=0.0; g_cur_bar_v=0.0;
      g_cur_bar_time=t[last];
   }
   if(g_vwap_anchor==0) g_vwap_anchor=DayAnchor(t[last]);
   if(DayAnchor(t[last])!=DayAnchor(g_vwap_anchor))
   {
      g_vwap_anchor=DayAnchor(t[last]);
      g_committed_pv=0.0; g_committed_v=0.0;
   }
   double typical=(h[last]+l[last]+c[last])/3.0;
   double v=(double)MathMax(1,tv[last]);
   g_cur_bar_pv=typical*v;
   g_cur_bar_v=v;
   BufVWAP[last]=(g_committed_v+g_cur_bar_v>0 ?
                  (g_committed_pv+g_cur_bar_pv)/(g_committed_v+g_cur_bar_v) : typical);
   if(last-1>=0 && BufVWAP[last-1]==0.0)
      BufVWAP[last-1]=BufVWAP[last]; // warm-up guard
}

//====================================================================
// SESSIONS, TIMEZONES & DST  (all pure UTC math; no local-clock reads)
//====================================================================
datetime DayAnchor(const datetime t)
{
   // Broker-day anchor. Uses only the timestamp's own date fields.
   MqlDateTime dt;
   TimeToStruct(t,dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}
datetime LastSundayUTC(const int year,const int month,const int hour)
{
   // 00:00 UTC of the last Sunday of the given month.
   MqlDateTime m;
   m.year=year; m.mon=month; m.day=1; m.hour=hour; m.min=0; m.sec=0;
   // step to first day of next month minus one day
   int nm=month+1,ny=year;
   if(nm>12){nm=1; ny++;}
   m.year=ny; m.mon=nm; m.day=1;
   datetime next_first=StructToTime(m);
   datetime last_day=next_first-86400;
   MqlDateTime ld;
   TimeToStruct(last_day,ld);
   int dow=ld.day_of_week; // 0=Sunday
   datetime sunday=last_day-dow*86400;
   MqlDateTime sd;
   TimeToStruct(sunday,sd);
   sd.hour=hour; sd.min=0; sd.sec=0;
   return StructToTime(sd);
}
datetime NthSundayUTC(const int year,const int month,const int nth,const int hour)
{
   // 00:00 UTC of the nth Sunday (1-based) of the month.
   MqlDateTime m;
   m.year=year; m.mon=month; m.day=1; m.hour=hour; m.min=0; m.sec=0;
   datetime first=StructToTime(m);
   MqlDateTime fd;
   TimeToStruct(first,fd);
   int dow=fd.day_of_week;
   int first_sunday_day=1+((7-dow)%7);
   m.day=first_sunday_day+(nth-1)*7;
   return StructToTime(m);
}
bool IsEuropeDSTUTC(const datetime utc)
{
   // EU summer time: last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC.
   MqlDateTime dt;
   TimeToStruct(utc,dt);
   if(dt.mon>3 && dt.mon<10) return true;
   if(dt.mon<3 || dt.mon>10) return false;
   datetime switch_time=(dt.mon==3 ? LastSundayUTC(dt.year,3,1) : LastSundayUTC(dt.year,10,1));
   return (dt.mon==3 ? utc>=switch_time : utc<switch_time);
}
bool IsUSDSTUTC(const datetime utc)
{
   // US daylight saving: 2nd Sunday of March 07:00 UTC to 1st Sunday of November 06:00 UTC.
   MqlDateTime dt;
   TimeToStruct(utc,dt);
   if(dt.mon>3 && dt.mon<11) return true;
   if(dt.mon<3 || dt.mon>11) return false;
   if(dt.mon==3)
   {
      datetime start=NthSundayUTC(dt.year,3,2,7);
      return utc>=start;
   }
   datetime end=NthSundayUTC(dt.year,11,1,6);
   return utc<end;
}
int BrokerUTCOffsetSecondsAt(const datetime server_time)
{
   // Broker server offset applied at the timestamp's own date, so a session
   // window is evaluated with the DST rule that was actually in force.
   int winter_min=InpBrokerUTCOffsetWinterMinutes;
   if(InpBrokerDSTRule==BROKER_DST_NONE)
      return winter_min*60;
   datetime utc_winter=server_time-winter_min*60;
   bool dst=(InpBrokerDSTRule==BROKER_DST_EU ? IsEuropeDSTUTC(utc_winter)
                                             : IsUSDSTUTC(utc_winter));
   return (winter_min+(dst?60:0))*60;
}
datetime ServerToUTC(const datetime server_time)
{
   return server_time-BrokerUTCOffsetSecondsAt(server_time);
}
datetime SessionLocalTime(const datetime server_time,const ENUM_SESSION_ID session_id)
{
   // Session-local wall clock: UTC plus the session's own fixed offset,
   // with the broker offset removed first.
   datetime utc=ServerToUTC(server_time);
   int offset_hours=0;
   switch(session_id)
   {
      case SESSION_ASIA:   offset_hours=9;  break;  // Tokyo
      case SESSION_LONDON: offset_hours=0;  break;  // London
      case SESSION_NEWYORK:offset_hours=-5; break;  // New York (EST baseline)
   }
   if(session_id==SESSION_NEWYORK && InpUseDSTSessions && IsUSDSTUTC(utc))
      offset_hours=-4;
   if(session_id==SESSION_LONDON && InpUseDSTSessions && IsEuropeDSTUTC(utc))
      offset_hours=1;
   return utc+offset_hours*3600;
}
int DateKey(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t,dt);
   return dt.year*10000+dt.mon*100+dt.day;
}
bool HourInWindow(const int hour,const int start_hour,const int end_hour)
{
   if(start_hour==end_hour) return false;
   if(start_hour<end_hour) return (hour>=start_hour && hour<end_hour);
   return (hour>=start_hour || hour<end_hour); // overnight window
}
bool IsInSession(const datetime server_time,const ENUM_SESSION_ID session_id)
{
   datetime local=SessionLocalTime(server_time,session_id);
   MqlDateTime dt;
   TimeToStruct(local,dt);
   int h=dt.hour;
   switch(session_id)
   {
      case SESSION_ASIA:   return HourInWindow(h,InpAsianStart,InpAsianEnd);
      case SESSION_LONDON: return HourInWindow(h,InpLondonStart,InpLondonEnd);
      case SESSION_NEWYORK:return HourInWindow(h,InpNewYorkStart,InpNewYorkEnd);
   }
   return false;
}
bool IsInKillZone(const datetime server_time,const ENUM_SESSION_ID session_id)
{
   datetime local=SessionLocalTime(server_time,session_id);
   MqlDateTime dt;
   TimeToStruct(local,dt);
   int h=dt.hour;
   switch(session_id)
   {
      case SESSION_LONDON: return HourInWindow(h,InpLondonKillZoneStart,InpLondonKillZoneEnd);
      case SESSION_NEWYORK:return HourInWindow(h,InpNewYorkKillZoneStart,InpNewYorkKillZoneEnd);
      default: return false;
   }
}
int ChartEventBarAtTime(const datetime &chart_time[],const int total,const datetime event_time)
{
   if(event_time<=0 || total<1) return -1;
   // Chronological masters; binary search for the bar containing event_time.
   int lo=0,hi=total-1;
   if(event_time<chart_time[0]) return -1;
   while(lo<hi)
   {
      int mid=(lo+hi+1)/2;
      if(chart_time[mid]<=event_time) lo=mid;
      else hi=mid-1;
   }
   return lo;
}
int ChartClosedBarAtTime(const datetime &chart_time[],const int total,const datetime availability_time)
{
   // The chart bar whose OPEN is the first moment the information existed.
   if(availability_time<=0 || total<1) return -1;
   int ev=ChartEventBarAtTime(chart_time,total,availability_time-1);
   if(ev<0) return -1;
   if(ev+1<total && chart_time[ev]<availability_time)
      return ev+1;
   return ev;
}

//====================================================================
// FRACTAL HELPERS
//====================================================================
int FractalRightBars(const int n)
{
   // A swing is CONFIRMED only after n fully closed bars on the right.
   return MathMax(1,n);
}
int PreviewFractalRightBars(const int n)
{
   // Preview markers may appear earlier; they are display-only and never
   // feed structure, causal events, or trade decisions.
   return MathMax(1,MathMin(n,InpMinRightConfirmBars));
}
bool IsPreviewFractalHigh(const double &h[],const int i,const int n,const int total)
{
   if(i<n || i>=total-1) return false;
   int right=PreviewFractalRightBars(n);
   if(i+right>=total) right=total-1-i;
   if(right<1) return false;
   for(int k=i-n;k<=i+n;k++)
   {
      if(k<0 || k>=total || k==i) continue;
      if(k>i && k>i+right) continue;
      if(k<=i && h[k]>h[i]) return false;
      if(k>i && h[k]>=h[i]) return false; // right side strict: deterministic
   }
   return true;
}
bool IsPreviewFractalLow(const double &l[],const int i,const int n,const int total)
{
   if(i<n || i>=total-1) return false;
   int right=PreviewFractalRightBars(n);
   if(i+right>=total) right=total-1-i;
   if(right<1) return false;
   for(int k=i-n;k<=i+n;k++)
   {
      if(k<0 || k>=total || k==i) continue;
      if(k>i && k>i+right) continue;
      if(k<=i && l[k]<l[i]) return false;
      if(k>i && l[k]<=l[i]) return false;
   }
   return true;
}

//====================================================================
// STRUCTURE DETECTION - Item 2 persistent state machine
// BOS  = with-trend close beyond the last confirmed swing.
// CHoCH = first counter-trend close beyond the last confirmed swing.
// MSS  = counter-trend close WITH displacement (body >= ATR factor).
// All events are committed at the CLOSED bar and become available at
// the next bar's open (event/availability split).
//====================================================================
void DetectStructure(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false)
{
   int n=MathMax(1,InpSwingFractalN);
   int closed=total-2;
   if(closed<2*n+1) return;

   if(!incremental)
   {
      g_struct_last_high=0.0;
      g_struct_last_low=0.0;
      g_struct_trend=0;
      g_struct_last_processed_bar=-1;
      g_struct_last_break_bar=-1;
      ArrayResize(g_structures,0,32);
   }

   int start=MathMax(g_struct_last_processed_bar+1,n);
   bool seeded=false;
   for(int b=start;b<=closed;b++)
   {
      // 1) register newly confirmed fractals with LEFT edge at b-n
      int f=b-n;
      if(f-n>=0)
      {
         bool is_high=true,is_low=true;
         for(int k=f-n;k<=f+n;k++)
         {
            if(k==f) continue;
            if(k<0 || k>=total) {is_high=false; is_low=false; break;}
            if(k<f && h[k]>h[f]) is_high=false;
            if(k>f && h[k]>=h[f]) is_high=false;
            if(k<f && l[k]<l[f]) is_low=false;
            if(k>f && l[k]<=l[f]) is_low=false;
         }
         if(is_high && (g_struct_last_high<=0.0 || h[f]!=g_struct_last_high))
            g_struct_last_high=h[f];
         if(is_low && (g_struct_last_low<=0.0 || l[f]!=g_struct_last_low))
            g_struct_last_low=l[f];
      }

      // 2) first seeding pass establishes a baseline without events
      if(!seeded && g_struct_last_high>0.0 && g_struct_last_low>0.0 &&
         g_struct_trend==0 && g_struct_last_break_bar<0)
      {
         seeded=true;
         if(ArraySize(g_structures)==0)
         {
            SStructureBreak init;
            init.bar=b; init.time=t[b];
            init.price=(MathAbs(c[b]-g_struct_last_high)<MathAbs(c[b]-g_struct_last_low) ?
                        g_struct_last_high : g_struct_last_low);
            init.bullish=(c[b]>init.price);
            init.type="INIT";
            init.ob_bar=-1; init.strength=1; init.priority=0;
            int idx=ArraySize(g_structures);
            ArrayResize(g_structures,idx+1,32);
            g_structures[idx]=init;
            g_struct_trend=(c[b]>init.price ? 1 : -1);
         }
      }

      // 3) close-based break detection
      if(g_struct_last_high>0.0 && c[b]>g_struct_last_high)
      {
         bool with_trend=(g_struct_trend>=0);
         bool displacement=false;
         double body=MathAbs(c[b]-o[b]);
         double atr=(b<ArraySize(g_atr_buf) && g_atr_buf[b]>0.0) ? g_atr_buf[b] : g_atr;
         if(atr>0.0 && body>=atr*InpDisplacementATR) displacement=true;
         SStructureBreak br;
         br.bar=b; br.time=t[b]; br.price=g_struct_last_high;
         br.bullish=true;
         if(with_trend) br.type="BOS";
         else br.type=(displacement ? "MSS" : "CHoCH");
         br.ob_bar=b; br.strength=(br.type=="MSS"?5:(br.type=="BOS"?4:3));
         br.priority=(br.type=="MSS"?5:(br.type=="BOS"?4:3));
         int idx=ArraySize(g_structures);
         ArrayResize(g_structures,idx+1,32);
         g_structures[idx]=br;
         g_struct_trend=1;
         g_struct_last_break_bar=b;
         g_struct_last_high=0.0; // consumed; next confirmed fractal re-arms
         if(InpLogLifecycleTransitions)
            LogLifecycle(StringFormat("STRUCT %s bull @ %s",br.type,TimeToString(t[b])));
      }
      else if(g_struct_last_low>0.0 && c[b]<g_struct_last_low)
      {
         bool with_trend=(g_struct_trend<=0);
         bool displacement=false;
         double body=MathAbs(c[b]-o[b]);
         double atr=(b<ArraySize(g_atr_buf) && g_atr_buf[b]>0.0) ? g_atr_buf[b] : g_atr;
         if(atr>0.0 && body>=atr*InpDisplacementATR) displacement=true;
         SStructureBreak br;
         br.bar=b; br.time=t[b]; br.price=g_struct_last_low;
         br.bullish=false;
         if(with_trend) br.type="BOS";
         else br.type=(displacement ? "MSS" : "CHoCH");
         br.ob_bar=b; br.strength=(br.type=="MSS"?5:(br.type=="BOS"?4:3));
         br.priority=(br.type=="MSS"?5:(br.type=="BOS"?4:3));
         int idx=ArraySize(g_structures);
         ArrayResize(g_structures,idx+1,32);
         g_structures[idx]=br;
         g_struct_trend=-1;
         g_struct_last_break_bar=b;
         g_struct_last_low=0.0;
         if(InpLogLifecycleTransitions)
            LogLifecycle(StringFormat("STRUCT %s bear @ %s",br.type,TimeToString(t[b])));
      }
      g_struct_last_processed_bar=b;
   }

   // deterministic contradictory-break suppression: the state machine cannot
   // emit both directions on one bar, but if it ever did, keep the last.
   int ns=ArraySize(g_structures);
   if(ns>=2 && g_structures[ns-1].bar==g_structures[ns-2].bar &&
      g_structures[ns-1].bullish!=g_structures[ns-2].bullish)
   {
      for(int i=ns-2;i<ns-1;i++) g_structures[i]=g_structures[i+1];
      ArrayResize(g_structures,ns-1,32);
      ns--;
   }
   // chronological cap: drop the OLDEST entries beyond the limit
   if(ns>InpMaxStructuresKeep)
   {
      int excess=ns-InpMaxStructuresKeep;
      for(int i=0;i<ns-excess;i++)
         g_structures[i]=g_structures[i+excess];
      ArrayResize(g_structures,InpMaxStructuresKeep,32);
   }
}

//====================================================================
// ORDER BLOCKS - displacement-bound, causally anchored
//====================================================================
void AddBreakerBlock(const double &h[],const double &l[],const double &c[],const datetime &t[],const int break_bar,const double top,const double bottom,const bool bullish,const int total)
{
   SBreaker bk;
   bk.bar=break_bar;
   bk.time1=t[MathMax(0,break_bar-8)];
   bk.time2=t[MathMin(total-1,break_bar+8)];
   bk.top=top; bk.bottom=bottom;
   bk.bullish=bullish;
   bk.state="ACTIVE";
   int idx=ArraySize(g_breakers);
   ArrayResize(g_breakers,idx+1,8);
   g_breakers[idx]=bk;
   if(ArraySize(g_breakers)>InpMaxBreakersShown*3)
   {
      int excess=ArraySize(g_breakers)-InpMaxBreakersShown*3;
      for(int i=0;i<ArraySize(g_breakers)-excess;i++) g_breakers[i]=g_breakers[i+excess];
      ArrayResize(g_breakers,InpMaxBreakersShown*3,8);
   }
}

void DetectOrderBlocks(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false)
{
   int closed=total-2;
   if(closed<5) return;
   if(!incremental)
      g_last_ob_struct_time=0;

   for(int si=0;si<ArraySize(g_structures);si++)
   {
      SStructureBreak st=g_structures[si];
      if(st.type=="INIT") continue;
      if(t[st.bar]<=g_last_ob_struct_time && incremental) continue;
      if(st.bar>=closed) continue; // only fully closed origins

      // locate the aligned swept pool that precedes this break
      double sweep_price=0.0;
      int liq=FindAlignedLiquiditySweep(st.bullish,st.bar,InpSweepToStructureMaxBars,sweep_price);
      int sweep_bar=(liq>=0 ? g_liquidity[liq].origin_bar : -1);

      int impulse_bar=-1;
      bool leg_ok=ValidateDisplacementLeg(MathMax(0,sweep_bar),st.bar,st.bullish,
                                          st.price,o,h,l,c,impulse_bar);
      if(!leg_ok)
      {
         // OB requires a displacement leg; an opposite-candle without a
         // displacement bound is NOT an order block.
         continue;
      }

      // the causal OB is the final opposing candle before the exact impulse
      int leg_start=MathMax(0,sweep_bar-MathMax(0,InpOrderZonePreSweepBars));
      int ob_bar=-1;
      for(int k=impulse_bar-1;k>=leg_start;k--)
      {
         if((st.bullish && c[k]<o[k]) || (!st.bullish && c[k]>o[k]))
         {ob_bar=k; break;}
      }
      if(ob_bar<0) continue;

      double ob_top,ob_bottom;
      if(st.bullish){ob_top=MathMax(o[ob_bar],c[ob_bar]); ob_bottom=l[ob_bar];}
      else{ob_top=h[ob_bar]; ob_bottom=MathMin(o[ob_bar],c[ob_bar]);}
      double atr=(ob_bar<ArraySize(g_atr_buf) && g_atr_buf[ob_bar]>0.0) ? g_atr_buf[ob_bar] : g_atr;
      double height=ob_top-ob_bottom;
      if(atr>0.0 && height>atr*InpOBMaxHeightATR)
      {
         // institutional OB: trim to the body envelope when wicks are excessive
         ob_top=MathMax(o[ob_bar],c[ob_bar]);
         ob_bottom=MathMin(o[ob_bar],c[ob_bar]);
         if(ob_top-ob_bottom<_Point) continue;
      }

      string id=GenerateOBId(t[ob_bar],ob_top,ob_bottom,st.bullish);
      if(FindOBIndexByUID(id)>=0) {g_last_ob_struct_time=t[st.bar]; continue;}

      int strength=2;
      if(leg_ok && atr>0.0)
      {
         double body_ratio=MathAbs(c[impulse_bar]-o[impulse_bar])/atr;
         strength=2+(body_ratio>=1.0?1:0)+(body_ratio>=1.5?1:0)+(liq>=0?1:0);
         strength=MathMin(5,strength);
      }
      SOrderBlock ob;
      ob.id=id;
      ob.bar=ob_bar;
      ob.time1=t[ob_bar];
      ob.time2=t[st.bar];
      ob.top=ob_top; ob.bottom=ob_bottom;
      ob.bullish=st.bullish;
      ob.mitigated=false;
      ob.strength=strength;
      ob.state="ACTIVE";
      ob.distance_from_price=MathAbs(c[closed]-(ob_top+ob_bottom)*0.5);
      ob.age=closed-ob_bar;
      ob.origin_struct_bar=st.bar;
      ob.source_displacement_bar=impulse_bar;
      ob.source_displacement_time=t[impulse_bar];
      ob.source_displacement_event_id="";
      ob.source_structure_event_id="";
      ob.source_structure_time=0;
      ob.closed_state="ACTIVE";
      ob.live_preview="";
      int idx=ArraySize(g_order_blocks);
      ArrayResize(g_order_blocks,idx+1,16);
      g_order_blocks[idx]=ob;
      g_last_ob_struct_time=t[st.bar];
      if(InpLogLifecycleTransitions)
         LogLifecycle(StringFormat("OB %s @ %s strength=%d",id,
                                   TimeToString(t[ob_bar]),strength));
   }
   EnforceArrayLimits();
}

//====================================================================
// SUPPLY / DEMAND ZONES
//====================================================================
void DetectZones(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false)
{
   int closed=total-2;
   if(closed<InpZoneLookback+2) return;
   if(!incremental) ArrayResize(g_zones,0,8);

   int start=(incremental ? MathMax(1,closed-3) : MathMax(1,closed-InpZoneLookback));
   for(int b=closed;b>=start;b--)
   {
      double atr=(b<ArraySize(g_atr_buf) && g_atr_buf[b]>0.0) ? g_atr_buf[b] : g_atr;
      if(atr<=0.0) continue;
      double body=MathAbs(c[b]-o[b]);
      if(body<atr*InpZoneBaseBodyATR) continue;
      double top=MathMax(o[b],c[b]);
      double bottom=MathMin(o[b],c[b]);
      if(top-bottom>atr*InpZoneMaxHeightATR) continue;
      bool bull=(c[b]>o[b]);
      // base candle: previous candle opposite or small
      bool base_ok=(c[b-1]<o[b-1])!=bull || MathAbs(c[b-1]-o[b-1])<atr*0.4;
      if(!base_ok) continue;
      // fresh zone: price must have LEFT the zone after it formed
      bool left=false;
      for(int k=b+1;k<=closed && k<=b+20;k++)
      {
         if(bull && l[k]>top){left=true; break;}
         if(!bull && h[k]<bottom){left=true; break;}
      }
      if(!left) continue;
      string zid=StringFormat("ZN_%s_%I64d_%s",_Symbol,(long)t[b],bull?"B":"S");
      bool exists=false;
      for(int i=0;i<ArraySize(g_zones);i++)
         if(StringFormat("ZN_%s_%I64d_%s",_Symbol,(long)t[g_zones[i].bar],g_zones[i].bullish?"B":"S")==zid){exists=true; break;}
      if(exists) continue;
      SZone z;
      z.bar=b; z.time1=t[b]; z.time2=t[closed];
      z.top=top; z.bottom=bottom;
      z.bullish=bull;
      z.state="ACTIVE";
      z.touches=0;
      z.strength_score=MathMin(100.0,60.0+body/atr*20.0);
      int idx=ArraySize(g_zones);
      ArrayResize(g_zones,idx+1,8);
      g_zones[idx]=z;
   }
   // chronological cap: newest survive
   if(ArraySize(g_zones)>InpMaxZonesShown*4)
   {
      int excess=ArraySize(g_zones)-InpMaxZonesShown*4;
      for(int i=0;i<ArraySize(g_zones)-excess;i++) g_zones[i]=g_zones[i+excess];
      ArrayResize(g_zones,InpMaxZonesShown*4,8);
   }
}

//====================================================================
// FAIR VALUE GAPS (3-candle)
//====================================================================
void AddOrMergeFVG(SFVG &fvg,const int total,const double &h[],const double &l[])
{
   if(!InpMergeFVG){ 
      int n=ArraySize(g_fvgs); ArrayResize(g_fvgs,n+1,16); g_fvgs[n]=fvg; return; }
   for(int i=0;i<ArraySize(g_fvgs);i++)
   {
      if(g_fvgs[i].bullish!=fvg.bullish) continue;
      if(g_fvgs[i].state=="FILLED") continue;
      bool overlap=(fvg.bottom<=g_fvgs[i].top && fvg.top>=g_fvgs[i].bottom);
      if(!overlap) continue;
      // merge into the older gap, keep the OLDER id (deterministic)
      g_fvgs[i].top=MathMax(g_fvgs[i].top,fvg.top);
      g_fvgs[i].bottom=MathMin(g_fvgs[i].bottom,fvg.bottom);
      g_fvgs[i].time2=fvg.time2;
      g_fvgs[i].mid_price=(g_fvgs[i].top+g_fvgs[i].bottom)*0.5;
      ReevaluateFVGStateFull(g_fvgs[i],total,h,l);
      return;
   }
   int n=ArraySize(g_fvgs);
   ArrayResize(g_fvgs,n+1,16);
   g_fvgs[n]=fvg;
}
void DetectFVG(const int total,const double &o[],const double &h[],const double &l[],const double &c[],const datetime &t[],const bool incremental=false)
{
   int closed=total-2;
   if(closed<3) return;
   int start=(incremental ? MathMax(2,closed-2) : MathMax(2,closed-InpFVGLookbackBars));
   for(int C=start;C<=closed;C++)
   {
      int A=C-2,B=C-1;
      double atr=(B<ArraySize(g_atr_buf) && g_atr_buf[B]>0.0) ? g_atr_buf[B] : g_atr;
      if(atr<=0.0) continue;
      bool bullish_gap=(l[C]>h[A]);
      bool bearish_gap=(h[C]<l[A]);
      if(!bullish_gap && !bearish_gap) continue;
      bool bullish=bullish_gap;
      double top=(bullish ? l[C] : h[A]);
      double bottom=(bullish ? h[A] : l[C]);
      double size=top-bottom;
      if(size<atr*InpFVGMinSizeATR) continue;
      // middle candle must be the displacement source (causal binding)
      double body=c[B]-o[B];
      if(InpRequireCausalFVGBody)
      {
         if((bullish && body<atr*InpCausalDisplacementBodyATR) ||
            (!bullish && -body<atr*InpCausalDisplacementBodyATR)) continue;
      }
      string id=GenerateFVGId(bullish,t[B],t[C],top,bottom);
      bool exists=false;
      for(int i=0;i<ArraySize(g_fvgs);i++)
         if(g_fvgs[i].id==id){exists=true; break;}
      if(exists) continue;
      SFVG f;
      f.id=id;
      f.bar=C;                    // alias of creation_bar
      f.time1=t[A]; f.time2=t[C];
      f.top=top; f.bottom=bottom;
      f.bullish=bullish;
      f.filled=false;
      f.state="OPEN";
      f.mid_price=(top+bottom)*0.5;
      f.creation_bar=C;
      f.creation_time=t[C];       // occurrence: completion-candle open
      f.availability_bar=C;       // authoritative closed decision bar
      f.availability_time=(C+1<total ? t[C+1] : t[C]+PeriodSeconds());
      f.source_displacement_bar=B;
      f.source_displacement_time=t[B];
      f.source_displacement_event_id="";
      f.source_structure_bar=-1;
      f.source_structure_time=0;
      f.source_structure_event_id="";
      AddOrMergeFVG(f,total,h,l);
   }
   // re-evaluate states on the freshly closed bar
   for(int i=0;i<ArraySize(g_fvgs);i++)
      ReevaluateFVGStateIncremental(g_fvgs[i],closed,h,l);
   // cap: newest survive
   if(ArraySize(g_fvgs)>InpMaxFVGKeep)
   {
      int excess=ArraySize(g_fvgs)-InpMaxFVGKeep;
      for(int i=0;i<ArraySize(g_fvgs)-excess;i++) g_fvgs[i]=g_fvgs[i+excess];
      ArrayResize(g_fvgs,InpMaxFVGKeep,16);
   }
   if(InpHideFilledFVG)
   {
      int w=0;
      for(int i=0;i<ArraySize(g_fvgs);i++)
         if(g_fvgs[i].state!="FILLED"){g_fvgs[w]=g_fvgs[i]; w++;}
      ArrayResize(g_fvgs,w,16);
   }
}

//====================================================================
// LIQUIDITY POOLS & SWEEPS
// Pool = equal highs/lows within a point/ATR tolerance (never float
// equality).  Sweep = trade-through + close-back rejection; a touch
// alone is never a sweep.  Pool and sweep records stay an atomic pair.
//====================================================================
void DetectLiquidity(const int total,const double &h[],const double &l[],const double &c[],const double &o[],const long &tv[],const datetime &t[],const bool incremental)
{
   int closed=total-2;
   int n=MathMax(1,InpLiquidityFractalN);
   if(closed<2*n+2) return;
   if(!incremental) ArrayResize(g_liquidity,0,32);

   double atr=(closed<ArraySize(g_atr_buf) && g_atr_buf[closed]>0.0) ? g_atr_buf[closed] : g_atr;
   double tol=MathMax(atr*InpLiqToleranceATR,InpLiquidityTolerancePips*PipSize());
   if(tol<=0.0) tol=_Point;

   //--- build confirmed pools from fractal swing points
   int start=(incremental ? MathMax(n,closed-3) : MathMax(n,closed-InpLiquidityLookback));
   for(int f=closed-n;f>=start;f--)
   {
      bool is_high=true,is_low=true;
      for(int k=f-n;k<=f+n;k++)
      {
         if(k==f) continue;
         if(k<0 || k>=total){is_high=false; is_low=false; break;}
         if(k<f && h[k]>h[f]) is_high=false;
         if(k>f && h[k]>=h[f]) is_high=false;
         if(k<f && l[k]<l[f]) is_low=false;
         if(k>f && l[k]<=l[f]) is_low=false;
      }
      if(is_high)
      {
         // merge with an existing EQH within tolerance (cluster, no float ==)
         string merged_id="";
         for(int i=0;i<ArraySize(g_liquidity);i++)
         {
            if(g_liquidity[i].type!="EQH" || g_liquidity[i].swept) continue;
            if(MathAbs(g_liquidity[i].price-h[f])<=tol)
            {
               merged_id=g_liquidity[i].id;
               g_liquidity[i].price=(g_liquidity[i].price+h[f])*0.5;
               break;
            }
         }
         if(merged_id=="")
         {
            int avail_bar=MathMin(total-1,f+n);
            SLiquidity q;
            q.id=GenerateLiquidityId("EQH",t[f],t[avail_bar],h[f]);
            q.bar=avail_bar; q.time=t[f];
            q.origin_bar=f; q.origin_time=t[f];
            q.availability_bar=avail_bar;
            q.availability_time=(avail_bar+1<total ? t[avail_bar+1] : t[avail_bar]+PeriodSeconds());
            q.price=h[f]; q.type="EQH"; q.swept=false; q.priority=3;
            q.parent_pool_bar=-1; q.parent_level=0.0; q.parent_pool_id="";
            q.parent_pool_origin_bar=-1; q.parent_pool_origin_time=0;
            q.parent_pool_availability_bar=-1; q.parent_pool_availability_time=0;
            int idx=ArraySize(g_liquidity);
            ArrayResize(g_liquidity,idx+1,32);
            g_liquidity[idx]=q;
         }
      }
      if(is_low)
      {
         string merged_id="";
         for(int i=0;i<ArraySize(g_liquidity);i++)
         {
            if(g_liquidity[i].type!="EQL" || g_liquidity[i].swept) continue;
            if(MathAbs(g_liquidity[i].price-l[f])<=tol)
            {
               merged_id=g_liquidity[i].id;
               g_liquidity[i].price=(g_liquidity[i].price+l[f])*0.5;
               break;
            }
         }
         if(merged_id=="")
         {
            int avail_bar=MathMin(total-1,f+n);
            SLiquidity q;
            q.id=GenerateLiquidityId("EQL",t[f],t[avail_bar],l[f]);
            q.bar=avail_bar; q.time=t[f];
            q.origin_bar=f; q.origin_time=t[f];
            q.availability_bar=avail_bar;
            q.availability_time=(avail_bar+1<total ? t[avail_bar+1] : t[avail_bar]+PeriodSeconds());
            q.price=l[f]; q.type="EQL"; q.swept=false; q.priority=3;
            q.parent_pool_bar=-1; q.parent_level=0.0; q.parent_pool_id="";
            q.parent_pool_origin_bar=-1; q.parent_pool_origin_time=0;
            q.parent_pool_availability_bar=-1; q.parent_pool_availability_time=0;
            int idx=ArraySize(g_liquidity);
            ArrayResize(g_liquidity,idx+1,32);
            g_liquidity[idx]=q;
         }
      }
   }

   //--- sweep detection on closed bars: trade-through + close-back
   for(int i=0;i<ArraySize(g_liquidity);i++)
   {
      if(g_liquidity[i].swept) continue;
      if(g_liquidity[i].type!="EQH" && g_liquidity[i].type!="EQL") continue;
      bool is_high=(g_liquidity[i].type=="EQH");
      double level=g_liquidity[i].price;
      // a pool can only be swept after it became known to the chart
      int sweep_search_start=MathMax(g_liquidity[i].availability_bar+1,1);
      for(int b=MathMax(sweep_search_start,closed-5);b<=closed;b++)
      {
         bool trade_through=is_high ? (h[b]>level) : (l[b]<level);
         if(!trade_through) continue;
         bool close_back=is_high ? (c[b]<level) : (c[b]>level);
         if(!close_back) continue; // touch-only closes are NOT sweeps
         bool strength_ok=SweepHasDisplacementOrVolume(b,is_high,level,atr,h,l,o,c,tv);
         // record the sweep as a CHILD of the pool (atomic pair)
         SLiquidity s;
         string stype=(is_high ? "BSL TAKEN" : "SSL TAKEN");
         s.id=GenerateLiquidityId(stype,t[b],(b+1<total ? t[b+1] : t[b]),level);
         s.bar=b; s.time=t[b];
         s.origin_bar=b; s.origin_time=t[b];
         s.availability_bar=b;
         s.availability_time=(b+1<total ? t[b+1] : t[b]+PeriodSeconds());
         s.price=level; s.type=stype; s.swept=true;
         s.priority=strength_ok?6:4;
         s.parent_pool_bar=g_liquidity[i].availability_bar;
         s.parent_level=level;
         s.parent_pool_id=g_liquidity[i].id;
         s.parent_pool_origin_bar=g_liquidity[i].origin_bar;
         s.parent_pool_origin_time=g_liquidity[i].origin_time;
         s.parent_pool_availability_bar=g_liquidity[i].availability_bar;
         s.parent_pool_availability_time=g_liquidity[i].availability_time;
         int idx=ArraySize(g_liquidity);
         ArrayResize(g_liquidity,idx+1,32);
         g_liquidity[idx]=s;
         g_liquidity[i].swept=true;   // pool consumed by its own sweep
         if(InpLogLifecycleTransitions)
            LogLifecycle(StringFormat("SWEEP %s (%s) @ %s",s.id,g_liquidity[i].id,
                                      TimeToString(t[b])));
         break; // one sweep event per pool
      }
   }

   BuildLiquidityPriorityIndex();
   // chronological cap, sweep+pool pairs stay adjacent in the array
   if(ArraySize(g_liquidity)>InpMaxLiquidityKeep)
   {
      int excess=ArraySize(g_liquidity)-InpMaxLiquidityKeep;
      for(int i=0;i<ArraySize(g_liquidity)-excess;i++)
         g_liquidity[i]=g_liquidity[i+excess];
      ArrayResize(g_liquidity,InpMaxLiquidityKeep,32);
   }
}

//====================================================================
// DEALING RANGE / PREMIUM-DISCOUNT / OTE
//====================================================================
void DetectDealingRange(const int total,const double &h[],const double &l[],const datetime &t[],const bool incremental=false)
{
   // Full and incremental passes intentionally scan the SAME window, so the
   // result never depends on how the call was triggered.
   int closed=total-2;
   int n=MathMax(2,InpSwingRangeFractalN);
   if(closed<n*2+2){g_range.valid=false; return;}
   int win_start=MathMax(0,closed-InpSwingLookback);
   int hb=-1,lb=-1;
   for(int i=win_start;i<=closed;i++)
   {
      if(hb<0 || h[i]>h[hb]) hb=i;
      if(lb<0 || l[i]<l[lb]) lb=i;
   }
   if(hb<0 || lb<0 || hb==lb) {g_range.valid=false; return;}
   g_range.valid=true;
   g_range.bar_high=hb; g_range.bar_low=lb;
   g_range.time_high=t[hb]; g_range.time_low=t[lb];
   g_range.high=h[hb]; g_range.low=l[lb];
   g_range.eq=(h[hb]+l[lb])*0.5;
   g_range.bullish_leg=(hb>lb);
}
bool GetOTEZone(double &ote_top,double &ote_bottom,bool &ote_is_buy)
{
   ote_top=0; ote_bottom=0; ote_is_buy=false;
   if(!g_range.valid) return false;
   double range=g_range.high-g_range.low;
   if(range<=_Point) return false;
   if(g_range.bullish_leg)
   {
      ote_is_buy=true;
      ote_top=g_range.high-range*InpOTEFibStart;
      ote_bottom=g_range.high-range*InpOTEFibEnd;
   }
   else
   {
      ote_is_buy=false;
      ote_bottom=g_range.low+range*InpOTEFibStart;
      ote_top=g_range.low+range*InpOTEFibEnd;
   }
   return (ote_top>ote_bottom);
}

//====================================================================
// HTF BIAS (closed HTF candles only; event/availability split)
//====================================================================
int ComputeClosedStructureBias(const ENUM_TIMEFRAMES tf,const int lookback,const int fractal_n,
                               double &eq_out,string &state_out,datetime &last_event_time,
                               datetime &last_availability_time)
{
   eq_out=0.0; state_out="NEUTRAL";
   last_event_time=0; last_availability_time=0;
   MqlRates rt[];
   int need=MathMin(lookback,299);
   int copied=CopyRates(_Symbol,tf,0,need+1,rt);
   if(copied<5) return 0;
   // chronological fill: index 0 oldest, copied-1 = forming HTF candle
   int last_confirmed=copied-2; // index of last closed HTF candle
   if(last_confirmed<fractal_n*2) return 0;
   // local OHLC views over the copied rates (closed bars only are read)
   double hh[],ll[],cc[]; datetime tt[];
   ArrayResize(hh,copied); ArrayResize(ll,copied);
   ArrayResize(cc,copied); ArrayResize(tt,copied);
   for(int i=0;i<copied;i++)
   {
      hh[i]=rt[i].high; ll[i]=rt[i].low; cc[i]=rt[i].close; tt[i]=rt[i].time;
   }
   double hi=hh[0],lo=ll[0];
   for(int i=1;i<=last_confirmed;i++)
   {
      if(hh[i]>hi) hi=hh[i];
      if(ll[i]<lo) lo=ll[i];
   }
   eq_out=(hi+lo)*0.5;
   // EMA200-like proxy on closed HTF closes is replaced by swing logic:
   int n=MathMax(1,fractal_n);
   double last_high=0.0,last_low=0.0;
   datetime last_high_t=0,last_low_t=0;
   for(int f=last_confirmed-n;f>=n;f--)
   {
      if(last_high==0.0)
      {
         bool ok=true;
         for(int k=f-n;k<=f+n;k++)
         {
            if(k==f || k<0 || k>last_confirmed) continue;
            if(hh[k]>hh[f]){ok=false; break;}
         }
         if(ok){last_high=hh[f]; last_high_t=tt[f];}
      }
      if(last_low==0.0)
      {
         bool ok=true;
         for(int k=f-n;k<=f+n;k++)
         {
            if(k==f || k<0 || k>last_confirmed) continue;
            if(ll[k]<ll[f]){ok=false; break;}
         }
         if(ok){last_low=ll[f]; last_low_t=tt[f];}
      }
      if(last_high>0.0 && last_low>0.0) break;
   }
   int bias=0;
   if(last_high>0.0 && last_low>0.0)
   {
      // direction from recency of swings + equilibrium position
      if(last_high_t>last_low_t) bias=1; else bias=-1;
   }
   else if(last_high>0.0) bias=1;
   else if(last_low>0.0) bias=-1;
   // last closed candle position vs equilibrium refines the state label
   double c_last=cc[last_confirmed];
   if(bias>0) state_out=(c_last>eq_out?"BULLISH":"BULLISH_PULLBACK");
   else if(bias<0) state_out=(c_last<eq_out?"BEARISH":"BEARISH_PULLBACK");
   // event time = last confirmed HTF swing that set the bias; availability = its close
   datetime ev_t=(bias>0 ? last_high_t : last_low_t);
   if(ev_t>0)
   {
      int shift=iBarShift(_Symbol,tf,ev_t,false);
      if(shift>0)
      {
         last_event_time=iTime(_Symbol,tf,shift);
         last_availability_time=iTime(_Symbol,tf,shift-1);
      }
   }
   return bias;
}
void ComputeHTFBias()
{
   g_htf_bias=0;
   g_htf_structure_state="NEUTRAL";
   g_htf_last_event_time=0;
   g_htf_last_availability_time=0;
   if(!InpUseHTFBias) return;
   string st="";
   g_htf_bias=ComputeClosedStructureBias(InpHTFBiasTF,InpSwingLookback,
                                         InpHTFStructureFractalN,g_htf_eq,st,
                                         g_htf_last_event_time,
                                         g_htf_last_availability_time);
   g_htf_structure_state=st;

   // D1 structure state for the conflict engine
   string d1_st="";
   double d1_eq=0.0;
   datetime d1_ev=0,d1_av=0;
   int d1_bias=ComputeClosedStructureBias(PERIOD_D1,60,InpHTFStructureFractalN,
                                          d1_eq,d1_st,d1_ev,d1_av);
   g_d1_structure_state=(d1_bias>0?"BULLISH":(d1_bias<0?"BEARISH":"NEUTRAL"));
   g_d1_last_event_time=d1_ev;
   g_d1_last_availability_time=d1_av;

   // closed daily extremes for target logic (shift 1 = last CLOSED day)
   double dh=iHigh(_Symbol,PERIOD_D1,1);
   double dl=iLow(_Symbol,PERIOD_D1,1);
   double dc=iClose(_Symbol,PERIOD_D1,1);
   if(dh>0 && dl>0){g_d1_high=dh; g_d1_low=dl; g_d1_close=dc;}
}

//====================================================================
// JUDAS SWING  (v5.7.3 FIX A6: the post-Asia scan can no longer match
// pre-Asia hours of the same local day; candidates are restricted to
// bars whose session-local time is at or after the Asia session end)
//====================================================================
void DetectJudasSwing(const int total,const datetime &t[],const double &h[],const double &l[],const double &c[])
{
   g_judas=0; g_judas_bar=-1;
   int closed=total-2;
   if(closed<20) return;

   // The applicable Asia day: today's Tokyo day if its window has ended,
   // otherwise yesterday's (deterministic local-day arithmetic).
   datetime now_local=SessionLocalTime(t[closed],SESSION_ASIA);
   MqlDateTime nl;
   TimeToStruct(now_local,nl);
   int day_offset=(nl.hour>=InpAsianEnd ? 0 : 1);
   datetime target_local_day=now_local-day_offset*86400;
   int target_key=DateKey(target_local_day);

   // Asia session extremes (Tokyo-local hours [start,end) of target day)
   double asia_high=-DBL_MAX,asia_low=DBL_MAX;
   int scan_from=-1;
   for(int b=closed;b>=MathMax(0,closed-300);b--)
   {
      datetime lb_local=SessionLocalTime(t[b],SESSION_ASIA);
      if(DateKey(lb_local)!=target_key) continue;
      MqlDateTime ld;
      TimeToStruct(lb_local,ld);
      if(HourInWindow(ld.hour,InpAsianStart,InpAsianEnd))
      {
         asia_high=MathMax(asia_high,h[b]);
         asia_low=MathMin(asia_low,l[b]);
      }
      // earliest post-Asia bar of the target day bounds the reverse scan
      if(ld.hour>=InpAsianEnd && scan_from<0) scan_from=b;
   }
   if(asia_high<=-DBL_MAX/2 || asia_low>=DBL_MAX/2 || scan_from<0) return;

   // v5.7.3 FIX (A6): the candidate window is exclusively bars whose local
   // hour is >= InpAsianEnd on the target local day. Pre-Asia hours of the
   // same local day can never enter this window, so the historical bug —
   // where the sweep search re-matched the session's own pre-Asia spike —
   // is structurally impossible now.
   int end_key=target_key; 
   int judas=0,judas_bar=-1;
   for(int b=scan_from;b<=closed;b++)
   {
      datetime lb_local=SessionLocalTime(t[b],SESSION_ASIA);
      MqlDateTime ld;
      TimeToStruct(lb_local,ld);
      if(DateKey(lb_local)!=end_key) break;      // left the target local day
      if(ld.hour<InpAsianEnd) continue;          // pre/post guard (A6)
      // sweep of Asia highs = "JUDAS DN"; sweep of Asia lows = "JUDAS UP"
      if(h[b]>asia_high && c[b]<asia_high){judas=-1; judas_bar=b; break;}
      if(l[b]<asia_low && c[b]>asia_low){judas=1; judas_bar=b; break;}
   }
   g_judas=judas;
   g_judas_bar=judas_bar;
}

//====================================================================
// KILL ZONES (session-local windows mapped to broker server time)
//====================================================================
void DetectKillZones(const int total,const datetime &t[],const double &h[],const double &l[])
{
   ArrayResize(g_kill_zones,0,8);
   int closed=total-2;
   if(closed<10) return;

   // Build the last few London/NY kill-zone windows from CLOSED bars.
   for(int pass=0;pass<2;pass++)
   {
      ENUM_SESSION_ID sess=(pass==0 ? SESSION_LONDON : SESSION_NEWYORK);
      int kzs=(pass==0 ? InpLondonKillZoneStart : InpNewYorkKillZoneStart);
      int kze=(pass==0 ? InpLondonKillZoneEnd : InpNewYorkKillZoneEnd);
      if(kzs==kze) continue;
      for(int day_back=0;day_back<4;day_back++)
      {
         datetime local_day=SessionLocalTime(t[closed],sess)-day_back*86400;
         MqlDateTime ld;
         TimeToStruct(local_day,ld);
         ld.hour=kzs; ld.min=0; ld.sec=0;
         datetime local_start=StructToTime(ld);
         datetime local_end=local_start+(kze-kzs)*3600;
         // local -> server: subtract session offset, add broker offset
         datetime utc_start=ServerToUTC(t[closed]); // reference only
         int offset_hours=(sess==SESSION_ASIA?9:(sess==SESSION_LONDON ?
                          (IsEuropeDSTUTC(utc_start)?1:0) :
                          (IsUSDSTUTC(utc_start)?-4:-5)));
         datetime server_start=local_start-offset_hours*3600+
                               BrokerUTCOffsetSecondsAt(t[closed]);
         datetime server_end=server_start+(kze-kzs)*3600;
         if(server_end>t[closed]) continue; // window not finished yet
         double zh=-DBL_MAX,zl=DBL_MAX;
         bool found=false;
         for(int b=closed;b>=0;b--)
         {
            if(t[b]<server_start) break;
            if(t[b]<server_end)
            {
               zh=MathMax(zh,h[b]); zl=MathMin(zl,l[b]); found=true;
            }
         }
         if(!found) continue;
         SKillZone kz;
         kz.start=server_start; kz.end=server_end;
         kz.high=zh; kz.low=zl;
         kz.name=(pass==0 ? "LONDON KZ" : "NY KZ");
         kz.col=(pass==0 ? (color)0x2A2A5A : (color)0x5A2A2A);
         int idx=ArraySize(g_kill_zones);
         ArrayResize(g_kill_zones,idx+1,8);
         g_kill_zones[idx]=kz;
      }
   }
}

//====================================================================
// DRAW PRIMITIVES  (deterministic IDs, no per-tick recreation)
//====================================================================
void DrawHLine(const string name,const double price,const color col,const string label,const int width=1)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,label);
}
void DrawTextLabel(const string name,const datetime tm,const double price,const string text,const color col,const bool above,const int font_size=8)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TEXT,0,tm,price);
   ObjectSetInteger(0,name,OBJPROP_TIME,tm);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,font_size);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Black");
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,(above?ANCHOR_LOWER:ANCHOR_UPPER));
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void DrawFibLine(const string name,const datetime t1,const datetime t2,const double price,const color col,const int style=STYLE_DOT,const int width=1)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price);
   ObjectMove(0,name,0,t1,price);
   ObjectMove(0,name,1,t2,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
}
void DrawZoneBox(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color col,const string label,const int transparency=88)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectMove(0,name,0,t1,p1);
   ObjectMove(0,name,1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TEXT,label);
}
color GradeColor(const string g)
{
   if(g=="A+") return clrLime;
   if(g=="A") return clrLimeGreen;
   if(g=="B") return clrYellow;
   if(g=="C") return clrOrange;
   return clrTomato;
}
color PctColor(const int p)
{
   if(p>=80) return clrLime;
   if(p>=60) return clrYellowGreen;
   if(p>=40) return clrGoldenrod;
   return clrTomato;
}
color BlendColor(const color col,const int pct)
{
   // blend toward gray as confidence drops
   color gray=clrDimGray;
   return ColorLerp(gray,col,MathMax(0.0,MathMin(1.0,pct/100.0)));
}

//====================================================================
// DRAW: ZONES / OB / BREAKERS / FVG / LIQUIDITY / KILL ZONES
//====================================================================
void DrawZones()
{
   int shown=0;
   for(int i=ArraySize(g_zones)-1;i>=0 && shown<InpMaxZonesShown;i--)
   {
      if(g_zones[i].state=="MITIGATED") continue;
      string name=PFX+"ZONE_"+IntegerToString(g_zones[i].bar)+"_"+(g_zones[i].bullish?"B":"S");
      color col=g_zones[i].bullish?InpColorDemand:InpColorSupply;
      string label=(g_zones[i].bullish?"DEMAND":"SUPPLY")+" "+
                   DoubleToString(g_zones[i].bottom,_Digits)+"-"+
                   DoubleToString(g_zones[i].top,_Digits);
      DrawZoneBox(name,g_zones[i].time1,g_zones[i].top,g_zones[i].time2,
                   g_zones[i].bottom,col,label,InpOBTransparency);
      shown++;
   }
}
void DrawStructureAndOB()
{
   // structure labels (confirmed only)
   int shown=0;
   for(int i=ArraySize(g_structures)-1;i>=0 && shown<InpMaxStructureShown;i--)
   {
      SStructureBreak st=g_structures[i];
      if(st.type=="INIT") continue;
      string name=PFX+"STRUCT_"+IntegerToString(st.bar)+"_"+st.type;
      color col=st.bullish?clrLime:clrRed;
      DrawTextLabel(name,st.time,st.price,st.type,col,!st.bullish,9);
      shown++;
   }
   // order blocks
   BuildOBStrengthIndex();
   int ob_shown=0;
   for(int k=0;k<ArraySize(g_order_blocks) && ob_shown<MathMax(InpMaxStrongOB,4);k++)
   {
      int i=g_ob_strength_idx[k];
      SOrderBlock ob=g_order_blocks[i];
      if(ob.state=="MITIGATED" || ob.closed_state=="MITIGATED") continue;
      string name=PFX+"OB_"+ob.id;
      color col=ob.bullish?InpColorOB:InpColorOB_Bear;
      string label=(ob.bullish?"Bull OB ":"Bear OB ")+StringSubstr(ob.id,0,18)+
                   " S"+IntegerToString(ob.strength);
      DrawZoneBox(name,ob.time1,ob.top,ob.time2,ob.bottom,col,label,InpOBTransparency);
      ob_shown++;
   }
}
void DrawBreakerZones()
{
   for(int i=0;i<ArraySize(g_breakers);i++)
   {
      SBreaker bk=g_breakers[i];
      if(bk.state!="ACTIVE") continue;
      string name=PFX+"BRK_"+IntegerToString(bk.bar)+"_"+(bk.bullish?"B":"S");
      DrawZoneBox(name,bk.time1,bk.top,bk.time2,bk.bottom,InpColorBreaker,
                  "Breaker "+DoubleToString(bk.bottom,_Digits)+"-"+
                  DoubleToString(bk.top,_Digits),InpOBTransparency+2);
   }
}
void DrawFVGZones()
{
   int shown=0;
   for(int i=ArraySize(g_fvgs)-1;i>=0 && shown<InpMaxFVGShown;i--)
   {
      SFVG f=g_fvgs[i];
      if(f.state=="FILLED" && InpHideFilledFVG) continue;
      string name=PFX+"FVG_"+f.id;
      color col=(f.state=="PARTIAL"?ColorLerp(InpColorFVG,clrGray,0.5):InpColorFVG);
      string label="FVG "+DoubleToString(f.bottom,_Digits)+"-"+
                   DoubleToString(f.top,_Digits)+" ["+f.state+"]";
      DrawZoneBox(name,f.time1,f.top,f.time2,f.bottom,col,label,InpOBTransparency);
      shown++;
   }
}
void DrawLiquidityMarkers()
{
   int shown=0;
   for(int i=ArraySize(g_liquidity)-1;i>=0 && shown<InpMaxLiquidityShown*2;i--)
   {
      SLiquidity q=g_liquidity[i];
      bool is_sweep=(q.type=="BSL TAKEN" || q.type=="SSL TAKEN");
      if(!is_sweep && shown>=InpMaxLiquidityShown) continue;
      string name=PFX+"LIQ_"+q.id;
      color col;
      string label;
      if(q.type=="EQH"){col=clrOrangeRed; label="EQH "+DoubleToString(q.price,_Digits);}
      else if(q.type=="EQL"){col=clrMediumSeaGreen; label="EQL "+DoubleToString(q.price,_Digits);}
      else if(q.type=="BSL TAKEN"){col=clrCrimson; label="BSL SWEPT";}
      else{col=clrTeal; label="SSL SWEPT";}
      DrawFibLine(name,q.origin_time,
                  (q.availability_bar+12<ArraySize(g_buf_t) ?
                   g_buf_t[q.availability_bar+12] : q.availability_time),
                  q.price,col,is_sweep?STYLE_DASH:STYLE_DOT,1);
      if(!is_sweep) shown++;
   }
}
void DrawKillZones()
{
   for(int i=0;i<ArraySize(g_kill_zones);i++)
   {
      SKillZone kz=g_kill_zones[i];
      string name=PFX+"KZ_"+IntegerToString(i)+"_"+TimeToString(kz.start,TIME_DATE);
      DrawZoneBox(name,kz.start,kz.high,kz.end,kz.low,kz.col,kz.name,94);
   }
}

//====================================================================
// DRAW: PREMIUM/DISCOUNT, PROVISIONAL FRACTALS, EARLY-BREAK PREVIEW
//====================================================================
void DrawPremiumDiscount(const int total,const datetime &t[])
{
   if(!g_range.valid) return;
   string base="PD_";
   double top=g_range.high,bot=g_range.low,eq=g_range.eq;
   datetime t1=t[MathMax(0,MathMin(total-1,g_range.bar_low))]; 
   t1=MathMin(t1,t[MathMax(0,MathMin(total-1,g_range.bar_high))]);
   datetime t2=t[total-1]+(datetime)(PeriodSeconds()*10);
   color prem=ColorWithAlpha(InpColorPremium,(uchar)InpPDTransparency);
   color disc=ColorWithAlpha(InpColorDiscount,(uchar)InpPDTransparency);
   if(InpShowPremiumDiscount)
   {
      DrawZoneBox(PFX+base+"PREM",t1,top,t2,eq,prem,"PREMIUM",InpPDTransparency);
      DrawZoneBox(PFX+base+"DISC",t1,eq,t2,bot,disc,"DISCOUNT",InpPDTransparency);
      DrawFibLine(PFX+base+"EQ",t1,t2,eq,InpColorEQ,STYLE_DASH,1);
   }
   if(InpShowFibonacci)
   {
      double fibs[6]={0.0,0.382,0.5,0.618,0.79,1.0};
      for(int i=0;i<6;i++)
      {
         double price=top-(top-bot)*fibs[i];
         DrawFibLine(PFX+base+"FIB"+DoubleToString(fibs[i],3),t1,t2,price,InpColorFib,STYLE_DOT,1);
      }
   }
   if(InpShowOTE)
   {
      double ot,ob; bool ib;
      if(GetOTEZone(ot,ob,ib))
         DrawZoneBox(PFX+base+"OTE",t1,ot,t2,ob,InpColorOTE,
                     "OTE "+(ib?"BUY":"SELL"),InpPDTransparency+2);
   }
}
void DrawProvisionalFractals(const int total,const datetime &t[],const double &h[],const double &l[])
{
   // Display-only provisional swing markers. They NEVER feed structure,
   // causal events, or trade decisions, and are explicitly "DEVELOPING".
   if(!InpRealTimeFractal) return;
   int n=MathMax(1,InpSwingFractalN);
   int scan=MathMin(total-2,40);
   for(int i=total-1;i>total-1-scan && i>n;i--)
   {
      if(IsPreviewFractalHigh(h,i,n,total))
      {
         string name=PFX+"PROVH_"+IntegerToString(i);
         DrawTextLabel(name,t[i],h[i]+g_atr*0.15,"DEVELOPING",clrSilver,true,7);
      }
      if(IsPreviewFractalLow(l,i,n,total))
      {
         string name=PFX+"PROVL_"+IntegerToString(i);
         DrawTextLabel(name,t[i],l[i]-g_atr*0.15,"DEVELOPING",clrSilver,false,7);
      }
   }
}
void UpdateEarlyBreakPreview(const int total,const datetime &t[],const double &h[],const double &l[],const double &c[])
{
   // Live, non-authoritative preview of a structure break forming on the
   // current candle. Never mutates g_structures, causal events, or setups.
   g_early_break_preview=false;
   if(!InpShowEarlyBreakPreview || total<10) return;
   int forming=total-1;
   int closed=total-2;
   if(g_atr<=0.0) return;

   // authoritative candidate level = last confirmed structure price
   int ns=ArraySize(g_structures);
   if(ns<=0) return;
   SStructureBreak last=g_structures[ns-1];
   if(last.type=="INIT") return;

   double buffer=InpEarlyBreakBufferPoints*_Point;
   bool bull_break=(h[forming]>last.price+buffer);
   bool bear_break=(l[forming]<last.price-buffer);
   bool close_confirmed=(last.bullish ? c[forming]>last.price : c[forming]<last.price);

   if(close_confirmed)
   {
      g_early_break_status="CLOSE_CONFIRMED";
      g_early_break_preview=true;
      g_early_break_bull=last.bullish;
      g_early_break_price=last.price;
      g_early_break_time=t[forming];
      g_early_break_structure_idx=ns-1;
      g_early_break_structure_time=last.time;
      g_early_break_structure_type=last.type;
      return;
   }
   if(bull_break || bear_break)
   {
      g_early_break_status="EARLY_BREAK";
      g_early_break_preview=true;
      g_early_break_bull=bull_break;
      g_early_break_price=last.price;
      g_early_break_time=t[forming];
      g_early_break_structure_idx=ns-1;
      g_early_break_structure_time=last.time;
      g_early_break_structure_type=last.type;
      if(InpShowEarlyBreakTrigger)
         DrawTextLabel(PFX+"EARLYBREAK",t[forming],last.price,
                       StringFormat("EARLY BREAK %s (%s)",bull_break?"UP":"DN",
                                    g_early_break_structure_type),
                       bull_break?clrAqua:clrMagenta,true,8);
      return;
   }
   // stale FAILED state decays after one bar
   if(g_early_break_status!="")
   {
      if(g_early_break_time>0 && t[forming]-g_early_break_time>PeriodSeconds()*2)
      {
         g_early_break_status="FAILED";
         g_early_break_failed_time=t[forming];
      }
      else if(g_early_break_status=="FAILED" &&
              g_early_break_failed_time>0 &&
              t[forming]-g_early_break_failed_time>PeriodSeconds()*10)
         g_early_break_status="";
   }
   ObjectDelete(0,PFX+"EARLYBREAK");
}

//====================================================================
// DRAW: PDH/PDL, PIVOTS, CAMARILLA, SESSION H/L
// v5.7.3 FIX (A9): when D1 history is unavailable the levels are simply
// not drawn; they are never drawn at 0.0.
//====================================================================
bool D1HistoryAvailable()
{
   return (iTime(_Symbol,PERIOD_D1,1)>0 &&
           iHigh(_Symbol,PERIOD_D1,1)>0 &&
           iLow(_Symbol,PERIOD_D1,1)>0);
}
void DrawPDHPDL()
{
   if(!InpShowPDHPDL) return;
   if(!D1HistoryAvailable()) return; // A9
   double pdh=iHigh(_Symbol,PERIOD_D1,1);
   double pdl=iLow(_Symbol,PERIOD_D1,1);
   DrawHLine(PFX+"PDH",pdh,clrKhaki,"PDH",1);
   DrawHLine(PFX+"PDL",pdl,clrKhaki,"PDL",1);
}
void DrawPivotPoints()
{
   if(!InpShowPivots) return;
   if(!D1HistoryAvailable()) return; // A9
   double pdh=iHigh(_Symbol,PERIOD_D1,1);
   double pdl=iLow(_Symbol,PERIOD_D1,1);
   double pdc=iClose(_Symbol,PERIOD_D1,1);
   if(pdh<=0 || pdl<=0 || pdc<=0) return;
   double P=(pdh+pdl+pdc)/3.0;
   double R1=2*P-pdl, S1=2*P-pdh;
   double R2=P+(pdh-pdl), S2=P-(pdh-pdl);
   DrawHLine(PFX+"PIV_P",P,clrWhite,"P",1);
   DrawHLine(PFX+"PIV_R1",R1,clrIndianRed,"R1",1);
   DrawHLine(PFX+"PIV_S1",S1,clrSeaGreen,"S1",1);
   DrawHLine(PFX+"PIV_R2",R2,clrFireBrick,"R2",1);
   DrawHLine(PFX+"PIV_S2",S2,clrDarkGreen,"S2",1);
}
void DrawCamarilla()
{
   if(!InpShowCamarilla) return;
   if(!D1HistoryAvailable()) return; // A9
   double pdh=iHigh(_Symbol,PERIOD_D1,1);
   double pdl=iLow(_Symbol,PERIOD_D1,1);
   double pdc=iClose(_Symbol,PERIOD_D1,1);
   if(pdh<=0 || pdl<=0 || pdc<=0) return;
   double rng=pdh-pdl;
   if(rng<=_Point) return;
   double H4=pdc+rng*1.1/2, H3=pdc+rng*1.1/4;
   double L4=pdc-rng*1.1/2, L3=pdc-rng*1.1/4;
   DrawHLine(PFX+"CAM_H4",H4,clrTomato,"CAM H4",1);
   DrawHLine(PFX+"CAM_H3",H3,clrSalmon,"CAM H3",1);
   DrawHLine(PFX+"CAM_L3",L3,clrLightGreen,"CAM L3",1);
   DrawHLine(PFX+"CAM_L4",L4,clrLimeGreen,"CAM L4",1);
}
void DrawSessionHighLow(const int total,const datetime &t[],const double &h[],const double &l[])
{
   if(!InpShowSessionHL) return;
   int closed=total-2;
   if(closed<10) return;
   ENUM_SESSION_ID sess[2]={SESSION_LONDON,SESSION_NEWYORK};
   for(int s=0;s<2;s++)
   {
      datetime now=t[closed];
      datetime ref=SessionLocalTime(now,sess[s]);
      int key=DateKey(ref);
      double sh=-DBL_MAX,sl=DBL_MAX;
      datetime st=0;
      for(int b=closed;b>=0 && closed-b<600;b--)
      {
         if(DateKey(SessionLocalTime(t[b],sess[s]))!=key) break;
         sh=MathMax(sh,h[b]); sl=MathMin(sl,l[b]);
         if(st==0) st=t[b];
      }
      if(sh<=-DBL_MAX/2) continue;
      string tag=(s==0?"LDN":"NY");
      DrawHLine(PFX+"SESSH_"+tag,sh,(s==0?clrCornflowerBlue:clrLightSalmon),tag+" H",1);
      DrawHLine(PFX+"SESSL_"+tag,sl,(s==0?clrCornflowerBlue:clrLightSalmon),tag+" L",1);
   }
}

//====================================================================
// DRAW: SETUP ZONE / TRADE BOX / TRADE LEVELS
//====================================================================
void DrawSetupZone(const int total,const datetime &t[])
{
   if(!InpUseRetestLifecycle || !g_active_setup.active) return;
   string name=PFX+"SETUPZONE";
   datetime t1=g_active_setup.created_time;
   datetime t2=t[total-1]+(datetime)(PeriodSeconds()*15);
   color col=g_active_setup.is_buy ? clrDodgerBlue : clrTomato;
   string state_tag=g_active_setup.state;
   string label=StringFormat("%s SETUP %s | entry %.2f SL %.2f | %s",
                             g_active_setup.is_buy?"BUY":"SELL",
                             state_tag,g_active_setup.entry,g_active_setup.sl,
                             state_tag=="CONFIRMED"?"MSS CONFIRMED":
                             (state_tag=="RETEST_PREVIEW"?"RETEST (LIVE, DEVELOPING)":
                              state_tag=="RETEST_CONFIRMED"?"RETEST CONFIRMED":"AWAITING RETEST"));
   DrawZoneBox(name,t1,g_active_setup.zone_top,t2,g_active_setup.zone_bottom,col,label,80);
}
void DrawTradeBox()
{
   if(!g_trade_setup.valid) {ObjectDelete(0,PFX+"TRADEBOX"); return;}
   datetime t1=g_trade_setup.created_time;
   datetime t2=t1+(datetime)(PeriodSeconds()*20);
   color col=g_trade_setup.is_buy ? clrDodgerBlue : clrCrimson;
   string label=StringFormat("%s %s | E %.2f SL %.2f TP1 %.2f TP2 %.2f TP3 %.2f | RR %.2f/%.2f/%.2f | grade %s",
                             g_trade_setup.is_buy?"BUY":"SELL","SETUP",
                             g_trade_setup.entry,g_trade_setup.sl,
                             g_trade_setup.tp1,g_trade_setup.tp2,g_trade_setup.tp3,
                             g_trade_setup.rr1,g_trade_setup.rr2,g_trade_setup.rr3,
                             g_trade_setup.quality_grade);
   DrawZoneBox(PFX+"TRADEBOX",t1,g_trade_setup.zone_top,t2,g_trade_setup.zone_bottom,col,label,85);
}
void DrawTradeLevels(const int total,const datetime &t[])
{
   if(!g_trade_setup.valid){ 
      ObjectDelete(0,PFX+"TL_E"); ObjectDelete(0,PFX+"TL_SL");
      ObjectDelete(0,PFX+"TL_TP1"); ObjectDelete(0,PFX+"TL_TP2"); ObjectDelete(0,PFX+"TL_TP3");
      return; }
   datetime t1=g_trade_setup.created_time;
   datetime t2=t[total-1]+(datetime)(PeriodSeconds()*10);
   DrawFibLine(PFX+"TL_E",t1,t2,g_trade_setup.entry,clrAqua,STYLE_SOLID,2);
   DrawFibLine(PFX+"TL_SL",t1,t2,g_trade_setup.sl,clrRed,STYLE_SOLID,2);
   DrawFibLine(PFX+"TL_TP1",t1,t2,g_trade_setup.tp1,clrLimeGreen,STYLE_DASH,1);
   DrawFibLine(PFX+"TL_TP2",t1,t2,g_trade_setup.tp2,clrLimeGreen,STYLE_DASH,1);
   DrawFibLine(PFX+"TL_TP3",t1,t2,g_trade_setup.tp3,clrLimeGreen,STYLE_DASH,1);
}

//====================================================================
// DRAW: AI DASHBOARD v5.7.5 — size modes (MINI/COMPACT/FULL) + color legend.
// confidence/reliability bars, institutional pattern checklist.
// Same call signature as before; nothing else in the file changes.
// v5.7.4 wire-up: BuildConfidenceBar() and
// BuildInstitutionalPatternChecklist() were fully implemented but had
// zero call sites; both are rendered here now.
//====================================================================
color DecisionAccentColor()
{
   if(g_decision_state=="CONFIRMED")
      return (InpUseRetestLifecycle ? (g_active_setup.is_buy?clrLime:clrTomato)
                                     : (g_trade_setup.is_buy?clrLime:clrTomato));
   if(g_decision_state=="BUY_WATCH")  return clrLimeGreen;
   if(g_decision_state=="SELL_WATCH") return clrTomato;
   if(StringFind(g_decision_state,"EARLY")>=0) return clrAqua;
   return clrDimGray; // WAIT
}

// Pushes one text line + color, with an optional section header rendered
// as a thin separator above it. Keeps DrawQuantumDashboard's body readable.
void DashLine(string &L[],color &C[],bool &H[],int &ln,const string text,
             const color col,const bool is_header=false)
{
   if(ln>=64) return;
   L[ln]=text; C[ln]=col; H[ln]=is_header; ln++;
}

void DrawQuantumDashboard(const int total,const double &c[])
{
   if(!InpShowAIDashboard) return;
   int closed=total-2;
   if(closed<1) return;
   bool full=(InpDashMode==DASH_FULL);

   string L[64]; color C[64]; bool H[64];
   int ln=0;
   int panel_font=(InpPanelFontSize>0 ? InpPanelFontSize : 9);
   color accent=DecisionAccentColor();

   // diagnostics refreshed once per draw (same cost as v5.7.4)
   DiagnoseCausalChain(total,g_buf_o,g_buf_h,g_buf_l,c,g_buf_t);
   DiagnoseDirectionalWatch(total,g_buf_o,g_buf_h,g_buf_l,c);

   bool has_candidate=(g_causal_diag.candidate_structure_bar>=0);
   int conf=0,rel=0; string grade="-",igrade="";
   if(InpUseRetestLifecycle && g_active_setup.active)
   {conf=g_active_setup.confidence; rel=g_active_setup.reliability;
    grade=g_active_setup.quality_grade; igrade=g_active_setup.institutional_grade;}
   else if(g_trade_setup.valid || g_trade_setup.confidence>0)
   {conf=g_trade_setup.confidence; rel=g_trade_setup.reliability;
    grade=(g_trade_setup.quality_grade==""?"-":g_trade_setup.quality_grade);
    igrade=g_trade_setup.institutional_grade;}
   bool have_setup=(InpUseRetestLifecycle ? g_active_setup.active : g_trade_setup.valid);

   if(InpDashMode==DASH_MINI)
   {
      //==================================================================
      // MINI (default): ~6 rows, plain words, one color meaning per row
      //==================================================================
      DashLine(L,C,H,ln,"QSMC v5.7.5  "+_Symbol+" "+TFName((ENUM_TIMEFRAMES)_Period),clrWhite,true);

      string status_txt=g_decision_state;
      if(g_decision_state=="CONFIRMED")
         status_txt="CONFIRMED "+((InpUseRetestLifecycle?g_active_setup.is_buy:g_trade_setup.is_buy)?"BUY":"SELL");
      else if(g_decision_state=="WAIT")
         status_txt="WAIT - no valid setup yet";
      DashLine(L,C,H,ln,"STATE: "+status_txt,accent,false);

      string why=""; color why_col=clrSilver;
      if(g_decision_state=="CONFIRMED")
         why="trade confirmed - manage TP1 / TP2 / TP3";
      else if(InpUseRetestLifecycle && g_active_setup.active && g_active_setup.state=="RETEST_PREVIEW")
        {why="price inside zone - waiting for confirm close (NOT confirmed)"; why_col=clrAqua;}
      else if(g_trade_setup.blocker_count>0)
        {why=g_trade_setup.blockers[0]; why_col=clrOrange;}
      else if(g_causal_diag.causal_fail_reason!="")
        {why=g_causal_diag.causal_fail_reason; why_col=clrOrange;}
      else if(g_directional_watch_text!="" && g_directional_watch_text!="DIAGNOSTICS UNAVAILABLE")
        {why="watch: "+g_directional_watch_text; why_col=clrAqua;}
      else
        {why="scanning - no candidate structure yet"; why_col=clrDimGray;}
      if(StringLen(why)>52) why=StringSubstr(why,0,49)+"...";
      DashLine(L,C,H,ln,"WHY: "+why,why_col,false);

      if(has_candidate || conf>0)
         DashLine(L,C,H,ln,StringFormat("SCORE: %s  confidence %s %d%%",
                  grade,BuildConfidenceBar(conf,10),conf),GradeColor(grade),false);

      if(have_setup)
      {
         double e,sl,t1; bool is_buy;
         if(InpUseRetestLifecycle)
           {e=g_active_setup.entry; sl=g_active_setup.sl; t1=g_active_setup.tp1; is_buy=g_active_setup.is_buy;}
         else
           {e=g_trade_setup.entry; sl=g_trade_setup.sl; t1=g_trade_setup.tp1; is_buy=g_trade_setup.is_buy;}
         DashLine(L,C,H,ln,StringFormat("PLAN: %s  entry %s  stop %s  target1 %s",
                  (is_buy?"BUY":"SELL"),DoubleToString(e,_Digits),
                  DoubleToString(sl,_Digits),DoubleToString(t1,_Digits)),
                  (is_buy?clrLime:clrTomato),false);
      }
      else
      {
         int align_pct=MTFAlignmentPercent();
         DashLine(L,C,H,ln,StringFormat("TREND (HTF): %s",
                  (align_pct<0?"n/a":IntegerToString(align_pct)+"% aligned")),
                  PctColor(MathMax(0,align_pct)),false);
      }
   }
   else
   {
      //==================================================================
      // COMPACT / FULL: grouped layout, palette reduced to legend colors
      //==================================================================
      DashLine(L,C,H,ln,"QUANTUM SMC AI PRO v5.7.5",clrWhite,true);
      DashLine(L,C,H,ln,_Symbol+"  "+TFName((ENUM_TIMEFRAMES)_Period)+
               "  |  decisions on CLOSED bars only",clrDarkGray,false);

      // ---- STATUS ----
      string status_txt=g_decision_state;
      if(g_decision_state=="CONFIRMED")
         status_txt="CONFIRMED "+((InpUseRetestLifecycle?g_active_setup.is_buy:g_trade_setup.is_buy)?"BUY":"SELL")+" (structure break confirmed)";
      DashLine(L,C,H,ln,"- STATUS -",clrDarkSlateGray,true);
      DashLine(L,C,H,ln,"  "+status_txt,accent,false);

      if(InpUseRetestLifecycle && g_active_setup.active)
      {
         DashLine(L,C,H,ln,StringFormat("  Lifecycle: %s  |  created %s",
                  g_active_setup.state,
                  TimeToString(g_active_setup.created_time,TIME_DATE|TIME_MINUTES)),
                  (g_active_setup.state=="CONFIRMED"?clrLime:
                   (g_active_setup.state=="RETEST_PREVIEW"?clrAqua:clrOrange)),false);
         DashLine(L,C,H,ln,StringFormat("  TP1 %s   TP2 %s   TP3 %s",
                  g_active_setup.tp_consumed[0]?"HIT":"resting",
                  g_active_setup.tp_consumed[1]?"HIT":"resting",
                  g_active_setup.tp_consumed[2]?"HIT":"resting"),clrSilver,false);
      }

      // ---- CAUSAL CHAIN ----
      DashLine(L,C,H,ln,"- CAUSAL CHAIN -",clrDarkSlateGray,true);
      DashLine(L,C,H,ln,"  "+g_causal_chain_text,g_causal_chain_color,false);
      DashLine(L,C,H,ln,"  "+GateTxt(g_causal_diag.hop_sweep_disp)+"SWEEP->DISP   "+
               GateTxt(g_causal_diag.hop_disp_mss)+"DISP->"+
               (g_causal_diag.candidate_structure_type==""?"STRUCT":g_causal_diag.candidate_structure_type)+"   "+
               GateTxt(g_causal_diag.hop_mss_zone)+"STRUCT->ZONE",
               (g_causal_diag.causal_valid?clrLimeGreen:clrOrange),false);

      string chk[]; int chk_n=0;
      BuildInstitutionalPatternChecklist(chk,chk_n);
      for(int i=0;i<chk_n;i++)
         DashLine(L,C,H,ln,"  "+chk[i],
                  (i==0?clrWhite:(StringFind(chk[i],"[v]")>=0?clrLimeGreen:clrDarkGray)),false);

      if(g_directional_watch_text!="" && g_directional_watch_text!="DIAGNOSTICS UNAVAILABLE")
         DashLine(L,C,H,ln,"  Next watch: "+g_directional_watch_text,g_directional_watch_color,false);

      int align_pct=MTFAlignmentPercent();
      DashLine(L,C,H,ln,StringFormat("  MTF align: %s",align_pct<0?"n/a":IntegerToString(align_pct)+"%"),
               PctColor(MathMax(0,align_pct)),false);

      // ---- SCORE (only when there is something real to score) ----
      if(has_candidate)
      {
         DashLine(L,C,H,ln,"- SCORE -",clrDarkSlateGray,true);
         DashLine(L,C,H,ln,StringFormat("  Grade %s  %s",grade,igrade),GradeColor(grade),false);
         DashLine(L,C,H,ln,StringFormat("  Confidence   %s %3d%%",BuildConfidenceBar(conf,14),conf),
                  PctColor(conf),false);
         DashLine(L,C,H,ln,StringFormat("  Reliability  %s %3d%%",BuildConfidenceBar(rel,14),rel),
                  PctColor(rel),false);
         if(full)
         {
            DashLine(L,C,H,ln,StringFormat("  STR %.0f  LIQ %.0f  ZONE %.0f  SES %.0f  HTF %.0f  ALGO %.0f  CND %.0f",
                     g_score.structure,g_score.liquidity,MathMax(g_score.orderblock,g_score.fvg),
                     g_score.session,g_score.htf,g_score.algo,g_score.candle_context),clrSilver,false);
            DashLine(L,C,H,ln,StringFormat("  Regime %s (x%.2f)   ADX %.0f   MTF conflict: %s",
                     g_trade_setup.market_regime==""?"n/a":g_trade_setup.market_regime,
                     (InpUseRegimeAdaptiveScoring?g_score.regime/100.0:1.0),g_adx,
                     g_trade_setup.mtf_conflict_label==""?"none":g_trade_setup.mtf_conflict_label),
                     clrSilver,false);
         }
      }

      // ---- WHY NOT YET (only when relevant) ----
      if(g_trade_setup.blocker_count>0 || g_causal_diag.causal_fail_reason!="")
      {
         DashLine(L,C,H,ln,"- WHY NOT YET -",clrDarkSlateGray,true);
         if(g_trade_setup.blocker_count>0)
         {
            string bl="";
            for(int i=0;i<g_trade_setup.blocker_count && i<2;i++)
            { if(i>0) bl+="; "; bl+=g_trade_setup.blockers[i]; }
            DashLine(L,C,H,ln,"  "+bl,clrTomato,false);
         }
         else
            DashLine(L,C,H,ln,"  "+g_causal_diag.causal_fail_reason,clrTomato,false);
      }

      // ---- TRADE ----
      if(have_setup)
      {
         double e,sl,t1,t2,t3,rr1,rr2,rr3; bool is_buy; string zone_src,barrier_type,zone_bot_s,zone_top_s;
         double barrier;
         if(InpUseRetestLifecycle)
         {
            e=g_active_setup.entry; sl=g_active_setup.sl;
            t1=g_active_setup.tp1; t2=g_active_setup.tp2; t3=g_active_setup.tp3;
            rr1=g_active_setup.rr1; rr2=g_active_setup.rr2; rr3=g_active_setup.rr3;
            is_buy=g_active_setup.is_buy; zone_src=g_active_setup.zone_source;
            barrier=g_active_setup.immutable_target_barrier; barrier_type=g_active_setup.immutable_target_barrier_type;
            zone_bot_s=DoubleToString(g_active_setup.zone_bottom,_Digits);
            zone_top_s=DoubleToString(g_active_setup.zone_top,_Digits);
         }
         else
         {
            e=g_trade_setup.entry; sl=g_trade_setup.sl;
            t1=g_trade_setup.tp1; t2=g_trade_setup.tp2; t3=g_trade_setup.tp3;
            rr1=g_trade_setup.rr1; rr2=g_trade_setup.rr2; rr3=g_trade_setup.rr3;
            is_buy=g_trade_setup.is_buy; zone_src=g_trade_setup.zone_source;
            barrier=g_trade_setup.immutable_target_barrier; barrier_type=g_trade_setup.immutable_target_barrier_type;
            zone_bot_s=DoubleToString(g_trade_setup.zone_bottom,_Digits);
            zone_top_s=DoubleToString(g_trade_setup.zone_top,_Digits);
         }
         DashLine(L,C,H,ln,"- TRADE -",clrDarkSlateGray,true);
         DashLine(L,C,H,ln,StringFormat("  %s | zone %s-%s [%s]",is_buy?"BUY":"SELL",
                  zone_bot_s,zone_top_s,zone_src),is_buy?clrLime:clrTomato,false);
         DashLine(L,C,H,ln,StringFormat("  Entry %s   SL %s  (%.1f pips, %s)",
                  DoubleToString(e,_Digits),DoubleToString(sl,_Digits),
                  (InpUseRetestLifecycle?g_active_setup.risk_pips:g_trade_setup.risk_pips),
                  (InpUseRetestLifecycle?g_active_setup.risk_level:g_trade_setup.risk_level)),clrWhite,false);
         DashLine(L,C,H,ln,StringFormat("  TP1 %s (RR %.2f) %s",DoubleToString(t1,_Digits),rr1,
                  (InpUseRetestLifecycle&&g_active_setup.tp_consumed[0])?"HIT":"resting"),clrLimeGreen,false);
         DashLine(L,C,H,ln,StringFormat("  TP2 %s (RR %.2f) %s",DoubleToString(t2,_Digits),rr2,
                  (InpUseRetestLifecycle&&g_active_setup.tp_consumed[1])?"HIT":"resting"),clrLimeGreen,false);
         DashLine(L,C,H,ln,StringFormat("  TP3 %s (RR %.2f) %s",DoubleToString(t3,_Digits),rr3,
                  (InpUseRetestLifecycle&&g_active_setup.tp_consumed[2])?"HIT":"resting"),clrLimeGreen,false);
         DashLine(L,C,H,ln,"  Ceiling: "+(barrier>0?DoubleToString(barrier,_Digits)+" ("+barrier_type+")":"none"),
                  clrSilver,false);
         if(InpUseRetestLifecycle && g_active_setup.state=="RETEST_PREVIEW")
            DashLine(L,C,H,ln,"  RETEST IN PROGRESS - DEVELOPING, NOT CONFIRMED",clrAqua,false);
      }
      else if(!has_candidate)
         DashLine(L,C,H,ln,"  No structural anchor yet - fewer, correct signals preferred.",clrDimGray,false);

      // ---- ENGINE (FULL mode only) ----
      if(full)
      {
         DashLine(L,C,H,ln,"- ENGINE -",clrDarkSlateGray,true);
         DashLine(L,C,H,ln,StringFormat("  events %d  invariants %s  replay %s",
                  ArraySize(g_causal_events),g_causal_invariants_ok?"PASS":"FAIL",
                  g_replay_audit_status),clrDarkGray,false);
         DashLine(L,C,H,ln,"  mask "+IntegerToBinary(g_signal_mask),clrDarkGray,false);
      }
   }

   DashLine(L,C,H,ln,(InpDashMode==DASH_MINI?"Educational only - not advice."
                     :"Educational analysis only - not financial advice."),clrGray,false);

   // D4 legend: EVERY color on this dashboard means exactly one of these
   // five buckets (rendered as one multi-colored row below the text rows;
   // suppressed in FULL mode where the grouped headers already explain).
   string leg[5]; color legc[5];
   leg[0]="■ BUY / OK ";       legc[0]=clrLime;
   leg[1]="■ SELL / PROBLEM "; legc[1]=clrTomato;
   leg[2]="■ WATCH ";          legc[2]=clrAqua;
   leg[3]="■ NO SETUP ";       legc[3]=clrDimGray;
   leg[4]="■ BLOCKED";         legc[4]=clrOrange;

   // ---- RENDER ---------------------------------------------------------
   int chart_w=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   if(chart_w<=0) chart_w=800;
   int max_text=0;
   for(int i=0;i<ln;i++) max_text=(int)MathMax(max_text,StringLen(L[i]));
   int legend_rows=(InpDashMode==DASH_FULL ? 0 : 1);
   int legend_w=0;
   if(legend_rows>0)
      for(int k=0;k<5;k++)
         legend_w+=(int)MathCeil(StringLen(leg[k])*panel_font*0.62)+6;
   g_dash_width=MathMin(chart_w-20,(int)MathMax(max_text*7+22,legend_w+22));
   int bg_x=chart_w-InpPanelRightPad-g_dash_width;
   if(bg_x<5) bg_x=5;
   int txt_x=bg_x+10;
   int y=26;
   int line_h=panel_font+7;

   string bg=PFX+"DASH_BG";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,bg_x);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y-8);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,g_dash_width);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,(ln+legend_rows)*line_h+14);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,(color)0x0C0C12);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,accent);           // state-tinted border
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,bg,OBJPROP_ZORDER,0);

   // thin accent strip along the left edge (visual state cue at a glance)
   string strip=PFX+"DASH_STRIP";
   if(ObjectFind(0,strip)<0) ObjectCreate(0,strip,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,strip,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,strip,OBJPROP_XDISTANCE,bg_x);
   ObjectSetInteger(0,strip,OBJPROP_YDISTANCE,y-8);
   ObjectSetInteger(0,strip,OBJPROP_XSIZE,4);
   ObjectSetInteger(0,strip,OBJPROP_YSIZE,(ln+legend_rows)*line_h+14);
   ObjectSetInteger(0,strip,OBJPROP_BGCOLOR,accent);
   ObjectSetInteger(0,strip,OBJPROP_BACK,false);
   ObjectSetInteger(0,strip,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,strip,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,strip,OBJPROP_ZORDER,1);

   for(int i=0;i<ln;i++)
   {
      string name=PFX+"DASH_"+IntegerToString(i);
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,txt_x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+i*line_h);
      ObjectSetString(0,name,OBJPROP_TEXT,L[i]);
      ObjectSetString(0,name,OBJPROP_FONT,H[i]?"Consolas Bold":"Consolas");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,H[i]?panel_font-1:panel_font);
      ObjectSetInteger(0,name,OBJPROP_COLOR,C[i]);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,10);
   }
   // hide any stale labels left over from a longer previous render
   for(int i=ln;i<64;i++)
   {
      string name=PFX+"DASH_"+IntegerToString(i);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   }
   // D4 legend row (deterministic IDs DASH_LEG0..4, cleaned when hidden)
   if(legend_rows>0)
   {
      int lx=txt_x;
      for(int k=0;k<5;k++)
      {
         string lname=PFX+"DASH_LEG"+IntegerToString(k);
         if(ObjectFind(0,lname)<0) ObjectCreate(0,lname,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,lname,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,lname,OBJPROP_XDISTANCE,lx);
         ObjectSetInteger(0,lname,OBJPROP_YDISTANCE,y+ln*line_h);
         ObjectSetString(0,lname,OBJPROP_TEXT,leg[k]);
         ObjectSetString(0,lname,OBJPROP_FONT,"Consolas");
         ObjectSetInteger(0,lname,OBJPROP_FONTSIZE,panel_font);
         ObjectSetInteger(0,lname,OBJPROP_COLOR,legc[k]);
         ObjectSetInteger(0,lname,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,lname,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,lname,OBJPROP_ZORDER,10);
         lx+=(int)MathCeil(StringLen(leg[k])*panel_font*0.62)+6;
      }
   }
   else
   {
      for(int k=0;k<5;k++)
      {
         string lname=PFX+"DASH_LEG"+IntegerToString(k);
         if(ObjectFind(0,lname)>=0) ObjectDelete(0,lname);
      }
   }
   g_dash_lines=ln;
}


//====================================================================
// DRAW: MTF PANEL (MN/W1/D1/H4/H1, closed HTF candles only)
//====================================================================
void DrawMTFPanel()
{
   ENUM_TIMEFRAMES tfs[MTF_TF_COUNT];
   tfs[0]=InpMTF1; tfs[1]=InpMTF2; tfs[2]=InpMTF3; tfs[3]=InpMTF4; tfs[4]=InpMTF5;
   g_mtf_self_index=-1;
   int self=(int)_Period;
   for(int i=0;i<MTF_TF_COUNT;i++)
      if((int)tfs[i]==self) g_mtf_self_index=i;

   int x=8,y=22,line_h=16;
   if(InpPanelFontSize>0) line_h=InpPanelFontSize+8;

   string title=PFX+"MTFP_TITLE";
   if(ObjectFind(0,title)<0) ObjectCreate(0,title,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,title,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,title,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,title,OBJPROP_YDISTANCE,y-line_h);
   ObjectSetString(0,title,OBJPROP_TEXT,"MTF EMA200 ALIGN (closed candles)");
   ObjectSetString(0,title,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,title,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,title,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,title,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,title,OBJPROP_HIDDEN,true);

   g_mtf_panel_tick++;
   bool refresh_data=(g_mtf_panel_tick%10==1); // throttle HTF fetches (perf)
   for(int i=0;i<MTF_TF_COUNT;i++)
   {
      int aligned=0;
      string note="";
      if(refresh_data)
      {
         double ema[2],c_[2];
         if(h_ema_mtf[i]!=INVALID_HANDLE &&
            CopyBuffer(h_ema_mtf[i],0,0,2,ema)==2 &&
            CopyClose(_Symbol,tfs[i],1,1,c_)==1)
         {
            // CopyBuffer fills oldest-first: ema[0]=last CLOSED bar's EMA
            if(ema[0]!=EMPTY_VALUE && ema[0]!=0.0)
            {
               aligned=(c_[0]>ema[0] ? 1 : -1);
               note=(c_[0]>ema[0]?"CLOSE > EMA200":"CLOSE < EMA200");
            }
            else note="EMA warm-up";
         }
         else note="no data";
         g_mtf_aligned[i]=aligned;
         g_mtf_note[i]=note;
      }
      else
      {
         aligned=g_mtf_aligned[i];
         note=g_mtf_note[i];
      }
      string name=PFX+"MTFP_"+IntegerToString(i);
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y+i*line_h);
      string row=StringFormat("%-4s %s  %s",TFName(tfs[i]),
                 aligned>0?"BULL":(aligned<0?"BEAR":"----"),
                 note+(i==g_mtf_self_index?"  <- chart TF":""));
      ObjectSetString(0,name,OBJPROP_TEXT,row);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_COLOR,
                       aligned>0?clrLimeGreen:(aligned<0?clrTomato:clrDarkGray));
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
}

//====================================================================
// v5.6.9 CAUSAL GRAPH PATH OPTIMIZATION
// Diagnostic ranking support for flexible mode. Deterministic;
// reads the causal event store only.
//====================================================================
void ResetCausalPathResult(SCausalPathResult &r)
{
   r.valid=false;
   r.negative_cycle=false;
   r.cost=0.0;
   r.score=0.0;
   r.hops=0;
   r.start_event=-1;
   r.target_event=-1;
   r.algorithm="";
   r.agreement=false;
   for(int i=0;i<16;i++) r.nodes[i]=-1;
}
double CausalEdgeSignedWeight(const int from,const int to)
{
   if(from<0 || to<0 || from>=ArraySize(g_causal_events) ||
      to>=ArraySize(g_causal_events)) return 0.0;
   SCausalEvent a=g_causal_events[from],b=g_causal_events[to];
   if(a.availability_time<=0 || b.availability_time<=0) return 0.0;
   // reward direct causal linkage, penalise temporal distance (ATR units)
   double gap_bars=(double)MathMax(0,b.event_bar-a.event_bar);
   double penalty=InpGraphTemporalPenaltyATR*g_atr*gap_bars/MathMax(1.0,g_atr);
   double reward=(a.type==CE_DISPLACEMENT&&b.type==CE_MSS)?InpGraphCausalReward:0.0;
   double w=b.strength/20.0-penalty+reward;
   if((a.bullish!=b.bullish)) w-=InpGraphConflictPenalty;
   return w;
}
double CausalEdgeCost(const int from,const int to)
{
   // Dijkstra/Bellman-Ford work on non-negative costs.
   double w=CausalEdgeSignedWeight(from,to);
   return MathMax(0.0,-w);
}
bool RunDijkstraCausalPath(const int start_event,const int target_event,SCausalPathResult &out)
{
   ResetCausalPathResult(out);
   int n=ArraySize(g_causal_events);
   if(start_event<0||target_event<0||start_event>=n||target_event>=n) return false;
   out.algorithm="Dijkstra";
   double dist[]; ArrayResize(dist,n);
   int prev[]; ArrayResize(prev,n);
   bool done[]; ArrayResize(done,n);
   for(int i=0;i<n;i++){dist[i]=DBL_MAX; prev[i]=-1; done[i]=false;}
   dist[start_event]=0.0;
   for(int iter=0;iter<n;iter++)
   {
      int u=-1; double best=DBL_MAX;
      for(int i=0;i<n;i++) if(!done[i] && dist[i]<best){best=dist[i]; u=i;}
      if(u<0) break;
      done[u]=true;
      if(u==target_event) break;
      for(int v=0;v<n;v++)
      {
         if(done[v]) continue;
         // edge exists only via explicit parent links (child->parent walk)
         double c=DBL_MAX;
         if(g_causal_events[v].parent_primary==u || g_causal_events[v].parent_secondary==u)
            c=CausalEdgeCost(u,v);
         if(c<DBL_MAX && dist[u]+c<dist[v]){dist[v]=dist[u]+c; prev[v]=u;}
      }
   }
   if(dist[target_event]>=DBL_MAX) return false;
   out.valid=true;
   out.cost=dist[target_event];
   int hop=target_event;
   while(hop>=0 && out.hops<16){out.nodes[out.hops++]=hop; if(hop==start_event) break; hop=prev[hop];}
   // reverse path order
   for(int i=0;i<out.hops/2;i++)
   {
      int tmp=out.nodes[i]; out.nodes[i]=out.nodes[out.hops-1-i]; out.nodes[out.hops-1-i]=tmp;
   }
   out.start_event=start_event; out.target_event=target_event;
   out.score=MathMax(0.0,100.0-out.cost);
   return true;
}
bool RunBellmanFordCausalPath(const int start_event,const int target_event,SCausalPathResult &out)
{
   ResetCausalPathResult(out);
   int n=ArraySize(g_causal_events);
   if(start_event<0||target_event<0||start_event>=n||target_event>=n) return false;
   out.algorithm="BellmanFord";
   double dist[]; ArrayResize(dist,n);
   int prev[]; ArrayResize(prev,n);
   for(int i=0;i<n;i++){dist[i]=DBL_MAX; prev[i]=-1;}
   dist[start_event]=0.0;
   // parent-direction edges with signed weights (can be negative)
   for(int iter=0;iter<n-1;iter++)
   {
      bool changed=false;
      for(int v=0;v<n;v++)
      {
         int ps[2]; ps[0]=g_causal_events[v].parent_primary; ps[1]=g_causal_events[v].parent_secondary;
         for(int pi=0;pi<2;pi++)
         {
            int u=ps[pi];
            if(u<0 || (pi==1 && u==ps[0])) continue;
            if(dist[u]>=DBL_MAX) continue;
            double w=CausalEdgeSignedWeight(u,v);
            double nd=dist[u]-w; // negative weight reduces cost
            if(nd<dist[v]){dist[v]=nd; prev[v]=u; changed=true;}
         }
      }
      if(!changed) break;
   }
   // negative cycle detection
   for(int v=0;v<n;v++)
   {
      int ps[2]; ps[0]=g_causal_events[v].parent_primary; ps[1]=g_causal_events[v].parent_secondary;
      for(int pi=0;pi<2;pi++)
      {
         int u=ps[pi];
         if(u<0 || dist[u]>=DBL_MAX) continue;
         if(dist[u]-CausalEdgeSignedWeight(u,v)<dist[v]-1e-9)
         {
            out.negative_cycle=true;
            if(InpRejectGraphNegativeCycle){out.valid=false; return false;}
         }
      }
   }
   if(dist[target_event]>=DBL_MAX) return false;
   out.valid=true;
   out.cost=dist[target_event];
   int hop=target_event;
   while(hop>=0 && out.hops<16){out.nodes[out.hops++]=hop; if(hop==start_event) break; hop=prev[hop];}
   for(int i=0;i<out.hops/2;i++)
   {
      int tmp=out.nodes[i]; out.nodes[i]=out.nodes[out.hops-1-i]; out.nodes[out.hops-1-i]=tmp;
   }
   out.start_event=start_event; out.target_event=target_event;
   out.score=MathMax(0.0,100.0+out.cost);
   return true;
}
bool RunBeamCausalPath(const int start_event,const int target_event,SCausalPathResult &out)
{
   ResetCausalPathResult(out);
   int n=ArraySize(g_causal_events);
   if(start_event<0||target_event<0||start_event>=n||target_event>=n) return false;
   out.algorithm="Beam";
   // beam over child->parent chains from the target (bounded width)
   int beam[]; ArrayResize(beam,InpBeamWidth*4);
   int beam_score[]; ArrayResize(beam_score,InpBeamWidth*4);
   int cnt=1; beam[0]=target_event; beam_score[0]=0;
   for(int depth=0;depth<InpGraphMaxPathHops;depth++)
   {
      int next[]; ArrayResize(next,InpBeamWidth*16);
      int nscore[]; ArrayResize(nscore,InpBeamWidth*16);
      int ncnt=0;
      for(int b=0;b<cnt;b++)
      {
         int cur=beam[b];
         if(cur==start_event) continue;
         int ps[2]; ps[0]=g_causal_events[cur].parent_primary; ps[1]=g_causal_events[cur].parent_secondary;
         for(int pi=0;pi<2;pi++)
         {
            int p=ps[pi];
            if(p<0 || (pi==1 && p==ps[0])) continue;
            if(ncnt<InpBeamWidth*16)
            {
               next[ncnt]=p;
               nscore[ncnt]=beam_score[b]+(g_causal_events[p].confirmed?1:0);
               ncnt++;
            }
         }
      }
      if(ncnt==0) break;
      // keep best InpBeamWidth by score (deterministic tiebreak: lower index)
      for(int i=1;i<ncnt;i++)
      {
         int k=next[i],ks=nscore[i],j=i-1;
         while(j>=0 && nscore[j]<ks){next[j+1]=next[j]; nscore[j+1]=nscore[j]; j--;}
         next[j+1]=k; nscore[j+1]=ks;
      }
      cnt=MathMin(ncnt,InpBeamWidth);
      for(int i=0;i<cnt;i++){beam[i]=next[i]; beam_score[i]=nscore[i];}
      for(int i=0;i<cnt;i++)
         if(beam[i]==start_event)
         {
            out.valid=true;
            out.cost=MathMax(0.0,(double)-beam_score[i]);
            out.score=(double)beam_score[i]*20.0;
            out.hops=depth+2;
            out.algorithm="Beam";
            out.start_event=start_event; out.target_event=target_event;
            return true;
         }
   }
   return false;
}
bool OptimizeCausalGraphPath(const int start_event,const int target_event,SCausalPathResult &out)
{
   ResetCausalPathResult(out);
   if(!InpUseCausalGraphOptimizer) return false;
   SCausalPathResult best;
   bool have=false;
   if(InpUseDijkstraPathSearch && RunDijkstraCausalPath(start_event,target_event,out))
   {best=out; have=true;}
   SCausalPathResult bf;
   if(InpUseBellmanFordValidation && RunBellmanFordCausalPath(start_event,target_event,bf))
   {
      if(!have || bf.cost<best.cost){best=bf; have=true;}
      if(have) best.agreement=ValidateCausalPathAgreement(out,bf);
   }
   if(!have && InpUseBeamSearch && RunBeamCausalPath(start_event,target_event,out))
   {best=out; have=true;}
   if(!have){ResetCausalPathResult(out); return false;}
   if(InpRequireGraphAgreement && !best.agreement &&
      InpUseBellmanFordValidation && InpUseDijkstraPathSearch)
   {ResetCausalPathResult(out); return false;}
   out=best;
   return true;
}
bool ValidateCausalPathAgreement(const SCausalPathResult &a,const SCausalPathResult &b)
{
   if(!a.valid || !b.valid) return false;
   if(a.start_event!=b.start_event || a.target_event!=b.target_event) return false;
   if(a.negative_cycle!=b.negative_cycle) return false;
   // both algorithms must reach the target; hop counts may differ
   return true;
}
int CausalEvidenceDP(SSignalFactor &factors[],const int max_weight)
{
   if(!InpUseCausalDPOptimizer || max_weight<=0) return 0;
   int n=ArraySize(factors);
   int dp[]; ArrayResize(dp,max_weight+1); ArrayInitialize(dp,0);
   for(int i=0;i<n;i++)
   {
      if(!factors[i].active) continue;
      int w=factors[i].weight;
      if(w<=0 || w>max_weight) continue;
      for(int cap=max_weight;cap>=w;cap--)
         dp[cap]=MathMax(dp[cap],dp[cap-w]+factors[i].value);
   }
   return dp[max_weight];
}
//+------------------------------------------------------------------+
//| END OF FILE                                                      |
//+------------------------------------------------------------------+

//====================================================================
// SMALL CONFIRMED-FRACTAL / OB LOOKUP HELPERS
// (declared API kept total; used by flexible-mode tooling)
//====================================================================
bool IsFractalHigh(const double &h[],const int i,const int n,const int total)
{
   if(i<n || i+n>total-2) return false; // confirmed: fully inside closed bars
   for(int k=i-n;k<=i+n;k++)
   {
      if(k==i || k<0) continue;
      if(k<=i && h[k]>h[i]) return false;
      if(k>i && h[k]>=h[i]) return false;
   }
   return true;
}
bool IsFractalLow(const double &l[],const int i,const int n,const int total)
{
   if(i<n || i+n>total-2) return false;
   for(int k=i-n;k<=i+n;k++)
   {
      if(k==i || k<0) continue;
      if(k<=i && l[k]<l[i]) return false;
      if(k>i && l[k]<=l[i]) return false;
   }
   return true;
}
int FindLastBearishOB(const double &o[],const double &c[],const int from,const int lookback)
{
   for(int i=MathMin(from,ArraySize(g_order_blocks)-1);i>=0 && i>from-lookback;i--)
      if(!g_order_blocks[i].bullish && g_order_blocks[i].state!="MITIGATED")
         return i;
   return -1;
}
int FindLastBullishOB(const double &o[],const double &c[],const int from,const int lookback)
{
   for(int i=MathMin(from,ArraySize(g_order_blocks)-1);i>=0 && i>from-lookback;i--)
      if(g_order_blocks[i].bullish && g_order_blocks[i].state!="MITIGATED")
         return i;
   return -1;
}
string L_Trim(const string s)
{
   int a=0,b=StringLen(s)-1;
   while(a<=b && (StringGetCharacter(s,a)==' '||StringGetCharacter(s,a)==9)) a++;
   while(b>=a && (StringGetCharacter(s,b)==' '||StringGetCharacter(s,b)==9)) b--;
   return StringSubstr(s,a,MathMax(0,b-a+1));
}
