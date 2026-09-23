//+------------------------------------------------------------------+
//|                                           ManagePartialClose.mqh |
//|  Take part of a position off once it is triggerAtr x ATR in      |
//|  profit, once per position. Optionally moves the stop to entry.  |
//|                                                                  |
//|  "Already done" is detected from deal history (current volume <  |
//|  opening volume), so it survives EA restarts and tester passes.  |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGEPARTIALCLOSE_MQH
#define CLAUDE_MANAGEPARTIALCLOSE_MQH

#include "PositionModule.mqh"

class CManagePartialClose : public CPositionModule
  {
private:
   double            m_triggerAtr;
   double            m_percent;
   bool              m_moveToBE;
   ulong             m_done[];     // tickets already handled this session

   bool              IsDone(const ulong ticket) const
     {
      for(int i = ArraySize(m_done) - 1; i >= 0; i--)
         if(m_done[i] == ticket)
            return true;
      return false;
     }

   void              MarkDone(const ulong ticket)
     {
      int n = ArraySize(m_done);
      if(n >= 256)                  // keep the list short; old tickets are long closed
        {
         ArrayRemove(m_done, 0, 128);
         n = ArraySize(m_done);
        }
      ArrayResize(m_done, n + 1);
      m_done[n] = ticket;
     }

   //--- volume the position was opened with
   double            OpeningVolume(const ulong ticket) const
     {
      if(!HistorySelectByPosition(ticket))
         return 0.0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal != 0 && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            return HistoryDealGetDouble(deal, DEAL_VOLUME);
        }
      return 0.0;
     }

public:
                     CManagePartialClose(void)
      : CPositionModule("PartialClose"), m_triggerAtr(1.5), m_percent(50.0), m_moveToBE(true) {}

   void              Configure(const double triggerAtr, const double percent, const bool moveToBE)
     {
      m_triggerAtr = triggerAtr;
      m_percent    = MathMax(1.0, MathMin(99.0, percent));
      m_moveToBE   = moveToBE;
     }

   virtual void      Manage(SPosition &pos)
     {
      if(IsDone(pos.ticket))
         return;
      double atr = Atr();
      if(atr <= 0.0 || pos.Profit() < m_triggerAtr * atr)
         return;

      double opened = OpeningVolume(pos.ticket);
      if(opened > 0.0 && pos.volume < opened - 1e-9)
        {
         MarkDone(pos.ticket);        // partial already taken earlier
         return;
        }

      if(ClosePartial(pos, m_percent / 100.0))
        {
         if(m_moveToBE)
            ModifySL(pos, pos.open);
        }
      MarkDone(pos.ticket);           // also when volume is too small to split
     }
  };

#endif
//+------------------------------------------------------------------+
