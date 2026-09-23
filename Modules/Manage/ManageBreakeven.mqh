//+------------------------------------------------------------------+
//|                                              ManageBreakeven.mqh |
//|  Once a position is triggerAtr x ATR in profit, move the stop to |
//|  entry + lockAtr x ATR (locks a small gain / covers costs).      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGEBREAKEVEN_MQH
#define CLAUDE_MANAGEBREAKEVEN_MQH

#include "PositionModule.mqh"

class CManageBreakeven : public CPositionModule
  {
private:
   double            m_triggerAtr;
   double            m_lockAtr;

public:
                     CManageBreakeven(void) : CPositionModule("Breakeven"), m_triggerAtr(1.0), m_lockAtr(0.1) {}

   void              Configure(const double triggerAtr, const double lockAtr)
     {
      m_triggerAtr = triggerAtr;
      m_lockAtr    = lockAtr;
     }

   virtual void      Manage(SPosition &pos)
     {
      double atr = Atr();
      if(atr <= 0.0 || pos.Profit() < m_triggerAtr * atr)
         return;
      double target = pos.IsBuy() ? pos.open + m_lockAtr * atr : pos.open - m_lockAtr * atr;
      ModifySL(pos, target);   // no-op if the stop is already at/beyond it
     }
  };

#endif
//+------------------------------------------------------------------+
