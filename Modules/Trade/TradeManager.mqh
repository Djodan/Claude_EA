//+------------------------------------------------------------------+
//|                                                 TradeManager.mqh |
//|  Turns final signals into orders according to the trade mode.    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_TRADEMANAGER_MQH
#define CLAUDE_TRADEMANAGER_MQH

#include <Trade/Trade.mqh>
#include "../Core/Defines.mqh"
#include "RiskManager.mqh"
#include "../Guards/GuardManager.mqh"

struct STradeSettings
  {
   ENUM_EA_TRADE_MODE mode;
   bool              closeOnOpposite;   // close opposite positions on a new signal (stop & reverse)
   int               maxPositions;      // max open positions for this EA on the symbol
   ENUM_SL_MODE      slMode;
   double            slAtrMult;
   int               slPoints;
   ENUM_TP_MODE      tpMode;
   double            tpAtrMult;
   int               tpPoints;
   double            tpRR;
   ulong             magic;
   int               deviation;         // max slippage, points
   string            comment;
  };

class CTradeManager
  {
private:
   string            m_symbol;
   STradeSettings    m_cfg;
   CTrade            m_trade;
   CRiskManager     *m_risk;
   CGuardManager    *m_guards;

   double            NormalizePrice(const double price) const
     {
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double tick   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick > 0.0)
         return NormalizeDouble(MathRound(price / tick) * tick, digits);
      return NormalizeDouble(price, digits);
     }

   double            MinStopDistance(void) const
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      long   level = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      return (level + 1) * point;
     }

   bool              DirectionAllowed(const ENUM_SIGNAL_DIR dir) const
     {
      switch(m_cfg.mode)
        {
         case EA_TRADE_BOTH:
            return true;
         case EA_TRADE_LONG_ONLY:
            return dir == SIG_BUY;
         case EA_TRADE_SHORT_ONLY:
            return dir == SIG_SELL;
         default:
            return false;
        }
     }

   double            CalcSL(const ENUM_SIGNAL_DIR dir, const double entry, const double atr, const double signalSL) const
     {
      double dist = 0.0;
      bool   signalOk = signalSL > 0.0 && (dir == SIG_BUY ? signalSL < entry : signalSL > entry);
      if(m_cfg.slMode == SL_SIGNAL && signalOk)
         dist = MathAbs(entry - signalSL);
      else
         if(m_cfg.slMode == SL_ATR || m_cfg.slMode == SL_SIGNAL)
            dist = m_cfg.slAtrMult * atr;
      else
         if(m_cfg.slMode == SL_POINTS)
            dist = m_cfg.slPoints * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(dist <= 0.0)
         return 0.0;
      dist = MathMax(dist, MinStopDistance());
      return NormalizePrice(dir == SIG_BUY ? entry - dist : entry + dist);
     }

   double            CalcTP(const ENUM_SIGNAL_DIR dir, const double entry, const double sl, const double atr, const double signalTP) const
     {
      if(signalTP > 0.0 && (dir == SIG_BUY ? signalTP > entry : signalTP < entry))
         return NormalizePrice(signalTP);
      double dist = 0.0;
      if(m_cfg.tpMode == TP_ATR)
         dist = m_cfg.tpAtrMult * atr;
      else
         if(m_cfg.tpMode == TP_POINTS)
            dist = m_cfg.tpPoints * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         else
            if(m_cfg.tpMode == TP_RR && sl > 0.0)
               dist = m_cfg.tpRR * MathAbs(entry - sl);
      if(dist <= 0.0)
         return 0.0;
      dist = MathMax(dist, MinStopDistance());
      return NormalizePrice(dir == SIG_BUY ? entry + dist : entry - dist);
     }

   bool              Open(const SSignal &sig)
     {
      bool            isBuy = (sig.dir == SIG_BUY);
      ENUM_ORDER_TYPE type  = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double entry = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl    = CalcSL(sig.dir, entry, sig.atr, sig.sl);
      double tp    = CalcTP(sig.dir, entry, sl, sig.atr, sig.tp);
      double lots  = m_risk.Calculate(type, entry, sl);
      if(lots <= 0.0)
        {
         Print("TradeManager: calculated volume is zero - order skipped");
         return false;
        }

      bool ok = isBuy ? m_trade.Buy(lots, m_symbol, 0.0, sl, tp, m_cfg.comment)
                      : m_trade.Sell(lots, m_symbol, 0.0, sl, tp, m_cfg.comment);
      if(!ok || (m_trade.ResultRetcode() != TRADE_RETCODE_DONE && m_trade.ResultRetcode() != TRADE_RETCODE_PLACED))
        {
         PrintFormat("TradeManager: %s %.2f failed, retcode %u (%s)", SignalDirToString(sig.dir), lots,
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
        }
      PrintFormat("TradeManager: %s %.2f %s @ %s  SL %s  TP %s", SignalDirToString(sig.dir), lots, m_symbol,
                  DoubleToString(m_trade.ResultPrice(), _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
      return true;
     }

public:
                     CTradeManager(void) : m_symbol(""), m_risk(NULL), m_guards(NULL) {}

   //--- guards is optional (NULL = no guards)
   bool              Init(const string symbol, const STradeSettings &cfg, CRiskManager *risk, CGuardManager *guards = NULL)
     {
      m_symbol = symbol;
      m_cfg    = cfg;
      m_risk   = risk;
      m_guards = guards;
      if(CheckPointer(m_risk) == POINTER_INVALID)
         return false;
      m_trade.SetExpertMagicNumber(m_cfg.magic);
      m_trade.SetDeviationInPoints(m_cfg.deviation);
      m_trade.SetTypeFillingBySymbol(m_symbol);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      if((m_cfg.tpMode == TP_RR) && m_cfg.slMode == SL_NONE)
         Print("TradeManager: TP mode Risk:Reward needs a stop loss - no TP will be set");
      return true;
     }

   bool              Enabled(void) const { return m_cfg.mode != EA_TRADE_OFF; }

   //--- positions owned by this EA on this symbol (type < 0 = both directions)
   int               CountPositions(const int type = -1) const
     {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != m_cfg.magic)
            continue;
         if(type >= 0 && PositionGetInteger(POSITION_TYPE) != type)
            continue;
         count++;
        }
      return count;
     }

   bool              ClosePositions(const int type = -1)
     {
      bool ok = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol || (ulong)PositionGetInteger(POSITION_MAGIC) != m_cfg.magic)
            continue;
         if(type >= 0 && PositionGetInteger(POSITION_TYPE) != type)
            continue;
         if(!m_trade.PositionClose(ticket, m_cfg.deviation))
           {
            PrintFormat("TradeManager: close #%I64u failed, retcode %u", ticket, m_trade.ResultRetcode());
            ok = false;
           }
        }
      return ok;
     }

   //--- exit-only signal: close positions against 'sig' without opening a new one
   void              OnExitSignal(const SSignal &sig)
     {
      if(!Enabled() || sig.dir == SIG_NONE || !m_cfg.closeOnOpposite)
         return;
      int against = (sig.dir == SIG_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      if(CountPositions(against) > 0)
        {
         PrintFormat("TradeManager: filtered %s flip - closing opposite positions", SignalDirToString(sig.dir));
         ClosePositions(against);
        }
     }

   void              OnSignal(const SSignal &sig)
     {
      if(!Enabled() || sig.dir == SIG_NONE)
         return;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
         Print("TradeManager: algo trading is disabled - signal not traded");
         return;
        }

      if(m_cfg.closeOnOpposite)
         ClosePositions(sig.dir == SIG_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);

      if(!DirectionAllowed(sig.dir))
         return;
      if(CountPositions() >= m_cfg.maxPositions)
         return;
      string reason;
      if(CheckPointer(m_guards) != POINTER_INVALID && !m_guards.CanOpen(reason))
        {
         PrintFormat("TradeManager: %s signal not traded - %s", SignalDirToString(sig.dir), reason);
         return;
        }
      Open(sig);
     }
  };

#endif
//+------------------------------------------------------------------+
