//+------------------------------------------------------------------+
//|                                                  GuardSpread.mqh |
//|  Blocks new positions while the spread exceeds a maximum.        |
//|  Limit modes (first that applies):                               |
//|   - % of the symbol's daily ATR: same cost vs. range on any pair |
//|   - price distance (e.g. 0.60 = $0.60 on XAUUSD), which with a   |
//|     reference symbol scales by price (same % of price elsewhere) |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDSPREAD_MQH
#define CLAUDE_GUARDSPREAD_MQH

#include "GuardBase.mqh"

class CGuardSpread : public CGuard
  {
private:
   double            m_maxPrice;
   string            m_ref;       // "" = absolute limit
   double            m_atrPct;    // > 0: limit = this % of D1 ATR(14)
   double            m_d1Atr;
   datetime          m_atrDay;

   double            D1Atr(void)
     {
      datetime day = iTime(m_symbol, PERIOD_D1, 0);
      if(day == m_atrDay && m_d1Atr > 0.0)
         return m_d1Atr;
      MqlRates r[];
      int n = CopyRates(m_symbol, PERIOD_D1, 1, 15, r);
      if(n < 2)
         return 0.0;
      double sum = 0.0;
      for(int i = 1; i < n; i++)
         sum += MathMax(r[i].high, r[i - 1].close) - MathMin(r[i].low, r[i - 1].close);
      m_d1Atr  = sum / (n - 1);
      m_atrDay = day;
      return m_d1Atr;
     }

public:
                     CGuardSpread(void) : CGuard("Spread"), m_maxPrice(0.0), m_ref(""), m_atrPct(0.0), m_d1Atr(0.0), m_atrDay(0) {}

   void              Configure(const double maxPrice, const string refSymbol = "", const double atrPct = 0.0)
     {
      m_maxPrice = maxPrice;
      m_ref      = refSymbol;
      m_atrPct   = atrPct;
     }

   double            Limit(void)
     {
      if(m_atrPct > 0.0)
         return m_atrPct / 100.0 * D1Atr();
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
      m_status = StringFormat("%s / %s%s", DoubleToString(spread, digits), DoubleToString(limit, digits),
                              m_atrPct > 0.0 ? StringFormat(" (%.1f%% D1 ATR)", m_atrPct) : "");
      return limit <= 0.0 || spread <= limit + SymbolInfoDouble(m_symbol, SYMBOL_POINT) / 2.0;
     }
  };

#endif
//+------------------------------------------------------------------+
