//+------------------------------------------------------------------+
//|                                                    GuardNews.mqh |
//|  Blocks new entries from minutesBefore to minutesAfter around    |
//|  economic-calendar events of the chosen currencies/importance.   |
//|                                                                  |
//|  Events come from Common\Files\ClaudeEA\calendar_utc.csv (UTC,   |
//|  any broker), written by CalendarExport on a live chart          |
//|  chart - the Strategy Tester has no calendar access of its own.  |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDNEWS_MQH
#define CLAUDE_GUARDNEWS_MQH

#include "GuardBase.mqh"
#include "../Core/TimeZone.mqh"

#define CALENDAR_FILE "ClaudeEA\\calendar_utc.csv"   // event times in UTC

struct SGuardNewsSettings
  {
   string            currencies;      // e.g. "USD" or "USD,EUR"
   int               minImportance;   // 1 low, 2 moderate, 3 high
   int               minutesBefore;
   int               minutesAfter;
   string            exclude;         // comma-separated name fragments to ignore, e.g. "Crude Oil"
  };

class CGuardNews : public CGuard
  {
private:
   SGuardNewsSettings m_cfg;
   datetime          m_times[];
   string            m_names[];
   int               m_count;
   int               m_idx;          // first event that may still matter (time only moves forward)

   bool              Excluded(const string ev) const
     {
      string parts[];
      int n = StringSplit(m_cfg.exclude, ',', parts);
      for(int i = 0; i < n; i++)
        {
         string p = parts[i];
         StringTrimLeft(p);
         StringTrimRight(p);
         if(p != "" && StringFind(ev, p) >= 0)
            return true;
        }
      return false;
     }

   bool              Load(void)
     {
      m_count = 0;
      int h = FileOpen(CALENDAR_FILE, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
      if(h == INVALID_HANDLE)
         return false;
      // header: time_utc,currency,importance,event
      for(int k = 0; k < 4 && !FileIsEnding(h); k++)
         FileReadString(h);
      while(!FileIsEnding(h))
        {
         string t   = FileReadString(h);
         string cur = FileReadString(h);
         int    imp = (int)StringToInteger(FileReadString(h));
         string ev  = FileReadString(h);
         if(t == "")
            continue;
         if(imp < m_cfg.minImportance || StringFind(m_cfg.currencies, cur) < 0 || Excluded(ev))
            continue;
         ArrayResize(m_times, m_count + 1, 256);
         ArrayResize(m_names, m_count + 1, 256);
         m_times[m_count] = StringToTime(t);
         m_names[m_count] = cur + " " + ev;
         m_count++;
        }
      FileClose(h);
      return true;
     }

public:
                     CGuardNews(void) : CGuard("News"), m_count(0), m_idx(0)
     {
      m_cfg.currencies    = "USD";
      m_cfg.minImportance = 3;
      m_cfg.minutesBefore = 30;
      m_cfg.minutesAfter  = 30;
      m_cfg.exclude       = "Crude Oil";
     }

   void              Configure(const SGuardNewsSettings &cfg) { m_cfg = cfg; }
   int               Events(void) const { return m_count; }

   virtual bool      Init(const string symbol, const ulong magic)
     {
      CGuard::Init(symbol, magic);
      if(!Load())
         PrintFormat("%s: %s not found - run the EA once on a live chart to export the calendar. Guard inactive.",
                     m_name, CALENDAR_FILE);
      else
         PrintFormat("%s: %d events loaded (%s, importance >= %d)", m_name, m_count, m_cfg.currencies, m_cfg.minImportance);
      m_idx = 0;
      return true;
     }

   virtual bool      CanOpen(void)
     {
      if(m_count == 0)
        {
         m_status = "no calendar data";
         return true;
        }
      datetime now = CTimeZone::ServerToUtc(TimeCurrent());
      if(m_idx > 0 && m_idx < m_count && m_times[m_idx - 1] + m_cfg.minutesAfter * 60 >= now)
         m_idx--;                      // tolerate small time steps back (e.g. dashboard vs. tick)
      while(m_idx < m_count && m_times[m_idx] + m_cfg.minutesAfter * 60 < now)
         m_idx++;
      if(m_idx >= m_count)
        {
         m_status = "no upcoming events";
         return true;
        }
      if(now >= m_times[m_idx] - m_cfg.minutesBefore * 60)
        {
         m_status = m_names[m_idx] + " " + TimeToString(CTimeZone::UtcToServer(m_times[m_idx]), TIME_MINUTES);
         return false;
        }
      m_status = "next " + m_names[m_idx] + " " + TimeToString(CTimeZone::UtcToServer(m_times[m_idx]), TIME_DATE | TIME_MINUTES);
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
