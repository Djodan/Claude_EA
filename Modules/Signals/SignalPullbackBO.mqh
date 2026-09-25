//+------------------------------------------------------------------+
//|                                             SignalPullbackBO.mqh |
//|  Pullback-window breakout (intraday trend continuation).         |
//|                                                                  |
//|  1. Trend: EMA fast > EMA slow and close > EMA slow (long).      |
//|  2. Pullback: 1..maxPull consecutive counter-trend candles that  |
//|     stay above EMA slow - buffer.                                |
//|  3. Entry: the next bar closes bullish above the pullback's      |
//|     highest high. Stop below the pullback's lowest low.          |
//|  Short = mirror.                                                 |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALPULLBACKBO_MQH
#define CLAUDE_SIGNALPULLBACKBO_MQH

#include "SeriesModule.mqh"

struct SPBOSettings
  {
   int               fastLen;
   int               slowLen;
   int               maxPull;         // max counter-trend candles in the pullback
   double            depthAtr;        // pullback may dip at most this x ATR through EMA slow
   double            slBufAtr;
   double            minSlAtr;
   double            maxSlAtr;
   int               atrLen;
   int               lookback;
  };

class CSignalPullbackBO : public CSeriesModule
  {
private:
   SPBOSettings      m_cfg;
   double            m_fast[];
   double            m_slow[];
   double            m_atr[];

   bool              Bull(const int k) const { return m_close[k] > m_rates[k].open; }
   bool              Bear(const int k) const { return m_close[k] < m_rates[k].open; }

   ENUM_SIGNAL_DIR   DirAt(const int i, double &sl) const
     {
      sl = 0.0;
      if(i < m_cfg.maxPull + 2 || i >= m_n || CPineTA::IsNA(m_atr[i]) || m_atr[i] <= 0.0)
         return SIG_NONE;
      double atr = m_atr[i];
      for(int m = 1; m <= m_cfg.maxPull; m++)
        {
         int first = i - m, before = i - m - 1;
         if(CPineTA::IsNA(m_fast[before]) || CPineTA::IsNA(m_slow[before]))
            return SIG_NONE;
         double hh = -DBL_MAX, ll = DBL_MAX;
         bool allBear = true, allBull = true;
         for(int k = first; k < i; k++)
           {
            hh = MathMax(hh, m_high[k]);
            ll = MathMin(ll, m_low[k]);
            allBear = allBear && Bear(k);
            allBull = allBull && Bull(k);
           }
         //--- long
         if(allBear && Bull(before) && m_fast[before] > m_slow[before] && m_close[before] > m_slow[before] &&
            ll >= m_slow[i - 1] - m_cfg.depthAtr * atr && Bull(i) && m_close[i] > hh)
           {
            sl = ll - m_cfg.slBufAtr * atr;
            double dist = m_close[i] - sl;
            if(m_cfg.maxSlAtr > 0.0 && dist > m_cfg.maxSlAtr * atr)
               return SIG_NONE;
            if(dist < m_cfg.minSlAtr * atr)
               sl = m_close[i] - m_cfg.minSlAtr * atr;
            return SIG_BUY;
           }
         //--- short
         if(allBull && Bear(before) && m_fast[before] < m_slow[before] && m_close[before] < m_slow[before] &&
            hh <= m_slow[i - 1] + m_cfg.depthAtr * atr && Bear(i) && m_close[i] < ll)
           {
            sl = hh + m_cfg.slBufAtr * atr;
            double dist = sl - m_close[i];
            if(m_cfg.maxSlAtr > 0.0 && dist > m_cfg.maxSlAtr * atr)
               return SIG_NONE;
            if(dist < m_cfg.minSlAtr * atr)
               sl = m_close[i] + m_cfg.minSlAtr * atr;
            return SIG_SELL;
           }
        }
      return SIG_NONE;
     }

public:
                     CSignalPullbackBO(void) : CSeriesModule("PullbackBO")
     {
      m_cfg.fastLen  = 9;
      m_cfg.slowLen  = 21;
      m_cfg.maxPull  = 3;
      m_cfg.depthAtr = 0.5;
      m_cfg.slBufAtr = 0.1;
      m_cfg.minSlAtr = 0.8;
      m_cfg.maxSlAtr = 3.0;
      m_cfg.atrLen   = 14;
      m_cfg.lookback = 400;
     }

   void              Configure(const SPBOSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.fastLen < 2 || m_cfg.slowLen <= m_cfg.fastLen || m_cfg.maxPull < 1)
        {
         PrintFormat("%s: need 2 <= fast < slow and max pullback >= 1", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, m_cfg.slowLen * 6));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();
      if(!LoadRates(m_cfg.slowLen * 3))
         return false;
      CPineTA::EMA(m_close, m_n, m_cfg.fastLen, m_fast);
      CPineTA::EMA(m_close, m_n, m_cfg.slowLen, m_slow);
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, m_atr);
      double sl;
      ENUM_SIGNAL_DIR dir = DirAt(m_n - 1, sl);
      FillSignal(m_n - 1, dir, m_atr[m_n - 1], m_last);
      m_last.sl = sl;
      m_bias  = BiasAtIndex(m_n - 1);
      m_ready = true;
      return true;
     }

   virtual int       BiasAtIndex(const int i)
     {
      if(i < 0 || i >= m_n || CPineTA::IsNA(m_fast[i]) || CPineTA::IsNA(m_slow[i]))
         return 0;
      return m_fast[i] > m_slow[i] ? 1 : (m_fast[i] < m_slow[i] ? -1 : 0);
     }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 1; i < m_n; i++)
        {
         double sl;
         ENUM_SIGNAL_DIR dir = DirAt(i, sl);
         if(dir == SIG_NONE)
            continue;
         ArrayResize(out, count + 1, 64);
         FillSignal(i, dir, m_atr[i], out[count]);
         out[count++].sl = sl;
        }
      return count;
     }

   virtual string    Status(void)
     {
      if(!m_ready)
         return "waiting for data";
      return StringFormat("EMA%d/%d trend %s", m_cfg.fastLen, m_cfg.slowLen, CSignalModule::Status());
     }
  };

#endif
//+------------------------------------------------------------------+
