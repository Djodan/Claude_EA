//+------------------------------------------------------------------+
//|                                           ManageWeekendClose.mqh |
//|  Flat before the weekend: close on Friday at a reference hour,   |
//|  or 5 min before the broker's Friday session end if earlier.     |
//|  Stops swing strategies (S1, S3) from eating a Monday gap, which |
//|  can blow past the stop and break the prop 1% loss rule.         |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGEWEEKENDCLOSE_MQH
#define CLAUDE_MANAGEWEEKENDCLOSE_MQH

#include "PositionModule.mqh"
#include "../Core/TimeZone.mqh"

class CManageWeekendClose : public CPositionModule
  {
private:
   int               m_closeMinute;   // Friday minute of day, reference time
   int               m_beforeEndMin;

   int               FridayEnd(void) const
     {
      datetime from, to;
      int end = -1;
      for(uint s = 0; SymbolInfoSessionTrade(m_symbol, FRIDAY, s, from, to); s++)
         end = MathMax(end, (int)(to % 86400 == 0 && to > 0 ? 86400 : to % 86400));
      return end;
     }

public:
                     CManageWeekendClose(void) : CPositionModule("WeekendClose"), m_closeMinute(22 * 60), m_beforeEndMin(5) {}

   void              Configure(const int hour) { m_closeMinute = hour * 60; }

   virtual void      Manage(SPosition &pos)
     {
      datetime ref = CTimeZone::ServerToRef(TimeCurrent());
      MqlDateTime d;
      TimeToStruct(ref, d);
      if(d.day_of_week == SATURDAY || d.day_of_week == SUNDAY)
        {
         Close(pos, "weekend");
         return;
        }
      if(d.day_of_week != FRIDAY)
         return;
      if(d.hour * 60 + d.min >= m_closeMinute)
        {
         Close(pos, "weekend close");
         return;
        }
      MqlDateTime s;
      TimeToStruct(TimeCurrent(), s);
      int end = FridayEnd();
      int sec = s.hour * 3600 + s.min * 60 + s.sec;
      if(s.day_of_week == FRIDAY && end > 0 && sec >= end - m_beforeEndMin * 60)
         Close(pos, "before weekend session end");
     }
  };

#endif
//+------------------------------------------------------------------+
