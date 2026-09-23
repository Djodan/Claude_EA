//+------------------------------------------------------------------+
//|                                               ManageTrailing.mqh |
//|  ATR trailing stop: once startAtr x ATR in profit, keep the stop |
//|  distAtr x ATR behind price. Only moves when the improvement is  |
//|  at least stepAtr x ATR, to avoid spamming modify requests.      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_MANAGETRAILING_MQH
#define CLAUDE_MANAGETRAILING_MQH

#include "PositionModule.mqh"

class CManageTrailing : public CPositionModule
  {
private:
   double            m_startAtr;
   double            m_distAtr;
   double            m_stepAtr;

public:
                     CManageTrailing(void) : CPositionModule("Trailing"), m_startAtr(1.5), m_distAtr(2.0), m_stepAtr(0.1) {}

   void              Configure(const double startAtr, const double distAtr, const double stepAtr)
     {
      m_startAtr = startAtr;
      m_distAtr  = distAtr;
      m_stepAtr  = stepAtr;
     }

   virtual void      Manage(SPosition &pos)
     {
      double atr = Atr();
      if(atr <= 0.0 || pos.Profit() < m_startAtr * atr)
         return;
      double step = m_stepAtr * atr;
      if(pos.IsBuy())
        {
         double target = pos.price - m_distAtr * atr;
         if(pos.sl == 0.0 || target >= pos.sl + step)
            ModifySL(pos, target);
        }
      else
        {
         double target = pos.price + m_distAtr * atr;
         if(pos.sl == 0.0 || target <= pos.sl - step)
            ModifySL(pos, target);
        }
     }
  };

#endif
//+------------------------------------------------------------------+
