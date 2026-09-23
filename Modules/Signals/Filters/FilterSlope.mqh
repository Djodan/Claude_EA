//+------------------------------------------------------------------+
//|                                                  FilterSlope.mqh |
//|  MA slope filter: the moving average must be sloping in the      |
//|  signal's direction.                                             |
//|  slope = (MA[i] - MA[i-bars]) / ATR[i]   (in ATR units)          |
//|  bias = +1 if slope >= min, -1 if slope <= -min, else 0          |
//+------------------------------------------------------------------+
#ifndef CLAUDE_FILTERSLOPE_MQH
#define CLAUDE_FILTERSLOPE_MQH

#include "../SeriesModule.mqh"

struct SFilterSlopeSettings
  {
   ENUM_BASIS_TYPE   maType;
   int               maLen;
   int               slopeBars;
   double            minSlopeAtr;
   int               atrLen;
   double            almaOffset;
   double            almaSigma;
   int               lookback;
  };

class CFilterSlope : public CSeriesModule
  {
private:
   SFilterSlopeSettings m_cfg;
   double            m_slope[];

public:
                     CFilterSlope(void) : CSeriesModule("Slope")
     {
      m_cfg.maType      = BASIS_EMA;
      m_cfg.maLen       = 34;
      m_cfg.slopeBars   = 3;
      m_cfg.minSlopeAtr = 0.1;
      m_cfg.atrLen      = 14;
      m_cfg.almaOffset  = 0.85;
      m_cfg.almaSigma   = 6.0;
      m_cfg.lookback    = 500;
     }

   void              Configure(const SFilterSlopeSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.maLen < 2 || m_cfg.slopeBars < 1 || m_cfg.atrLen < 1)
        {
         PrintFormat("%s: MA len >= 2, slope bars >= 1, ATR len >= 1", m_name);
         return false;
        }
      Lookback(m_cfg.lookback);
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      if(!LoadRates(m_cfg.maLen * 2 + m_cfg.slopeBars + m_cfg.atrLen))
         return false;
      double ma[], atr[];
      CPineTA::MA(m_cfg.maType, m_src, m_n, m_cfg.maLen, m_cfg.almaOffset, m_cfg.almaSigma, ma);
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, atr);
      ArrayResize(m_slope, m_n);
      for(int i = 0; i < m_n; i++)
        {
         int j = i - m_cfg.slopeBars;
         if(j < 0 || CPineTA::IsNA(ma[i]) || CPineTA::IsNA(ma[j]) || CPineTA::IsNA(atr[i]) || atr[i] == 0.0)
            m_slope[i] = PINE_NA;
         else
            m_slope[i] = (ma[i] - ma[j]) / atr[i];
        }
      m_bias  = BiasAtIndex(m_n - 1);
      m_ready = true;
      return true;
     }

   virtual int       BiasAtIndex(const int i)
     {
      if(i < 0 || i >= m_n || CPineTA::IsNA(m_slope[i]))
         return 0;
      if(m_slope[i] >= m_cfg.minSlopeAtr)
         return 1;
      if(m_slope[i] <= -m_cfg.minSlopeAtr)
         return -1;
      return 0;
     }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_slope[m_n - 1]))
         return "waiting for data";
      return StringFormat("%+.2f ATR %s", m_slope[m_n - 1], CSignalModule::Status());
     }
  };

#endif
//+------------------------------------------------------------------+
