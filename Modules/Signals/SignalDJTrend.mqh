//+------------------------------------------------------------------+
//|                                                SignalDJTrend.mqh |
//|  Port of the "DJ Trend - Claude" Pine v6 indicator.              |
//|                                                                  |
//|  basis = MA(hlc3, len)  (EMA / SMA / HMA / ALMA)                 |
//|  trend flips to +1 when close > basis + mult*ATR                 |
//|  trend flips to -1 when close < basis - mult*ATR                 |
//|  BUY  when trend becomes +1, SELL when trend becomes -1          |
//|  Only closed bars are used, so signals never repaint.            |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALDJTREND_MQH
#define CLAUDE_SIGNALDJTREND_MQH

#include "SignalBase.mqh"
#include "../Math/PineTA.mqh"

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

class CSignalDJTrend : public CSignalModule
  {
private:
   SDJTrendSettings  m_cfg;
   MqlRates          m_rates[];
   double            m_src[];
   double            m_high[];
   double            m_low[];
   double            m_close[];
   double            m_basis[];
   double            m_atr[];
   int               m_trend[];
   int               m_n;

   int               MinBars(void) const
     {
      return MathMax(m_cfg.basisLen, m_cfg.atrLen) * 2 + 2;
     }

   void              CalcBasis(void)
     {
      switch(m_cfg.basisType)
        {
         case BASIS_SMA:
            CPineTA::SMA(m_src, m_n, m_cfg.basisLen, m_basis);
            break;
         case BASIS_HMA:
            CPineTA::HMA(m_src, m_n, m_cfg.basisLen, m_basis);
            break;
         case BASIS_ALMA:
            CPineTA::ALMA(m_src, m_n, m_cfg.basisLen, m_cfg.almaOffset, m_cfg.almaSigma, m_basis);
            break;
         default:
            CPineTA::EMA(m_src, m_n, m_cfg.basisLen, m_basis);
            break;
        }
     }

   //--- signal event on bar i (chronological index)
   void              SignalAt(const int i, SSignal &s) const
     {
      s.Reset();
      s.source = m_name;
      if(i < 1 || i >= m_n)
         return;
      int cur  = m_trend[i];
      int prev = m_trend[i - 1];
      if(cur == 1 && prev != 1)
         s.dir = SIG_BUY;
      else
         if(cur == -1 && prev != -1)
            s.dir = SIG_SELL;
      s.barTime   = m_rates[i].time;
      s.closeTime = m_rates[i].time + PeriodSeconds(m_tf);
      s.price     = m_rates[i].close;
      s.high      = m_rates[i].high;
      s.low       = m_rates[i].low;
      s.atr       = CPineTA::IsNA(m_atr[i]) ? 0.0 : m_atr[i];
     }

public:
                     CSignalDJTrend(void) : CSignalModule("DJTrend"), m_n(0)
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
      CSignalModule::Init(symbol, tf);
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
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();

      ArraySetAsSeries(m_rates, false);
      int copied = CopyRates(m_symbol, m_tf, 1, m_cfg.lookback, m_rates);   // closed bars only
      if(copied < MinBars())
         return false;
      m_n = copied;

      ArrayResize(m_src, m_n);
      ArrayResize(m_high, m_n);
      ArrayResize(m_low, m_n);
      ArrayResize(m_close, m_n);
      for(int i = 0; i < m_n; i++)
        {
         m_high[i]  = m_rates[i].high;
         m_low[i]   = m_rates[i].low;
         m_close[i] = m_rates[i].close;
         m_src[i]   = (m_rates[i].high + m_rates[i].low + m_rates[i].close) / 3.0;   // hlc3
        }

      CalcBasis();
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
      SignalAt(m_n - 1, m_last);
      m_ready = true;
      return true;
     }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 1; i < m_n; i++)
        {
         SSignal s;
         SignalAt(i, s);
         if(s.dir == SIG_NONE)
            continue;
         ArrayResize(out, count + 1, 64);
         out[count++] = s;
        }
      return count;
     }

   //--- trend of the last bar that had fully closed by time t
   virtual int       BiasAt(const datetime t)
     {
      int period = PeriodSeconds(m_tf);
      for(int i = m_n - 1; i >= 0; i--)
         if(m_rates[i].time + period <= t)
            return m_trend[i];
      return 0;
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
