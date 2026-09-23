//+------------------------------------------------------------------+
//|                                                  GuardSpread.mqh |
//|  Blocks new positions while the spread exceeds a maximum.        |
//|  The limit is a PRICE distance (e.g. 0.60 = $0.60 on XAUUSD), so |
//|  it means the same on 2- and 3-digit brokers.                    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDSPREAD_MQH
#define CLAUDE_GUARDSPREAD_MQH

#include "GuardBase.mqh"

class CGuardSpread : public CGuard
  {
private:
   double            m_maxPrice;

public:
                     CGuardSpread(void) : CGuard("Spread"), m_maxPrice(0.0) {}

   void              Configure(const double maxPrice) { m_maxPrice = maxPrice; }

   virtual bool      CanOpen(void)
     {
      double spread = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_status = StringFormat("%s / %s", DoubleToString(spread, _Digits), DoubleToString(m_maxPrice, _Digits));
      return m_maxPrice <= 0.0 || spread <= m_maxPrice + _Point / 2.0;
     }
  };

#endif
//+------------------------------------------------------------------+
