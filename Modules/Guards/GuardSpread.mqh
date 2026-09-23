//+------------------------------------------------------------------+
//|                                                  GuardSpread.mqh |
//|  Blocks new positions while the spread exceeds a maximum.        |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDSPREAD_MQH
#define CLAUDE_GUARDSPREAD_MQH

#include "GuardBase.mqh"

class CGuardSpread : public CGuard
  {
private:
   int               m_maxPoints;

public:
                     CGuardSpread(void) : CGuard("Spread"), m_maxPoints(0) {}

   void              Configure(const int maxPoints) { m_maxPoints = maxPoints; }

   virtual bool      CanOpen(void)
     {
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double ask    = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid    = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      int    spread = (point > 0.0) ? (int)MathRound((ask - bid) / point) : 0;
      m_status = StringFormat("%d / %d pts", spread, m_maxPoints);
      return m_maxPoints <= 0 || spread <= m_maxPoints;
     }
  };

#endif
//+------------------------------------------------------------------+
