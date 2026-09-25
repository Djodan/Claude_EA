//+------------------------------------------------------------------+
//|                                             FilterTimeWindow.mqh |
//|  Per-strategy trading hours (reference time, GMT+2/+3).          |
//|  Non-directional filter: allows signals only inside the window.  |
//|  Windows crossing midnight (e.g. 22:00-02:00) are supported.     |
//+------------------------------------------------------------------+
#ifndef CLAUDE_FILTERTIMEWINDOW_MQH
#define CLAUDE_FILTERTIMEWINDOW_MQH

#include "../SignalBase.mqh"
#include "../../Core/TimeZone.mqh"

class CFilterTimeWindow : public CSignalModule
  {
private:
   int               m_start;   // minute of day, reference time
   int               m_end;
   int               m_start2;  // optional second window (-1 = none)
   int               m_end2;

   static bool       In(const int m, const int a, const int b)
     {
      return (a <= b) ? (m >= a && m < b) : (m >= a || m < b);
     }

   bool              Inside(const datetime serverTime) const
     {
      datetime r = CTimeZone::ServerToRef(serverTime);
      int m = (int)((r % 86400) / 60);
      return In(m, m_start, m_end) || (m_start2 >= 0 && In(m, m_start2, m_end2));
     }

public:
                     CFilterTimeWindow(void) : CSignalModule("TimeWindow"), m_start(9 * 60), m_end(20 * 60), m_start2(-1), m_end2(-1) {}

   void              Configure(const int startHour, const int startMin, const int endHour, const int endMin)
     {
      m_start = startHour * 60 + startMin;
      m_end   = endHour * 60 + endMin;
     }

   void              Configure2(const int startHour, const int startMin, const int endHour, const int endMin)
     {
      m_start2 = startHour * 60 + startMin;
      m_end2   = endHour * 60 + endMin;
      if(m_start2 == m_end2)
         m_start2 = m_end2 = -1;              // equal times = second window off
     }

   virtual bool      Update(void) { m_ready = true; m_bias = 0; return true; }

   //--- t = decision time (signal bar close) for historic checks
   virtual bool      Allows(const ENUM_SIGNAL_DIR dir, const bool historic, const datetime t)
     {
      return Inside(historic ? t : TimeCurrent());
     }

   virtual string    Status(void)
     {
      string w2 = m_start2 >= 0 ? StringFormat(" + %02d:%02d-%02d:%02d", m_start2 / 60, m_start2 % 60, m_end2 / 60, m_end2 % 60) : "";
      return StringFormat("%02d:%02d-%02d:%02d%s ref  %s", m_start / 60, m_start % 60, m_end / 60, m_end % 60, w2,
                          Inside(TimeCurrent()) ? "OPEN" : "closed");
     }
  };

#endif
//+------------------------------------------------------------------+
