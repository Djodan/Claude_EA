//+------------------------------------------------------------------+
//|                                          SignalMomentumScalp.mqh |
//|  Momentum-burst scalp: ride a strong impulse candle.             |
//|                                                                  |
//|  Long : body >= bodyAtr x ATR (ATR of the bars before it) and the|
//|         close is in the top (1 - closePct) of the candle's range.|
//|  Stop at the impulse candle's low (or its midpoint), buffer and  |
//|  [min, max] x ATR clamps. Short = mirror.                        |
//|  Pair it with a higher-TF trend filter and a session window.     |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALMOMENTUMSCALP_MQH
#define CLAUDE_SIGNALMOMENTUMSCALP_MQH

#include "SeriesModule.mqh"

enum ENUM_IMPULSE_STOP
  {
   IMPULSE_STOP_EXTREME,   // Impulse candle's far end
   IMPULSE_STOP_MID        // Impulse candle's midpoint
  };

struct SMomentumSettings
  {
   double            bodyAtr;        // impulse body >= this x ATR
   double            closePct;       // close in the outer part of the range, e.g. 0.75 = top 25%
   ENUM_IMPULSE_STOP stopMode;
   double            slBufAtr;
   double            minSlAtr;
   double            maxSlAtr;
   int               atrLen;
   int               lookback;
  };

class CSignalMomentumScalp : public CSeriesModule
  {
private:
   SMomentumSettings m_cfg;
   double            m_atr[];

   ENUM_SIGNAL_DIR   DirAt(const int i, double &sl) const
     {
      sl = 0.0;
      if(i < 2 || i >= m_n || CPineTA::IsNA(m_atr[i - 1]) || m_atr[i - 1] <= 0.0)
         return SIG_NONE;
      double atr = m_atr[i - 1];                        // volatility before the impulse
      double o = m_rates[i].open, c = m_close[i], h = m_high[i], l = m_low[i];
      double range = h - l;
      if(range <= 0.0 || MathAbs(c - o) < m_cfg.bodyAtr * atr)
         return SIG_NONE;
      ENUM_SIGNAL_DIR dir = SIG_NONE;
      if(c > o && (c - l) / range >= m_cfg.closePct)
        {
         dir = SIG_BUY;
         sl  = (m_cfg.stopMode == IMPULSE_STOP_MID ? (h + l) / 2.0 : l) - m_cfg.slBufAtr * atr;
        }
      else
         if(c < o && (h - c) / range >= m_cfg.closePct)
           {
            dir = SIG_SELL;
            sl  = (m_cfg.stopMode == IMPULSE_STOP_MID ? (h + l) / 2.0 : h) + m_cfg.slBufAtr * atr;
           }
      if(dir == SIG_NONE)
         return SIG_NONE;
      double risk = MathAbs(c - sl);
      if(m_cfg.maxSlAtr > 0.0 && risk > m_cfg.maxSlAtr * atr)
         return SIG_NONE;
      if(risk < m_cfg.minSlAtr * atr)
         sl = (dir == SIG_BUY) ? c - m_cfg.minSlAtr * atr : c + m_cfg.minSlAtr * atr;
      return dir;
     }

public:
                     CSignalMomentumScalp(void) : CSeriesModule("MomentumScalp")
     {
      m_cfg.bodyAtr  = 1.2;
      m_cfg.closePct = 0.75;
      m_cfg.stopMode = IMPULSE_STOP_MID;
      m_cfg.slBufAtr = 0.1;
      m_cfg.minSlAtr = 0.5;
      m_cfg.maxSlAtr = 2.5;
      m_cfg.atrLen   = 14;
      m_cfg.lookback = 200;
     }

   void              Configure(const SMomentumSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      Lookback(MathMax(m_cfg.lookback, m_cfg.atrLen * 6));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();
      if(!LoadRates(m_cfg.atrLen * 3))
         return false;
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, m_atr);
      double sl;
      ENUM_SIGNAL_DIR dir = DirAt(m_n - 1, sl);
      FillSignal(m_n - 1, dir, m_atr[m_n - 1], m_last);
      m_last.sl = sl;
      m_ready = true;
      return true;
     }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 2; i < m_n; i++)
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
      return StringFormat("impulse >= %.1f ATR (ATR %s)", m_cfg.bodyAtr, DoubleToString(m_atr[m_n - 1], _Digits));
     }
  };

#endif
//+------------------------------------------------------------------+
