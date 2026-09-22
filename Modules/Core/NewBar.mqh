//+------------------------------------------------------------------+
//|                                                       NewBar.mqh |
//|  Detects the opening of a new bar on a symbol/timeframe.         |
//+------------------------------------------------------------------+
#ifndef CLAUDE_NEWBAR_MQH
#define CLAUDE_NEWBAR_MQH

class CNewBar
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   datetime          m_lastTime;

public:
                     CNewBar(void) : m_symbol(""), m_tf(PERIOD_CURRENT), m_lastTime(0) {}

   void              Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      m_symbol   = symbol;
      m_tf       = tf;
      m_lastTime = iTime(m_symbol, m_tf, 0);   // don't fire for the bar we attached on
     }

   //--- true once per bar, on the first tick of the new bar
   bool              IsNew(void)
     {
      datetime t = iTime(m_symbol, m_tf, 0);
      if(t == 0 || t == m_lastTime)
         return false;
      m_lastTime = t;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
