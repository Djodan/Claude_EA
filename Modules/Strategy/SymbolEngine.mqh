//+------------------------------------------------------------------+
//|                                                 SymbolEngine.mqh |
//|  Everything the EA runs on one symbol: its config copy (with the |
//|  symbol's overrides), guards, strategies, excursion tracker and  |
//|  alerts. The EA holds one engine per traded symbol.              |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SYMBOLENGINE_MQH
#define CLAUDE_SYMBOLENGINE_MQH

#include "Strategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/SymbolList.mqh"
#include "../Core/ExcursionTracker.mqh"
#include "../Guards/GuardManager.mqh"
#include "../Guards/GuardNews.mqh"
#include "../Notify/AlertManager.mqh"

class CSymbolEngine
  {
public:
   SSymbolSpec       spec;
   string            symbol;
   bool              isChart;      // the chart's symbol: draws signals on the chart
   SEAConfig         cfg;
   CGuardManager     guards;
   CGuardNews       *news;         // owned by guards; kept for health checks
   CStrategy        *strategies[];
   CExcursionTracker excursions;
   CAlertManager     alerts;

                     CSymbolEngine(void) : symbol(""), isChart(false), news(NULL) {}

   int               Total(void) const { return ArraySize(strategies); }

   void              Add(CStrategy *st)
     {
      int n = ArraySize(strategies);
      ArrayResize(strategies, n + 1);
      strategies[n] = st;
     }

   void              Deinit(void)
     {
      for(int k = 0; k < ArraySize(strategies); k++)
        {
         strategies[k].Deinit();
         delete strategies[k];
        }
      ArrayResize(strategies, 0);
      guards.Deinit();
      news = NULL;
     }
  };

#endif
//+------------------------------------------------------------------+
