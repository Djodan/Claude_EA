//+------------------------------------------------------------------+
//|                                               ManageTimeExit.mqh |
//|  Close a position after it has been open for maxBars bars of the |
//|  signal timeframe (optionally only if it is not in profit).      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGETIMEEXIT_MQH
#define CLAUDE_MANAGETIMEEXIT_MQH

#include "PositionModule.mqh"

class CManageTimeExit : public CPositionModule
  {
private:
   int               m_maxBars;
   bool              m_onlyIfLosing;

public:
                     CManageTimeExit(void) : CPositionModule("TimeExit"), m_maxBars(48), m_onlyIfLosing(false) {}

   void              Configure(const int maxBars, const bool onlyIfLosing)
     {
      m_maxBars      = maxBars;
      m_onlyIfLosing = onlyIfLosing;
     }

   virtual void      Manage(SPosition &pos)
     {
      if(m_maxBars <= 0)
         return;
      int bars = iBarShift(m_symbol, m_tf, pos.openTime, false);
      if(bars < m_maxBars)
         return;
      if(m_onlyIfLosing && pos.Profit() > 0.0)
         return;
      Close(pos, StringFormat("open %d bars", bars));
     }
  };

#endif
//+------------------------------------------------------------------+
