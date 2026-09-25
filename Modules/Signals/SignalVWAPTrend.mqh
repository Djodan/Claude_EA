//+------------------------------------------------------------------+
//|                                              SignalVWAPTrend.mqh |
//|  Intraday VWAP trend pullback.                                   |
//|                                                                  |
//|  Session VWAP (tick-volume weighted typical price) resets every  |
//|  day at the anchor time (reference time). Long when price is     |
//|  above VWAP and a bar dips to within touchAtr x ATR of VWAP and  |
//|  closes bullish back above it; short = mirror. Stop below the    |
//|  pullback bar (buffer), clamped to [minSl, maxSl] x ATR.         |
//|  Combine with a higher-TF trend filter and a time-window filter. |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALVWAPTREND_MQH
#define CLAUDE_SIGNALVWAPTREND_MQH

#include "SeriesModule.mqh"
#include "../Core/TimeZone.mqh"

struct SVWAPSettings
  {
   int               anchorHour;      // VWAP reset, reference time
   int               anchorMin;
   double            touchAtr;        // pullback must come within this x ATR of VWAP
   double            slBufAtr;        // stop buffer beyond the pullback bar
   double            minSlAtr;
   double            maxSlAtr;        // skip if the stop would be wider
   int               atrLen;
   int               lookback;
  };

class CSignalVWAPTrend : public CSeriesModule
  {
private:
   SVWAPSettings     m_cfg;
   double            m_vwap[];
   double            m_atr[];

   //--- session id: reference day shifted by the anchor, so a session runs anchor -> anchor
   long              SessionId(const datetime t) const
     {
      datetime r = CTimeZone::ServerToRef(t) - (m_cfg.anchorHour * 60 + m_cfg.anchorMin) * 60;
      return (long)(r / 86400);
     }

   void              CalcVWAP(void)
     {
      ArrayResize(m_vwap, m_n);
      long   sid = -1;
      double sPV = 0.0, sV = 0.0;
      for(int i = 0; i < m_n; i++)
        {
         long id = SessionId(m_rates[i].time);
         if(id != sid)
           {
            sid = id;
            sPV = 0.0;
            sV  = 0.0;
           }
         double v = (double)MathMax(1, m_rates[i].tick_volume);
         sPV += m_src[i] * v;
         sV  += v;
         m_vwap[i] = sPV / sV;
        }
     }

   ENUM_SIGNAL_DIR   DirAt(const int i, double &sl) const
     {
      sl = 0.0;
      if(i < 2 || i >= m_n || CPineTA::IsNA(m_atr[i]) || m_atr[i] <= 0.0)
         return SIG_NONE;
      if(SessionId(m_rates[i].time) != SessionId(m_rates[i - 1].time))
         return SIG_NONE;                                // first bar of a session: VWAP not meaningful
      double atr = m_atr[i], vw = m_vwap[i];
      double o = m_rates[i].open, c = m_close[i], h = m_high[i], l = m_low[i];
      ENUM_SIGNAL_DIR dir = SIG_NONE;
      if(c > vw && c > o && l <= vw + m_cfg.touchAtr * atr && m_close[i - 1] > m_vwap[i - 1] - m_cfg.touchAtr * atr)
        {
         dir = SIG_BUY;
         sl  = MathMin(l, vw) - m_cfg.slBufAtr * atr;
        }
      else
         if(c < vw && c < o && h >= vw - m_cfg.touchAtr * atr && m_close[i - 1] < m_vwap[i - 1] + m_cfg.touchAtr * atr)
           {
            dir = SIG_SELL;
            sl  = MathMax(h, vw) + m_cfg.slBufAtr * atr;
           }
      if(dir == SIG_NONE)
         return SIG_NONE;
      double dist = MathAbs(c - sl);
      if(m_cfg.maxSlAtr > 0.0 && dist > m_cfg.maxSlAtr * atr)
         return SIG_NONE;
      if(dist < m_cfg.minSlAtr * atr)
         sl = (dir == SIG_BUY) ? c - m_cfg.minSlAtr * atr : c + m_cfg.minSlAtr * atr;
      return dir;
     }

public:
                     CSignalVWAPTrend(void) : CSeriesModule("VWAPTrend")
     {
      m_cfg.anchorHour = 1;
      m_cfg.anchorMin  = 0;
      m_cfg.touchAtr   = 0.2;
      m_cfg.slBufAtr   = 0.3;
      m_cfg.minSlAtr   = 0.8;
      m_cfg.maxSlAtr   = 3.0;
      m_cfg.atrLen     = 14;
      m_cfg.lookback   = 500;
     }

   void              Configure(const SVWAPSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      // at least one full session plus warm-up
      Lookback(MathMax(m_cfg.lookback, 86400 / MathMax(60, PeriodSeconds(m_tf)) + m_cfg.atrLen * 3));
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
      CalcVWAP();
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
      if(i < 0 || i >= m_n)
         return 0;
      return m_close[i] > m_vwap[i] ? 1 : (m_close[i] < m_vwap[i] ? -1 : 0);
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
      return StringFormat("VWAP %s  price %s  %s", DoubleToString(m_vwap[m_n - 1], _Digits),
                          DoubleToString(m_close[m_n - 1], _Digits), CSignalModule::Status());
     }
  };

#endif
//+------------------------------------------------------------------+
