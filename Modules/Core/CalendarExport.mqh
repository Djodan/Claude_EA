//+------------------------------------------------------------------+
//|                                               CalendarExport.mqh |
//|  Exports MT5 economic-calendar events to                         |
//|  Common\Files\ClaudeEA\calendar_utc.csv (UTC) so the Strategy   |
//|  Tester (no calendar access) can use them via CGuardNews.        |
//|  Runs only on a live chart.                                      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_CALENDAREXPORT_MQH
#define CLAUDE_CALENDAREXPORT_MQH

#include "../Guards/GuardNews.mqh"
#include "TimeZone.mqh"

string g_calendarExportError = "";      // last export problem (shown on the dashboard)

bool ExportCalendar(const datetime from, const datetime to)
  {
   g_calendarExportError = "";
   if(MQLInfoInteger(MQL_TESTER))
      return false;
   MqlCalendarValue values[];
   ResetLastError();
   int n = CalendarValueHistory(values, from, to);
   if(n <= 0)
     {
      g_calendarExportError = StringFormat("calendar export failed (error %d) - terminal connected?", GetLastError());
      Print("CalendarExport: " + g_calendarExportError);
      return false;
     }
   FolderCreate("ClaudeEA", FILE_COMMON);
   int h = FileOpen(CALENDAR_FILE, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE)
     {
      g_calendarExportError = StringFormat("cannot write %s (error %d)", CALENDAR_FILE, GetLastError());
      Print("CalendarExport: " + g_calendarExportError);
      return false;
     }
   FileWrite(h, "time_utc", "currency", "importance", "event");
   int written = 0;
   for(int i = 0; i < n; i++)          // values come sorted by time
     {
      MqlCalendarEvent event;
      MqlCalendarCountry country;
      if(!CalendarEventById(values[i].event_id, event) || !CalendarCountryById(event.country_id, country))
         continue;
      if(event.importance == CALENDAR_IMPORTANCE_NONE)
         continue;
      string name = event.name;
      StringReplace(name, ",", " ");
      // calendar times are in this terminal's server time -> store as UTC
      FileWrite(h, TimeToString(CTimeZone::ServerToUtc(values[i].time), TIME_DATE | TIME_MINUTES), country.currency,
                (int)event.importance, name);
      written++;
     }
   FileClose(h);
   CGuardNews::FileChanged();          // all news guards / news exits reload on their next check
   PrintFormat("CalendarExport: %d events %s - %s written to Common\\Files\\%s", written,
               TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE), CALENDAR_FILE);
   return true;
  }

#endif
//+------------------------------------------------------------------+
