//+------------------------------------------------------------------+
//|                                                 SeriesModule.mqh |
//|  Base for modules computed from a window of closed bars.         |
//|  Handles loading rates, time->bar lookup and filter plumbing so  |
//|  derived modules only implement their math.                      |
//|                                                                  |
//|  Derived classes implement:                                      |
//|    Update()          - LoadRates(), compute series, set m_bias   |
//|    BiasAtIndex(i)    - directional state on bar i                |
//|    AllowsAt(i, dir)  - (filters) override for non-directional    |
//|                        rules; default = BiasAtIndex(i) == dir    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SERIESMODULE_MQH
#define CLAUDE_SERIESMODULE_MQH

#include "SignalBase.mqh"
#include "../Math/PineTA.mqh"

class CSeriesModule : public CSignalModule
  {
protected:
   int               m_lookback;
   MqlRates          m_rates[];
   double            m_src[];      // hlc3
   double            m_high[];
   double            m_low[];
   double            m_close[];
   int               m_n;

   //--- load the last m_lookback closed bars (chronological)
   bool              LoadRates(const int minBars)
     {
      ArraySetAsSeries(m_rates, false);
      int copied = CopyRates(m_symbol, m_tf, 1, MathMax(m_lookback, minBars), m_rates);
      if(copied < minBars)
        {
         m_n = 0;
         return false;
        }
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
         m_src[i]   = (m_rates[i].high + m_rates[i].low + m_rates[i].close) / 3.0;
        }
      return true;
     }

   //--- last bar that had fully closed by time t (-1 if none)
   int               IndexAt(const datetime t) const
     {
      int period = PeriodSeconds(m_tf);
      for(int i = m_n - 1; i >= 0; i--)
         if(m_rates[i].time + period <= t)
            return i;
      return -1;
     }

   //--- fill a signal struct from bar i
   void              FillSignal(const int i, const ENUM_SIGNAL_DIR dir, const double atr, SSignal &s) const
     {
      s.Reset();
      s.source = m_name;
      if(i < 0 || i >= m_n)
         return;
      s.dir       = dir;
      s.barTime   = m_rates[i].time;
      s.closeTime = m_rates[i].time + PeriodSeconds(m_tf);
      s.price     = m_rates[i].close;
      s.high      = m_rates[i].high;
      s.low       = m_rates[i].low;
      s.atr       = CPineTA::IsNA(atr) ? 0.0 : atr;
     }

public:
                     CSeriesModule(const string name) : CSignalModule(name), m_lookback(500), m_n(0) {}

   void              Lookback(const int bars) { m_lookback = MathMax(50, bars); }

   virtual int       BiasAtIndex(const int i) { return 0; }
   virtual bool      AllowsAt(const int i, const ENUM_SIGNAL_DIR dir) { return BiasAtIndex(i) == (int)dir; }

   virtual int       BiasAt(const datetime t)
     {
      int i = IndexAt(t);
      return (i < 0) ? 0 : BiasAtIndex(i);
     }

   virtual bool      Allows(const ENUM_SIGNAL_DIR dir, const bool historic, const datetime t)
     {
      if(!m_ready || m_n == 0)
         return false;
      int i = historic ? IndexAt(t) : m_n - 1;
      if(i < 1)
         return false;
      return AllowsAt(i, dir);
     }
  };

#endif
//+------------------------------------------------------------------+
