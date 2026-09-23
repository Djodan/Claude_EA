//+------------------------------------------------------------------+
//|                                               PositionModule.mqh |
//|  Base class for modules that manage OPEN positions every tick    |
//|  (breakeven, trailing, partial close, time exit, ...).           |
//|                                                                  |
//|  To add one: derive from CPositionModule, implement Manage()     |
//|  and register it in Claude.mq5 with g_positions.Add(...).        |
//|  Use ModifySL() / Close() / ClosePartial() so broker rules and   |
//|  the shared SPosition state are handled consistently.            |
//+------------------------------------------------------------------+
#ifndef CLAUDE_POSITIONMODULE_MQH
#define CLAUDE_POSITIONMODULE_MQH

#include <Trade/Trade.mqh>
#include "../Core/Defines.mqh"
#include "../Math/AtrProvider.mqh"

//--- snapshot of one position, shared by all modules on this tick
struct SPosition
  {
   ulong              ticket;
   ENUM_POSITION_TYPE type;
   double             open;
   double             sl;
   double             tp;
   double             volume;
   datetime           openTime;
   double             price;     // price the position would close at (bid for buys, ask for sells)
   double             risk;      // initial stop distance (1R) in price, 0 if unknown
   bool               closed;    // set once a module closes it fully

   //--- distance in price the position is in profit (negative = loss)
   double             Profit(void) const { return type == POSITION_TYPE_BUY ? price - open : open - price; }
   bool               IsBuy(void)  const { return type == POSITION_TYPE_BUY; }
  };

class CPositionModule
  {
protected:
   string            m_name;
   string            m_symbol;
   ulong             m_magic;
   ENUM_TIMEFRAMES   m_tf;
   CTrade           *m_trade;
   CAtrProvider     *m_atr;
   bool              m_useR;      // thresholds in R multiples of the initial stop instead of ATR

   double            NormalizePrice(const double price) const
     {
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double tick   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick > 0.0)
         return NormalizeDouble(MathRound(price / tick) * tick, digits);
      return NormalizeDouble(price, digits);
     }

   double            Atr(void) const { return CheckPointer(m_atr) != POINTER_INVALID ? m_atr.Value() : 0.0; }

   //--- distance unit for thresholds: 1R (initial stop distance) or ATR
   double            Unit(const SPosition &pos) const { return m_useR ? pos.risk : Atr(); }

   //--- tighten the stop only; respects stops & freeze levels
   bool              ModifySL(SPosition &pos, const double target)
     {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double stops  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double freeze = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
      double sl     = NormalizePrice(target);

      if(pos.IsBuy())
        {
         if(pos.sl > 0.0 && sl <= pos.sl + point / 2.0)
            return false;                       // not an improvement
         if(sl > pos.price - stops)
            return false;                       // too close to price
         if(pos.sl > 0.0 && freeze > 0.0 && pos.price - pos.sl <= freeze)
            return false;
        }
      else
        {
         if(pos.sl > 0.0 && sl >= pos.sl - point / 2.0)
            return false;
         if(sl < pos.price + stops)
            return false;
         if(pos.sl > 0.0 && freeze > 0.0 && pos.sl - pos.price <= freeze)
            return false;
        }

      if(!m_trade.PositionModify(pos.ticket, sl, pos.tp))
        {
         PrintFormat("%s: modify #%I64u SL %s failed, retcode %u", m_name, pos.ticket,
                     DoubleToString(sl, _Digits), m_trade.ResultRetcode());
         return false;
        }
      pos.sl = sl;
      return true;
     }

   bool              Close(SPosition &pos, const string why)
     {
      if(!m_trade.PositionClose(pos.ticket))
        {
         PrintFormat("%s: close #%I64u failed, retcode %u", m_name, pos.ticket, m_trade.ResultRetcode());
         return false;
        }
      PrintFormat("%s: closed #%I64u (%s)", m_name, pos.ticket, why);
      pos.closed = true;
      return true;
     }

   //--- close part of the volume; returns false if the remainder would be below min volume
   bool              ClosePartial(SPosition &pos, const double fraction)
     {
      double minV = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = minV;
      double vol = MathFloor(pos.volume * fraction / step + 1e-9) * step;
      if(vol < minV || pos.volume - vol < minV - 1e-9)
         return false;
      int digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
      vol = NormalizeDouble(vol, digits);
      if(!m_trade.PositionClosePartial(pos.ticket, vol))
        {
         PrintFormat("%s: partial close #%I64u %.2f failed, retcode %u", m_name, pos.ticket, vol, m_trade.ResultRetcode());
         return false;
        }
      PrintFormat("%s: closed %.2f of #%I64u", m_name, vol, pos.ticket);
      pos.volume -= vol;
      return true;
     }

public:
                     CPositionModule(const string name)
      : m_name(name), m_symbol(""), m_magic(0), m_tf(PERIOD_CURRENT), m_trade(NULL), m_atr(NULL), m_useR(false) {}
   virtual          ~CPositionModule(void) {}

   virtual bool      Init(const string symbol, const ulong magic, const ENUM_TIMEFRAMES tf, CTrade *trade, CAtrProvider *atr)
     {
      m_symbol = symbol;
      m_magic  = magic;
      m_tf     = tf;
      m_trade  = trade;
      m_atr    = atr;
      return CheckPointer(m_trade) != POINTER_INVALID;
     }
   virtual void      Deinit(void) {}

   virtual void      Manage(SPosition &pos) = 0;

   string            Name(void) const { return m_name; }
   void              UseR(const bool useR) { m_useR = useR; }
  };

#endif
//+------------------------------------------------------------------+
