//+------------------------------------------------------------------+
//|                                                GuardActivity.mqh |
//|  Per-pair activity filter from the symbol's own tick volume.     |
//|                                                                  |
//|  Builds an hour-of-day volume profile (reference time) from the  |
//|  last N days of H1 bars and allows entries only in hours whose   |
//|  average volume is >= min x the pair's mean hourly volume.       |
//|  Gold, EURUSD and USDJPY each get their own active hours without |
//|  any session settings.                                           |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDACTIVITY_MQH
#define CLAUDE_GUARDACTIVITY_MQH

#include "GuardBase.mqh"
#include "../Core/TimeZone.mqh"

class CGuardActivity : public CGuard
  {
private:
   double            m_min;        // hour volume / mean hourly volume
   int               m_days;
   double            m_prof[24];
   double            m_mean;
   datetime          m_built;

   void              Build(void)
     {
      m_built = TimeCurrent();
      m_mean  = 0.0;
      ArrayInitialize(m_prof, 0.0);
      MqlRates r[];
      int n = CopyRates(m_symbol, PERIOD_H1, 1, m_days * 24, r);
      if(n < 48)
         return;
      int cnt[24];
      ArrayInitialize(cnt, 0);
      for(int i = 0; i < n; i++)
        {
         int h = (int)((CTimeZone::ServerToRef(r[i].time) % 86400) / 3600);
         m_prof[h] += (double)r[i].tick_volume;
         cnt[h]++;
        }
      int hours = 0;
      for(int h = 0; h < 24; h++)
         if(cnt[h] > 0)
           {
            m_prof[h] /= cnt[h];
            m_mean += m_prof[h];
            hours++;
           }
      if(hours > 0)
         m_mean /= hours;
     }

public:
                     CGuardActivity(void) : CGuard("Activity"), m_min(0.8), m_days(20), m_mean(0.0), m_built(0)
     {
      ArrayInitialize(m_prof, 0.0);
     }

   void              Configure(const double minRatio, const int days)
     {
      m_min  = minRatio;
      m_days = MathMax(days, 3);
     }

   //--- current hour's volume vs the pair's mean hour (1.0 = average)
   double            Ratio(void)
     {
      if(TimeCurrent() - m_built >= 86400 || m_mean <= 0.0)
         Build();
      if(m_mean <= 0.0)
         return 1.0;
      int h = (int)((CTimeZone::ServerToRef(TimeCurrent()) % 86400) / 3600);
      return m_prof[h] / m_mean;
     }

   virtual bool      CanOpen(void)
     {
      double r = Ratio();
      m_status = m_mean <= 0.0 ? "no H1 history yet - allowed"
                 : StringFormat("hour volume %.2f x mean (min %.2f) %s", r, m_min, r >= m_min ? "ACTIVE" : "quiet");
      return m_mean <= 0.0 || r >= m_min;
     }
  };

#endif
//+------------------------------------------------------------------+
