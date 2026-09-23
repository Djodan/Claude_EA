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
   double            accountSize;    // cap for the sizing base, e.g. prop account size (0 = off)
  };

class CRiskManager
  {
private:
   string            m_symbol;
   SRiskSettings     m_cfg;
   string            m_issue;        // why the last calculation returned 0

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
   string            LastIssue(void) const { return m_issue; }

   double            Calculate(const ENUM_ORDER_TYPE type, const double entry, const double sl)
     {
      m_issue = "";
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
              {
               // size from the lower of balance and equity (prop rules usually measure against balance)
               double base = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
               if(m_cfg.accountSize > 0.0)
                  base = MathMin(base, m_cfg.accountSize);   // never risk more than x% of the starting size
               lots = base * m_cfg.riskPercent / 100.0 / lossPerLot;
               double minV = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
               if(lots < minV - 1e-9)
                 {
                  // rounding up to the minimum lot would risk more than allowed (prop rule)
                  m_issue = StringFormat("stop too wide: %.2f%% risk needs %.3f lots < min %.2f - trade skipped",
                                         m_cfg.riskPercent, lots, minV);
                  return 0.0;
                 }
              }
           }
        }

      // don't request more than free margin allows
      double marginPerLot = 0.0;
      if(OrderCalcMargin(type, m_symbol, 1.0, entry, marginPerLot) && marginPerLot > 0.0)
        {
         double maxLots = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95 / marginPerLot;
         if(lots > maxLots)
           {
            lots = maxLots;
            m_issue = "size reduced by free margin";
           }
        }

      return NormalizeVolume(lots);
     }
  };

#endif
//+------------------------------------------------------------------+
