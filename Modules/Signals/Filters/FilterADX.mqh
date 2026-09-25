//+------------------------------------------------------------------+
//|                                                    FilterADX.mqh |
//|  Trend-strength filter (Pine ta.dmi).                            |
//|  Passes a signal when ADX >= minimum, optionally requiring the   |
//|  DI lines to agree with the direction and/or ADX to be rising.   |
//+------------------------------------------------------------------+
#ifndef CLAUDE_FILTERADX_MQH
#define CLAUDE_FILTERADX_MQH

#include "../SeriesModule.mqh"

struct SFilterADXSettings
  {
   int               diLen;
   int               adxLen;
   double            minAdx;         // 0 = no minimum
   double            maxAdx;         // 0 = no maximum (set e.g. 25 to trade only ranging markets)
   bool              requireDI;      // +DI > -DI for buys, -DI > +DI for sells
   bool              requireRising;  // ADX higher than on the previous bar
   int               lookback;
  };

class CFilterADX : public CSeriesModule
  {
private:
   SFilterADXSettings m_cfg;
   double            m_plus[];
   double            m_minus[];
   double            m_adx[];

public:
                     CFilterADX(void) : CSeriesModule("ADX")
     {
      m_cfg.diLen         = 14;
      m_cfg.adxLen        = 14;
      m_cfg.minAdx        = 20.0;
      m_cfg.maxAdx        = 0.0;
      m_cfg.requireDI     = false;
      m_cfg.requireRising = false;
      m_cfg.lookback      = 500;
     }

   void              Configure(const SFilterADXSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.diLen < 1 || m_cfg.adxLen < 1)
        {
         PrintFormat("%s: DI and ADX lengths must be >= 1", m_name);
         return false;
        }
      Lookback(m_cfg.lookback);
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      if(!LoadRates((m_cfg.diLen + m_cfg.adxLen) * 3))
         return false;
      CPineTA::DMI(m_high, m_low, m_close, m_n, m_cfg.diLen, m_cfg.adxLen, m_plus, m_minus, m_adx);
      m_bias  = BiasAtIndex(m_n - 1);
      m_ready = true;
      return true;
     }

   //--- DI direction when the trend is strong enough, else flat
   virtual int       BiasAtIndex(const int i)
     {
      if(i < 0 || i >= m_n || CPineTA::IsNA(m_adx[i]) || m_adx[i] < m_cfg.minAdx)
         return 0;
      return m_plus[i] > m_minus[i] ? 1 : (m_minus[i] > m_plus[i] ? -1 : 0);
     }

   virtual bool      AllowsAt(const int i, const ENUM_SIGNAL_DIR dir)
     {
      if(CPineTA::IsNA(m_adx[i]) || m_adx[i] < m_cfg.minAdx)
         return false;
      if(m_cfg.maxAdx > 0.0 && m_adx[i] > m_cfg.maxAdx)
         return false;
      if(m_cfg.requireRising && (CPineTA::IsNA(m_adx[i - 1]) || m_adx[i] <= m_adx[i - 1]))
         return false;
      if(m_cfg.requireDI)
        {
         if(dir == SIG_BUY && !(m_plus[i] > m_minus[i]))
            return false;
         if(dir == SIG_SELL && !(m_minus[i] > m_plus[i]))
            return false;
        }
      return true;
     }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_adx[m_n - 1]))
         return "waiting for data";
      double a = m_adx[m_n - 1];
      return StringFormat("%.1f (+DI %.1f / -DI %.1f) %s", a, m_plus[m_n - 1], m_minus[m_n - 1],
                          (m_cfg.maxAdx > 0.0 ? (a <= m_cfg.maxAdx && a >= m_cfg.minAdx ? "RANGING OK" : "TOO STRONG") : (a >= m_cfg.minAdx ? "TRENDING" : "WEAK")));
     }
  };

#endif
//+------------------------------------------------------------------+
