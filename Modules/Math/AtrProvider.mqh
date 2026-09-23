//+------------------------------------------------------------------+
//|                                                  AtrProvider.mqh |
//|  Shared Pine-style ATR of the last closed bar, refreshed once    |
//|  per bar. Used by position-management modules.                   |
//+------------------------------------------------------------------+
#ifndef CLAUDE_ATRPROVIDER_MQH
#define CLAUDE_ATRPROVIDER_MQH

#include "PineTA.mqh"

class CAtrProvider
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_len;
   double            m_value;

public:
                     CAtrProvider(void) : m_symbol(""), m_tf(PERIOD_CURRENT), m_len(14), m_value(0.0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf, const int len)
     {
      m_symbol = symbol;
      m_tf     = tf;
      m_len    = MathMax(1, len);
      Update();
     }

   bool              Update(void)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      int n = CopyRates(m_symbol, m_tf, 1, m_len * 10, rates);
      if(n < m_len + 1)
         return false;
      double high[], low[], close[], atr[];
      ArrayResize(high, n);
      ArrayResize(low, n);
      ArrayResize(close, n);
      for(int i = 0; i < n; i++)
        {
         high[i]  = rates[i].high;
         low[i]   = rates[i].low;
         close[i] = rates[i].close;
        }
      CPineTA::ATR(high, low, close, n, m_len, atr);
      if(CPineTA::IsNA(atr[n - 1]))
         return false;
      m_value = atr[n - 1];
      return true;
     }

   double            Value(void) const { return m_value; }
  };

#endif
//+------------------------------------------------------------------+
