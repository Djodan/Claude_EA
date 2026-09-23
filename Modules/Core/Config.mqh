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
#include "../Signals/Filters/FilterADX.mqh"
#include "../Signals/Filters/FilterVolatility.mqh"
#include "../Signals/Filters/FilterSlope.mqh"
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
  };

//--- settings every strategy has
struct SStrategyCommon
  {
   bool              enabled;
   ENUM_TIMEFRAMES   tf;
   int               atrLen;               // ATR for SL/TP and position management
   bool              exitOnFilteredFlip;
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
  };

//--- S3: trend pullback
struct SPullbackConfig
  {
   SStrategyCommon   s;
   SPullbackSettings pb;
  };

struct SEAConfig
  {
   STrendConfig      trend;
   SBreakoutConfig   brk;
   SPullbackConfig   pb;
   SRiskSettings     risk;                 // shared sizing
   //--- shared guards
   bool              useSession;
   SGuardSessionSettings session;
   int               maxSpread;
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
   if(s.exits.usePartial)
      r += StringFormat(" PART%.1f", s.exits.partialAtr);
   if(s.exits.useBE)
      r += StringFormat(" BE%.1f", s.exits.beTriggerAtr);
   if(s.exits.useTrail)
      r += StringFormat(" TRAIL%.1f/%.1f", s.exits.trailStartAtr, s.exits.trailDistAtr);
   if(s.exits.useTimeExit)
      r += StringFormat(" TIME%d", s.exits.timeExitBars);
   if(s.exits.useSessionClose)
      r += StringFormat(" EOD%02d", s.exits.closeHour);
   return r;
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
      s += StringFormat("B[%s %02d:%02d-%02d:%02d<%02d buf%.2f rng%.1f-%.1f%s%s] ", TfName(c.brk.s.tf),
                        c.brk.brk.rangeStartHour, c.brk.brk.rangeStartMin, c.brk.brk.rangeEndHour, c.brk.brk.rangeEndMin,
                        c.brk.brk.tradeEndHour, c.brk.brk.bufferAtr, c.brk.brk.minRangeAtr, c.brk.brk.maxRangeAtr,
                        (c.brk.brk.stopMode == BRK_STOP_MID ? " MID" : "") + (c.brk.brk.oneTradePerDay ? " 1/day" : " multi"),
                        ExitSummary(c.brk.s));
   if(c.pb.s.enabled)
      s += StringFormat("P[%s %d/%d RSI%d %.0f/%.0f%s] ", TfName(c.pb.s.tf), c.pb.pb.fastLen, c.pb.pb.slowLen,
                        c.pb.pb.rsiLen, c.pb.pb.rsiLow, c.pb.pb.rsiHigh, ExitSummary(c.pb.s));
   if(c.risk.lotMode == LOT_RISK_PERCENT)
      s += StringFormat("risk%.2f%%", c.risk.riskPercent);
   else
      s += StringFormat("lots%.2f", c.risk.fixedLots);
   if(c.useNews)
      s += StringFormat(" NEWS%d/%d", c.news.minutesBefore, c.news.minutesAfter);
   if(c.useSession)
      s += " SESS";
   if(c.useDaily)
      s += " DAILY";
   if(c.maxSpread > 0)
      s += StringFormat(" SPR%d", c.maxSpread);
   return s;
  }

#endif
//+------------------------------------------------------------------+
