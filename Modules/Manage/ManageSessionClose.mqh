//+------------------------------------------------------------------+
//|                                           ManageSessionClose.mqh |
//|  Close positions at a fixed reference time each day (and any     |
//|  position still open from a previous day) - keeps intraday       |
//|  strategies flat overnight.                                      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGESESSIONCLOSE_MQH
#define CLAUDE_MANAGESESSIONCLOSE_MQH

#include "PositionModule.mqh"
#include "../Core/TimeZone.mqh"

class CManageSessionClose : public CPositionModule
  {
private:
   int               m_closeMinute;   // minute of day, reference time
   int               m_beforeEndMin;  // also close this many minutes before the broker's session end

   //--- end of today's last trading session in server seconds-of-day (-1 if unknown)
   int               SessionEnd(const datetime serverNow) const
     {
      MqlDateTime d;
      TimeToStruct(serverNow, d);
      datetime from, to;
      int end = -1;
      for(uint s = 0; SymbolInfoSessionTrade(m_symbol, (ENUM_DAY_OF_WEEK)d.day_of_week, s, from, to); s++)
         end = MathMax(end, (int)(to % 86400 == 0 && to > 0 ? 86400 : to % 86400));
      return end;
     }

public:
                     CManageSessionClose(void) : CPositionModule("SessionClose"), m_closeMinute(23 * 60), m_beforeEndMin(5) {}

   void              Configure(const int hour, const int minute) { m_closeMinute = hour * 60 + minute; }

   virtual void      Manage(SPosition &pos)
     {
      datetime now      = CTimeZone::ServerToRef(TimeCurrent());
      datetime opened   = CTimeZone::ServerToRef(pos.openTime);
      datetime today    = now - now % 86400;
      datetime openDay  = opened - opened % 86400;
      int      minute   = (int)((now % 86400) / 60);
      if(openDay < today)
         Close(pos, "held past day end");
      else
         if(minute >= m_closeMinute)
            Close(pos, "session close");
         else
           {
            // markets can close before the EOD time (early daily break, Fridays): get out first
            datetime server = TimeCurrent();
            int end = SessionEnd(server);
            int sec = (int)(server % 86400);
            if(end > 0 && end < 86400 && sec >= end - m_beforeEndMin * 60)
               Close(pos, "before broker session end");
           }
     }
  };

#endif
//+------------------------------------------------------------------+
