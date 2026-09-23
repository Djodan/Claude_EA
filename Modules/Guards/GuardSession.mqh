//+------------------------------------------------------------------+
//|                                                 GuardSession.mqh |
//|  Trading-hours window (server time) and allowed weekdays.        |
//|  Windows that cross midnight (e.g. 22:00 - 06:00) are supported. |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDSESSION_MQH
#define CLAUDE_GUARDSESSION_MQH

#include "GuardBase.mqh"

struct SGuardSessionSettings
  {
   int               startHour;
   int               startMinute;
   int               endHour;
   int               endMinute;
   bool              days[7];      // index = day_of_week (0 = Sunday)
  };

class CGuardSession : public CGuard
  {
private:
   SGuardSessionSettings m_cfg;

public:
                     CGuardSession(void) : CGuard("Session")
     {
      m_cfg.startHour   = 0;
      m_cfg.startMinute = 0;
      m_cfg.endHour     = 24;
      m_cfg.endMinute   = 0;
      for(int d = 0; d < 7; d++)
         m_cfg.days[d] = (d >= 1 && d <= 5);
     }

   void              Configure(const SGuardSessionSettings &cfg) { m_cfg = cfg; }

   virtual bool      CanOpen(void)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(!m_cfg.days[dt.day_of_week])
        {
         m_status = "day not allowed";
         return false;
        }
      int now   = dt.hour * 60 + dt.min;
      int start = m_cfg.startHour * 60 + m_cfg.startMinute;
      int end   = m_cfg.endHour * 60 + m_cfg.endMinute;
      bool inside = (start <= end) ? (now >= start && now < end) : (now >= start || now < end);
      m_status = StringFormat("%02d:%02d-%02d:%02d", m_cfg.startHour, m_cfg.startMinute, m_cfg.endHour, m_cfg.endMinute);
      if(!inside)
         m_status = "outside " + m_status;
      return inside;
     }
  };

#endif
//+------------------------------------------------------------------+
