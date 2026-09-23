//+------------------------------------------------------------------+
//|                                                SignalDJTrend.mqh |
//|  Port of the "DJ Trend - Claude" Pine v6 indicator.              |
//|                                                                  |
//|  basis = MA(hlc3, len)  (EMA / SMA / HMA / ALMA)                 |
//|  trend flips to +1 when close > basis + mult*ATR                 |
//|  trend flips to -1 when close < basis - mult*ATR                 |
//|  BUY  when trend becomes +1, SELL when trend becomes -1          |
//|  Only closed bars are used, so signals never repaint.            |
//|                                                                  |
//|  As ROLE_FILTER (e.g. on a higher timeframe) it passes signals   |
//|  that agree with its current trend.                              |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALDJTREND_MQH
#define CLAUDE_SIGNALDJTREND_MQH

#include "SeriesModule.mqh"

struct SDJTrendSettings
  {
   ENUM_BASIS_TYPE   basisType;
   int               basisLen;
   int               atrLen;
   double            sigMult;      // signal buffer, ATR multiple
   double            almaOffset;
   double            almaSigma;
   int               lookback;     // closed bars recomputed on each update
   bool              drawBasis;
   int               basisBars;    // how many bars of basis line to draw
   color             upColor;
   color             downColor;
   color             flatColor;
  };

class CSignalDJTrend : public CSeriesModule
  {
private:
   SDJTrendSettings  m_cfg;
   double            m_basis[];
   double            m_atr[];
   int               m_trend[];

   int               MinBars(void) const
     {
      return MathMax(m_cfg.basisLen, m_cfg.atrLen) * 2 + 2;
     }

   ENUM_SIGNAL_DIR   DirAt(const int i) const
     {
      if(i < 1 || i >= m_n)
         return SIG_NONE;
      if(m_trend[i] == 1 && m_trend[i - 1] != 1)
         return SIG_BUY;
      if(m_trend[i] == -1 && m_trend[i - 1] != -1)
         return SIG_SELL;
      return SIG_NONE;
     }

public:
                     CSignalDJTrend(void) : CSeriesModule("DJTrend")
     {
      m_cfg.basisType  = BASIS_EMA;
      m_cfg.basisLen   = 34;
      m_cfg.atrLen     = 14;
      m_cfg.sigMult    = 0.5;
      m_cfg.almaOffset = 0.85;
      m_cfg.almaSigma  = 6.0;
      m_cfg.lookback   = 500;
      m_cfg.drawBasis  = true;
      m_cfg.basisBars  = 300;
      m_cfg.upColor    = C'30,158,74';
      m_cfg.downColor  = C'224,21,27';
      m_cfg.flatColor  = clrGray;
     }

   void              Configure(const SDJTrendSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.basisLen < 2 || m_cfg.atrLen < 1 || m_cfg.sigMult < 0.0)
        {
         PrintFormat("%s: invalid settings (basis len >= 2, ATR len >= 1, buffer >= 0)", m_name);
         return false;
        }
      if(m_cfg.lookback < MinBars())
        {
         PrintFormat("%s: lookback raised from %d to %d bars", m_name, m_cfg.lookback, MinBars() * 5);
         m_cfg.lookback = MinBars() * 5;
        }
      Lookback(m_cfg.lookback);
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();
      if(!LoadRates(MinBars()))
         return false;

      CPineTA::MA(m_cfg.basisType, m_src, m_n, m_cfg.basisLen, m_cfg.almaOffset, m_cfg.almaSigma, m_basis);
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, m_atr);

      // var int trend = 0 -- only flips when price clears the basis by the buffer
      ArrayResize(m_trend, m_n);
      int trend = 0;
      for(int i = 0; i < m_n; i++)
        {
         if(!CPineTA::IsNA(m_basis[i]) && !CPineTA::IsNA(m_atr[i]))
           {
            double buffer = m_cfg.sigMult * m_atr[i];
            if(m_close[i] > m_basis[i] + buffer)
               trend = 1;
            else
               if(m_close[i] < m_basis[i] - buffer)
                  trend = -1;
           }
         m_trend[i] = trend;
        }

      m_bias = m_trend[m_n - 1];
      FillSignal(m_n - 1, DirAt(m_n - 1), m_atr[m_n - 1], m_last);
      m_ready = true;
      return true;
     }

   virtual int       BiasAtIndex(const int i) { return (i >= 0 && i < m_n) ? m_trend[i] : 0; }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 1; i < m_n; i++)
        {
         ENUM_SIGNAL_DIR dir = DirAt(i);
         if(dir == SIG_NONE)
            continue;
         ArrayResize(out, count + 1, 64);
         FillSignal(i, dir, m_atr[i], out[count++]);
        }
      return count;
     }

   //--- basis line coloured by trend
   virtual void      DrawOverlay(CChartDrawer &drawer)
     {
      if(!m_cfg.drawBasis || !drawer.CanDraw() || m_n < 2)
         return;
      int bars = MathMin(m_cfg.basisBars, m_n - 1);
      for(int k = 0; k < bars; k++)
        {
         int    i    = m_n - 1 - k;
         string name = m_name + "_basis_" + IntegerToString(k);
         if(CPineTA::IsNA(m_basis[i]) || CPineTA::IsNA(m_basis[i - 1]))
           {
            drawer.Delete(name);
            continue;
           }
         color clr = m_trend[i] == 1 ? m_cfg.upColor : (m_trend[i] == -1 ? m_cfg.downColor : m_cfg.flatColor);
         drawer.DrawSegment(name, m_rates[i - 1].time, m_basis[i - 1], m_rates[i].time, m_basis[i], clr);
        }
     }

   //--- exposed for other modules / debugging (shift 0 = last closed bar)
   double            Basis(const int shift = 0) const { return (shift < m_n) ? m_basis[m_n - 1 - shift] : PINE_NA; }
   double            Atr(const int shift = 0)   const { return (shift < m_n) ? m_atr[m_n - 1 - shift]   : PINE_NA; }
   int               Trend(const int shift = 0) const { return (shift < m_n) ? m_trend[m_n - 1 - shift] : 0; }
  };

#endif
//+------------------------------------------------------------------+
