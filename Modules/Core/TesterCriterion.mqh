//+------------------------------------------------------------------+
//|                                              TesterCriterion.mqh |
//|  Custom optimisation score returned from OnTester().             |
//|  Select "Custom max" as the optimisation criterion in the tester.|
//|  Passes with fewer than minTrades trades score 0, so the         |
//|  optimiser can't favour a handful of lucky trades.               |
//+------------------------------------------------------------------+
#ifndef CLAUDE_TESTERCRITERION_MQH
#define CLAUDE_TESTERCRITERION_MQH

enum ENUM_TESTER_CRITERION
  {
   TC_NET_PROFIT,        // Net profit
   TC_PROFIT_FACTOR,     // Profit factor
   TC_RECOVERY_FACTOR,   // Recovery factor (profit / max DD)
   TC_SHARPE,            // Sharpe ratio
   TC_EXPECTED_PAYOFF,   // Expected payoff per trade
   TC_PF_SQRT_TRADES,    // Profit factor x sqrt(trades)
   TC_PROFIT_DD_PCT,     // Net profit / equity DD %
   TC_CONSISTENCY        // Net profit, cut when best day > 40% of total (prop rule)
  };

class CTesterCriterion
  {
public:
   static double     ProfitFactor(void)
     {
      double gp = TesterStatistics(STAT_GROSS_PROFIT);
      double gl = MathAbs(TesterStatistics(STAT_GROSS_LOSS));
      if(gl == 0.0)
         return gp > 0.0 ? 100.0 : 0.0;   // cap "no losing trades"
      return gp / gl;
     }

   //--- net profit scaled down when the best day exceeds 40% of total profit
   static double     Consistency(const double net, const double bestSharePct)
     {
      if(net <= 0.0)
         return net;
      return bestSharePct <= 40.0 ? net : net * 40.0 / bestSharePct;
     }

   static double     Calculate(const ENUM_TESTER_CRITERION criterion, const int minTrades, const double bestSharePct = 100.0)
     {
      double trades = TesterStatistics(STAT_TRADES);
      if(trades < minTrades)
         return 0.0;
      double profit = TesterStatistics(STAT_PROFIT);

      switch(criterion)
        {
         case TC_PROFIT_FACTOR:
            return ProfitFactor();
         case TC_RECOVERY_FACTOR:
            return TesterStatistics(STAT_RECOVERY_FACTOR);
         case TC_SHARPE:
            return TesterStatistics(STAT_SHARPE_RATIO);
         case TC_EXPECTED_PAYOFF:
            return TesterStatistics(STAT_EXPECTED_PAYOFF);
         case TC_PF_SQRT_TRADES:
            return profit > 0.0 ? ProfitFactor() * MathSqrt(trades) : 0.0;
         case TC_CONSISTENCY:
            return Consistency(profit, bestSharePct);
         case TC_PROFIT_DD_PCT:
           {
            double dd = TesterStatistics(STAT_EQUITYDD_PERCENT);
            return dd > 0.0 ? profit / dd : profit;
           }
         default:
            return profit;
        }
     }
  };

#endif
//+------------------------------------------------------------------+
