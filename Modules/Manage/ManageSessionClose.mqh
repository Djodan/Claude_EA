//+------------------------------------------------------------------+
//|                                           ManageSessionClose.mqh |
//|  Close positions at a fixed server time each day (and any        |
//|  position still open from a previous day) - keeps intraday       |
//|  strategies flat overnight.                                      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGESESSIONCLOSE_MQH
#define CLAUDE_MANAGESESSIONCLOSE_MQH

#include "PositionModule.mqh"

class CManageSessionClose : public CPositionModule
  {
private:
   int               m_closeMinute;   // minute of day, server time

public:
                     CManageSessionClose(void) : CPositionModule("SessionClose"), m_closeMinute(23 * 60) {}

   void              Configure(const int hour, const int minute) { m_closeMinute = hour * 60 + minute; }

   virtual void      Manage(SPosition &pos)
     {
      datetime now      = TimeCurrent();
      datetime today    = now - now % 86400;
      datetime openDay  = pos.openTime - pos.openTime % 86400;
      int      minute   = (int)((now % 86400) / 60);
      if(openDay < today)
         Close(pos, "held past day end");
      else
         if(minute >= m_closeMinute)
            Close(pos, "session close");
     }
  };

#endif
//+------------------------------------------------------------------+
