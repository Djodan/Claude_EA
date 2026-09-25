//+------------------------------------------------------------------+
//|                                           SignalMeanRevScalp.mqh |
//|  Mean-reversion scalp: fade short-term extremes back to the mean.|
//|                                                                  |
//|  Long : previous bar closed below the lower Bollinger band, this |
//|         bar closes back inside it, and RSI was oversold on one of|
//|         the two bars. Target = middle band (SMA). Stop below the |
//|         two-bar low + buffer. Short = mirror.                    |
//|  Meant for ranging conditions - pair it with a max-ADX regime    |
//|  filter and a liquid-session time window.                        |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALMEANREVSCALP_MQH
#define CLAUDE_SIGNALMEANREVSCALP_MQH

#include "SeriesModule.mqh"

struct SMeanRevSettings
  {
   int               bbLen;
   double            bbDev;
   int               rsiLen;
   double            rsiLow;
   double            rsiHigh;
   double            slBufAtr;       // stop buffer beyond the two-bar extreme
   double            maxSlAtr;       // skip wider setups
   double            minTpAtr;       // skip if the mean is too close (reward too small)
   int               atrLen;
   int               lookback;
  };

class CSignalMeanRevScalp : public CSeriesModule
  {
private:
   SMeanRevSettings  m_cfg;
   double            m_mid[];
   double            m_up[];
   double            m_dn[];
   double            m_rsi[];
   double            m_atr[];

   void              CalcBands(void)
     {
      CPineTA::SMA(m_close, m_n, m_cfg.bbLen, m_mid);
      ArrayResize(m_up, m_n);
      ArrayResize(m_dn, m_n);
      for(int i = 0; i < m_n; i++)
        {
         m_up[i] = m_dn[i] = PINE_NA;
         if(i < m_cfg.bbLen - 1 || CPineTA::IsNA(m_mid[i]))
            continue;
         double ss = 0.0;
         for(int k = i - m_cfg.bbLen + 1; k <= i; k++)
            ss += (m_close[k] - m_mid[i]) * (m_close[k] - m_mid[i]);
         double sd = MathSqrt(ss / m_cfg.bbLen);           // population stdev, like ta.stdev
         m_up[i] = m_mid[i] + m_cfg.bbDev * sd;
         m_dn[i] = m_mid[i] - m_cfg.bbDev * sd;
        }
     }

   ENUM_SIGNAL_DIR   DirAt(const int i, double &sl, double &tp) const
     {
      sl = tp = 0.0;
      if(i < 2 || i >= m_n || CPineTA::IsNA(m_dn[i - 1]) || CPineTA::IsNA(m_dn[i]) || CPineTA::IsNA(m_atr[i]) ||
         CPineTA::IsNA(m_rsi[i]) || CPineTA::IsNA(m_rsi[i - 1]) || m_atr[i] <= 0.0)
         return SIG_NONE;
      double atr = m_atr[i], c = m_close[i];
      ENUM_SIGNAL_DIR dir = SIG_NONE;
      if(m_close[i - 1] < m_dn[i - 1] && c > m_dn[i] && MathMin(m_rsi[i], m_rsi[i - 1]) < m_cfg.rsiLow)
        {
         dir = SIG_BUY;
         sl  = MathMin(m_low[i], m_low[i - 1]) - m_cfg.slBufAtr * atr;
         tp  = m_mid[i];
        }
      else
         if(m_close[i - 1] > m_up[i - 1] && c < m_up[i] && MathMax(m_rsi[i], m_rsi[i - 1]) > m_cfg.rsiHigh)
           {
            dir = SIG_SELL;
            sl  = MathMax(m_high[i], m_high[i - 1]) + m_cfg.slBufAtr * atr;
            tp  = m_mid[i];
           }
      if(dir == SIG_NONE)
         return SIG_NONE;
      double risk   = MathAbs(c - sl);
      double reward = MathAbs(tp - c);
      if((m_cfg.maxSlAtr > 0.0 && risk > m_cfg.maxSlAtr * atr) || reward < m_cfg.minTpAtr * atr ||
         (dir == SIG_BUY ? tp <= c : tp >= c))
         return SIG_NONE;
      return dir;
     }

public:
                     CSignalMeanRevScalp(void) : CSeriesModule("MeanRevScalp")
     {
      m_cfg.bbLen    = 20;
      m_cfg.bbDev    = 2.0;
      m_cfg.rsiLen   = 7;
      m_cfg.rsiLow   = 25.0;
      m_cfg.rsiHigh  = 75.0;
      m_cfg.slBufAtr = 0.5;
      m_cfg.maxSlAtr = 2.5;
      m_cfg.minTpAtr = 0.3;
      m_cfg.atrLen   = 14;
      m_cfg.lookback = 300;
     }

   void              Configure(const SMeanRevSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.bbLen < 5 || m_cfg.rsiLen < 2 || m_cfg.bbDev <= 0.0)
        {
         PrintFormat("%s: need BB length >= 5, BB deviation > 0, RSI length >= 2", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, (m_cfg.bbLen + m_cfg.atrLen) * 4));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();
      if(!LoadRates(m_cfg.bbLen + m_cfg.atrLen * 3))
         return false;
      CalcBands();
      CPineTA::RSI(m_close, m_n, m_cfg.rsiLen, m_rsi);
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, m_atr);
      double sl, tp;
      ENUM_SIGNAL_DIR dir = DirAt(m_n - 1, sl, tp);
      FillSignal(m_n - 1, dir, m_atr[m_n - 1], m_last);
      m_last.sl = sl;
      m_last.tp = tp;
      m_ready = true;
      return true;
     }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 2; i < m_n; i++)
        {
         double sl, tp;
         ENUM_SIGNAL_DIR dir = DirAt(i, sl, tp);
         if(dir == SIG_NONE)
            continue;
         ArrayResize(out, count + 1, 64);
         FillSignal(i, dir, m_atr[i], out[count]);
         out[count].sl   = sl;
         out[count++].tp = tp;
        }
      return count;
     }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_up[m_n - 1]))
         return "waiting for data";
      return StringFormat("BB %s / %s / %s  RSI %.0f", DoubleToString(m_dn[m_n - 1], _Digits),
                          DoubleToString(m_mid[m_n - 1], _Digits), DoubleToString(m_up[m_n - 1], _Digits), m_rsi[m_n - 1]);
     }
  };

#endif
//+------------------------------------------------------------------+
