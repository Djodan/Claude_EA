//+------------------------------------------------------------------+
//|                                                   DailyStats.mqh |
//|  Day-by-day P/L of this EA (all strategies) from deal history,   |
//|  for prop-firm consistency checks: best day share of total,      |
//|  winning days, trades per day. Days are reference-time days.     |
//+------------------------------------------------------------------+
#ifndef CLAUDE_DAILYSTATS_MQH
#define CLAUDE_DAILYSTATS_MQH

#include "TimeZone.mqh"

struct SDailyStats
  {
   int               days;            // days with at least one closed trade
   int               winDays;
   double            total;
   double            best;
   double            worst;
   double            avg;
   double            bestShare;       // best day / total profit, % (100 if total <= 0)
   double            tradesPerDay;
   int               trades;
  };

class CDailyStats
  {
public:
   static bool       Compute(const string symbol, const ulong baseMagic, SDailyStats &s)
     {
      ZeroMemory(s);
      s.bestShare = 100.0;
      if(!HistorySelect(0, TimeCurrent() + 86400))
         return false;
      int total = HistoryDealsTotal();

      ulong posIds[];
      int   np = 0;
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         ulong mg = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
         if(mg < baseMagic || mg >= baseMagic + 100)
            continue;
         ArrayResize(posIds, np + 1, 256);
         posIds[np++] = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         s.trades++;
        }
      if(np == 0)
         return true;
      ArraySort(posIds);

      long   dayKey[];
      double dayPnl[];
      int    nd = 0;
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol)
            continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
            continue;
         ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int   k   = ArrayBsearch(posIds, pid);
         if(k < 0 || posIds[k] != pid)
            continue;                                // not one of this EA's positions
         double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
         long key = (long)(CTimeZone::ServerToRef((datetime)HistoryDealGetInteger(d, DEAL_TIME)) / 86400);
         if(nd == 0 || dayKey[nd - 1] != key)          // deals are chronological
           {
            ArrayResize(dayKey, nd + 1, 256);
            ArrayResize(dayPnl, nd + 1, 256);
            dayKey[nd] = key;
            dayPnl[nd] = 0.0;
            nd++;
           }
         dayPnl[nd - 1] += p;
        }

      s.days  = nd;
      s.best  = -DBL_MAX;
      s.worst = DBL_MAX;
      for(int k = 0; k < nd; k++)
        {
         s.total += dayPnl[k];
         s.best   = MathMax(s.best, dayPnl[k]);
         s.worst  = MathMin(s.worst, dayPnl[k]);
         if(dayPnl[k] > 0.0)
            s.winDays++;
        }
      if(nd > 0)
        {
         s.avg          = s.total / nd;
         s.tradesPerDay = (double)s.trades / nd;
        }
      s.bestShare = (s.total > 0.0) ? s.best / s.total * 100.0 : 100.0;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
