//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|  One struct holding every EA setting. Claude.mq5 fills it from   |
//|  the inputs, a preset may then override parts of it, and all     |
//|  strategies/modules are built from it.                           |
//+------------------------------------------------------------------+
#ifndef CLAUDE_CONFIG_MQH
#define CLAUDE_CONFIG_MQH

#include "Defines.mqh"
#include "../Signals/SignalDJTrend.mqh"
#include "../Signals/SignalSessionBreakout.mqh"
#include "../Signals/SignalTrendPullback.mqh"
#include "../Signals/SignalVWAPTrend.mqh"
#include "../Signals/SignalPullbackBO.mqh"
#include "../Signals/Filters/FilterADX.mqh"
#include "../Signals/Filters/FilterVolatility.mqh"
#include "../Signals/Filters/FilterSlope.mqh"
#include "../Signals/Filters/FilterTrendMA.mqh"
#include "../Signals/Filters/FilterTimeWindow.mqh"
#include "../Guards/GuardSession.mqh"
#include "../Guards/GuardDailyLimits.mqh"
#include "../Guards/GuardNews.mqh"
#include "../Trade/TradeManager.mqh"
#include "../Trade/RiskManager.mqh"

//--- open-position management of one strategy
struct SExitSettings
  {
   bool              usePartial;
   double            partialAtr;
   double            partialPct;
   bool              partialBE;
   bool              useBE;
   double            beTriggerAtr;
   double            beLockAtr;
   bool              useTrail;
   double            trailStartAtr;
   double            trailDistAtr;
   double            trailStepAtr;
   bool              useTimeExit;
   int               timeExitBars;
   bool              timeExitLosing;
   bool              useSessionClose;
   int               closeHour;
   int               closeMinute;
   bool              unitR;                // BE / partial / trail thresholds in R instead of ATR
   int               newsExitMins;         // close positions N minutes before high-impact news (0 = off)
  };

//--- settings every strategy has
struct SStrategyCommon
  {
   bool              enabled;
   ENUM_TIMEFRAMES   tf;
   int               atrLen;               // ATR for SL/TP and position management
   bool              exitOnFilteredFlip;
   bool              retryBlocked;         // retry signals a guard blocked (news/spread) while still valid
   int               retryMins;
   double            riskPct;              // per-strategy risk % (0 = use the global setting)
   STradeSettings    trade;
   SExitSettings     exits;
  };

//--- S1: DJ Trend
struct STrendConfig
  {
   SStrategyCommon   s;
   SDJTrendSettings  dj;
   bool              useHTF;
   ENUM_TIMEFRAMES   htf;                  // PERIOD_CURRENT = automatic (next timeframe up)
   bool              useADX;
   SFilterADXSettings adx;
   bool              useVol;
   SFilterVolatilitySettings vol;
   bool              useSlope;
   SFilterSlopeSettings slope;
  };

//--- S2: session breakout
struct SBreakoutConfig
  {
   SStrategyCommon   s;
   SBreakoutSettings brk;
   bool              alignAsian;           // only trade in the direction price broke the Asian range
   int               trendLen;             // higher-TF trend filter: MA length (0 = off)
   ENUM_TIMEFRAMES   trendTF;
   ENUM_BASIS_TYPE   trendType;
  };

//--- S3: trend pullback
struct SPullbackConfig
  {
   SStrategyCommon   s;
   SPullbackSettings pb;
  };

//--- shared settings of the intraday strategies (S5, S6)
struct SIntradayFilters
  {
   int               startHour;            // trading window, reference time
   int               startMin;
   int               endHour;
   int               endMin;
   ENUM_TIMEFRAMES   trendTF;              // higher-TF trend filter
   int               trendLen;             // EMA length (0 = off)
  };

//--- S5: VWAP trend pullback
struct SVWAPConfig
  {
   SStrategyCommon   s;
   SVWAPSettings     vw;
  };

//--- S6: pullback-window breakout
struct SPBOConfig
  {
   SStrategyCommon   s;
   SPBOSettings      pbo;
  };

struct SEAConfig
  {
   SVWAPConfig       vw;
   SPBOConfig        pbo;
   SIntradayFilters  intra;
   STrendConfig      trend;
   SBreakoutConfig   brk;
   SBreakoutConfig   ny;                   // S4: NY opening-range breakout
   SPullbackConfig   pb;
   SRiskSettings     risk;                 // shared sizing
   //--- shared guards
   bool              useSession;
   SGuardSessionSettings session;
   double            maxSpread;            // price distance, e.g. 0.60 on XAUUSD (0 = off)
   bool              useDaily;
   SGuardDailySettings daily;
   bool              useNews;
   SGuardNewsSettings news;
  };

//--- higher timeframe used when the HTF filter is set to automatic
ENUM_TIMEFRAMES AutoHigherTimeframe(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return PERIOD_M15;
      case PERIOD_M2:  return PERIOD_M15;
      case PERIOD_M5:  return PERIOD_M30;
      case PERIOD_M15: return PERIOD_H1;
      case PERIOD_M30: return PERIOD_H4;
      case PERIOD_H1:  return PERIOD_H4;
      case PERIOD_H2:  return PERIOD_H8;
      case PERIOD_H4:  return PERIOD_D1;
      case PERIOD_D1:  return PERIOD_W1;
      default:         return PERIOD_MN1;
     }
  }

string TfName(const ENUM_TIMEFRAMES tf) { return StringSubstr(EnumToString(tf), 7); }

string ExitSummary(const SStrategyCommon &s)
  {
   string r = "";
   if(s.trade.slMode == SL_ATR)
      r += StringFormat(" SL%.1f", s.trade.slAtrMult);
   else
      if(s.trade.slMode == SL_SIGNAL)
         r += " SLsig";
      else
         if(s.trade.slMode == SL_POINTS)
            r += StringFormat(" SL%dpt", s.trade.slPoints);
   if(s.trade.tpMode == TP_ATR)
      r += StringFormat(" TP%.1f", s.trade.tpAtrMult);
   else
      if(s.trade.tpMode == TP_RR)
         r += StringFormat(" TP%.1fR", s.trade.tpRR);
      else
         if(s.trade.tpMode == TP_POINTS)
            r += StringFormat(" TP%dpt", s.trade.tpPoints);
   if(s.trade.mode == EA_TRADE_LONG_ONLY)
      r += " LONG";
   if(s.trade.mode == EA_TRADE_SHORT_ONLY)
      r += " SHORT";
   if(s.exitOnFilteredFlip)
      r += " XF";
   if(s.retryBlocked)
      r += StringFormat(" RETRY%d", s.retryMins);
   if(s.riskPct > 0.0)
      r += StringFormat(" risk%.2f", s.riskPct);
   if(s.trade.maxPerDay > 0)
      r += StringFormat(" max%d/d", s.trade.maxPerDay);
   if(s.trade.cooldownSec > 0)
      r += StringFormat(" cd%dm", s.trade.cooldownSec / 60);
   string u = s.exits.unitR ? "R" : "A";
   if(s.exits.usePartial)
      r += StringFormat(" PART%.0f%%@%.2f%s", s.exits.partialPct, s.exits.partialAtr, u);
   if(s.exits.useBE)
      r += StringFormat(" BE%.2f%s", s.exits.beTriggerAtr, u);
   if(s.exits.useTrail)
      r += StringFormat(" TRAIL%.1f/%.1f%s", s.exits.trailStartAtr, s.exits.trailDistAtr, u);
   if(s.exits.useTimeExit)
      r += StringFormat(" TIME%d", s.exits.timeExitBars);
   if(s.exits.useSessionClose)
      r += StringFormat(" EOD%02d", s.exits.closeHour);
   if(s.exits.newsExitMins > 0)
      r += StringFormat(" NX%d", s.exits.newsExitMins);
   return r;
  }

string BreakoutSummary(const string tag, const SBreakoutConfig &b)
  {
   string d1 = "";
   if(b.brk.maxRangeD1 > 0.0 || b.brk.minRangeD1 > 0.0)
      d1 = StringFormat(" d1%.2f-%.2f", b.brk.minRangeD1, b.brk.maxRangeD1);
   return StringFormat("%s[%s %02d:%02d-%02d:%02d<%02d buf%.2f%s%s%s%s] ", tag, TfName(b.s.tf),
                       b.brk.rangeStartHour, b.brk.rangeStartMin, b.brk.rangeEndHour, b.brk.rangeEndMin,
                       b.brk.tradeEndHour, b.brk.bufferAtr, d1, b.brk.stopMode == BRK_STOP_MID ? " MID" : "",
                       (b.brk.oneTradePerDay ? " 1/day" : " multi") + (b.brk.bodyRange ? " BODY" : "") + (b.alignAsian ? " ALIGN" : "") +
                       (b.trendLen > 0 ? StringFormat(" TR%s/%s%d", TfName(b.trendTF), StringSubstr(EnumToString(b.trendType), 6), b.trendLen) : ""),
                       ExitSummary(b.s));
  }

//--- short text describing the active setup (for reports and the dashboard)
string ConfigSummary(const SEAConfig &c)
  {
   string s = "";
   if(c.trend.s.enabled)
     {
      s += StringFormat("T[%s %s%d x%.2f%s", TfName(c.trend.s.tf), StringSubstr(EnumToString(c.trend.dj.basisType), 6),
                        c.trend.dj.basisLen, c.trend.dj.sigMult, ExitSummary(c.trend.s));
      if(c.trend.useHTF)
         s += " HTF";
      if(c.trend.useADX)
         s += StringFormat(" ADX%.0f", c.trend.adx.minAdx);
      if(c.trend.useVol)
         s += StringFormat(" VOL%.2f-%.1f", c.trend.vol.minRatio, c.trend.vol.maxRatio);
      if(c.trend.useSlope)
         s += " SLOPE";
      s += "] ";
     }
   if(c.brk.s.enabled)
      s += BreakoutSummary("B", c.brk);
   if(c.ny.s.enabled)
      s += BreakoutSummary("N", c.ny);
   if(c.vw.s.enabled || c.pbo.s.enabled)
      s += StringFormat("I[%02d:%02d-%02d:%02d%s] ", c.intra.startHour, c.intra.startMin, c.intra.endHour, c.intra.endMin,
                        c.intra.trendLen > 0 ? StringFormat(" TR%s/%d", TfName(c.intra.trendTF), c.intra.trendLen) : "");
   if(c.vw.s.enabled)
      s += StringFormat("V[%s touch%.2f buf%.2f sl%.1f-%.1f%s] ", TfName(c.vw.s.tf), c.vw.vw.touchAtr, c.vw.vw.slBufAtr,
                        c.vw.vw.minSlAtr, c.vw.vw.maxSlAtr, ExitSummary(c.vw.s));
   if(c.pbo.s.enabled)
      s += StringFormat("X[%s %d/%d pull%d sl%.1f-%.1f%s] ", TfName(c.pbo.s.tf), c.pbo.pbo.fastLen, c.pbo.pbo.slowLen,
                        c.pbo.pbo.maxPull, c.pbo.pbo.minSlAtr, c.pbo.pbo.maxSlAtr, ExitSummary(c.pbo.s));
   if(c.pb.s.enabled)
      s += StringFormat("P[%s %d/%d RSI%d %.0f/%.0f%s] ", TfName(c.pb.s.tf), c.pb.pb.fastLen, c.pb.pb.slowLen,
                        c.pb.pb.rsiLen, c.pb.pb.rsiLow, c.pb.pb.rsiHigh, ExitSummary(c.pb.s));
   if(c.risk.lotMode == LOT_RISK_PERCENT)
      s += StringFormat("risk%.2f%%", c.risk.riskPercent) + (c.risk.accountSize > 0.0 ? StringFormat(" cap%.0f", c.risk.accountSize) : "");
   else
      s += StringFormat("lots%.2f", c.risk.fixedLots);
   if(c.useNews)
      s += StringFormat(" NEWS%d/%d", c.news.minutesBefore, c.news.minutesAfter);
   if(c.useSession)
      s += " SESS";
   if(c.useDaily)
      s += StringFormat(" DAILY+%.0f/-%.0f", c.daily.profitTargetMoney, c.daily.maxLossMoney);
   if(c.maxSpread > 0.0)
      s += StringFormat(" SPR%.2f", c.maxSpread);
   return s;
  }

#endif
//+------------------------------------------------------------------+
