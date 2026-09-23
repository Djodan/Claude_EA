//+------------------------------------------------------------------+
//|                                        SignalSessionBreakout.mqh |
//|  Session range breakout (e.g. Asian range -> London/NY move).    |
//|                                                                  |
//|  Each server day: range = high/low of bars opening inside        |
//|  [rangeStart, rangeEnd). After rangeEnd and before tradeEnd, the |
//|  first bar that CLOSES beyond the range +/- buffer x ATR fires.  |
//|  Suggested stop: opposite side of the range, or its midpoint.    |
//|  All times are REFERENCE time (GMT+2/+3, see TimeZone.mqh).      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALSESSIONBREAKOUT_MQH
#define CLAUDE_SIGNALSESSIONBREAKOUT_MQH

#include "SeriesModule.mqh"
#include "../Core/TimeZone.mqh"

enum ENUM_BRK_STOP
  {
   BRK_STOP_RANGE,   // Opposite side of range
   BRK_STOP_MID      // Range midpoint
  };

struct SBreakoutSettings
  {
   int               rangeStartHour;
   int               rangeStartMin;
   int               rangeEndHour;
   int               rangeEndMin;
   int               tradeEndHour;      // no new breakouts after this time
   int               tradeEndMin;
   double            bufferAtr;         // close must clear the range by this x ATR
   double            minRangeAtr;       // skip days with a range narrower than this x ATR (0 = off)
   double            maxRangeAtr;       // skip days with a range wider than this x ATR (0 = off)
   double            maxRangeD1;        // skip days with a range wider than this x daily ATR (0 = off)
   double            minRangeD1;        // skip days with a range narrower than this x daily ATR (0 = off)
   int               atrLen;
   ENUM_BRK_STOP     stopMode;
   bool              oneTradePerDay;    // only the first breakout of the day, either side
   int               lookback;
  };

class CSignalSessionBreakout : public CSeriesModule
  {
private:
   SBreakoutSettings m_cfg;
   double            m_atr[];
   double            m_lastHigh;
   double            m_lastLow;
   double            m_d1Atr;           // ATR(14) of closed daily bars

   void              UpdateDailyAtr(void)
     {
      MqlRates d1[];
      ArraySetAsSeries(d1, false);
      int n = CopyRates(m_symbol, PERIOD_D1, 1, 60, d1);
      m_d1Atr = 0.0;
      if(n < 20)
         return;
      double h[], l[], c[], atr[];
      ArrayResize(h, n);
      ArrayResize(l, n);
      ArrayResize(c, n);
      for(int i = 0; i < n; i++)
        {
         h[i] = d1[i].high;
         l[i] = d1[i].low;
         c[i] = d1[i].close;
        }
      CPineTA::ATR(h, l, c, n, 14, atr);
      if(!CPineTA::IsNA(atr[n - 1]))
         m_d1Atr = atr[n - 1];
     }

   //--- day / minute of day in reference time (bar times are server time)
   static datetime   Day(const datetime t)            { datetime r = CTimeZone::ServerToRef(t); return r - r % 86400; }
   static int        MinuteOfDay(const datetime t)    { datetime r = CTimeZone::ServerToRef(t); return (int)((r % 86400) / 60); }
   int               RangeStart(void) const           { return m_cfg.rangeStartHour * 60 + m_cfg.rangeStartMin; }
   int               RangeEnd(void) const             { return m_cfg.rangeEndHour * 60 + m_cfg.rangeEndMin; }
   int               TradeEnd(void) const             { return m_cfg.tradeEndHour * 60 + m_cfg.tradeEndMin; }

   //--- today's range as of bar i (false if no range bars)
   bool              RangeFor(const int i, double &hi, double &lo) const
     {
      datetime day = Day(m_rates[i].time);
      hi = -DBL_MAX;
      lo = DBL_MAX;
      int count = 0;
      for(int j = i; j >= 0 && Day(m_rates[j].time) == day; j--)
        {
         int m = MinuteOfDay(m_rates[j].time);
         if(m >= RangeStart() && m < RangeEnd())
           {
            hi = MathMax(hi, m_rates[j].high);
            lo = MathMin(lo, m_rates[j].low);
            count++;
           }
        }
      return count > 0;
     }

   //--- breakout on bar i? sets the suggested stop
   ENUM_SIGNAL_DIR   Evaluate(const int i, double &sl) const
     {
      sl = 0.0;
      if(i < 1 || i >= m_n)
         return SIG_NONE;
      int m = MinuteOfDay(m_rates[i].time);
      if(m < RangeEnd() || m >= TradeEnd())
         return SIG_NONE;
      double hi, lo;
      if(!RangeFor(i, hi, lo))
         return SIG_NONE;
      double atr = m_atr[i];
      if(CPineTA::IsNA(atr) || atr <= 0.0)
         return SIG_NONE;
      double width = hi - lo;
      if(m_cfg.minRangeAtr > 0.0 && width < m_cfg.minRangeAtr * atr)
         return SIG_NONE;
      if(m_cfg.maxRangeAtr > 0.0 && width > m_cfg.maxRangeAtr * atr)
         return SIG_NONE;
      if(m_d1Atr > 0.0 && m_cfg.maxRangeD1 > 0.0 && width > m_cfg.maxRangeD1 * m_d1Atr)
         return SIG_NONE;
      if(m_d1Atr > 0.0 && m_cfg.minRangeD1 > 0.0 && width < m_cfg.minRangeD1 * m_d1Atr)
         return SIG_NONE;

      double up = hi + m_cfg.bufferAtr * atr;
      double dn = lo - m_cfg.bufferAtr * atr;
      ENUM_SIGNAL_DIR dir = m_close[i] > up ? SIG_BUY : (m_close[i] < dn ? SIG_SELL : SIG_NONE);
      if(dir == SIG_NONE)
         return SIG_NONE;

      // only the first qualifying close after the range
      datetime day = Day(m_rates[i].time);
      for(int j = i - 1; j >= 0 && Day(m_rates[j].time) == day; j--)
        {
         if(MinuteOfDay(m_rates[j].time) < RangeEnd())
            break;
         bool brokeUp = m_close[j] > up, brokeDn = m_close[j] < dn;
         if(m_cfg.oneTradePerDay && (brokeUp || brokeDn))
            return SIG_NONE;
         if((dir == SIG_BUY && brokeUp) || (dir == SIG_SELL && brokeDn))
            return SIG_NONE;
        }

      if(m_cfg.stopMode == BRK_STOP_MID)
         sl = (hi + lo) / 2.0;
      else
         sl = (dir == SIG_BUY) ? lo : hi;
      return dir;
     }

public:
                     CSignalSessionBreakout(void) : CSeriesModule("Breakout"), m_lastHigh(0.0), m_lastLow(0.0), m_d1Atr(0.0)
     {
      m_cfg.rangeStartHour = 1;
      m_cfg.rangeStartMin  = 0;
      m_cfg.rangeEndHour   = 9;
      m_cfg.rangeEndMin    = 0;
      m_cfg.tradeEndHour   = 17;
      m_cfg.tradeEndMin    = 0;
      m_cfg.bufferAtr      = 0.1;
      m_cfg.minRangeAtr    = 1.5;
      m_cfg.maxRangeAtr    = 12.0;
      m_cfg.maxRangeD1     = 0.0;
      m_cfg.minRangeD1     = 0.0;
      m_cfg.atrLen         = 14;
      m_cfg.stopMode       = BRK_STOP_RANGE;
      m_cfg.oneTradePerDay = true;
      m_cfg.lookback       = 400;
     }

   void              Configure(const SBreakoutSettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      CSeriesModule::Init(symbol, tf);
      if(RangeEnd() <= RangeStart() || TradeEnd() <= RangeEnd())
        {
         PrintFormat("%s: need range start < range end < trade end (reference time)", m_name);
         return false;
        }
      Lookback(MathMax(m_cfg.lookback, 86400 / MathMax(60, PeriodSeconds(m_tf)) * 3));
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
      UpdateDailyAtr();

      double sl;
      ENUM_SIGNAL_DIR dir = Evaluate(m_n - 1, sl);
      FillSignal(m_n - 1, dir, m_atr[m_n - 1], m_last);
      m_last.sl = sl;

      double hi, lo;
      if(RangeFor(m_n - 1, hi, lo) && MinuteOfDay(m_rates[m_n - 1].time) >= RangeEnd())
        {
         m_lastHigh = hi;
         m_lastLow  = lo;
         m_bias = m_close[m_n - 1] > hi ? 1 : (m_close[m_n - 1] < lo ? -1 : 0);
        }
      m_ready = true;
      return true;
     }

   virtual int       BiasAtIndex(const int i)
     {
      double hi, lo;
      if(i < 0 || i >= m_n || !RangeFor(i, hi, lo))
         return 0;
      return m_close[i] > hi ? 1 : (m_close[i] < lo ? -1 : 0);
     }

   virtual int       History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 1; i < m_n; i++)
        {
         double sl;
         ENUM_SIGNAL_DIR dir = Evaluate(i, sl);
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
      if(m_lastHigh <= 0.0)
         return StringFormat("range %02d:%02d-%02d:%02d building", m_cfg.rangeStartHour, m_cfg.rangeStartMin,
                             m_cfg.rangeEndHour, m_cfg.rangeEndMin);
      return StringFormat("range %s - %s (%.2f x D1 ATR)  %s", DoubleToString(m_lastLow, _Digits),
                          DoubleToString(m_lastHigh, _Digits), m_d1Atr > 0.0 ? (m_lastHigh - m_lastLow) / m_d1Atr : 0.0,
                          CSignalModule::Status());
     }
  };

#endif
//+------------------------------------------------------------------+
