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

   bool              Inside(const datetime serverTime) const
     {
      datetime r = CTimeZone::ServerToRef(serverTime);
      int m = (int)((r % 86400) / 60);
      return (m_start <= m_end) ? (m >= m_start && m < m_end) : (m >= m_start || m < m_end);
     }

public:
                     CFilterTimeWindow(void) : CSignalModule("TimeWindow"), m_start(9 * 60), m_end(20 * 60) {}

   void              Configure(const int startHour, const int startMin, const int endHour, const int endMin)
     {
      m_start = startHour * 60 + startMin;
      m_end   = endHour * 60 + endMin;
     }

   virtual bool      Update(void) { m_ready = true; m_bias = 0; return true; }

   //--- t = decision time (signal bar close) for historic checks
   virtual bool      Allows(const ENUM_SIGNAL_DIR dir, const bool historic, const datetime t)
     {
      return Inside(historic ? t : TimeCurrent());
     }

   virtual string    Status(void)
     {
      return StringFormat("%02d:%02d-%02d:%02d ref  %s", m_start / 60, m_start % 60, m_end / 60, m_end % 60,
                          Inside(TimeCurrent()) ? "OPEN" : "closed");
     }
  };

#endif
//+------------------------------------------------------------------+
