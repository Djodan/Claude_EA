//+------------------------------------------------------------------+
//|                                               ManageNewsExit.mqh |
//|  Closes open positions shortly before a high-impact news event   |
//|  so a spike can't gap price through the stop (protects the prop  |
//|  firm "max loss per trade" rule). Reuses CGuardNews with a       |
//|  window of [event - minutesBefore, event].                       |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGENEWSEXIT_MQH
#define CLAUDE_MANAGENEWSEXIT_MQH

#include "PositionModule.mqh"
#include "../Guards/GuardNews.mqh"

class CManageNewsExit : public CPositionModule
  {
private:
   CGuardNews        m_news;
   SGuardNewsSettings m_cfg;

public:
                     CManageNewsExit(void) : CPositionModule("NewsExit") {}

   //--- same calendar filters as the entry guard, own "minutes before"
   void              Configure(const SGuardNewsSettings &news, const int minutesBefore)
     {
      m_cfg = news;
      m_cfg.minutesBefore = minutesBefore;
      m_cfg.minutesAfter  = 0;
      m_news.Configure(m_cfg);
     }

   virtual bool      Init(const string symbol, const ulong magic, const ENUM_TIMEFRAMES tf, CTrade *trade, CAtrProvider *atr)
     {
      if(!CPositionModule::Init(symbol, magic, tf, trade, atr))
         return false;
      return m_news.Init(symbol, magic);
     }

   virtual void      Manage(SPosition &pos)
     {
      if(!m_news.CanOpen())                  // inside [event - N min, event]
         Close(pos, "news: " + m_news.Status());
     }
  };

#endif
//+------------------------------------------------------------------+
