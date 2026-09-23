//+------------------------------------------------------------------+
//|                                                FilterTrendMA.mqh |
//|  Trend-direction filter: close of the last closed bar vs. a      |
//|  moving average on the module's own timeframe (e.g. D1 EMA 50).  |
//|  Buys only while close > MA, sells only while close < MA.        |
//+------------------------------------------------------------------+
#ifndef CLAUDE_FILTERTRENDMA_MQH
#define CLAUDE_FILTERTRENDMA_MQH

#include "../SeriesModule.mqh"

struct SFilterTrendMASettings
  {
   ENUM_BASIS_TYPE   maType;
   int               maLen;
   int               lookback;
  };

class CFilterTrendMA : public CSeriesModule
  {
private:
   SFilterTrendMASettings m_cfg;
   double            m_ma[];

public:
                     CFilterTrendMA(void) : CSeriesModule("TrendMA")
     {
      m_cfg.maType   = BASIS_EMA;
      m_cfg.maLen    = 50;
      m_cfg.lookback = 300;
     }

   void              Configure(const SFilterTrendMASettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.maLen < 2)
        {
         PrintFormat("%s: MA length must be >= 2", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, m_cfg.maLen * 3));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      if(!LoadRates(m_cfg.maLen + 2))
         return false;
      CPineTA::MA(m_cfg.maType, m_close, m_n, m_cfg.maLen, 0.85, 6.0, m_ma);
      m_bias  = BiasAtIndex(m_n - 1);
      m_ready = true;
      return true;
     }

   virtual int       BiasAtIndex(const int i)
     {
      if(i < 0 || i >= m_n || CPineTA::IsNA(m_ma[i]))
         return 0;
      return m_close[i] > m_ma[i] ? 1 : (m_close[i] < m_ma[i] ? -1 : 0);
     }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_ma[m_n - 1]))
         return "waiting for data";
      return StringFormat("%s%d %s  close %s  %s", StringSubstr(EnumToString(m_cfg.maType), 6), m_cfg.maLen,
                          DoubleToString(m_ma[m_n - 1], _Digits), DoubleToString(m_close[m_n - 1], _Digits),
                          CSignalModule::Status());
     }
  };

#endif
//+------------------------------------------------------------------+
