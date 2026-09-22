//+------------------------------------------------------------------+
//|                                                 AlertManager.mqh |
//|  Popup / push / email / sound notifications for final signals.   |
//+------------------------------------------------------------------+
#ifndef CLAUDE_ALERTMANAGER_MQH
#define CLAUDE_ALERTMANAGER_MQH

#include "../Core/Defines.mqh"

struct SAlertSettings
  {
   string            title;      // e.g. "DJ Trend"
   bool              popup;
   bool              push;
   bool              email;
   bool              sound;
   string            soundFile;
  };

class CAlertManager
  {
private:
   SAlertSettings    m_cfg;
   string            m_symbol;

public:
   void              Init(const string symbol, const SAlertSettings &cfg)
     {
      m_symbol = symbol;
      m_cfg    = cfg;
     }

   //--- "DJ Trend BUY on EURUSD @ 1.08512"
   string            Format(const SSignal &s) const
     {
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      return StringFormat("%s %s on %s @ %s", m_cfg.title, SignalDirToString(s.dir), m_symbol,
                          DoubleToString(s.price, digits));
     }

   void              Notify(const SSignal &s)
     {
      if(s.dir == SIG_NONE)
         return;
      string msg = Format(s);
      Print(msg);
      if(MQLInfoInteger(MQL_TESTER))
         return;
      if(m_cfg.popup)
         Alert(msg);
      if(m_cfg.push)
         SendNotification(msg);
      if(m_cfg.email)
         SendMail(m_cfg.title + " " + SignalDirToString(s.dir) + " " + m_symbol, msg);
      if(m_cfg.sound && !m_cfg.popup)   // Alert() already plays a sound
         PlaySound(m_cfg.soundFile);
     }
  };

#endif
//+------------------------------------------------------------------+
