//+------------------------------------------------------------------+
//|                                                       Claude.mq5 |
//|  DJ Trend - Claude EA                                            |
//|                                                                  |
//|  Flow on every new closed bar:                                   |
//|    signal modules -> CSignalManager -> drawer / alerts / trader  |
//|                                                                  |
//|  Modules live in ./Modules:                                      |
//|    Core/     shared types, new-bar detection                     |
//|    Math/     Pine ta.* ports                                     |
//|    Signals/  signal modules + manager (add new modules here)     |
//|    Trade/    trade execution and position sizing                 |
//|    Notify/   alerts                                              |
//|    Visual/   chart objects                                       |
//+------------------------------------------------------------------+
#property copyright "DjoDan Maviaki"
#property version   "1.00"
#property description "DJ Trend (Pine v6 port): MA basis on hlc3 with an ATR buffer; trades trend flips on closed bars."

#include "Modules/Core/Defines.mqh"
#include "Modules/Core/NewBar.mqh"
#include "Modules/Signals/SignalManager.mqh"
#include "Modules/Signals/SignalDJTrend.mqh"
#include "Modules/Trade/RiskManager.mqh"
#include "Modules/Trade/TradeManager.mqh"
#include "Modules/Notify/AlertManager.mqh"
#include "Modules/Visual/ChartDrawer.mqh"

//--- Inputs ---------------------------------------------------------
input group "=== DJ Trend Signal ==="
input ENUM_TIMEFRAMES    InpSignalTF      = PERIOD_CURRENT; // Signal timeframe
input ENUM_BASIS_TYPE    InpBasisType     = BASIS_EMA;      // Basis Type
input int                InpBasisLen      = 34;             // Basis Length
input int                InpAtrLen        = 14;             // ATR Length
input double             InpSigMult       = 0.5;            // Signal Buffer (ATR x)
input double             InpAlmaOffset    = 0.85;           // ALMA offset
input double             InpAlmaSigma     = 6.0;            // ALMA sigma
input int                InpLookback      = 500;            // Bars recalculated per update

input group "=== Trading ==="
input ENUM_EA_TRADE_MODE InpTradeMode     = EA_TRADE_BOTH;  // Trade mode
input bool               InpCloseOpposite = true;           // Close opposite position on signal
input int                InpMaxPositions  = 1;              // Max open positions
input ulong              InpMagic         = 20260922;       // Magic number
input int                InpDeviation     = 20;             // Max slippage (points)
input string             InpComment       = "DJ Trend";     // Order comment

input group "=== Position Sizing ==="
input ENUM_LOT_MODE      InpLotMode       = LOT_FIXED;      // Lot mode
input double             InpFixedLots     = 0.01;           // Fixed lots
input double             InpRiskPercent   = 1.0;            // Risk % of equity (needs SL)

input group "=== Stop Loss / Take Profit ==="
input ENUM_SL_MODE       InpSLMode        = SL_NONE;        // Stop loss mode
input double             InpSLAtrMult     = 1.5;            // SL ATR multiple
input int                InpSLPoints      = 500;            // SL points
input ENUM_TP_MODE       InpTPMode        = TP_NONE;        // Take profit mode
input double             InpTPAtrMult     = 3.0;            // TP ATR multiple
input int                InpTPPoints      = 1000;           // TP points
input double             InpTPRR          = 2.0;            // TP Risk:Reward

input group "=== Alerts ==="
input bool               InpAlertPopup    = true;           // Popup alert
input bool               InpAlertPush     = false;          // Push notification
input bool               InpAlertEmail    = false;          // Email
input bool               InpAlertSound    = false;          // Sound (when popup off)
input string             InpAlertSoundFile= "alert.wav";    // Sound file

input group "=== Chart ==="
input bool               InpDrawSignals   = true;           // Draw signals
input bool               InpDrawHistory   = true;           // Draw historic signals on attach
input bool               InpDrawBasis     = true;           // Draw basis line
input int                InpBasisBars     = 300;            // Basis line length (bars)
input string             InpBuyText       = "BUY";          // Buy label text
input string             InpSellText      = "SELL";         // Sell label text
input color              InpBuyColor      = C'30,158,74';   // Buy colour
input color              InpSellColor     = C'224,21,27';   // Sell colour
input int                InpFontSize      = 9;              // Label font size

//--- Globals --------------------------------------------------------
CSignalManager g_signals;
CRiskManager   g_risk;
CTradeManager  g_trader;
CAlertManager  g_alerts;
CChartDrawer   g_drawer;
CNewBar        g_newBar;

string          g_symbol;
ENUM_TIMEFRAMES g_tf;

//+------------------------------------------------------------------+
//| Module registration - add new signal modules here                |
//+------------------------------------------------------------------+
bool RegisterSignalModules(void)
  {
   SDJTrendSettings dj;
   dj.basisType  = InpBasisType;
   dj.basisLen   = InpBasisLen;
   dj.atrLen     = InpAtrLen;
   dj.sigMult    = InpSigMult;
   dj.almaOffset = InpAlmaOffset;
   dj.almaSigma  = InpAlmaSigma;
   dj.lookback   = InpLookback;
   dj.drawBasis  = InpDrawBasis;
   dj.basisBars  = InpBasisBars;
   dj.upColor    = InpBuyColor;
   dj.downColor  = InpSellColor;
   dj.flatColor  = clrGray;

   CSignalDJTrend *djTrend = new CSignalDJTrend();
   djTrend.Configure(dj);
   if(!g_signals.Add(djTrend, ROLE_TRIGGER))
      return false;

   // Example: a higher-timeframe DJ Trend as a trend filter
   //   CSignalDJTrend *htf = new CSignalDJTrend();
   //   htf.Configure(dj);
   //   htf.Timeframe(PERIOD_H4);
   //   g_signals.Add(htf, ROLE_FILTER);   // BUY only when H4 trend is up, SELL only when down

   return true;
  }

//+------------------------------------------------------------------+
//| Draw historic signals and module overlays                        |
//+------------------------------------------------------------------+
void DrawChart(const bool withHistory)
  {
   if(!g_drawer.CanDraw())
      return;
   if(withHistory && g_drawer.DrawHistory())
     {
      SSignal hist[];
      int n = g_signals.History(hist);
      for(int i = 0; i < n; i++)
         g_drawer.DrawSignal(hist[i]);
     }
   g_signals.DrawOverlays(g_drawer);
   g_drawer.Redraw();
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbol = _Symbol;
   g_tf     = (InpSignalTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpSignalTF;

   //--- visuals
   SDrawSettings draw;
   draw.enabled     = InpDrawSignals || InpDrawBasis;
   draw.drawSignals = InpDrawSignals;
   draw.drawHistory = InpDrawHistory;
   draw.buyText     = InpBuyText;
   draw.sellText    = InpSellText;
   draw.buyColor    = InpBuyColor;
   draw.sellColor   = InpSellColor;
   draw.fontSize    = InpFontSize;
   g_drawer.Init("CLD_" + IntegerToString((long)InpMagic) + "_", draw);

   //--- signals
   if(!RegisterSignalModules() || !g_signals.Init(g_symbol, g_tf))
      return INIT_PARAMETERS_INCORRECT;

   //--- sizing & trading
   SRiskSettings risk;
   risk.lotMode     = InpLotMode;
   risk.fixedLots   = InpFixedLots;
   risk.riskPercent = InpRiskPercent;
   g_risk.Init(g_symbol, risk);

   STradeSettings trade;
   trade.mode            = InpTradeMode;
   trade.closeOnOpposite = InpCloseOpposite;
   trade.maxPositions    = MathMax(1, InpMaxPositions);
   trade.slMode          = InpSLMode;
   trade.slAtrMult       = InpSLAtrMult;
   trade.slPoints        = InpSLPoints;
   trade.tpMode          = InpTPMode;
   trade.tpAtrMult       = InpTPAtrMult;
   trade.tpPoints        = InpTPPoints;
   trade.tpRR            = InpTPRR;
   trade.magic           = InpMagic;
   trade.deviation       = InpDeviation;
   trade.comment         = InpComment;
   if(!g_trader.Init(g_symbol, trade, GetPointer(g_risk)))
      return INIT_FAILED;

   //--- alerts
   SAlertSettings alerts;
   alerts.title     = "DJ Trend";
   alerts.popup     = InpAlertPopup;
   alerts.push      = InpAlertPush;
   alerts.email     = InpAlertEmail;
   alerts.sound     = InpAlertSound;
   alerts.soundFile = InpAlertSoundFile;
   g_alerts.Init(g_symbol, alerts);

   //--- prime modules with history (no trading on the bar we attach to)
   g_newBar.Init(g_symbol, g_tf);
   SSignal ignored;
   g_signals.Update(ignored);
   DrawChart(true);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_signals.Deinit();
   g_drawer.Clear();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_newBar.IsNew())
      return;

   SSignal sig;
   bool fired = g_signals.Update(sig);

   // history may have been unavailable at attach time (e.g. tester start)
   static bool historyDrawn = false;
   DrawChart(!historyDrawn);
   historyDrawn = true;

   if(!fired)
      return;

   g_drawer.DrawSignal(sig);
   g_drawer.Redraw();
   g_alerts.Notify(sig);
   g_trader.OnSignal(sig);
  }
//+------------------------------------------------------------------+
