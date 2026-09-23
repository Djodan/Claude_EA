//+------------------------------------------------------------------+
//|                                                 TestReporter.mqh |
//|  Writes backtest results to the terminal COMMON Files folder:    |
//|    ClaudeEA/results.csv  - one row per tester pass (appended,    |
//|                            also during optimisation)             |
//|    ClaudeEA/strategies.csv - one row per strategy per pass       |
//|    ClaudeEA/trades_<symbol>_<tf>_P<preset>.csv                   |
//|                          - every closing deal (single runs only) |
//|  Strategies are identified by magic = base magic + strategy id.  |
//|  Common folder: %APPDATA%\MetaQuotes\Terminal\Common\Files       |
//+------------------------------------------------------------------+
#ifndef CLAUDE_TESTREPORTER_MQH
#define CLAUDE_TESTREPORTER_MQH

#include "TesterCriterion.mqh"
#include "ExcursionTracker.mqh"

class CTestReporter
  {
private:
   static string     Reason(const long reason)
     {
      switch((int)reason)
        {
         case DEAL_REASON_SL:     return "SL";
         case DEAL_REASON_TP:     return "TP";
         case DEAL_REASON_EXPERT: return "EA";
         case DEAL_REASON_SO:     return "STOPOUT";
         default:                 return "OTHER";
        }
     }

   static double     Ratio(const double num, const double den) { return den != 0.0 ? num / den * 100.0 : 0.0; }

public:
   //--- append one summary row for this pass
   static void       WriteSummary(const string symbol, const ENUM_TIMEFRAMES tf, const datetime from, const datetime to,
                                  const int preset, const string build, const string config, const double criterion)
     {
      FolderCreate("ClaudeEA", FILE_COMMON);
      string name = "ClaudeEA\\results.csv";
      int h = FileOpen(name, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("TestReporter: cannot open %s (%d)", name, GetLastError());
         return;
        }
      if(FileSize(h) == 0)
         FileWrite(h, "run_time", "build", "symbol", "tf", "from", "to", "preset", "config",
                   "trades", "net_profit", "gross_profit", "gross_loss", "profit_factor", "win_pct",
                   "long_trades", "long_win_pct", "short_trades", "short_win_pct",
                   "max_dd_pct", "max_dd_money", "recovery", "sharpe", "expected_payoff",
                   "initial_deposit", "criterion", "max_loss", "max_loss_pct");
      FileSeek(h, 0, SEEK_END);

      double trades = TesterStatistics(STAT_TRADES);
      double longs  = TesterStatistics(STAT_LONG_TRADES);
      double shorts = TesterStatistics(STAT_SHORT_TRADES);
      FileWrite(h, TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS), build, symbol, StringSubstr(EnumToString(tf), 7),
                TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE), preset, config,
                (int)trades,
                DoubleToString(TesterStatistics(STAT_PROFIT), 2),
                DoubleToString(TesterStatistics(STAT_GROSS_PROFIT), 2),
                DoubleToString(TesterStatistics(STAT_GROSS_LOSS), 2),
                DoubleToString(CTesterCriterion::ProfitFactor(), 3),
                DoubleToString(Ratio(TesterStatistics(STAT_PROFIT_TRADES), trades), 1),
                (int)longs, DoubleToString(Ratio(TesterStatistics(STAT_PROFIT_LONGTRADES), longs), 1),
                (int)shorts, DoubleToString(Ratio(TesterStatistics(STAT_PROFIT_SHORTTRADES), shorts), 1),
                DoubleToString(TesterStatistics(STAT_EQUITY_DDREL_PERCENT), 2),
                DoubleToString(TesterStatistics(STAT_EQUITY_DD), 2),
                DoubleToString(TesterStatistics(STAT_RECOVERY_FACTOR), 3),
                DoubleToString(TesterStatistics(STAT_SHARPE_RATIO), 3),
                DoubleToString(TesterStatistics(STAT_EXPECTED_PAYOFF), 3),
                DoubleToString(TesterStatistics(STAT_INITIAL_DEPOSIT), 2),
                DoubleToString(criterion, 4),
                DoubleToString(TesterStatistics(STAT_MAX_LOSSTRADE), 2),
                DoubleToString(TesterStatistics(STAT_INITIAL_DEPOSIT) > 0.0 ?
                               MathAbs(TesterStatistics(STAT_MAX_LOSSTRADE)) / TesterStatistics(STAT_INITIAL_DEPOSIT) * 100.0 : 0.0, 3));
      FileClose(h);
     }

   //--- one row per strategy: stats computed from its own deals
   static void       WriteStrategyStats(const string symbol, const ENUM_TIMEFRAMES tf, const int preset, const string build,
                                        const string config, const ulong baseMagic, const string &names[])
     {
      int ns = ArraySize(names);
      if(ns == 0 || !HistorySelect(0, TimeCurrent() + 86400))
         return;
      double net[], gp[], gl[];
      int    trades[], wins[];
      ArrayResize(net, ns);
      ArrayResize(gp, ns);
      ArrayResize(gl, ns);
      ArrayResize(trades, ns);
      ArrayResize(wins, ns);
      ArrayInitialize(net, 0.0);
      ArrayInitialize(gp, 0.0);
      ArrayInitialize(gl, 0.0);
      ArrayInitialize(trades, 0);
      ArrayInitialize(wins, 0);

      // position id -> strategy index, from the entry deals
      ulong posId[];
      int   posStrat[];
      int   np = 0;
      int   total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol || HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         long idx = (long)HistoryDealGetInteger(d, DEAL_MAGIC) - (long)baseMagic - 1;
         if(idx < 0 || idx >= ns)
            continue;
         ArrayResize(posId, np + 1, 256);
         ArrayResize(posStrat, np + 1, 256);
         posId[np]    = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         posStrat[np] = (int)idx;
         np++;
        }
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol)
            continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
            continue;
         ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int k = -1;
         for(int j = 0; j < np; j++)
            if(posId[j] == pid)
              {
               k = posStrat[j];
               break;
              }
         if(k < 0)
            continue;
         double p = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
         net[k] += p;
         trades[k]++;
         if(p > 0.0)
           {
            gp[k] += p;
            wins[k]++;
           }
         else
            gl[k] += p;
        }

      FolderCreate("ClaudeEA", FILE_COMMON);
      string name = "ClaudeEA\\strategies.csv";
      int h = FileOpen(name, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
      if(h == INVALID_HANDLE)
         return;
      if(FileSize(h) == 0)
         FileWrite(h, "run_time", "build", "symbol", "tf", "preset", "config", "strategy", "trades", "net_profit",
                   "gross_profit", "gross_loss", "profit_factor", "win_pct");
      FileSeek(h, 0, SEEK_END);
      for(int k = 0; k < ns; k++)
        {
         if(trades[k] == 0)
            continue;
         double pf = gl[k] != 0.0 ? gp[k] / MathAbs(gl[k]) : (gp[k] > 0.0 ? 100.0 : 0.0);
         FileWrite(h, TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS), build, symbol, StringSubstr(EnumToString(tf), 7),
                   preset, config, names[k], trades[k], DoubleToString(net[k], 2), DoubleToString(gp[k], 2),
                   DoubleToString(gl[k], 2), DoubleToString(pf, 3), DoubleToString(Ratio(wins[k], trades[k]), 1));
        }
      FileClose(h);
     }

   //--- one row per closing deal of this EA (entry matched by position id)
   static void       WriteTrades(const string symbol, const ENUM_TIMEFRAMES tf, const ulong baseMagic, const int preset,
                                 CExcursionTracker *tracker = NULL)
     {
      if(!HistorySelect(0, TimeCurrent() + 86400))
         return;
      FolderCreate("ClaudeEA", FILE_COMMON);
      string name = StringFormat("ClaudeEA\\trades_%s_%s_P%d.csv", symbol, StringSubstr(EnumToString(tf), 7), preset);
      int h = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("TestReporter: cannot open %s (%d)", name, GetLastError());
         return;
        }
      FileWrite(h, "strategy", "position", "dir", "entry_time", "entry_price", "exit_time", "exit_price", "volume",
                "net_profit", "exit_reason", "bars_held", "entry_hour", "entry_weekday",
                "risk_price", "mfe_price", "mae_price", "mfe_r", "mae_r", "result_r");

      int total = HistoryDealsTotal();
      ulong    posId[];
      datetime inTime[];
      double   inPrice[];
      long     inType[];
      long     inMagic[];
      int      nIn = 0;
      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         ulong mg = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
         if(d == 0 || mg < baseMagic || mg >= baseMagic + 100 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol)
            continue;
         if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         ArrayResize(posId, nIn + 1, 256);
         ArrayResize(inTime, nIn + 1, 256);
         ArrayResize(inPrice, nIn + 1, 256);
         ArrayResize(inType, nIn + 1, 256);
         ArrayResize(inMagic, nIn + 1, 256);
         inMagic[nIn] = (long)(mg - baseMagic);
         posId[nIn]   = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         inTime[nIn]  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         inPrice[nIn] = HistoryDealGetDouble(d, DEAL_PRICE);
         inType[nIn]  = HistoryDealGetInteger(d, DEAL_TYPE);
         nIn++;
        }

      for(int i = 0; i < total; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetString(d, DEAL_SYMBOL) != symbol)
            continue;
         long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
            continue;
         ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         int k = -1;
         for(int j = 0; j < nIn; j++)
            if(posId[j] == pid)
              {
               k = j;
               break;
              }
         if(k < 0)
            continue;   // not one of ours (SL/TP deals carry no magic, so match via position)
         datetime outTime = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         double net = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                      HistoryDealGetDouble(d, DEAL_COMMISSION);
         MqlDateTime dt;
         TimeToStruct(inTime[k], dt);
         double outPrice = HistoryDealGetDouble(d, DEAL_PRICE);
         double mfe = 0.0, mae = 0.0, risk = 0.0;
         if(CheckPointer(tracker) != POINTER_INVALID)
            tracker.Get(pid, mfe, mae, risk);
         double moved = inType[k] == DEAL_TYPE_BUY ? outPrice - inPrice[k] : inPrice[k] - outPrice;
         FileWrite(h, inMagic[k], (long)pid, inType[k] == DEAL_TYPE_BUY ? "BUY" : "SELL",
                   TimeToString(inTime[k], TIME_DATE | TIME_MINUTES), DoubleToString(inPrice[k], _Digits),
                   TimeToString(outTime, TIME_DATE | TIME_MINUTES),
                   DoubleToString(HistoryDealGetDouble(d, DEAL_PRICE), _Digits),
                   DoubleToString(HistoryDealGetDouble(d, DEAL_VOLUME), 2),
                   DoubleToString(net, 2), Reason(HistoryDealGetInteger(d, DEAL_REASON)),
                   (int)((outTime - inTime[k]) / PeriodSeconds(tf)), dt.hour, dt.day_of_week,
                   DoubleToString(risk, _Digits), DoubleToString(mfe, _Digits), DoubleToString(mae, _Digits),
                   risk > 0.0 ? DoubleToString(mfe / risk, 2) : "", risk > 0.0 ? DoubleToString(mae / risk, 2) : "",
                   risk > 0.0 ? DoubleToString(moved / risk, 2) : "");
        }
      FileClose(h);
      PrintFormat("TestReporter: trades written to Common\\Files\\%s", name);
     }
  };

#endif
//+------------------------------------------------------------------+
