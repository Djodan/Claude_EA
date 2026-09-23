//+------------------------------------------------------------------+
//|                                          SignalTrendPullback.mqh |
//|  Trend pullback: trade with the EMA trend after an RSI dip.      |
//|  Long : EMA fast > EMA slow, close > EMA slow, RSI crosses back  |
//|         up through rsiLow (dip is over)                          |
//|  Short: mirror, RSI crosses back down through rsiHigh            |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALTRENDPULLBACK_MQH
#define CLAUDE_SIGNALTRENDPULLBACK_MQH

#include "SeriesModule.mqh"

struct SPullbackSettings
  {
   int               fastLen;
   int               slowLen;
   int               rsiLen;
   double            rsiLow;
   double            rsiHigh;
   int               atrLen;
   int               lookback;
  };

class CSignalTrendPullback : public CSeriesModule
  {
private:
   SPullbackSettings m_cfg;
   double            m_fast[];
   double            m_slow[];
   double            m_rsi[];
   double            m_atr[];

   ENUM_SIGNAL_DIR   DirAt(const int i) const
     {
      if(i < 1 || i >= m_n)
         return SIG_NONE;
      if(CPineTA::IsNA(m_fast[i]) || CPineTA::IsNA(m_slow[i]) || CPineTA::IsNA(m_rsi[i]) || CPineTA::IsNA(m_rsi[i - 1]))
         return SIG_NONE;
      if(m_fast[i] > m_slow[i] && m_close[i] > m_slow[i] && m_rsi[i - 1] < m_cfg.rsiLow && m_rsi[i] >= m_cfg.rsiLow)
         return SIG_BUY;
      if(m_fast[i] < m_slow[i] && m_close[i] < m_slow[i] && m_rsi[i - 1] > m_cfg.rsiHigh && m_rsi[i] <= m_cfg.rsiHigh)
         return SIG_SELL;
      return SIG_NONE;
     }

public:
                     CSignalTrendPullback(void) : CSeriesModule("Pullback")
     {
      m_cfg.fastLen  = 50;
      m_cfg.slowLen  = 200;
      m_cfg.rsiLen   = 14;
      m_cfg.rsiLow   = 40.0;
      m_cfg.rsiHigh  = 60.0;
      m_cfg.atrLen   = 14;
      m_cfg.lookback = 800;
     }

   void              Configure(const SPullbackSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(m_cfg.fastLen < 2 || m_cfg.slowLen <= m_cfg.fastLen || m_cfg.rsiLen < 2)
        {
         PrintFormat("%s: need 2 <= fast < slow and RSI len >= 2", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, m_cfg.slowLen * 4));
      return true;
     }

   virtual bool      Update(void)
     {
      m_ready = false;
      m_bias  = 0;
      m_last.Reset();
      if(!LoadRates(m_cfg.slowLen * 2))
         return false;
      CPineTA::EMA(m_close, m_n, m_cfg.fastLen, m_fast);
      CPineTA::EMA(m_close, m_n, m_cfg.slowLen, m_slow);
      CPineTA::RSI(m_close, m_n, m_cfg.rsiLen, m_rsi);
      CPineTA::ATR(m_high, m_low, m_close, m_n, m_cfg.atrLen, m_atr);
      m_bias = BiasAtIndex(m_n - 1);
      FillSignal(m_n - 1, DirAt(m_n - 1), m_atr[m_n - 1], m_last);
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
         ENUM_SIGNAL_DIR dir = DirAt(i);
         if(dir == SIG_NONE)
            continue;
         ArrayResize(out, count + 1, 64);
         FillSignal(i, dir, m_atr[i], out[count++]);
        }
      return count;
     }

   virtual string    Status(void)
     {
      if(!m_ready || CPineTA::IsNA(m_rsi[m_n - 1]))
         return "waiting for data";
      return StringFormat("trend %s  RSI %.1f", CSignalModule::Status(), m_rsi[m_n - 1]);
     }
  };

#endif
//+------------------------------------------------------------------+
