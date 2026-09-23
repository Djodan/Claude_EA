//+------------------------------------------------------------------+
//|                                             FilterVolatility.mqh |
//|  Volatility-regime filter: ATR relative to its own average.      |
//|  ratio = ATR / SMA(ATR, avgLen); passes when min <= ratio <= max |
//|  Skips dead markets (low ratio) and spikes (high ratio).         |
//|  Non-directional: same rule for buys and sells.                  |
//+------------------------------------------------------------------+
#ifndef CLAUDE_FILTERVOLATILITY_MQH
#define CLAUDE_FILTERVOLATILITY_MQH

#include "../SeriesModule.mqh"

struct SFilterVolatilitySettings
  {
   int               atrLen;
   int               avgLen;
   double            minRatio;   // 0 = no lower bound
   double            maxRatio;   // 0 = no upper bound
   int               lookback;
  };

class CFilterVolatility : public CSeriesModule
  {
private:
   SFilterVolatilitySettings m_cfg;
   double            m_ratio[];

   bool              InRange(const double r) const
     {
      if(CPineTA::IsNA(r))
         return false;
      if(m_cfg.minRatio > 0.0 && r < m_cfg.minRatio)
         return false;
      if(m_cfg.maxRatio > 0.0 && r > m_cfg.maxRatio)
         return false;
      return true;
     }

public:
                     CFilterVolatility(void) : CSeriesModule("Volatility")
     {
      m_cfg.atrLen   = 14;
      m_cfg.avgLen   = 100;
      m_cfg.minRatio = 0.7;
      m_cfg.maxRatio = 2.5;
      m_cfg.lookback = 500;
     }

   void              Configure(const SFilterVolatilitySettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.atrLen < 1 || m_cfg.avgLen < 1)
        {
         PrintFormat("%s: ATR and average lengths must be >= 1", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, (m_cfg.atrLen + m_cfg.avgLen) * 2));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      if(!LoadRates(m_cfg.atrLen + m_cfg.avgLen + 2))
         return false;
      double atr[], avg[];
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, atr);
      CPineTA::SMA(atr, m_n, m_cfg.avgLen, avg);
      ArrayResize(m_ratio, m_n);
      for(int i = 0; i < m_n; i++)
         m_ratio[i] = (CPineTA::IsNA(atr[i]) || CPineTA::IsNA(avg[i]) || avg[i] == 0.0) ? PINE_NA : atr[i] / avg[i];
      m_ready = true;
      return true;
     }

   virtual bool      AllowsAt(const int i, const ENUM_SIGNAL_DIR dir) { return InRange(m_ratio[i]); }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_ratio[m_n - 1]))
         return "waiting for data";
      double r = m_ratio[m_n - 1];
      return StringFormat("ATR ratio %.2f %s", r, InRange(r) ? "OK" : "OUT OF RANGE");
     }
  };

#endif
//+------------------------------------------------------------------+
