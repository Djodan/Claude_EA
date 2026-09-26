//+------------------------------------------------------------------+
//|                                                  GuardSpread.mqh |
//|  Blocks new positions while the spread exceeds a maximum.        |
//|  The limit is a PRICE distance (e.g. 0.60 = $0.60 on XAUUSD), so |
//|  it means the same on 2- and 3-digit brokers.                    |
//|  With a reference symbol the limit scales by price: a 0.60 limit |
//|  set for XAUUSD becomes the same % of price on EURUSD.           |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDSPREAD_MQH
#define CLAUDE_GUARDSPREAD_MQH

#include "GuardBase.mqh"

class CGuardSpread : public CGuard
  {
private:
   double            m_maxPrice;
   string            m_ref;       // "" = absolute limit

public:
                     CGuardSpread(void) : CGuard("Spread"), m_maxPrice(0.0), m_ref("") {}

   void              Configure(const double maxPrice, const string refSymbol = "") { m_maxPrice = maxPrice; m_ref = refSymbol; }

   double            Limit(void) const
     {
      if(m_ref == "" || m_ref == m_symbol)
         return m_maxPrice;
      double ref = SymbolInfoDouble(m_ref, SYMBOL_BID), px = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      return (ref > 0.0 && px > 0.0) ? m_maxPrice * px / ref : 0.0;
     }

   virtual bool      CanOpen(void)
     {
      double spread = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double limit  = Limit();
      m_status = StringFormat("%s / %s", DoubleToString(spread, digits), DoubleToString(limit, digits));
      return limit <= 0.0 || spread <= limit + SymbolInfoDouble(m_symbol, SYMBOL_POINT) / 2.0;
     }
  };

#endif
//+------------------------------------------------------------------+
