//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|  Position sizing: fixed lots or % of equity risked to the SL.    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_RISKMANAGER_MQH
#define CLAUDE_RISKMANAGER_MQH

#include "../Core/Defines.mqh"

struct SRiskSettings
  {
   ENUM_LOT_MODE     lotMode;
   double            fixedLots;
   double            riskPercent;
  };

class CRiskManager
  {
private:
   string            m_symbol;
   SRiskSettings     m_cfg;

public:
   void              Init(const string symbol, const SRiskSettings &cfg)
     {
      m_symbol = symbol;
      m_cfg    = cfg;
     }

   //--- round to the symbol's volume step and clamp to min/max
   double            NormalizeVolume(const double volume) const
     {
      double minV = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxV = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = minV;
      double v = MathFloor(volume / step + 1e-9) * step;
      if(v < minV)
         v = minV;
      if(v > maxV)
         v = maxV;
      int digits = (int)MathMax(0, MathCeil(-MathLog10(step)));
      return NormalizeDouble(v, digits);
     }

   //--- lots for an order at 'entry' with stop 'sl' (sl = 0 means no stop)
   double            Calculate(const ENUM_ORDER_TYPE type, const double entry, const double sl) const
     {
      double lots = m_cfg.fixedLots;

      if(m_cfg.lotMode == LOT_RISK_PERCENT)
        {
         if(sl <= 0.0)
            Print("RiskManager: risk % sizing needs a stop loss - using fixed lots");
         else
           {
            double lossPerLot = 0.0;
            if(!OrderCalcProfit(type, m_symbol, 1.0, entry, sl, lossPerLot) || lossPerLot == 0.0)
              {
               double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
               double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
               if(tickSize > 0.0)
                  lossPerLot = -MathAbs(entry - sl) / tickSize * tickValue;
              }
            lossPerLot = MathAbs(lossPerLot);
            if(lossPerLot > 0.0)
               lots = AccountInfoDouble(ACCOUNT_EQUITY) * m_cfg.riskPercent / 100.0 / lossPerLot;
           }
        }

      // don't request more than free margin allows
      double marginPerLot = 0.0;
      if(OrderCalcMargin(type, m_symbol, 1.0, entry, marginPerLot) && marginPerLot > 0.0)
        {
         double maxLots = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95 / marginPerLot;
         if(lots > maxLots)
            lots = maxLots;
        }

      return NormalizeVolume(lots);
     }
  };

#endif
//+------------------------------------------------------------------+
