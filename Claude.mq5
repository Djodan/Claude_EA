//+------------------------------------------------------------------+
//|                                                       Claude.mq5 |
//|  Claude XAUUSD portfolio EA                                      |
//|                                                                  |
//|  Inputs -> SEAConfig -> (optional preset) -> strategies          |
//|  Each CStrategy = its own signal modules, timeframe, magic       |
//|  (base + id), trade/risk settings and position management.       |
//|  Guards (news, session, spread, daily limits) are shared.        |
//|                                                                  |
//|    S1 Trend     - DJ Trend flip (Pine port) + filters            |
//|    S2 Breakout  - session range breakout (Asian -> London/NY)    |
//|    S3 Pullback  - EMA trend + RSI dip entries                    |
//|    S4 BreakoutNY - NY opening-range breakout (same module as S2)  |
//|    S5 VWAPTrend  - intraday VWAP trend pullback                  |
//|    S6 PullbackBO - intraday pullback-window breakout              |
//|    S7 MeanRevScalp  - Bollinger/RSI fade to the mean (ranging)    |
//|    S8 MomentumScalp - impulse-candle continuation (trending)      |
//|                                                                  |
//|  Modules live in ./Modules:                                      |
//|    Core/     types, config, presets, new bar, tester reporting   |
//|    Math/     Pine ta.* ports, shared ATR                         |
//|    Signals/  trigger + filter modules and their manager          |
//|    Strategy/ strategy container                                  |
//|    Guards/   pre-trade checks                                    |
//|    Manage/   open-position management                            |
//|    Trade/    execution and position sizing                       |
//|    Notify/   alerts          Visual/ chart objects, dashboard    |
//|  Session times are in reference time (GMT+2/+3, US DST) and are |
//|  converted from the broker's timezone (input), see TimeZone.mqh. |
//|  Research/PROGRESS.md tracks backtest rounds and conclusions.    |
//|  Multi-symbol: "Symbols" input -> one CSymbolEngine per symbol  |
//|  (own guards, strategies, overrides); daily limits are account- |
//|  wide. "Symbol slot" lets the optimiser run the pairs one by one.|
//|  Pairs (v4.52): 5 on/off slots, each a symbol + its own settings |
//|  text, so a whole multi-pair portfolio lives in one .set file.   |
//+------------------------------------------------------------------+
#property copyright "DjoDan Maviaki"
#define EA_VERSION "4.52"
#define EA_BUILD   TimeToString(__DATETIME__, TIME_DATE | TIME_MINUTES)   // compile time, shown in journal/dashboard/results
#property version   EA_VERSION
#property description "XAUUSD scalper (mean reversion + momentum bursts, London/NY sessions) plus Asian-breakout (best_2026 preset), prop-firm guards."

#include "Modules/Core/Defines.mqh"
#include "Modules/Core/TimeZone.mqh"
#include "Modules/Core/Config.mqh"
#include "Modules/Core/Presets.mqh"
#include "Modules/Core/TesterCriterion.mqh"
#include "Modules/Core/TestReporter.mqh"
#include "Modules/Core/CalendarExport.mqh"
#include "Modules/Core/ExcursionTracker.mqh"
#include "Modules/Core/DailyStats.mqh"
#include "Modules/Strategy/Strategy.mqh"
#include "Modules/Strategy/SymbolEngine.mqh"
#include "Modules/Core/SymbolList.mqh"
#include "Modules/Core/Profile.mqh"
#include "Modules/Guards/GuardActivity.mqh"
#include "Modules/Signals/SignalDJTrend.mqh"
#include "Modules/Signals/SignalSessionBreakout.mqh"
#include "Modules/Signals/SignalTrendPullback.mqh"
#include "Modules/Signals/SignalVWAPTrend.mqh"
#include "Modules/Signals/SignalPullbackBO.mqh"
#include "Modules/Signals/SignalMeanRevScalp.mqh"
#include "Modules/Signals/SignalMomentumScalp.mqh"
#include "Modules/Signals/Filters/FilterADX.mqh"
#include "Modules/Signals/Filters/FilterVolatility.mqh"
#include "Modules/Signals/Filters/FilterSlope.mqh"
#include "Modules/Signals/Filters/FilterTrendMA.mqh"
#include "Modules/Signals/Filters/FilterTimeWindow.mqh"
#include "Modules/Guards/GuardManager.mqh"
#include "Modules/Guards/GuardSession.mqh"
#include "Modules/Guards/GuardSpread.mqh"
#include "Modules/Guards/GuardDailyLimits.mqh"
#include "Modules/Guards/GuardNews.mqh"
#include "Modules/Manage/ManageBreakeven.mqh"
#include "Modules/Manage/ManageTrailing.mqh"
#include "Modules/Manage/ManagePartialClose.mqh"
#include "Modules/Manage/ManageTimeExit.mqh"
#include "Modules/Manage/ManageSessionClose.mqh"
#include "Modules/Manage/ManageWeekendClose.mqh"
#include "Modules/Manage/ManageNewsExit.mqh"
#include "Modules/Notify/AlertManager.mqh"
#include "Modules/Visual/ChartDrawer.mqh"
#include "Modules/Visual/Dashboard.mqh"

//--- strategy ids (magic = base magic + id)
#define STRAT_TREND    1
#define STRAT_BREAKOUT 2
#define STRAT_PULLBACK 3
#define STRAT_NY       4
#define STRAT_VWAP     5
#define STRAT_PBO      6
#define STRAT_MR       7
#define STRAT_MO       8

//--- Inputs ---------------------------------------------------------
input group "=== General ==="
input ENUM_SERVER_TZ     InpServerTZ      = TZ_NY_CLOSE;    // Broker SERVER clock (not the company location!) - dashboard verifies it
input ENUM_EA_PRESET     InpPreset        = PRESET_SCALP;   // Preset (0 = use inputs below; 2 = best_2026)
input ulong              InpMagic         = 20260900;       // Base magic (strategies use +1, +2, +3)
input double             InpMaxSlippage   = 0.50;           // Max slippage (price, e.g. 0.50 = $0.50 on gold)
input ENUM_LOT_MODE      InpLotMode       = LOT_RISK_PERCENT; // Lot mode
input double             InpFixedLots     = 0.10;           // Fixed lots
input double             InpRiskPercent   = 0.8;            // Risk % per trade (prop rule: max loss 1%)
input bool               InpAllowHedge    = false;          // Allow opposite positions (prop: no hedging)
input bool               InpWeekendClose  = true;           // Close all positions before the weekend (Monday gaps break the 1% rule)
input int                InpWeekendHour   = 22;             // Friday close hour (ref GMT+2/+3; also 5 min before broker Friday end)
input double             InpAccountSize   = 100000;         // Account size cap for risk (prop size, 0 = off)

input group "=== Symbols (multi-pair) ==="
input string             InpSymbols       = "";             // Symbols, comma-separated ("" = chart symbol). Overrides: EURUSD:spread=0.0002;slip=0.0003;risk=0.5;srisk=0.3
input int                InpSymbolSlot    = 0;              // Trade only the Nth symbol of the list (0 = all) - optimise 1..N to test pairs one by one
input bool               InpUseProfiles   = false;          // Per-pair profiles: Common\Files\ClaudeEA\profiles\<SYMBOL>.set replaces inputs for that pair
input bool               InpUseActivity   = false;          // Trade only in each pair's own active hours (hourly tick-volume profile)
input double             InpActivityMin   = 0.8;            // Active hour = volume >= this x the pair's mean hourly volume
input int                InpActivityDays  = 20;             // Days of H1 history for the volume profile

input group "=== Pairs: up to 5 pairs, each with its own settings, in one set ==="
input bool               InpPair1_On    = false;          // Pair 1: on (any pair on -> the pairs replace "Symbols")
input string             InpPair1       = "";             // Pair 1: symbol, e.g. XAUUSD
input string             InpPair1_S1    = "";             // Pair 1: settings key=value;... (only what differs from the inputs)
input string             InpPair1_S2    = "";             // Pair 1: settings, continued
input string             InpPair1_S3    = "";             // Pair 1: settings, continued
input string             InpPair1_S4    = "";             // Pair 1: settings, continued
input bool               InpPair2_On    = false;          // Pair 2: on
input string             InpPair2       = "";             // Pair 2: symbol, e.g. GBPUSD
input string             InpPair2_S1    = "";             // Pair 2: settings key=value;... (only what differs from the inputs)
input string             InpPair2_S2    = "";             // Pair 2: settings, continued
input string             InpPair2_S3    = "";             // Pair 2: settings, continued
input string             InpPair2_S4    = "";             // Pair 2: settings, continued
input bool               InpPair3_On    = false;          // Pair 3: on
input string             InpPair3       = "";             // Pair 3: symbol, e.g. EURUSD
input string             InpPair3_S1    = "";             // Pair 3: settings key=value;... (only what differs from the inputs)
input string             InpPair3_S2    = "";             // Pair 3: settings, continued
input string             InpPair3_S3    = "";             // Pair 3: settings, continued
input string             InpPair3_S4    = "";             // Pair 3: settings, continued
input bool               InpPair4_On    = false;          // Pair 4: on
input string             InpPair4       = "";             // Pair 4: symbol, e.g. USDJPY
input string             InpPair4_S1    = "";             // Pair 4: settings key=value;... (only what differs from the inputs)
input string             InpPair4_S2    = "";             // Pair 4: settings, continued
input string             InpPair4_S3    = "";             // Pair 4: settings, continued
input string             InpPair4_S4    = "";             // Pair 4: settings, continued
input bool               InpPair5_On    = false;          // Pair 5: on
input string             InpPair5       = "";             // Pair 5: symbol, e.g. XAGUSD
input string             InpPair5_S1    = "";             // Pair 5: settings key=value;... (only what differs from the inputs)
input string             InpPair5_S2    = "";             // Pair 5: settings, continued
input string             InpPair5_S3    = "";             // Pair 5: settings, continued
input string             InpPair5_S4    = "";             // Pair 5: settings, continued

input group "=== S1 Trend: DJ Trend flip ==="
input bool               InpT_Enable      = true;           // Enable
input ENUM_TIMEFRAMES    InpT_TF          = PERIOD_CURRENT; // Timeframe (current = chart)
input ENUM_EA_TRADE_MODE InpT_Mode        = EA_TRADE_BOTH;  // Direction
input ENUM_BASIS_TYPE    InpT_BasisType   = BASIS_EMA;      // Basis type
input int                InpT_BasisLen    = 34;             // Basis length
input int                InpT_AtrLen      = 14;             // ATR length
input double             InpT_SigMult     = 0.5;            // Signal buffer (ATR x)
input double             InpT_AlmaOffset  = 0.85;           // ALMA offset
input double             InpT_AlmaSigma   = 6.0;            // ALMA sigma
input int                InpT_Lookback    = 500;            // Bars recalculated per update
input bool               InpT_CloseOpp    = true;           // Close opposite position on signal
input bool               InpT_ExitOnFlip  = false;          // Filtered flips still close opposite position
input ENUM_SL_MODE       InpT_SLMode      = SL_ATR;         // Stop loss mode
input double             InpT_SLAtr       = 3.0;            // SL ATR multiple
input ENUM_TP_MODE       InpT_TPMode      = TP_NONE;        // Take profit mode
input double             InpT_TPAtr       = 3.0;            // TP ATR multiple
input double             InpT_TPRR        = 2.0;            // TP risk:reward
input bool               InpT_UseHTF      = false;          // Filter: HTF DJ Trend
input ENUM_TIMEFRAMES    InpT_HTF         = PERIOD_CURRENT; // Filter: HTF timeframe (current = auto)
input bool               InpT_UseADX      = false;          // Filter: ADX
input double             InpT_AdxMin      = 20.0;           // Filter: ADX minimum
input bool               InpT_UseVol      = true;           // Filter: volatility regime
input int                InpT_VolAvgLen   = 100;            // Filter: ATR average length
input double             InpT_VolMin      = 0.8;            // Filter: min ATR / avg ATR (0 = off)
input double             InpT_VolMax      = 0.0;            // Filter: max ATR / avg ATR (0 = off)
input bool               InpT_UseSlope    = false;          // Filter: MA slope
input double             InpT_SlopeMin    = 0.15;           // Filter: min slope (ATR units)
input bool               InpT_UseBE       = false;          // Exit: breakeven
input double             InpT_BETrigger   = 1.0;            // Exit: BE trigger (ATR x)
input bool               InpT_UseTrail    = false;          // Exit: ATR trailing stop
input double             InpT_TrailStart  = 3.0;            // Exit: trail start (ATR x)
input double             InpT_TrailDist   = 3.0;            // Exit: trail distance (ATR x)

input group "=== S2 Breakout: session range ==="
input bool               InpB_Enable      = true;           // Enable
input ENUM_TIMEFRAMES    InpB_TF          = PERIOD_CURRENT; // Timeframe (current = chart)
input ENUM_EA_TRADE_MODE InpB_Mode        = EA_TRADE_BOTH;  // Direction
input int                InpB_RangeStartH = 1;              // Range start hour (ref GMT+2/+3)
input int                InpB_RangeStartM = 0;              // Range start minute
input int                InpB_RangeEndH   = 9;              // Range end hour (ref GMT+2/+3)
input int                InpB_RangeEndM   = 0;              // Range end minute
input int                InpB_TradeEndH   = 17;             // Last entry hour (ref GMT+2/+3)
input double             InpB_BufferAtr   = 0.25;           // Breakout buffer (ATR x)
input double             InpB_MinRangeAtr = 0.0;            // Min range width (ATR x, 0 = off)
input double             InpB_MaxRangeAtr = 0.0;            // Max range width (ATR x, 0 = off)
input double             InpB_MinRangeD1  = 0.0;            // Min range width (x daily ATR, 0 = off)
input double             InpB_MaxRangeD1  = 0.0;            // Max range width (x daily ATR, 0 = off)
input int                InpB_AtrLen      = 14;             // ATR length
input ENUM_BRK_STOP      InpB_StopMode    = BRK_STOP_RANGE; // Stop placement
input bool               InpB_OnePerDay   = true;           // One breakout per day
input bool               InpB_BodyRange   = false;          // Range from candle bodies (ignore wick spikes)
input double             InpB_SLAtr       = 3.0;            // Fallback SL (ATR x)
input ENUM_TP_MODE       InpB_TPMode      = TP_RR;          // Take profit mode
input double             InpB_TPRR        = 2.0;            // TP risk:reward
input double             InpB_TPAtr       = 4.0;            // TP ATR multiple
input bool               InpB_EOD         = true;           // Close at session end
input int                InpB_EODHour     = 23;             // Session end hour (ref GMT+2/+3)
input bool               InpB_UseBE       = false;          // Exit: breakeven
input double             InpB_BETrigger   = 1.0;            // Exit: BE trigger (R)
input double             InpB_BELock      = 0.05;           // Exit: BE lock beyond entry (R)
input bool               InpB_UsePartial  = false;          // Exit: partial close
input double             InpB_PartialR    = 1.0;            // Exit: partial at (R)
input double             InpB_PartialPct  = 50.0;           // Exit: partial close %
input int                InpB_TrendLen    = 0;              // Trend filter: MA length (0 = off)
input ENUM_TIMEFRAMES    InpB_TrendTF     = PERIOD_D1;      // Trend filter: timeframe
input ENUM_BASIS_TYPE    InpB_TrendType   = BASIS_EMA;      // Trend filter: MA type
input int                InpB_NewsExit    = 0;              // Exit: close N min before high-impact news (0 = off)
input bool               InpB_RetryBlocked= false;          // Retry a breakout blocked by news/spread once the block ends
input int                InpB_RetryMins   = 240;            // Retry for at most N minutes (and never after last entry hour)

input group "=== S4 NY opening-range breakout ==="
input bool               InpN_Enable      = false;          // Enable (R8/R9: no edge)
input ENUM_EA_TRADE_MODE InpN_Mode        = EA_TRADE_BOTH;  // Direction
input int                InpN_StartH      = 16;             // Range start hour (ref GMT+2/+3; NY open = 16:30)
input int                InpN_StartM      = 30;             // Range start minute
input int                InpN_RangeMins   = 30;             // Range length (minutes)
input int                InpN_TradeEndH   = 20;             // Last entry hour (ref GMT+2/+3)
input double             InpN_BufferAtr   = 0.25;           // Breakout buffer (ATR x)
input double             InpN_MaxRangeD1  = 0.0;            // Max range width (x daily ATR, 0 = off)
input ENUM_BRK_STOP      InpN_StopMode    = BRK_STOP_RANGE; // Stop placement
input double             InpN_TPRR        = 2.0;            // TP risk:reward
input int                InpN_EODHour     = 23;             // Close at (server hour)
input bool               InpN_AlignAsian  = true;           // Only trade in the direction of the Asian-range break

input group "=== S3 Pullback: EMA trend + RSI dip ==="
input bool               InpP_Enable      = true;           // Enable
input ENUM_TIMEFRAMES    InpP_TF          = PERIOD_CURRENT; // Timeframe (current = chart)
input ENUM_EA_TRADE_MODE InpP_Mode        = EA_TRADE_BOTH;  // Direction
input int                InpP_FastLen     = 50;             // Fast EMA
input int                InpP_SlowLen     = 200;            // Slow EMA
input int                InpP_RsiLen      = 14;             // RSI length
input double             InpP_RsiLow      = 40.0;           // Long: RSI crosses up through
input double             InpP_RsiHigh     = 60.0;           // Short: RSI crosses down through
input int                InpP_AtrLen      = 14;             // ATR length
input double             InpP_SLAtr       = 3.0;            // SL ATR multiple
input ENUM_TP_MODE       InpP_TPMode      = TP_ATR;         // Take profit mode
input double             InpP_TPAtr       = 4.5;            // TP ATR multiple
input double             InpP_TPRR        = 1.5;            // TP risk:reward
input bool               InpP_UseTrail    = false;          // Exit: ATR trailing stop
input double             InpP_TrailStart  = 2.0;            // Exit: trail start (ATR x)
input double             InpP_TrailDist   = 2.0;            // Exit: trail distance (ATR x)
input int                InpP_MaxBars     = 0;              // Exit: close after N bars (0 = off)

input group "=== Scalper (S7 mean reversion, S8 momentum burst) ==="
input ENUM_TIMEFRAMES    InpS_TF          = PERIOD_M1;      // Scalper signal timeframe
input int                InpS_W1StartH    = 0;             // Session 1 start hour (ref GMT+2/+3) - default all day
input int                InpS_W1StartM    = 0;              // Session 1 start minute
input int                InpS_W1EndH      = 23;             // Session 1 end hour (entries stop; EOD close separate)
input int                InpS_W1EndM      = 0;              // Session 1 end minute
input int                InpS_W2StartH    = 0;             // Session 2 start hour (equal start/end = off)
input int                InpS_W2StartM    = 0;             // Session 2 start minute
input int                InpS_W2EndH      = 0;             // Session 2 end hour (equal start/end = off)
input int                InpS_W2EndM      = 0;              // Session 2 end minute
input double             InpS_RiskPct     = 0.25;           // Risk % per scalp
input int                InpS_MaxPerDay   = 0;             // Max scalps per day per engine (0 = no limit)
input int                InpS_CooldownBars= 0;              // Bars to wait after an exit (0 = none)
input int                InpS_MaxBars     = 30;             // Time exit: close after N bars (0 = off)
input bool               InpS_UseBE       = false;          // Breakeven (R17: scratched winners)
input double             InpS_BETrigger   = 0.6;            // Breakeven trigger (R)
input int                InpS_EODHour     = 23;             // Close all scalps at (ref hour)
input int                InpS_NewsExit    = 5;              // Close N min before high-impact news (0 = off)
input int                InpS_AtrLen      = 14;             // ATR length
input bool               InpS_AlignAsian  = true;           // Only scalp in the direction price broke the Asian range
input bool               InpM_Enable      = false;          // S7 mean reversion: enable (presets 12/14/15)
input int                InpM_BBLen       = 20;             // S7 Bollinger length
input double             InpM_BBDev       = 2.0;            // S7 Bollinger deviation
input int                InpM_RSILen      = 7;              // S7 RSI length
input double             InpM_RSILow      = 25;             // S7 RSI oversold
input double             InpM_RSIHigh     = 75;             // S7 RSI overbought
input double             InpM_SLBufAtr    = 0.5;            // S7 stop buffer beyond extreme (ATR x)
input double             InpM_MaxSlAtr    = 2.5;            // S7 max stop (ATR x)
input double             InpM_MinTpAtr    = 0.3;            // S7 min distance to target (ATR x)
input ENUM_TIMEFRAMES    InpM_RegimeTF    = PERIOD_M5;      // S7 regime (ADX) timeframe
input double             InpM_MaxAdx      = 25;             // S7 only trade when ADX <= this (0 = off)
input bool               InpK_Enable      = false;          // S8 momentum burst: enable (presets 13/14/15)
input double             InpK_BodyAtr     = 1.2;            // S8 impulse body >= (ATR x)
input double             InpK_ClosePct    = 0.75;           // S8 close in outer part of candle (0.75 = top 25%)
input ENUM_IMPULSE_STOP  InpK_StopMode    = IMPULSE_STOP_MID; // S8 stop placement
input double             InpK_TPRR        = 1.0;            // S8 take profit (R)
input ENUM_TIMEFRAMES    InpK_TrendTF     = PERIOD_M15;     // S8 trend filter timeframe
input int                InpK_TrendLen    = 50;             // S8 trend EMA length (0 = off)

input group "=== Intraday (S5 VWAP trend, S6 pullback breakout) ==="
input ENUM_TIMEFRAMES    InpI_TF          = PERIOD_M5;      // Intraday signal timeframe
input int                InpI_StartH      = 9;              // Trading window start hour (ref GMT+2/+3)
input int                InpI_StartM      = 0;              // Trading window start minute
input int                InpI_EndH        = 20;             // Trading window end hour (ref)
input int                InpI_EndM        = 0;              // Trading window end minute
input ENUM_TIMEFRAMES    InpI_TrendTF     = PERIOD_H1;      // Trend filter timeframe
input int                InpI_TrendLen    = 50;             // Trend filter EMA length (0 = off)
input double             InpI_RiskPct     = 0.30;           // Risk % per intraday trade
input int                InpI_MaxPerDay   = 6;              // Max trades per day per strategy (0 = no limit)
input int                InpI_CooldownBars= 3;              // Bars to wait after an exit
input double             InpI_TPRR        = 1.5;            // Take profit (R)
input bool               InpI_UseBE       = false;          // Breakeven
input double             InpI_BETrigger   = 1.0;            // Breakeven trigger (R)
input int                InpI_EODHour     = 22;             // Close all intraday positions at (ref hour)
input int                InpI_NewsExit    = 5;              // Close N min before high-impact news (0 = off)
input int                InpI_AtrLen      = 14;             // ATR length
input double             InpI_MinSlAtr    = 0.8;            // Min stop (ATR x)
input double             InpI_MaxSlAtr    = 3.0;            // Max stop (ATR x) - wider setups skipped
input bool               InpV_Enable      = false;          // S5 VWAP trend: enable (presets 8/10/11 switch it on)
input int                InpV_AnchorH     = 1;              // S5 VWAP reset hour (ref)
input double             InpV_TouchAtr    = 0.2;            // S5 pullback must reach VWAP +/- (ATR x)
input double             InpV_SLBufAtr    = 0.3;            // S5 stop buffer beyond pullback bar (ATR x)
input bool               InpX_Enable      = false;          // S6 pullback breakout: enable (presets 9/10/11)
input int                InpX_Fast        = 9;              // S6 fast EMA
input int                InpX_Slow        = 21;             // S6 slow EMA
input int                InpX_MaxPull     = 3;              // S6 max pullback candles
input double             InpX_DepthAtr    = 0.5;            // S6 pullback may pierce slow EMA by (ATR x)
input double             InpX_SLBufAtr    = 0.1;            // S6 stop buffer (ATR x)

input group "=== Guard: News ==="
input bool               InpUseNews       = true;           // Block entries around news
input string             InpNewsCurrencies= "AUTO";          // Currencies ("AUTO" = each symbol\'s own, e.g. EURUSD -> EUR,USD)
input int                InpNewsImportance= 3;              // Min importance (1 low - 3 high)
input int                InpNewsBefore    = 30;             // Minutes before event
input int                InpNewsAfter     = 30;             // Minutes after event
input string             InpNewsExclude   = "Crude Oil";    // Ignore events containing (comma-separated)
input bool               InpNewsExport    = true;           // Export calendar on a live chart (refreshed every 6 h)
input datetime           InpNewsFrom      = D'2024.12.01';  // Export from

input group "=== Guard: Session / Spread / Daily ==="
input bool               InpUseSession    = false;          // Session filter (ref time GMT+2/+3)
input int                InpSessStartH    = 9;              // Start hour
input int                InpSessEndH      = 22;             // End hour
input bool               InpTradeFri      = true;           // Trade Fridays
input double             InpMaxSpread     = 0.60;           // Max spread (price, e.g. 0.60 = $0.60 on gold; 0 = off)
input double             InpSpreadAtrPct  = 0;              // Max spread as % of the pair's daily ATR (0 = use the price limit) - adapts to every pair
input bool               InpUseDaily      = false;          // Daily limits
input double             InpDailyMaxLoss  = 3.0;            // Max daily loss %
input int                InpDailyMaxTrades= 0;              // Max trades per day (0 = off)
input double             InpDailyTargetUSD= 0;              // Daily profit goal in money - stop for the day (0 = off)
input double             InpDailyTargetPct= 0;              // Daily profit goal in % of day-start balance - scales as the account grows (0 = off)
input double             InpDailyMaxLossUSD= 0;             // Daily loss limit in money - stop for the day (0 = off)

input group "=== Alerts ==="
input bool               InpAlertPopup    = false;          // Popup alert
input bool               InpAlertPush     = false;          // Push notification

input group "=== Chart ==="
input bool               InpDrawSignals   = true;           // Draw signals
input bool               InpDrawHistory   = true;           // Draw historic signals on attach
input bool               InpDrawBasis     = true;           // Draw DJ Trend basis line
input color              InpBuyColor      = C'30,158,74';   // Buy colour
input color              InpSellColor     = C'224,21,27';   // Sell colour
input int                InpFontSize      = 8;              // Label font size
input bool               InpShowDashboard = true;           // Show dashboard

input group "=== Strategy Tester ==="
input ENUM_TESTER_CRITERION InpCriterion  = TC_PROFIT_DD_PCT; // Custom optimisation criterion
input int                InpMinTrades     = 30;             // Min trades for a valid pass
input bool               InpReportResults = true;           // Write results CSVs (Common\Files\ClaudeEA)
input bool               InpExportTrades  = true;           // Export trade list (single runs)

//--- Globals --------------------------------------------------------
SEAConfig        g_cfg;                 // inputs + preset; each engine holds a copy with its symbol overrides
CSymbolEngine   *g_engines[];           // one engine per traded symbol
CSymbolEngine   *g_eng = NULL;          // engine being built (used by the Build* functions)
CProfile        *g_prof = NULL;         // profile of the symbol being configured (NULL = inputs only)
string           g_symbolIssue = "";    // problems in the Symbols input (dashboard)
CChartDrawer     g_drawer;
CDashboard       g_dashboard;
datetime         g_lastExport = 0;
string           g_healthPrinted = "";  // last health report written to the journal
string           g_symbol;
datetime         g_testStart;
string           g_stratNames[] = {"Trend", "Breakout", "Pullback", "BreakoutNY", "VWAPTrend", "PullbackBO", "MeanRevScalp", "MomentumScalp"};   // index = id - 1

//--- input value, or the per-pair profile's value when one is being applied
double PD(const string k, const double v) { return g_prof == NULL ? v : g_prof.D(k, v); }
long   PL(const string k, const long v)   { return g_prof == NULL ? v : g_prof.L(k, v); }
bool   PB(const string k, const bool v)   { return g_prof == NULL ? v : g_prof.B(k, v); }
string PS(const string k, const string v) { return g_prof == NULL ? v : g_prof.S(k, v); }

string SymbolsLabel(const string sep)
  {
   string r = "";
   for(int e = 0; e < ArraySize(g_engines); e++)
      r += (e > 0 ? sep : "") + g_engines[e].symbol;
   return r == "" ? _Symbol : r;
  }

//--- the news guard of the first engine (all read the same calendar file)
CGuardNews *NewsGuard(void)
  {
   for(int e = 0; e < ArraySize(g_engines); e++)
      if(CheckPointer(g_engines[e].news) != POINTER_INVALID)
         return g_engines[e].news;
   return NULL;
  }

//+------------------------------------------------------------------+
//| Inputs -> config                                                 |
//+------------------------------------------------------------------+
void DefaultExits(SExitSettings &e)
  {
   e.usePartial      = false;
   e.partialAtr      = 1.5;
   e.partialPct      = 50.0;
   e.partialBE       = true;
   e.useBE           = false;
   e.beTriggerAtr    = 1.0;
   e.beLockAtr       = 0.1;
   e.useTrail        = false;
   e.trailStartAtr   = 2.0;
   e.trailDistAtr    = 2.0;
   e.trailStepAtr    = 0.1;
   e.useTimeExit     = false;
   e.timeExitBars    = 0;
   e.timeExitLosing  = false;
   e.useSessionClose = false;
   e.closeHour       = 23;
   e.closeMinute     = 0;
   e.unitR           = false;
   e.newsExitMins    = 0;
  }

void DefaultTrade(STradeSettings &t, const ENUM_EA_TRADE_MODE mode)
  {
   t.mode            = mode;
   t.closeOnOpposite = true;
   t.maxPositions    = 1;
   t.slMode          = SL_ATR;
   t.slAtrMult       = 2.0;
   t.slPoints        = 0;
   t.tpMode          = TP_NONE;
   t.tpAtrMult       = 3.0;
   t.tpPoints        = 0;
   t.tpRR            = 2.0;
   t.magic           = (ulong)PL("InpMagic", (long)InpMagic);
   t.deviation       = (int)MathRound(PD("InpMaxSlippage", InpMaxSlippage) / _Point);   // price -> broker points
   t.comment         = "";
   t.allowHedge      = PB("InpAllowHedge", InpAllowHedge);
   t.maxPerDay       = 0;
   t.cooldownSec     = 0;
  }

void BuildConfig(SEAConfig &c)
  {
   //--- S1 Trend
   c.trend.s.enabled            = PB("InpT_Enable", InpT_Enable);
   c.trend.s.tf                 = (ENUM_TIMEFRAMES)PL("InpT_TF", (long)InpT_TF);
   c.trend.s.atrLen             = (int)PL("InpT_AtrLen", InpT_AtrLen);
   c.trend.s.riskPct = 0.0;
   c.trend.s.exitOnFilteredFlip = PB("InpT_ExitOnFlip", InpT_ExitOnFlip);
   c.trend.s.retryBlocked = false;
   c.trend.s.retryMins = 0;
   DefaultTrade(c.trend.s.trade, (ENUM_EA_TRADE_MODE)PL("InpT_Mode", (long)InpT_Mode));
   c.trend.s.trade.closeOnOpposite = PB("InpT_CloseOpp", InpT_CloseOpp);
   c.trend.s.trade.slMode       = (ENUM_SL_MODE)PL("InpT_SLMode", (long)InpT_SLMode);
   c.trend.s.trade.slAtrMult    = PD("InpT_SLAtr", InpT_SLAtr);
   c.trend.s.trade.tpMode       = (ENUM_TP_MODE)PL("InpT_TPMode", (long)InpT_TPMode);
   c.trend.s.trade.tpAtrMult    = PD("InpT_TPAtr", InpT_TPAtr);
   c.trend.s.trade.tpRR         = PD("InpT_TPRR", InpT_TPRR);
   DefaultExits(c.trend.s.exits);
   c.trend.s.exits.useBE         = PB("InpT_UseBE", InpT_UseBE);
   c.trend.s.exits.beTriggerAtr  = PD("InpT_BETrigger", InpT_BETrigger);
   c.trend.s.exits.useTrail      = PB("InpT_UseTrail", InpT_UseTrail);
   c.trend.s.exits.trailStartAtr = PD("InpT_TrailStart", InpT_TrailStart);
   c.trend.s.exits.trailDistAtr  = PD("InpT_TrailDist", InpT_TrailDist);

   c.trend.dj.basisType  = (ENUM_BASIS_TYPE)PL("InpT_BasisType", (long)InpT_BasisType);
   c.trend.dj.basisLen   = (int)PL("InpT_BasisLen", InpT_BasisLen);
   c.trend.dj.atrLen     = (int)PL("InpT_AtrLen", InpT_AtrLen);
   c.trend.dj.sigMult    = PD("InpT_SigMult", InpT_SigMult);
   c.trend.dj.almaOffset = PD("InpT_AlmaOffset", InpT_AlmaOffset);
   c.trend.dj.almaSigma  = PD("InpT_AlmaSigma", InpT_AlmaSigma);
   c.trend.dj.lookback   = (int)PL("InpT_Lookback", InpT_Lookback);
   c.trend.dj.drawBasis  = PB("InpDrawBasis", InpDrawBasis);
   c.trend.dj.basisBars  = 300;
   c.trend.dj.upColor    = (color)PL("InpBuyColor", (long)InpBuyColor);
   c.trend.dj.downColor  = (color)PL("InpSellColor", (long)InpSellColor);
   c.trend.dj.flatColor  = clrGray;

   c.trend.useHTF = PB("InpT_UseHTF", InpT_UseHTF);
   c.trend.htf    = (ENUM_TIMEFRAMES)PL("InpT_HTF", (long)InpT_HTF);
   c.trend.useADX            = PB("InpT_UseADX", InpT_UseADX);
   c.trend.adx.diLen         = 14;
   c.trend.adx.adxLen        = 14;
   c.trend.adx.minAdx        = PD("InpT_AdxMin", InpT_AdxMin);
   c.trend.adx.requireDI     = false;
   c.trend.adx.requireRising = false;
   c.trend.adx.lookback      = (int)PL("InpT_Lookback", InpT_Lookback);
   c.trend.useVol       = PB("InpT_UseVol", InpT_UseVol);
   c.trend.vol.atrLen   = (int)PL("InpT_AtrLen", InpT_AtrLen);
   c.trend.vol.avgLen   = (int)PL("InpT_VolAvgLen", InpT_VolAvgLen);
   c.trend.vol.minRatio = PD("InpT_VolMin", InpT_VolMin);
   c.trend.vol.maxRatio = PD("InpT_VolMax", InpT_VolMax);
   c.trend.vol.lookback = (int)PL("InpT_Lookback", InpT_Lookback);
   c.trend.useSlope          = PB("InpT_UseSlope", InpT_UseSlope);
   c.trend.slope.maType      = (ENUM_BASIS_TYPE)PL("InpT_BasisType", (long)InpT_BasisType);
   c.trend.slope.maLen       = (int)PL("InpT_BasisLen", InpT_BasisLen);
   c.trend.slope.slopeBars   = 3;
   c.trend.slope.minSlopeAtr = PD("InpT_SlopeMin", InpT_SlopeMin);
   c.trend.slope.atrLen      = (int)PL("InpT_AtrLen", InpT_AtrLen);
   c.trend.slope.almaOffset  = PD("InpT_AlmaOffset", InpT_AlmaOffset);
   c.trend.slope.almaSigma   = PD("InpT_AlmaSigma", InpT_AlmaSigma);
   c.trend.slope.lookback    = (int)PL("InpT_Lookback", InpT_Lookback);

   //--- S2 Breakout
   c.brk.s.enabled            = PB("InpB_Enable", InpB_Enable);
   c.brk.s.tf                 = (ENUM_TIMEFRAMES)PL("InpB_TF", (long)InpB_TF);
   c.brk.s.atrLen             = (int)PL("InpB_AtrLen", InpB_AtrLen);
   c.brk.s.riskPct = 0.0;
   c.brk.s.exitOnFilteredFlip = false;
   DefaultTrade(c.brk.s.trade, (ENUM_EA_TRADE_MODE)PL("InpB_Mode", (long)InpB_Mode));
   c.brk.s.trade.closeOnOpposite = true;
   c.brk.s.trade.slMode       = SL_SIGNAL;
   c.brk.s.trade.slAtrMult    = PD("InpB_SLAtr", InpB_SLAtr);
   c.brk.s.trade.tpMode       = (ENUM_TP_MODE)PL("InpB_TPMode", (long)InpB_TPMode);
   c.brk.s.trade.tpRR         = PD("InpB_TPRR", InpB_TPRR);
   c.brk.s.trade.tpAtrMult    = PD("InpB_TPAtr", InpB_TPAtr);
   DefaultExits(c.brk.s.exits);
   c.brk.s.exits.useSessionClose = PB("InpB_EOD", InpB_EOD);
   c.brk.s.exits.closeHour       = (int)PL("InpB_EODHour", InpB_EODHour);
   c.brk.s.exits.unitR           = true;
   c.brk.s.exits.useBE           = PB("InpB_UseBE", InpB_UseBE);
   c.brk.s.exits.beTriggerAtr    = PD("InpB_BETrigger", InpB_BETrigger);
   c.brk.s.exits.beLockAtr       = PD("InpB_BELock", InpB_BELock);
   c.brk.s.exits.usePartial      = PB("InpB_UsePartial", InpB_UsePartial);
   c.brk.s.exits.partialAtr      = PD("InpB_PartialR", InpB_PartialR);
   c.brk.s.exits.partialPct      = PD("InpB_PartialPct", InpB_PartialPct);
   c.brk.s.exits.partialBE       = false;

   c.brk.brk.rangeStartHour = (int)PL("InpB_RangeStartH", InpB_RangeStartH);
   c.brk.brk.rangeStartMin  = (int)PL("InpB_RangeStartM", InpB_RangeStartM);
   c.brk.brk.rangeEndHour   = (int)PL("InpB_RangeEndH", InpB_RangeEndH);
   c.brk.brk.rangeEndMin    = (int)PL("InpB_RangeEndM", InpB_RangeEndM);
   c.brk.brk.tradeEndHour   = (int)PL("InpB_TradeEndH", InpB_TradeEndH);
   c.brk.brk.tradeEndMin    = 0;
   c.brk.brk.bufferAtr      = PD("InpB_BufferAtr", InpB_BufferAtr);
   c.brk.brk.minRangeAtr    = PD("InpB_MinRangeAtr", InpB_MinRangeAtr);
   c.brk.brk.maxRangeAtr    = PD("InpB_MaxRangeAtr", InpB_MaxRangeAtr);
   c.brk.brk.atrLen         = (int)PL("InpB_AtrLen", InpB_AtrLen);
   c.brk.brk.stopMode       = (ENUM_BRK_STOP)PL("InpB_StopMode", (long)InpB_StopMode);
   c.brk.brk.oneTradePerDay = PB("InpB_OnePerDay", InpB_OnePerDay);
   c.brk.brk.bodyRange      = PB("InpB_BodyRange", InpB_BodyRange);
   c.brk.brk.lookback       = 400;
   c.brk.alignAsian         = false;
   c.brk.trendLen           = (int)PL("InpB_TrendLen", InpB_TrendLen);
   c.brk.trendTF            = (ENUM_TIMEFRAMES)PL("InpB_TrendTF", (long)InpB_TrendTF);
   c.brk.trendType          = (ENUM_BASIS_TYPE)PL("InpB_TrendType", (long)InpB_TrendType);
   c.brk.s.exits.newsExitMins = (int)PL("InpB_NewsExit", InpB_NewsExit);
   c.brk.s.retryBlocked       = PB("InpB_RetryBlocked", InpB_RetryBlocked);
   c.brk.s.retryMins          = (int)PL("InpB_RetryMins", InpB_RetryMins);
   c.brk.brk.minRangeD1     = PD("InpB_MinRangeD1", InpB_MinRangeD1);
   c.brk.brk.maxRangeD1     = PD("InpB_MaxRangeD1", InpB_MaxRangeD1);

   //--- S4 NY opening-range breakout (same module, own window)
   c.ny = c.brk;
   c.ny.s.enabled          = PB("InpN_Enable", InpN_Enable);
   c.ny.s.trade.mode       = (ENUM_EA_TRADE_MODE)PL("InpN_Mode", (long)InpN_Mode);
   c.ny.s.trade.tpRR       = PD("InpN_TPRR", InpN_TPRR);
   c.ny.s.exits.closeHour  = (int)PL("InpN_EODHour", InpN_EODHour);
   c.ny.s.exits.useBE      = false;
   c.ny.s.exits.usePartial = false;
   int nyEnd = (int)PL("InpN_StartH", InpN_StartH) * 60 + (int)PL("InpN_StartM", InpN_StartM) + (int)PL("InpN_RangeMins", InpN_RangeMins);
   c.ny.brk.rangeStartHour = (int)PL("InpN_StartH", InpN_StartH);
   c.ny.brk.rangeStartMin  = (int)PL("InpN_StartM", InpN_StartM);
   c.ny.brk.rangeEndHour   = nyEnd / 60;
   c.ny.brk.rangeEndMin    = nyEnd % 60;
   c.ny.brk.tradeEndHour   = (int)PL("InpN_TradeEndH", InpN_TradeEndH);
   c.ny.brk.tradeEndMin    = 0;
   c.ny.brk.bufferAtr      = PD("InpN_BufferAtr", InpN_BufferAtr);
   c.ny.brk.minRangeAtr    = 0.0;
   c.ny.brk.maxRangeAtr    = 0.0;
   c.ny.brk.minRangeD1     = 0.0;
   c.ny.brk.maxRangeD1     = PD("InpN_MaxRangeD1", InpN_MaxRangeD1);
   c.ny.brk.stopMode       = (ENUM_BRK_STOP)PL("InpN_StopMode", (long)InpN_StopMode);
   c.ny.brk.oneTradePerDay = true;
   c.ny.alignAsian         = PB("InpN_AlignAsian", InpN_AlignAsian);
   c.ny.s.retryBlocked     = false;
   c.ny.trendLen           = 0;

   //--- S3 Pullback
   c.pb.s.enabled            = PB("InpP_Enable", InpP_Enable);
   c.pb.s.tf                 = (ENUM_TIMEFRAMES)PL("InpP_TF", (long)InpP_TF);
   c.pb.s.atrLen             = (int)PL("InpP_AtrLen", InpP_AtrLen);
   c.pb.s.riskPct = 0.0;
   c.pb.s.exitOnFilteredFlip = false;
   c.pb.s.retryBlocked = false;
   c.pb.s.retryMins = 0;
   DefaultTrade(c.pb.s.trade, (ENUM_EA_TRADE_MODE)PL("InpP_Mode", (long)InpP_Mode));
   c.pb.s.trade.closeOnOpposite = true;
   c.pb.s.trade.slMode       = SL_ATR;
   c.pb.s.trade.slAtrMult    = PD("InpP_SLAtr", InpP_SLAtr);
   c.pb.s.trade.tpMode       = (ENUM_TP_MODE)PL("InpP_TPMode", (long)InpP_TPMode);
   c.pb.s.trade.tpAtrMult    = PD("InpP_TPAtr", InpP_TPAtr);
   c.pb.s.trade.tpRR         = PD("InpP_TPRR", InpP_TPRR);
   DefaultExits(c.pb.s.exits);
   c.pb.s.exits.useTrail      = PB("InpP_UseTrail", InpP_UseTrail);
   c.pb.s.exits.trailStartAtr = PD("InpP_TrailStart", InpP_TrailStart);
   c.pb.s.exits.trailDistAtr  = PD("InpP_TrailDist", InpP_TrailDist);
   c.pb.s.exits.useTimeExit   = (int)PL("InpP_MaxBars", InpP_MaxBars) > 0;
   c.pb.s.exits.timeExitBars  = (int)PL("InpP_MaxBars", InpP_MaxBars);

   c.pb.pb.fastLen  = (int)PL("InpP_FastLen", InpP_FastLen);
   c.pb.pb.slowLen  = (int)PL("InpP_SlowLen", InpP_SlowLen);
   c.pb.pb.rsiLen   = (int)PL("InpP_RsiLen", InpP_RsiLen);
   c.pb.pb.rsiLow   = PD("InpP_RsiLow", InpP_RsiLow);
   c.pb.pb.rsiHigh  = PD("InpP_RsiHigh", InpP_RsiHigh);
   c.pb.pb.atrLen   = (int)PL("InpP_AtrLen", InpP_AtrLen);
   c.pb.pb.lookback = 800;

   //--- S5 / S6 intraday strategies (shared intraday settings)
   c.intra.startHour = (int)PL("InpI_StartH", InpI_StartH);
   c.intra.startMin  = (int)PL("InpI_StartM", InpI_StartM);
   c.intra.endHour   = (int)PL("InpI_EndH", InpI_EndH);
   c.intra.endMin    = (int)PL("InpI_EndM", InpI_EndM);
   c.intra.trendTF   = (ENUM_TIMEFRAMES)PL("InpI_TrendTF", (long)InpI_TrendTF);
   c.intra.trendLen  = (int)PL("InpI_TrendLen", InpI_TrendLen);

   SStrategyCommon ic;
   ic.enabled            = false;
   ic.tf                 = (ENUM_TIMEFRAMES)PL("InpI_TF", (long)InpI_TF);
   ic.atrLen             = (int)PL("InpI_AtrLen", InpI_AtrLen);
   ic.exitOnFilteredFlip = false;
   ic.retryBlocked       = false;
   ic.retryMins          = 0;
   ic.riskPct            = PD("InpI_RiskPct", InpI_RiskPct);
   DefaultTrade(ic.trade, EA_TRADE_BOTH);
   ic.trade.closeOnOpposite = false;
   ic.trade.slMode       = SL_SIGNAL;
   ic.trade.slAtrMult    = 1.5;
   ic.trade.tpMode       = TP_RR;
   ic.trade.tpRR         = PD("InpI_TPRR", InpI_TPRR);
   ic.trade.maxPerDay    = (int)PL("InpI_MaxPerDay", InpI_MaxPerDay);
   ic.trade.cooldownSec  = (int)PL("InpI_CooldownBars", InpI_CooldownBars) * PeriodSeconds((ENUM_TIMEFRAMES)PL("InpI_TF", (long)InpI_TF) == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : (ENUM_TIMEFRAMES)PL("InpI_TF", (long)InpI_TF));
   DefaultExits(ic.exits);
   ic.exits.unitR           = true;
   ic.exits.useBE           = PB("InpI_UseBE", InpI_UseBE);
   ic.exits.beTriggerAtr    = PD("InpI_BETrigger", InpI_BETrigger);
   ic.exits.beLockAtr       = 0.05;
   ic.exits.useSessionClose = true;
   ic.exits.closeHour       = (int)PL("InpI_EODHour", InpI_EODHour);
   ic.exits.newsExitMins    = (int)PL("InpI_NewsExit", InpI_NewsExit);

   c.vw.s = ic;
   c.vw.s.enabled     = PB("InpV_Enable", InpV_Enable);
   c.vw.vw.anchorHour = (int)PL("InpV_AnchorH", InpV_AnchorH);
   c.vw.vw.anchorMin  = 0;
   c.vw.vw.touchAtr   = PD("InpV_TouchAtr", InpV_TouchAtr);
   c.vw.vw.slBufAtr   = PD("InpV_SLBufAtr", InpV_SLBufAtr);
   c.vw.vw.minSlAtr   = PD("InpI_MinSlAtr", InpI_MinSlAtr);
   c.vw.vw.maxSlAtr   = PD("InpI_MaxSlAtr", InpI_MaxSlAtr);
   c.vw.vw.atrLen     = (int)PL("InpI_AtrLen", InpI_AtrLen);
   c.vw.vw.lookback   = 500;

   c.pbo.s = ic;
   c.pbo.s.enabled      = PB("InpX_Enable", InpX_Enable);
   c.pbo.pbo.fastLen    = (int)PL("InpX_Fast", InpX_Fast);
   c.pbo.pbo.slowLen    = (int)PL("InpX_Slow", InpX_Slow);
   c.pbo.pbo.maxPull    = (int)PL("InpX_MaxPull", InpX_MaxPull);
   c.pbo.pbo.depthAtr   = PD("InpX_DepthAtr", InpX_DepthAtr);
   c.pbo.pbo.slBufAtr   = PD("InpX_SLBufAtr", InpX_SLBufAtr);
   c.pbo.pbo.minSlAtr   = PD("InpI_MinSlAtr", InpI_MinSlAtr);
   c.pbo.pbo.maxSlAtr   = PD("InpI_MaxSlAtr", InpI_MaxSlAtr);
   c.pbo.pbo.atrLen     = (int)PL("InpI_AtrLen", InpI_AtrLen);
   c.pbo.pbo.lookback   = 400;

   //--- S7 / S8 scalper (shared scalper settings)
   c.scalp.w1StartH = (int)PL("InpS_W1StartH", InpS_W1StartH);
   c.scalp.w1StartM = (int)PL("InpS_W1StartM", InpS_W1StartM);
   c.scalp.w1EndH   = (int)PL("InpS_W1EndH", InpS_W1EndH);
   c.scalp.w1EndM   = (int)PL("InpS_W1EndM", InpS_W1EndM);
   c.scalp.w2StartH = (int)PL("InpS_W2StartH", InpS_W2StartH);
   c.scalp.w2StartM = (int)PL("InpS_W2StartM", InpS_W2StartM);
   c.scalp.w2EndH   = (int)PL("InpS_W2EndH", InpS_W2EndH);
   c.scalp.w2EndM   = (int)PL("InpS_W2EndM", InpS_W2EndM);
   c.scalp.regimeTF = (ENUM_TIMEFRAMES)PL("InpM_RegimeTF", (long)InpM_RegimeTF);
   c.scalp.maxAdx   = PD("InpM_MaxAdx", InpM_MaxAdx);
   c.scalp.trendTF  = (ENUM_TIMEFRAMES)PL("InpK_TrendTF", (long)InpK_TrendTF);
   c.scalp.trendLen = (int)PL("InpK_TrendLen", InpK_TrendLen);
   c.scalp.alignAsian = PB("InpS_AlignAsian", InpS_AlignAsian);

   SStrategyCommon sc = ic;
   sc.tf                  = (ENUM_TIMEFRAMES)PL("InpS_TF", (long)InpS_TF);
   sc.atrLen              = (int)PL("InpS_AtrLen", InpS_AtrLen);
   sc.riskPct             = PD("InpS_RiskPct", InpS_RiskPct);
   sc.trade.maxPerDay     = (int)PL("InpS_MaxPerDay", InpS_MaxPerDay);
   sc.trade.cooldownSec   = (int)PL("InpS_CooldownBars", InpS_CooldownBars) * PeriodSeconds((ENUM_TIMEFRAMES)PL("InpS_TF", (long)InpS_TF) == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : (ENUM_TIMEFRAMES)PL("InpS_TF", (long)InpS_TF));
   DefaultExits(sc.exits);
   sc.exits.unitR           = true;
   sc.exits.useBE           = PB("InpS_UseBE", InpS_UseBE);
   sc.exits.beTriggerAtr    = PD("InpS_BETrigger", InpS_BETrigger);
   sc.exits.beLockAtr       = 0.05;
   sc.exits.useTimeExit     = (int)PL("InpS_MaxBars", InpS_MaxBars) > 0;
   sc.exits.timeExitBars    = (int)PL("InpS_MaxBars", InpS_MaxBars);
   sc.exits.useSessionClose = true;
   sc.exits.closeHour       = (int)PL("InpS_EODHour", InpS_EODHour);
   sc.exits.newsExitMins    = (int)PL("InpS_NewsExit", InpS_NewsExit);

   c.mr.s = sc;
   c.mr.s.enabled       = PB("InpM_Enable", InpM_Enable);
   c.mr.s.trade.tpMode  = TP_RR;          // fallback only - the signal's own target (middle band) is used
   c.mr.s.trade.tpRR    = 1.0;
   c.mr.mr.bbLen        = (int)PL("InpM_BBLen", InpM_BBLen);
   c.mr.mr.bbDev        = PD("InpM_BBDev", InpM_BBDev);
   c.mr.mr.rsiLen       = (int)PL("InpM_RSILen", InpM_RSILen);
   c.mr.mr.rsiLow       = PD("InpM_RSILow", InpM_RSILow);
   c.mr.mr.rsiHigh      = PD("InpM_RSIHigh", InpM_RSIHigh);
   c.mr.mr.slBufAtr     = PD("InpM_SLBufAtr", InpM_SLBufAtr);
   c.mr.mr.maxSlAtr     = PD("InpM_MaxSlAtr", InpM_MaxSlAtr);
   c.mr.mr.minTpAtr     = PD("InpM_MinTpAtr", InpM_MinTpAtr);
   c.mr.mr.atrLen       = (int)PL("InpS_AtrLen", InpS_AtrLen);
   c.mr.mr.lookback     = 300;

   c.mo.s = sc;
   c.mo.s.enabled       = PB("InpK_Enable", InpK_Enable);
   c.mo.s.trade.tpMode  = TP_RR;
   c.mo.s.trade.tpRR    = PD("InpK_TPRR", InpK_TPRR);
   c.mo.mo.bodyAtr      = PD("InpK_BodyAtr", InpK_BodyAtr);
   c.mo.mo.closePct     = PD("InpK_ClosePct", InpK_ClosePct);
   c.mo.mo.stopMode     = (ENUM_IMPULSE_STOP)PL("InpK_StopMode", (long)InpK_StopMode);
   c.mo.mo.slBufAtr     = 0.1;
   c.mo.mo.minSlAtr     = 0.5;
   c.mo.mo.maxSlAtr     = 2.5;
   c.mo.mo.atrLen       = (int)PL("InpS_AtrLen", InpS_AtrLen);
   c.mo.mo.lookback     = 200;

   //--- sizing
   c.risk.lotMode     = (ENUM_LOT_MODE)PL("InpLotMode", (long)InpLotMode);
   c.risk.fixedLots   = PD("InpFixedLots", InpFixedLots);
   c.risk.riskPercent = PD("InpRiskPercent", InpRiskPercent);
   c.risk.accountSize = PD("InpAccountSize", InpAccountSize);
   c.weekendClose     = PB("InpWeekendClose", InpWeekendClose);
   c.weekendHour      = (int)PL("InpWeekendHour", InpWeekendHour);

   //--- guards
   c.useSession          = PB("InpUseSession", InpUseSession);
   c.session.startHour   = (int)PL("InpSessStartH", InpSessStartH);
   c.session.startMinute = 0;
   c.session.endHour     = (int)PL("InpSessEndH", InpSessEndH);
   c.session.endMinute   = 0;
   for(int d = 0; d < 7; d++)
      c.session.days[d] = (d >= 1 && d <= 4) || (d == 5 && PB("InpTradeFri", InpTradeFri));
   c.maxSpread = PD("InpMaxSpread", InpMaxSpread);
   c.spreadAtrPct = PD("InpSpreadAtrPct", InpSpreadAtrPct);
   c.useActivity  = PB("InpUseActivity", InpUseActivity);
   c.activityMin  = PD("InpActivityMin", InpActivityMin);
   c.activityDays = (int)PL("InpActivityDays", InpActivityDays);
   c.useDaily              = PB("InpUseDaily", InpUseDaily);
   c.daily.maxLossPct      = PD("InpDailyMaxLoss", InpDailyMaxLoss);
   c.daily.profitTargetPct = PD("InpDailyTargetPct", InpDailyTargetPct);
   c.daily.maxTrades       = (int)PL("InpDailyMaxTrades", InpDailyMaxTrades);
   c.daily.closeOnLimit    = true;
   c.daily.profitTargetMoney = PD("InpDailyTargetUSD", InpDailyTargetUSD);
   c.daily.maxLossMoney      = PD("InpDailyMaxLossUSD", InpDailyMaxLossUSD);
   c.useNews            = PB("InpUseNews", InpUseNews);
   c.news.currencies    = PS("InpNewsCurrencies", InpNewsCurrencies);
   c.news.minImportance = (int)PL("InpNewsImportance", InpNewsImportance);
   c.news.minutesBefore = (int)PL("InpNewsBefore", InpNewsBefore);
   c.news.minutesAfter  = (int)PL("InpNewsAfter", InpNewsAfter);
   c.news.exclude       = PS("InpNewsExclude", InpNewsExclude);
  }

//+------------------------------------------------------------------+
//| Strategy construction                                            |
//+------------------------------------------------------------------+
void AddExits(CStrategy *st, const SExitSettings &e)
  {
   if(e.usePartial)
     {
      CManagePartialClose *m = new CManagePartialClose();
      m.Configure(e.partialAtr, e.partialPct, e.partialBE);
      m.UseR(e.unitR);
      st.AddPositionModule(m);
     }
   if(e.useBE)
     {
      CManageBreakeven *m = new CManageBreakeven();
      m.Configure(e.beTriggerAtr, e.beLockAtr);
      m.UseR(e.unitR);
      st.AddPositionModule(m);
     }
   if(e.useTrail)
     {
      CManageTrailing *m = new CManageTrailing();
      m.Configure(e.trailStartAtr, e.trailDistAtr, e.trailStepAtr);
      m.UseR(e.unitR);
      st.AddPositionModule(m);
     }
   if(e.useTimeExit)
     {
      CManageTimeExit *m = new CManageTimeExit();
      m.Configure(e.timeExitBars, e.timeExitLosing);
      st.AddPositionModule(m);
     }
   if(e.useSessionClose)
     {
      CManageSessionClose *m = new CManageSessionClose();
      m.Configure(e.closeHour, e.closeMinute);
      st.AddPositionModule(m);
     }
   if(g_eng.cfg.weekendClose)
     {
      CManageWeekendClose *m = new CManageWeekendClose();
      m.Configure(g_eng.cfg.weekendHour);
      st.AddPositionModule(m);
     }
   if(e.newsExitMins > 0)
     {
      CManageNewsExit *m = new CManageNewsExit();
      m.Configure(g_eng.cfg.news, e.newsExitMins);
      st.AddPositionModule(m);
     }
  }

bool StartStrategy(CStrategy *st, const int id, const SStrategyCommon &s)
  {
   ENUM_TIMEFRAMES tf = (s.tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : s.tf;
   AddExits(st, s.exits);
   st.Retry(s.retryBlocked, s.retryMins);
   SRiskSettings risk = g_eng.cfg.risk;
   if(s.riskPct > 0.0)
      risk.riskPercent = s.riskPct;
   if(!st.Init(g_eng.symbol, tf, InpMagic + id, s.trade, risk, s.atrLen, s.exitOnFilteredFlip, GetPointer(g_eng.guards)))
     {
      PrintFormat("Strategy %s failed to initialise", st.Name());
      delete st;
      return false;
     }
   g_eng.Add(st);
   return true;
  }

bool BuildTrend(const STrendConfig &c)
  {
   ENUM_TIMEFRAMES tf = (c.s.tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : c.s.tf;
   CStrategy *st = new CStrategy(g_stratNames[STRAT_TREND - 1]);
   CSignalDJTrend *dj = new CSignalDJTrend();
   SDJTrendSettings d = c.dj;
   d.drawBasis = d.drawBasis && g_eng.isChart;   // only the chart's symbol draws its basis line
   dj.Configure(d);
   st.AddSignal(dj, ROLE_TRIGGER);
   if(c.useHTF)
     {
      SDJTrendSettings h = c.dj;
      h.drawBasis = false;
      CSignalDJTrend *htf = new CSignalDJTrend();
      htf.Configure(h);
      htf.Name("DJTrend HTF");
      htf.Timeframe(c.htf == PERIOD_CURRENT ? AutoHigherTimeframe(tf) : c.htf);
      st.AddSignal(htf, ROLE_FILTER);
     }
   if(c.useADX)
     {
      CFilterADX *f = new CFilterADX();
      f.Configure(c.adx);
      st.AddSignal(f, ROLE_FILTER);
     }
   if(c.useVol)
     {
      CFilterVolatility *f = new CFilterVolatility();
      f.Configure(c.vol);
      st.AddSignal(f, ROLE_FILTER);
     }
   if(c.useSlope)
     {
      CFilterSlope *f = new CFilterSlope();
      f.Configure(c.slope);
      st.AddSignal(f, ROLE_FILTER);
     }
   return StartStrategy(st, STRAT_TREND, c.s);
  }

bool BuildBreakout(const SBreakoutConfig &c, const int id)
  {
   CStrategy *st = new CStrategy(g_stratNames[id - 1]);
   CSignalSessionBreakout *b = new CSignalSessionBreakout();
   b.Configure(c.brk);
   b.Name(g_stratNames[id - 1]);
   st.AddSignal(b, ROLE_TRIGGER);
   if(c.alignAsian)
     {
      // filter: price must be beyond today's Asian range on the side of the trade
      CSignalSessionBreakout *asian = new CSignalSessionBreakout();
      SBreakoutSettings a = g_eng.cfg.brk.brk;
      a.tradeEndHour = 23;
      a.tradeEndMin  = 59;
      asian.Configure(a);
      asian.Name("AsianBias");
      st.AddSignal(asian, ROLE_FILTER);
     }
   if(c.trendLen > 0)
     {
      SFilterTrendMASettings tr;
      tr.maType   = c.trendType;
      tr.maLen    = c.trendLen;
      tr.lookback = 300;
      CFilterTrendMA *f = new CFilterTrendMA();
      f.Configure(tr);
      f.Timeframe(c.trendTF);
      st.AddSignal(f, ROLE_FILTER);
     }
   return StartStrategy(st, id, c.s);
  }

//--- shared intraday filters: trading window + higher-TF trend
void AddIntradayFilters(CStrategy *st)
  {
   CFilterTimeWindow *w = new CFilterTimeWindow();
   w.Configure(g_eng.cfg.intra.startHour, g_eng.cfg.intra.startMin, g_eng.cfg.intra.endHour, g_eng.cfg.intra.endMin);
   st.AddSignal(w, ROLE_FILTER);
   if(g_eng.cfg.intra.trendLen > 0)
     {
      SFilterTrendMASettings tr;
      tr.maType   = BASIS_EMA;
      tr.maLen    = g_eng.cfg.intra.trendLen;
      tr.lookback = 300;
      CFilterTrendMA *f = new CFilterTrendMA();
      f.Configure(tr);
      f.Timeframe(g_eng.cfg.intra.trendTF);
      st.AddSignal(f, ROLE_FILTER);
     }
  }

//--- scalper session windows (London + New York by default)
void AddScalpWindow(CStrategy *st)
  {
   if(g_eng.cfg.scalp.alignAsian)
     {
      // daily bias from the proven Asian-range breakout: price must be beyond today's range on the trade side
      CSignalSessionBreakout *asian = new CSignalSessionBreakout();
      SBreakoutSettings a = g_eng.cfg.brk.brk;
      a.tradeEndHour = 23;
      a.tradeEndMin  = 59;
      asian.Configure(a);
      asian.Name("AsianBias");
      st.AddSignal(asian, ROLE_FILTER);
     }
   CFilterTimeWindow *w = new CFilterTimeWindow();
   w.Configure(g_eng.cfg.scalp.w1StartH, g_eng.cfg.scalp.w1StartM, g_eng.cfg.scalp.w1EndH, g_eng.cfg.scalp.w1EndM);
   w.Configure2(g_eng.cfg.scalp.w2StartH, g_eng.cfg.scalp.w2StartM, g_eng.cfg.scalp.w2EndH, g_eng.cfg.scalp.w2EndM);
   st.AddSignal(w, ROLE_FILTER);
  }

bool BuildMeanRev(const SMeanRevConfig &c)
  {
   CStrategy *st = new CStrategy(g_stratNames[STRAT_MR - 1]);
   CSignalMeanRevScalp *m = new CSignalMeanRevScalp();
   m.Configure(c.mr);
   st.AddSignal(m, ROLE_TRIGGER);
   AddScalpWindow(st);
   if(g_eng.cfg.scalp.maxAdx > 0.0)
     {
      SFilterADXSettings a;
      a.diLen         = 14;
      a.adxLen        = 14;
      a.minAdx        = 0.0;
      a.maxAdx        = g_eng.cfg.scalp.maxAdx;
      a.requireDI     = false;
      a.requireRising = false;
      a.lookback      = 300;
      CFilterADX *f = new CFilterADX();
      f.Configure(a);
      f.Name("Regime ADX");
      f.Timeframe(g_eng.cfg.scalp.regimeTF);
      st.AddSignal(f, ROLE_FILTER);
     }
   return StartStrategy(st, STRAT_MR, c.s);
  }

bool BuildMomentum(const SMomentumConfig &c)
  {
   CStrategy *st = new CStrategy(g_stratNames[STRAT_MO - 1]);
   CSignalMomentumScalp *m = new CSignalMomentumScalp();
   m.Configure(c.mo);
   st.AddSignal(m, ROLE_TRIGGER);
   AddScalpWindow(st);
   if(g_eng.cfg.scalp.trendLen > 0)
     {
      SFilterTrendMASettings tr;
      tr.maType   = BASIS_EMA;
      tr.maLen    = g_eng.cfg.scalp.trendLen;
      tr.lookback = 300;
      CFilterTrendMA *f = new CFilterTrendMA();
      f.Configure(tr);
      f.Timeframe(g_eng.cfg.scalp.trendTF);
      st.AddSignal(f, ROLE_FILTER);
     }
   return StartStrategy(st, STRAT_MO, c.s);
  }

bool BuildVWAP(const SVWAPConfig &c)
  {
   CStrategy *st = new CStrategy(g_stratNames[STRAT_VWAP - 1]);
   CSignalVWAPTrend *v = new CSignalVWAPTrend();
   v.Configure(c.vw);
   st.AddSignal(v, ROLE_TRIGGER);
   AddIntradayFilters(st);
   return StartStrategy(st, STRAT_VWAP, c.s);
  }

bool BuildPBO(const SPBOConfig &c)
  {
   CStrategy *st = new CStrategy(g_stratNames[STRAT_PBO - 1]);
   CSignalPullbackBO *p = new CSignalPullbackBO();
   p.Configure(c.pbo);
   st.AddSignal(p, ROLE_TRIGGER);
   AddIntradayFilters(st);
   return StartStrategy(st, STRAT_PBO, c.s);
  }

bool BuildPullback(const SPullbackConfig &c)
  {
   CStrategy *st = new CStrategy(g_stratNames[STRAT_PULLBACK - 1]);
   CSignalTrendPullback *p = new CSignalTrendPullback();
   p.Configure(c.pb);
   st.AddSignal(p, ROLE_TRIGGER);
   return StartStrategy(st, STRAT_PULLBACK, c.s);
  }

bool RegisterGuards(const SEAConfig &c)
  {
   if(c.useNews)
     {
      CGuardNews *g = new CGuardNews();
      g.Configure(c.news);
      g_eng.guards.Add(g);
      g_eng.news = g;
     }
   if(c.useSession)
     {
      CGuardSession *g = new CGuardSession();
      g.Configure(c.session);
      g_eng.guards.Add(g);
     }
   if(c.maxSpread > 0.0 || (c.spreadAtrPct > 0.0 && g_eng.spec.spread < 0.0))
     {
      CGuardSpread *g = new CGuardSpread();
      // a per-symbol spread override is absolute; else % of daily ATR if set; else chart symbol: the input as is,
      // other symbols: the same % of price
      bool own = g_eng.spec.spread >= 0.0;
      g.Configure(c.maxSpread, own ? "" : _Symbol, own ? 0.0 : c.spreadAtrPct);
      g_eng.guards.Add(g);
     }
   if(c.useActivity)
     {
      CGuardActivity *g = new CGuardActivity();
      g.Configure(c.activityMin, c.activityDays);
      g_eng.guards.Add(g);
     }
   if(c.useDaily)
     {
      CGuardDailyLimits *g = new CGuardDailyLimits();
      g.Configure(c.daily);
      g_eng.guards.Add(g);
     }
   return g_eng.guards.Init(g_eng.symbol, InpMagic);
  }

//+------------------------------------------------------------------+
//| One engine per symbol                                            |
//+------------------------------------------------------------------+
//--- symbol overrides on the engine's config copy
void ApplySymbol(CSymbolEngine *e)
  {
   double ratio = 1.0;                              // symbol price / chart price, scales the price inputs
   if(!e.isChart)
     {
      double ref = CSymbolList::Price(_Symbol), px = CSymbolList::Price(e.symbol);
      ratio = (ref > 0.0 && px > 0.0) ? px / ref : 0.0;
     }
   double slip  = e.spec.slip >= 0.0 ? e.spec.slip : InpMaxSlippage * ratio;
   double point = SymbolInfoDouble(e.symbol, SYMBOL_POINT);
   int    dev   = point > 0.0 ? (int)MathRound(slip / point) : 0;
   if(dev <= 0 && e.spec.slip < 0.0)
      dev = 30;                                     // price not known yet: moderate default
   e.cfg.trend.s.trade.deviation = dev;
   e.cfg.brk.s.trade.deviation   = dev;
   e.cfg.ny.s.trade.deviation    = dev;
   e.cfg.pb.s.trade.deviation    = dev;
   e.cfg.vw.s.trade.deviation    = dev;
   e.cfg.pbo.s.trade.deviation   = dev;
   e.cfg.mr.s.trade.deviation    = dev;
   e.cfg.mo.s.trade.deviation    = dev;
   if(e.spec.spread >= 0.0)
      e.cfg.maxSpread = e.spec.spread;
   if(e.spec.risk > 0.0)
      e.cfg.risk.riskPercent = e.spec.risk;
   if(e.spec.sRisk > 0.0)
     {
      e.cfg.mr.s.riskPct = e.spec.sRisk;
      e.cfg.mo.s.riskPct = e.spec.sRisk;
     }
   if(e.spec.iRisk > 0.0)
     {
      e.cfg.vw.s.riskPct  = e.spec.iRisk;
      e.cfg.pbo.s.riskPct = e.spec.iRisk;
     }
  }

bool BuildEngine(const SSymbolSpec &spec)
  {
   CSymbolEngine *e = new CSymbolEngine();
   e.spec    = spec;
   e.symbol  = spec.name;
   e.isChart = (spec.name == _Symbol);
   e.cfg     = g_cfg;
   CProfile prof;
   bool fileProf = InpUseProfiles && prof.Load(e.symbol);
   string bad = spec.settings != "" ? prof.AddText(spec.settings) : "";   // Pair settings beat the file
   if(bad != "")
      g_symbolIssue += e.symbol + ": bad pair settings " + bad + "; ";
   if(prof.Count() > 0)
     {
      // the profile's / pair settings' values replace the inputs for this pair only
      g_prof = GetPointer(prof);
      BuildConfig(e.cfg);
      ApplyPreset((ENUM_EA_PRESET)PL("InpPreset", (long)InpPreset), e.cfg);
      if(e.spec.spread < 0.0 && prof.Has("InpMaxSpread"))
         e.spec.spread = e.cfg.maxSpread;                // the pair's own absolute limits
      if(e.spec.slip < 0.0 && prof.Has("InpMaxSlippage"))
         e.spec.slip = PD("InpMaxSlippage", InpMaxSlippage);
      g_prof = NULL;
      string unused = prof.UnusedText();
      if(unused != "")
         g_symbolIssue += e.symbol + ": unknown pair settings " + unused + "; ";
      e.profile = fileProf ? StringFormat("%s (%d values)", prof.File(), prof.Count() - prof.TextCount()) : "";
      if(prof.TextCount() > 0)
         e.profile += (e.profile == "" ? "" : " + ") + StringFormat("%d pair settings", prof.TextCount());
      PrintFormat("%s: profile %s -> %s", e.symbol, e.profile, ConfigSummary(e.cfg));
     }
   ApplySymbol(e);
   int n = ArraySize(g_engines);
   ArrayResize(g_engines, n + 1);
   g_engines[n] = e;
   g_eng = e;
   e.excursions.Init(e.symbol, InpMagic);

   SAlertSettings alerts;
   alerts.title     = "Claude EA";
   alerts.popup     = InpAlertPopup;
   alerts.push      = InpAlertPush;
   alerts.email     = false;
   alerts.sound     = false;
   alerts.soundFile = "alert.wav";
   e.alerts.Init(e.symbol, alerts);

   SEAConfig c = e.cfg;
   if(!RegisterGuards(c))
      return false;
   if(c.trend.s.enabled && !BuildTrend(c.trend))
      return false;
   if(c.brk.s.enabled && !BuildBreakout(c.brk, STRAT_BREAKOUT))
      return false;
   if(c.ny.s.enabled && !BuildBreakout(c.ny, STRAT_NY))
      return false;
   if(c.pb.s.enabled && !BuildPullback(c.pb))
      return false;
   if(c.vw.s.enabled && !BuildVWAP(c.vw))
      return false;
   if(c.pbo.s.enabled && !BuildPBO(c.pbo))
      return false;
   if(c.mr.s.enabled && !BuildMeanRev(c.mr))
      return false;
   if(c.mo.s.enabled && !BuildMomentum(c.mo))
      return false;
   if(e.Total() == 0)
     {
      PrintFormat("%s: no strategy enabled", e.symbol);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Chart + dashboard                                                |
//+------------------------------------------------------------------+
void DrawChart(const bool withHistory)
  {
   if(!g_drawer.CanDraw())
      return;
   for(int e = 0; e < ArraySize(g_engines); e++)
     {
      if(!g_engines[e].isChart)
         continue;
      for(int k = 0; k < g_engines[e].Total(); k++)
        {
         CStrategy *st = g_engines[e].strategies[k];
         if(withHistory && g_drawer.DrawHistory())
           {
            SSignal hist[];
            int n = st.History(hist);
            for(int i = 0; i < n; i++)
               g_drawer.DrawSignal(hist[i]);
           }
         st.DrawOverlays(g_drawer);
        }
     }
   g_drawer.Redraw();
  }

void AppendLine(string &dst[], const string line)
  {
   int n = ArraySize(dst);
   ArrayResize(dst, n + 1);
   dst[n] = line;
  }

//+------------------------------------------------------------------+
//| Health checks: anything missing or wrong shows on the dashboard  |
//| (red = problem, orange = warning) and is written to the journal. |
//+------------------------------------------------------------------+
#define HEALTH_OK    clrLimeGreen
#define HEALTH_WARN  clrOrange
#define HEALTH_ERROR clrTomato

void AddHealth(string &txt[], color &clr[], const color c, const string s)
  {
   int n = ArraySize(txt);
   ArrayResize(txt, n + 1);
   ArrayResize(clr, n + 1);
   txt[n] = s;
   clr[n] = c;
  }

void CheckHealth(string &txt[], color &clr[])
  {
   ArrayResize(txt, 0);
   ArrayResize(clr, 0);
   bool tester = (bool)MQLInfoInteger(MQL_TESTER);

   //--- trading permissions (live)
   if(!tester)
     {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
         AddHealth(txt, clr, HEALTH_ERROR, "Algo Trading is OFF - no trades will be placed");
      if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
         AddHealth(txt, clr, HEALTH_ERROR, "Account does not allow EA trading");
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
         AddHealth(txt, clr, HEALTH_ERROR, "Terminal not connected to the broker");
     }

   //--- timezone: live clock check + price-data check (the latter also works in the tester)
   string tz;
   if(!CTimeZone::Check(tz))
      AddHealth(txt, clr, HEALTH_ERROR, "Timezone mismatch: " + tz + " - fix 'Broker server timezone'");
   static datetime tzChecked = 0;
   static bool     tzHistOk  = true;
   static string   tzHistMsg = "";
   if(TimeCurrent() - tzChecked >= 86400)            // price-data check once a day
     {
      tzHistOk  = CTimeZone::CheckHistory(g_symbol, tzHistMsg);
      tzChecked = TimeCurrent();
     }
   if(!tzHistOk)
      AddHealth(txt, clr, HEALTH_ERROR, "Timezone mismatch in price data: " + tzHistMsg);

   //--- account size cap vs real account
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_cfg.risk.lotMode == LOT_RISK_PERCENT && g_cfg.risk.accountSize > 0.0 && bal > g_cfg.risk.accountSize * 1.2)
      AddHealth(txt, clr, HEALTH_WARN, StringFormat("Balance %.0f is above 'Account size cap' %.0f - risk is capped at the smaller size",
                                                    bal, g_cfg.risk.accountSize));

   //--- symbols / chart
   if(g_symbolIssue != "")
      AddHealth(txt, clr, HEALTH_ERROR, "Symbols: " + g_symbolIssue);
   for(int e = 0; e < ArraySize(g_engines); e++)
     {
      string sym = g_engines[e].symbol;
      StringToUpper(sym);
      if(g_engines[e].profile != "")
         AddHealth(txt, clr, HEALTH_OK, g_engines[e].symbol + ": profile " + g_engines[e].profile);
      else
        {
         if(InpUseProfiles)
            AddHealth(txt, clr, HEALTH_WARN, g_engines[e].symbol + ": no profile (" + PROFILE_DIR + g_engines[e].symbol + ".set) - using the inputs");
         if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
            AddHealth(txt, clr, HEALTH_WARN, g_engines[e].symbol + ": settings were tuned on XAUUSD - optimise this pair first");
        }
     }
   if(_Period != PERIOD_M1)
      AddHealth(txt, clr, HEALTH_WARN, "Chart is " + TfName((ENUM_TIMEFRAMES)_Period) + " - EA is tuned for M1");

   //--- news calendar
   if(g_cfg.useNews || g_cfg.brk.s.exits.newsExitMins > 0)
     {
      if(CheckPointer(NewsGuard()) == POINTER_INVALID)
         AddHealth(txt, clr, HEALTH_WARN, "News exit is on but the news guard is off - enable 'Block entries around news'");
      else
        {
         NewsGuard().CanOpen();                               // reloads the file if it changed
         datetime nowUtc = CTimeZone::ServerToUtc(TimeCurrent());
         if(g_calendarExportError != "")
            AddHealth(txt, clr, HEALTH_ERROR, "News: " + g_calendarExportError);
         if(!NewsGuard().FileFound())
            AddHealth(txt, clr, HEALTH_ERROR, "News file NOT FOUND (Common\\Files\\" + CALENDAR_FILE +
                      ") - attach the EA to a live chart to export it");
         else
            if(NewsGuard().Events() == 0)
               AddHealth(txt, clr, HEALTH_ERROR, "News file has no " + g_cfg.news.currencies + " events - re-export");
            else
              {
               if(NewsGuard().LastEvent() < nowUtc + 2 * 86400)
                  AddHealth(txt, clr, tester ? HEALTH_WARN : HEALTH_ERROR, "News file ends " +
                            TimeToString(CTimeZone::UtcToServer(NewsGuard().LastEvent()), TIME_DATE) +
                            " - no protection after that" + (tester ? " (re-export)" : " (auto re-export every 6 h)"));
               if(NewsGuard().FirstEvent() > nowUtc)
                  AddHealth(txt, clr, HEALTH_WARN, "News file starts " +
                            TimeToString(CTimeZone::UtcToServer(NewsGuard().FirstEvent()), TIME_DATE) +
                            " - earlier dates unprotected (lower 'Export from')");
              }
        }
     }

   //--- strategies
   bool multi = ArraySize(g_engines) > 1;
   for(int e = 0; e < ArraySize(g_engines); e++)
      for(int k = 0; k < g_engines[e].Total(); k++)
        {
         CStrategy *st = g_engines[e].strategies[k];
         string name = (multi ? g_engines[e].symbol + " " : "") + st.Name();
         if(!st.Ready())
            AddHealth(txt, clr, HEALTH_WARN, name + ": waiting for price history");
         string issue = st.LastIssue();
         if(issue != "")
            AddHealth(txt, clr, HEALTH_ERROR, name + ": " + issue);
        }

   //--- risk summary (always shown)
   double base = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   if(g_cfg.risk.accountSize > 0.0)
      base = MathMin(base, g_cfg.risk.accountSize);
   if(g_cfg.risk.lotMode == LOT_RISK_PERCENT)
     {
      if(g_cfg.risk.riskPercent >= 1.0)
         AddHealth(txt, clr, HEALTH_WARN, StringFormat("Risk %.2f%% per trade - no slippage buffer under a 1%% loss rule",
                                                       g_cfg.risk.riskPercent));
      AddHealth(txt, clr, HEALTH_OK, StringFormat("Risk %.2f%% = %.0f %s per trade, %s", g_cfg.risk.riskPercent,
                                                  base * g_cfg.risk.riskPercent / 100.0, AccountInfoString(ACCOUNT_CURRENCY),
                                                  (InpAllowHedge ? "hedging allowed" : "no hedging") +
                                                  (multi ? StringFormat(", %d symbols", ArraySize(g_engines)) : "")));
     }
   bool allOk = ArraySize(txt) > 0;
   for(int i = 0; i < ArraySize(txt); i++)
      allOk = allOk && clr[i] == HEALTH_OK;
   if(allOk)
      txt[0] = "All checks OK. " + txt[0];
  }

//--- write new/changed problems to the journal (also shows them in backtests)
void LogHealth(const string &txt[], const color &clr[])
  {
   string report = "";
   for(int i = 0; i < ArraySize(txt); i++)
      if(clr[i] != HEALTH_OK)
         report += txt[i] + "\n";
   if(report == g_healthPrinted)
      return;
   g_healthPrinted = report;
   for(int i = 0; i < ArraySize(txt); i++)
      if(clr[i] != HEALTH_OK)
         PrintFormat("HEALTH %s: %s", clr[i] == HEALTH_ERROR ? "PROBLEM" : "WARNING", txt[i]);
  }

void UpdateDashboard(void)
  {
   // without a dashboard (e.g. non-visual backtests) only log health once per hour
   static datetime lastHealth = 0;
   if(!g_dashboard.Enabled() && TimeCurrent() - lastHealth < 3600)
      return;
   lastHealth = TimeCurrent();
   string htxt[];
   color  hclr[];
   CheckHealth(htxt, hclr);
   LogHealth(htxt, hclr);
   if(!g_dashboard.Enabled())
      return;
   string lines[], part[];
   color  colours[];
   AppendLine(lines, StringFormat("Claude EA v%s (build %s)  %s  preset %d", EA_VERSION, EA_BUILD, SymbolsLabel(", "), (int)InpPreset));
   AppendLine(lines, "Health:");
   for(int i = 0; i < ArraySize(htxt); i++)
     {
      AppendLine(lines, "  " + htxt[i]);
      ArrayResize(colours, ArraySize(lines));
      colours[ArraySize(lines) - 1] = hclr[i];
     }

   //--- next high-impact news
   string newsLine;
   color  newsClr = clrNONE;
   if(CheckPointer(NewsGuard()) == POINTER_INVALID)
     {
      newsLine = "Next news: news guard OFF";
      newsClr  = HEALTH_WARN;
     }
   else
     {
      datetime ev;
      string   evName;
      bool     active;
      if(!NewsGuard().NextEvent(ev, evName, active))
        {
         newsLine = "Next news: none in calendar file";
         newsClr  = HEALTH_ERROR;
        }
      else
        {
         long secs = (long)(ev - CTimeZone::ServerToUtc(TimeCurrent()));
         string when = secs <= 0 ? "now" : StringFormat("in %dd %02dh %02dm", (int)(secs / 86400), (int)(secs % 86400 / 3600),
                                                           (int)(secs % 3600 / 60));
         newsLine = StringFormat("Next news: %s  %s (%s)%s", evName,
                                 TimeToString(CTimeZone::UtcToServer(ev), TIME_DATE | TIME_MINUTES), when,
                                 active ? "  -> ENTRIES BLOCKED" : "");
         newsClr  = active ? HEALTH_WARN : clrDeepSkyBlue;
        }
     }
   AppendLine(lines, newsLine);
   ArrayResize(colours, ArraySize(lines));
   colours[ArraySize(lines) - 1] = newsClr;
   for(int e = 0; e < ArraySize(g_engines); e++)
     {
      CSymbolEngine *en = g_engines[e];
      if(ArraySize(g_engines) > 1)
         AppendLine(lines, "=== " + en.symbol + " ===");
      for(int k = 0; k < en.Total(); k++)
        {
         en.strategies[k].Statuses(part);
         for(int i = 0; i < ArraySize(part); i++)
            AppendLine(lines, part[i]);
        }
      if(en.guards.Total() > 0)
        {
         AppendLine(lines, "Guards:");
         en.guards.Statuses(part);
         for(int i = 0; i < ArraySize(part); i++)
            AppendLine(lines, "  " + part[i]);
        }
     }
   int n = ArraySize(colours);
   ArrayResize(colours, ArraySize(lines));
   for(int i = n; i < ArraySize(colours); i++)
      colours[i] = clrNONE;
   for(int i = 0; i < n; i++)
      if(colours[i] == 0)
         colours[i] = clrNONE;
   g_dashboard.Show(lines, colours);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol    = _Symbol;
   g_testStart = TimeCurrent();

   CTimeZone::Server(InpServerTZ);
   string tzMsg;
   if(!CTimeZone::Check(tzMsg))
     {
      PrintFormat("WARNING: timezone mismatch (%s) - set 'Broker server timezone' correctly!", tzMsg);
      if(!MQLInfoInteger(MQL_TESTER))
         Alert("Claude EA: timezone mismatch - " + tzMsg);
     }
   else
      if(tzMsg != "")
         PrintFormat("Timezone OK: %s", tzMsg);

   BuildConfig(g_cfg);
   ApplyPreset(InpPreset, g_cfg);
   PrintFormat("Claude EA v%s build %s: preset %d -> %s", EA_VERSION, EA_BUILD, (int)InpPreset, ConfigSummary(g_cfg));

   if(InpNewsExport && !MQLInfoInteger(MQL_TESTER))
     {
      ExportCalendar(InpNewsFrom, TimeCurrent() + 21 * 86400);
      g_lastExport = TimeCurrent();
     }

   string prefix = "CLD_" + IntegerToString((long)InpMagic) + "_";
   SDrawSettings draw;
   draw.enabled     = InpDrawSignals || InpDrawBasis;
   draw.drawSignals = InpDrawSignals;
   draw.drawHistory = InpDrawHistory;
   draw.buyText     = "BUY";
   draw.sellText    = "SELL";
   draw.buyColor    = InpBuyColor;
   draw.sellColor   = InpSellColor;
   draw.fontSize    = InpFontSize;
   g_drawer.Init(prefix, draw);
   g_dashboard.Init(prefix + "dash_", InpShowDashboard, 10, 25, InpFontSize);

   SSymbolSpec specs[];
   bool   pOn[]  = {InpPair1_On, InpPair2_On, InpPair3_On, InpPair4_On, InpPair5_On};
   string pSym[] = {InpPair1, InpPair2, InpPair3, InpPair4, InpPair5};
   string pSet[] = {InpPair1_S1 + ";" + InpPair1_S2 + ";" + InpPair1_S3 + ";" + InpPair1_S4,
                    InpPair2_S1 + ";" + InpPair2_S2 + ";" + InpPair2_S3 + ";" + InpPair2_S4,
                    InpPair3_S1 + ";" + InpPair3_S2 + ";" + InpPair3_S3 + ";" + InpPair3_S4,
                    InpPair4_S1 + ";" + InpPair4_S2 + ";" + InpPair4_S3 + ";" + InpPair4_S4,
                    InpPair5_S1 + ";" + InpPair5_S2 + ";" + InpPair5_S3 + ";" + InpPair5_S4};
   bool usePairs = false;
   for(int i = 0; i < 5; i++)
      usePairs = usePairs || pOn[i];
   bool listed = usePairs ? CSymbolList::ParsePairs(pOn, pSym, pSet, InpSymbolSlot, specs, g_symbolIssue)
                          : CSymbolList::Parse(InpSymbols, InpSymbolSlot, specs, g_symbolIssue);
   // MT5 cuts a string input at 255 chars including "InpPairN_SK=" (243 left): a full field may have lost its end
   string pAll[] = {InpPair1_S1, InpPair1_S2, InpPair1_S3, InpPair1_S4, InpPair2_S1, InpPair2_S2, InpPair2_S3, InpPair2_S4,
                    InpPair3_S1, InpPair3_S2, InpPair3_S3, InpPair3_S4, InpPair4_S1, InpPair4_S2, InpPair4_S3, InpPair4_S4,
                    InpPair5_S1, InpPair5_S2, InpPair5_S3, InpPair5_S4};
   for(int i = 0; i < ArraySize(pAll); i++)
      if(pOn[i / 4] && StringLen(pAll[i]) >= 243)
         g_symbolIssue += StringFormat("Pair %d settings %d is %d chars - probably cut off by MT5 (max 243), split it; ",
                                       i / 4 + 1, i % 4 + 1, StringLen(pAll[i]));
   if(usePairs && StringLen(InpSymbols) > 0)
      g_symbolIssue += "'Symbols' is ignored while Pair inputs are on; ";
   if(!listed)
     {
      PrintFormat("Symbols: %s", g_symbolIssue == "" ? "no symbol to trade" : g_symbolIssue);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_symbolIssue != "")
      PrintFormat("Symbols: %s", g_symbolIssue);
   for(int i = 0; i < ArraySize(specs); i++)
      if(!BuildEngine(specs[i]))
         return INIT_PARAMETERS_INCORRECT;
   g_eng = NULL;
   PrintFormat("Trading %d symbol(s): %s", ArraySize(g_engines), SymbolsLabel(", "));
   if(ArraySize(g_engines) > 1 && !MQLInfoInteger(MQL_TESTER))
      EventSetTimer(1);                              // other symbols tick independently of the chart

   DrawChart(true);
   UpdateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int e = 0; e < ArraySize(g_engines); e++)
     {
      g_engines[e].Deinit();
      delete g_engines[e];
     }
   ArrayResize(g_engines, 0);
   g_drawer.Clear();
   g_dashboard.Clear();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Run every symbol's guards, strategies and trackers               |
//+------------------------------------------------------------------+
bool ProcessEngines(void)
  {
   bool anyFired = false;
   for(int e = 0; e < ArraySize(g_engines); e++)
     {
      CSymbolEngine *en = g_engines[e];
      en.excursions.OnTick();
      en.guards.OnTick();
      for(int k = 0; k < en.Total(); k++)
        {
         SSignal sig;
         if(en.strategies[k].OnTick(sig))
           {
            anyFired = true;
            if(en.isChart)
               g_drawer.DrawSignal(sig);
            en.alerts.Notify(sig);
           }
        }
     }
   return anyFired;
  }

//--- live multi-symbol: other symbols can tick while the chart symbol is quiet
void OnTimer()
  {
   ProcessEngines();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // keep the news calendar covering the coming weeks on a live chart
   if(InpNewsExport && !MQLInfoInteger(MQL_TESTER) && TimeCurrent() - g_lastExport >= 6 * 3600)
     {
      ExportCalendar(InpNewsFrom, TimeCurrent() + 21 * 86400);
      g_lastExport = TimeCurrent();
     }
   bool anyFired = ProcessEngines();

   // history may have been unavailable at attach time (e.g. tester start)
   static bool historyDrawn = false;
   static datetime lastDash = 0;
   if(!historyDrawn || anyFired || TimeCurrent() - lastDash >= 1)
     {
      DrawChart(!historyDrawn);
      historyDrawn = true;
      lastDash = TimeCurrent();
      UpdateDashboard();
     }
  }

//+------------------------------------------------------------------+
//| Custom optimisation criterion ("Custom max") + result export     |
//+------------------------------------------------------------------+
double OnTester()
  {
   SDailyStats daily;
   CDailyStats::Compute(ArraySize(g_engines) == 1 ? g_engines[0].symbol : "", InpMagic, daily);   // "" = all symbols
   double score = CTesterCriterion::Calculate(InpCriterion, InpMinTrades, daily.bestShare);
   if(InpReportResults)
     {
      string build  = EA_VERSION + " " + EA_BUILD;
      // engines with their own settings (profile / Pair inputs) report their own config
      string config = ConfigSummary(g_cfg);
      bool own = false;
      for(int e = 0; e < ArraySize(g_engines); e++)
         own = own || g_engines[e].profile != "";
      if(own)
        {
         config = "";
         for(int e = 0; e < ArraySize(g_engines); e++)
            config += (e > 0 ? " | " : "") + g_engines[e].symbol + "{" + ConfigSummary(g_engines[e].cfg) + "}";
        }
      string label  = SymbolsLabel("+");
      CTestReporter::WriteConsistency(label, (ENUM_TIMEFRAMES)_Period, g_testStart, TimeCurrent(), (int)InpPreset, build, config, daily);
      CTestReporter::WriteSummary(label, (ENUM_TIMEFRAMES)_Period, g_testStart, TimeCurrent(), (int)InpPreset, build, config, score);
      for(int e = 0; e < ArraySize(g_engines); e++)
         CTestReporter::WriteStrategyStats(g_engines[e].symbol, (ENUM_TIMEFRAMES)_Period, (int)InpPreset, build, config, InpMagic, g_stratNames);
     }
   if(InpExportTrades && !MQLInfoInteger(MQL_OPTIMIZATION))
      for(int e = 0; e < ArraySize(g_engines); e++)
         CTestReporter::WriteTrades(g_engines[e].symbol, (ENUM_TIMEFRAMES)_Period, InpMagic, (int)InpPreset,
                                    GetPointer(g_engines[e].excursions), g_testStart);
   return score;
  }
//+------------------------------------------------------------------+
