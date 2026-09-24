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
//+------------------------------------------------------------------+
#property copyright "DjoDan Maviaki"
#define EA_VERSION "2.36"
#define EA_BUILD   TimeToString(__DATETIME__, TIME_DATE | TIME_MINUTES)   // compile time, shown in journal/dashboard/results
#property version   EA_VERSION
#property description "XAUUSD M1/M2 portfolio: Asian-range and NY opening-range breakouts (plus trend/pullback) with prop-firm risk guards."

#include "Modules/Core/Defines.mqh"
#include "Modules/Core/TimeZone.mqh"
#include "Modules/Core/Config.mqh"
#include "Modules/Core/Presets.mqh"
#include "Modules/Core/TesterCriterion.mqh"
#include "Modules/Core/TestReporter.mqh"
#include "Modules/Core/CalendarExport.mqh"
#include "Modules/Core/ExcursionTracker.mqh"
#include "Modules/Strategy/Strategy.mqh"
#include "Modules/Signals/SignalDJTrend.mqh"
#include "Modules/Signals/SignalSessionBreakout.mqh"
#include "Modules/Signals/SignalTrendPullback.mqh"
#include "Modules/Signals/Filters/FilterADX.mqh"
#include "Modules/Signals/Filters/FilterVolatility.mqh"
#include "Modules/Signals/Filters/FilterSlope.mqh"
#include "Modules/Signals/Filters/FilterTrendMA.mqh"
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
#include "Modules/Manage/ManageNewsExit.mqh"
#include "Modules/Notify/AlertManager.mqh"
#include "Modules/Visual/ChartDrawer.mqh"
#include "Modules/Visual/Dashboard.mqh"

//--- strategy ids (magic = base magic + id)
#define STRAT_TREND    1
#define STRAT_BREAKOUT 2
#define STRAT_PULLBACK 3
#define STRAT_NY       4

//--- Inputs ---------------------------------------------------------
input group "=== General ==="
input ENUM_SERVER_TZ     InpServerTZ      = TZ_NY_CLOSE;    // Broker SERVER clock (not the company location!) - dashboard verifies it
input ENUM_EA_PRESET     InpPreset        = PRESET_BREAKOUT; // Preset (0 = use inputs below)
input ulong              InpMagic         = 20260900;       // Base magic (strategies use +1, +2, +3)
input double             InpMaxSlippage   = 0.50;           // Max slippage (price, e.g. 0.50 = $0.50 on gold)
input ENUM_LOT_MODE      InpLotMode       = LOT_RISK_PERCENT; // Lot mode
input double             InpFixedLots     = 0.10;           // Fixed lots
input double             InpRiskPercent   = 0.8;            // Risk % per trade (prop rule: max loss 1%)
input bool               InpAllowHedge    = false;          // Allow opposite positions (prop: no hedging)
input double             InpAccountSize   = 100000;         // Account size cap for risk (prop size, 0 = off)

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
input int                InpB_TrendLen    = 50;             // Trend filter: MA length (0 = off)
input ENUM_TIMEFRAMES    InpB_TrendTF     = PERIOD_D1;      // Trend filter: timeframe
input ENUM_BASIS_TYPE    InpB_TrendType   = BASIS_EMA;      // Trend filter: MA type
input int                InpB_NewsExit    = 5;              // Exit: close N min before high-impact news (0 = off)

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

input group "=== Guard: News ==="
input bool               InpUseNews       = true;           // Block entries around news
input string             InpNewsCurrencies= "USD";          // Currencies
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
input bool               InpUseDaily      = false;          // Daily limits
input double             InpDailyMaxLoss  = 3.0;            // Max daily loss %
input int                InpDailyMaxTrades= 0;              // Max trades per day (0 = off)

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
SEAConfig        g_cfg;
CStrategy       *g_strategies[];
CGuardManager    g_guards;
CAlertManager    g_alerts;
CChartDrawer     g_drawer;
CDashboard       g_dashboard;
CExcursionTracker g_excursions;
CGuardNews      *g_newsGuard = NULL;   // owned by g_guards; kept for health checks
datetime         g_lastExport = 0;
string           g_healthPrinted = "";  // last health report written to the journal
string           g_symbol;
datetime         g_testStart;
string           g_stratNames[] = {"Trend", "Breakout", "Pullback", "BreakoutNY"};   // index = id - 1

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
   t.magic           = InpMagic;
   t.deviation       = (int)MathRound(InpMaxSlippage / _Point);   // price -> broker points
   t.comment         = "";
   t.allowHedge      = InpAllowHedge;
  }

void BuildConfig(SEAConfig &c)
  {
   //--- S1 Trend
   c.trend.s.enabled            = InpT_Enable;
   c.trend.s.tf                 = InpT_TF;
   c.trend.s.atrLen             = InpT_AtrLen;
   c.trend.s.exitOnFilteredFlip = InpT_ExitOnFlip;
   DefaultTrade(c.trend.s.trade, InpT_Mode);
   c.trend.s.trade.closeOnOpposite = InpT_CloseOpp;
   c.trend.s.trade.slMode       = InpT_SLMode;
   c.trend.s.trade.slAtrMult    = InpT_SLAtr;
   c.trend.s.trade.tpMode       = InpT_TPMode;
   c.trend.s.trade.tpAtrMult    = InpT_TPAtr;
   c.trend.s.trade.tpRR         = InpT_TPRR;
   DefaultExits(c.trend.s.exits);
   c.trend.s.exits.useBE         = InpT_UseBE;
   c.trend.s.exits.beTriggerAtr  = InpT_BETrigger;
   c.trend.s.exits.useTrail      = InpT_UseTrail;
   c.trend.s.exits.trailStartAtr = InpT_TrailStart;
   c.trend.s.exits.trailDistAtr  = InpT_TrailDist;

   c.trend.dj.basisType  = InpT_BasisType;
   c.trend.dj.basisLen   = InpT_BasisLen;
   c.trend.dj.atrLen     = InpT_AtrLen;
   c.trend.dj.sigMult    = InpT_SigMult;
   c.trend.dj.almaOffset = InpT_AlmaOffset;
   c.trend.dj.almaSigma  = InpT_AlmaSigma;
   c.trend.dj.lookback   = InpT_Lookback;
   c.trend.dj.drawBasis  = InpDrawBasis;
   c.trend.dj.basisBars  = 300;
   c.trend.dj.upColor    = InpBuyColor;
   c.trend.dj.downColor  = InpSellColor;
   c.trend.dj.flatColor  = clrGray;

   c.trend.useHTF = InpT_UseHTF;
   c.trend.htf    = InpT_HTF;
   c.trend.useADX            = InpT_UseADX;
   c.trend.adx.diLen         = 14;
   c.trend.adx.adxLen        = 14;
   c.trend.adx.minAdx        = InpT_AdxMin;
   c.trend.adx.requireDI     = false;
   c.trend.adx.requireRising = false;
   c.trend.adx.lookback      = InpT_Lookback;
   c.trend.useVol       = InpT_UseVol;
   c.trend.vol.atrLen   = InpT_AtrLen;
   c.trend.vol.avgLen   = InpT_VolAvgLen;
   c.trend.vol.minRatio = InpT_VolMin;
   c.trend.vol.maxRatio = InpT_VolMax;
   c.trend.vol.lookback = InpT_Lookback;
   c.trend.useSlope          = InpT_UseSlope;
   c.trend.slope.maType      = InpT_BasisType;
   c.trend.slope.maLen       = InpT_BasisLen;
   c.trend.slope.slopeBars   = 3;
   c.trend.slope.minSlopeAtr = InpT_SlopeMin;
   c.trend.slope.atrLen      = InpT_AtrLen;
   c.trend.slope.almaOffset  = InpT_AlmaOffset;
   c.trend.slope.almaSigma   = InpT_AlmaSigma;
   c.trend.slope.lookback    = InpT_Lookback;

   //--- S2 Breakout
   c.brk.s.enabled            = InpB_Enable;
   c.brk.s.tf                 = InpB_TF;
   c.brk.s.atrLen             = InpB_AtrLen;
   c.brk.s.exitOnFilteredFlip = false;
   DefaultTrade(c.brk.s.trade, InpB_Mode);
   c.brk.s.trade.closeOnOpposite = true;
   c.brk.s.trade.slMode       = SL_SIGNAL;
   c.brk.s.trade.slAtrMult    = InpB_SLAtr;
   c.brk.s.trade.tpMode       = InpB_TPMode;
   c.brk.s.trade.tpRR         = InpB_TPRR;
   c.brk.s.trade.tpAtrMult    = InpB_TPAtr;
   DefaultExits(c.brk.s.exits);
   c.brk.s.exits.useSessionClose = InpB_EOD;
   c.brk.s.exits.closeHour       = InpB_EODHour;
   c.brk.s.exits.unitR           = true;
   c.brk.s.exits.useBE           = InpB_UseBE;
   c.brk.s.exits.beTriggerAtr    = InpB_BETrigger;
   c.brk.s.exits.beLockAtr       = InpB_BELock;
   c.brk.s.exits.usePartial      = InpB_UsePartial;
   c.brk.s.exits.partialAtr      = InpB_PartialR;
   c.brk.s.exits.partialPct      = InpB_PartialPct;
   c.brk.s.exits.partialBE       = false;

   c.brk.brk.rangeStartHour = InpB_RangeStartH;
   c.brk.brk.rangeStartMin  = InpB_RangeStartM;
   c.brk.brk.rangeEndHour   = InpB_RangeEndH;
   c.brk.brk.rangeEndMin    = InpB_RangeEndM;
   c.brk.brk.tradeEndHour   = InpB_TradeEndH;
   c.brk.brk.tradeEndMin    = 0;
   c.brk.brk.bufferAtr      = InpB_BufferAtr;
   c.brk.brk.minRangeAtr    = InpB_MinRangeAtr;
   c.brk.brk.maxRangeAtr    = InpB_MaxRangeAtr;
   c.brk.brk.atrLen         = InpB_AtrLen;
   c.brk.brk.stopMode       = InpB_StopMode;
   c.brk.brk.oneTradePerDay = InpB_OnePerDay;
   c.brk.brk.bodyRange      = InpB_BodyRange;
   c.brk.brk.lookback       = 400;
   c.brk.alignAsian         = false;
   c.brk.trendLen           = InpB_TrendLen;
   c.brk.trendTF            = InpB_TrendTF;
   c.brk.trendType          = InpB_TrendType;
   c.brk.s.exits.newsExitMins = InpB_NewsExit;
   c.brk.brk.minRangeD1     = InpB_MinRangeD1;
   c.brk.brk.maxRangeD1     = InpB_MaxRangeD1;

   //--- S4 NY opening-range breakout (same module, own window)
   c.ny = c.brk;
   c.ny.s.enabled          = InpN_Enable;
   c.ny.s.trade.mode       = InpN_Mode;
   c.ny.s.trade.tpRR       = InpN_TPRR;
   c.ny.s.exits.closeHour  = InpN_EODHour;
   c.ny.s.exits.useBE      = false;
   c.ny.s.exits.usePartial = false;
   int nyEnd = InpN_StartH * 60 + InpN_StartM + InpN_RangeMins;
   c.ny.brk.rangeStartHour = InpN_StartH;
   c.ny.brk.rangeStartMin  = InpN_StartM;
   c.ny.brk.rangeEndHour   = nyEnd / 60;
   c.ny.brk.rangeEndMin    = nyEnd % 60;
   c.ny.brk.tradeEndHour   = InpN_TradeEndH;
   c.ny.brk.tradeEndMin    = 0;
   c.ny.brk.bufferAtr      = InpN_BufferAtr;
   c.ny.brk.minRangeAtr    = 0.0;
   c.ny.brk.maxRangeAtr    = 0.0;
   c.ny.brk.minRangeD1     = 0.0;
   c.ny.brk.maxRangeD1     = InpN_MaxRangeD1;
   c.ny.brk.stopMode       = InpN_StopMode;
   c.ny.brk.oneTradePerDay = true;
   c.ny.alignAsian         = InpN_AlignAsian;
   c.ny.trendLen           = 0;

   //--- S3 Pullback
   c.pb.s.enabled            = InpP_Enable;
   c.pb.s.tf                 = InpP_TF;
   c.pb.s.atrLen             = InpP_AtrLen;
   c.pb.s.exitOnFilteredFlip = false;
   DefaultTrade(c.pb.s.trade, InpP_Mode);
   c.pb.s.trade.closeOnOpposite = true;
   c.pb.s.trade.slMode       = SL_ATR;
   c.pb.s.trade.slAtrMult    = InpP_SLAtr;
   c.pb.s.trade.tpMode       = InpP_TPMode;
   c.pb.s.trade.tpAtrMult    = InpP_TPAtr;
   c.pb.s.trade.tpRR         = InpP_TPRR;
   DefaultExits(c.pb.s.exits);
   c.pb.s.exits.useTrail      = InpP_UseTrail;
   c.pb.s.exits.trailStartAtr = InpP_TrailStart;
   c.pb.s.exits.trailDistAtr  = InpP_TrailDist;
   c.pb.s.exits.useTimeExit   = InpP_MaxBars > 0;
   c.pb.s.exits.timeExitBars  = InpP_MaxBars;

   c.pb.pb.fastLen  = InpP_FastLen;
   c.pb.pb.slowLen  = InpP_SlowLen;
   c.pb.pb.rsiLen   = InpP_RsiLen;
   c.pb.pb.rsiLow   = InpP_RsiLow;
   c.pb.pb.rsiHigh  = InpP_RsiHigh;
   c.pb.pb.atrLen   = InpP_AtrLen;
   c.pb.pb.lookback = 800;

   //--- sizing
   c.risk.lotMode     = InpLotMode;
   c.risk.fixedLots   = InpFixedLots;
   c.risk.riskPercent = InpRiskPercent;
   c.risk.accountSize = InpAccountSize;

   //--- guards
   c.useSession          = InpUseSession;
   c.session.startHour   = InpSessStartH;
   c.session.startMinute = 0;
   c.session.endHour     = InpSessEndH;
   c.session.endMinute   = 0;
   for(int d = 0; d < 7; d++)
      c.session.days[d] = (d >= 1 && d <= 4) || (d == 5 && InpTradeFri);
   c.maxSpread = InpMaxSpread;
   c.useDaily              = InpUseDaily;
   c.daily.maxLossPct      = InpDailyMaxLoss;
   c.daily.profitTargetPct = 0.0;
   c.daily.maxTrades       = InpDailyMaxTrades;
   c.daily.closeOnLimit    = true;
   c.useNews            = InpUseNews;
   c.news.currencies    = InpNewsCurrencies;
   c.news.minImportance = InpNewsImportance;
   c.news.minutesBefore = InpNewsBefore;
   c.news.minutesAfter  = InpNewsAfter;
   c.news.exclude       = InpNewsExclude;
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
   if(e.newsExitMins > 0)
     {
      CManageNewsExit *m = new CManageNewsExit();
      m.Configure(g_cfg.news, e.newsExitMins);
      st.AddPositionModule(m);
     }
  }

bool StartStrategy(CStrategy *st, const int id, const SStrategyCommon &s)
  {
   ENUM_TIMEFRAMES tf = (s.tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : s.tf;
   AddExits(st, s.exits);
   if(!st.Init(g_symbol, tf, InpMagic + id, s.trade, g_cfg.risk, s.atrLen, s.exitOnFilteredFlip, GetPointer(g_guards)))
     {
      PrintFormat("Strategy %s failed to initialise", st.Name());
      delete st;
      return false;
     }
   int n = ArraySize(g_strategies);
   ArrayResize(g_strategies, n + 1);
   g_strategies[n] = st;
   return true;
  }

bool BuildTrend(const STrendConfig &c)
  {
   ENUM_TIMEFRAMES tf = (c.s.tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : c.s.tf;
   CStrategy *st = new CStrategy(g_stratNames[STRAT_TREND - 1]);
   CSignalDJTrend *dj = new CSignalDJTrend();
   dj.Configure(c.dj);
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
      SBreakoutSettings a = g_cfg.brk.brk;
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
      g_guards.Add(g);
      g_newsGuard = g;
     }
   if(c.useSession)
     {
      CGuardSession *g = new CGuardSession();
      g.Configure(c.session);
      g_guards.Add(g);
     }
   if(c.maxSpread > 0.0)
     {
      CGuardSpread *g = new CGuardSpread();
      g.Configure(c.maxSpread);
      g_guards.Add(g);
     }
   if(c.useDaily)
     {
      CGuardDailyLimits *g = new CGuardDailyLimits();
      g.Configure(c.daily);
      g_guards.Add(g);
     }
   return g_guards.Init(g_symbol, InpMagic);
  }

//+------------------------------------------------------------------+
//| Chart + dashboard                                                |
//+------------------------------------------------------------------+
void DrawChart(const bool withHistory)
  {
   if(!g_drawer.CanDraw())
      return;
   for(int k = 0; k < ArraySize(g_strategies); k++)
     {
      if(withHistory && g_drawer.DrawHistory())
        {
         SSignal hist[];
         int n = g_strategies[k].History(hist);
         for(int i = 0; i < n; i++)
            g_drawer.DrawSignal(hist[i]);
        }
      g_strategies[k].DrawOverlays(g_drawer);
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

   //--- symbol / chart
   string sym = g_symbol;
   StringToUpper(sym);
   if(StringFind(sym, "XAU") < 0 && StringFind(sym, "GOLD") < 0)
      AddHealth(txt, clr, HEALTH_WARN, "Symbol " + g_symbol + " - EA is tuned for XAUUSD");
   if(_Period != PERIOD_M1)
      AddHealth(txt, clr, HEALTH_WARN, "Chart is " + TfName((ENUM_TIMEFRAMES)_Period) + " - EA is tuned for M1");

   //--- news calendar
   if(g_cfg.useNews || g_cfg.brk.s.exits.newsExitMins > 0)
     {
      if(CheckPointer(g_newsGuard) == POINTER_INVALID)
         AddHealth(txt, clr, HEALTH_WARN, "News exit is on but the news guard is off - enable 'Block entries around news'");
      else
        {
         g_newsGuard.CanOpen();                               // reloads the file if it changed
         datetime nowUtc = CTimeZone::ServerToUtc(TimeCurrent());
         if(g_calendarExportError != "")
            AddHealth(txt, clr, HEALTH_ERROR, "News: " + g_calendarExportError);
         if(!g_newsGuard.FileFound())
            AddHealth(txt, clr, HEALTH_ERROR, "News file NOT FOUND (Common\\Files\\" + CALENDAR_FILE +
                      ") - attach the EA to a live chart to export it");
         else
            if(g_newsGuard.Events() == 0)
               AddHealth(txt, clr, HEALTH_ERROR, "News file has no " + g_cfg.news.currencies + " events - re-export");
            else
              {
               if(g_newsGuard.LastEvent() < nowUtc + 2 * 86400)
                  AddHealth(txt, clr, tester ? HEALTH_WARN : HEALTH_ERROR, "News file ends " +
                            TimeToString(CTimeZone::UtcToServer(g_newsGuard.LastEvent()), TIME_DATE) +
                            " - no protection after that" + (tester ? " (re-export)" : " (auto re-export every 6 h)"));
               if(g_newsGuard.FirstEvent() > nowUtc)
                  AddHealth(txt, clr, HEALTH_WARN, "News file starts " +
                            TimeToString(CTimeZone::UtcToServer(g_newsGuard.FirstEvent()), TIME_DATE) +
                            " - earlier dates unprotected (lower 'Export from')");
              }
        }
     }

   //--- strategies
   for(int k = 0; k < ArraySize(g_strategies); k++)
     {
      if(!g_strategies[k].Ready())
         AddHealth(txt, clr, HEALTH_WARN, g_strategies[k].Name() + ": waiting for price history");
      string issue = g_strategies[k].LastIssue();
      if(issue != "")
         AddHealth(txt, clr, HEALTH_ERROR, g_strategies[k].Name() + ": " + issue);
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
                                                  InpAllowHedge ? "hedging allowed" : "no hedging"));
     }
   if(ArraySize(txt) == 1 && clr[0] == HEALTH_OK)
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
   AppendLine(lines, StringFormat("Claude XAUUSD EA v%s (build %s)  %s  preset %d", EA_VERSION, EA_BUILD, g_symbol, (int)InpPreset));
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
   if(CheckPointer(g_newsGuard) == POINTER_INVALID)
     {
      newsLine = "Next news: news guard OFF";
      newsClr  = HEALTH_WARN;
     }
   else
     {
      datetime ev;
      string   evName;
      bool     active;
      if(!g_newsGuard.NextEvent(ev, evName, active))
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
   for(int k = 0; k < ArraySize(g_strategies); k++)
     {
      g_strategies[k].Statuses(part);
      for(int i = 0; i < ArraySize(part); i++)
         AppendLine(lines, part[i]);
     }
   if(g_guards.Total() > 0)
     {
      AppendLine(lines, "Guards:");
      g_guards.Statuses(part);
      for(int i = 0; i < ArraySize(part); i++)
         AppendLine(lines, "  " + part[i]);
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
   g_excursions.Init(_Symbol, InpMagic);

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

   if(!RegisterGuards(g_cfg))
      return INIT_PARAMETERS_INCORRECT;
   if(g_cfg.trend.s.enabled && !BuildTrend(g_cfg.trend))
      return INIT_PARAMETERS_INCORRECT;
   if(g_cfg.brk.s.enabled && !BuildBreakout(g_cfg.brk, STRAT_BREAKOUT))
      return INIT_PARAMETERS_INCORRECT;
   if(g_cfg.ny.s.enabled && !BuildBreakout(g_cfg.ny, STRAT_NY))
      return INIT_PARAMETERS_INCORRECT;
   if(g_cfg.pb.s.enabled && !BuildPullback(g_cfg.pb))
      return INIT_PARAMETERS_INCORRECT;
   if(ArraySize(g_strategies) == 0)
     {
      Print("No strategy enabled");
      return INIT_PARAMETERS_INCORRECT;
     }

   SAlertSettings alerts;
   alerts.title     = "Claude EA";
   alerts.popup     = InpAlertPopup;
   alerts.push      = InpAlertPush;
   alerts.email     = false;
   alerts.sound     = false;
   alerts.soundFile = "alert.wav";
   g_alerts.Init(g_symbol, alerts);

   DrawChart(true);
   UpdateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int k = 0; k < ArraySize(g_strategies); k++)
     {
      g_strategies[k].Deinit();
      delete g_strategies[k];
     }
   ArrayResize(g_strategies, 0);
   g_guards.Deinit();
   g_drawer.Clear();
   g_dashboard.Clear();
   ChartRedraw(0);
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
   g_excursions.OnTick();
   g_guards.OnTick();
   bool anyFired = false;
   for(int k = 0; k < ArraySize(g_strategies); k++)
     {
      SSignal sig;
      if(g_strategies[k].OnTick(sig))
        {
         anyFired = true;
         g_drawer.DrawSignal(sig);
         g_alerts.Notify(sig);
        }
     }

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
   double score = CTesterCriterion::Calculate(InpCriterion, InpMinTrades);
   if(InpReportResults)
     {
      string build  = EA_VERSION + " " + EA_BUILD;
      string config = ConfigSummary(g_cfg);
      CTestReporter::WriteSummary(g_symbol, (ENUM_TIMEFRAMES)_Period, g_testStart, TimeCurrent(), (int)InpPreset, build, config, score);
      CTestReporter::WriteStrategyStats(g_symbol, (ENUM_TIMEFRAMES)_Period, (int)InpPreset, build, config, InpMagic, g_stratNames);
     }
   if(InpExportTrades && !MQLInfoInteger(MQL_OPTIMIZATION))
      CTestReporter::WriteTrades(g_symbol, (ENUM_TIMEFRAMES)_Period, InpMagic, (int)InpPreset, GetPointer(g_excursions), g_testStart);
   return score;
  }
//+------------------------------------------------------------------+
