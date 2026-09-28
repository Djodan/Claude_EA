//+------------------------------------------------------------------+
//|                                          Claude_ImportCustom.mq5 |
//|  Creates / refreshes a custom symbol from the files written by   |
//|  Research/data/duka_convert.py (Common\Files\ClaudeEA\data\):    |
//|    <SYMBOL>_M1.csv           M1 bars (NY-close server time)      |
//|    <SYMBOL>_ticks_YYYYMM.bin real ticks (int64 msc, bid, ask)    |
//|  Contract set up like MNQ: 1 lot = 1 contract = $2 per point.    |
//|  Copy to MQL5\Scripts, compile, drag onto any chart.             |
//+------------------------------------------------------------------+
#property copyright "DjoDan Maviaki"
#property version   "1.00"
#property script_show_inputs

input string InpSymbol   = "NAS100_CONT";   // Custom symbol name (= SYMBOL used in duka_convert.py)
input string InpFolder   = "ClaudeEA\\data\\"; // Folder in Common\Files
input double InpPointVal = 2.0;             // $ per 1.00 point per lot (MNQ = 2, NQ = 20)
input bool   InpBars     = true;            // Import M1 bars
input bool   InpTicks    = true;            // Import real ticks (all *_ticks_YYYYMM.bin files)

struct STickRec
  {
   long              msc;
   double            bid;
   double            ask;
  };

bool SetUp(void)
  {
   bool custom = false;
   if(!SymbolExist(InpSymbol, custom))
     {
      if(!CustomSymbolCreate(InpSymbol, "Custom\\Claude"))
        {
         PrintFormat("CustomSymbolCreate failed, error %d", GetLastError());
         return false;
        }
     }
   else
      if(!custom)
        {
         PrintFormat("%s exists and is not a custom symbol", InpSymbol);
         return false;
        }
   bool ok = true;
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_DIGITS, 2);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_POINT, 0.01);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE, 0.01);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_TRADE_CONTRACT_SIZE, InpPointVal);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE, InpPointVal * 0.01);
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_TRADE_CALC_MODE, SYMBOL_CALC_MODE_CFD);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_VOLUME_MIN, 1.0);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_VOLUME_STEP, 1.0);
   ok &= CustomSymbolSetDouble(InpSymbol, SYMBOL_VOLUME_MAX, 100.0);
   ok &= CustomSymbolSetString(InpSymbol, SYMBOL_CURRENCY_BASE, "USD");
   ok &= CustomSymbolSetString(InpSymbol, SYMBOL_CURRENCY_PROFIT, "USD");
   ok &= CustomSymbolSetString(InpSymbol, SYMBOL_CURRENCY_MARGIN, "USD");
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_SPREAD_FLOAT, true);
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL);
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_TRADE_EXEMODE, SYMBOL_TRADE_EXECUTION_MARKET);
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_FILLING_MODE, SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC);
   ok &= CustomSymbolSetInteger(InpSymbol, SYMBOL_SWAP_MODE, SYMBOL_SWAP_MODE_DISABLED);
   ok &= CustomSymbolSetString(InpSymbol, SYMBOL_DESCRIPTION, "Nasdaq-100 (Dukascopy USATECH, NY-close time), MNQ contract spec");
   if(!ok)
      PrintFormat("some symbol properties could not be set, last error %d", GetLastError());
   SymbolSelect(InpSymbol, true);
   return true;
  }

bool ImportBars(void)
  {
   string name = InpFolder + InpSymbol + "_M1.csv";
   int h = FileOpen(name, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("%s not found in Common\\Files", name);
      return false;
     }
   for(int i = 0; i < 7; i++)
      FileReadString(h);                           // header
   MqlRates r[];
   ArrayResize(r, 0, 100000);
   int n = 0, total = 0;
   while(!FileIsEnding(h))
     {
      long t = (long)StringToInteger(FileReadString(h));
      if(t <= 0)
         break;
      ArrayResize(r, n + 1, 100000);
      r[n].time        = (datetime)t;
      r[n].open        = StringToDouble(FileReadString(h));
      r[n].high        = StringToDouble(FileReadString(h));
      r[n].low         = StringToDouble(FileReadString(h));
      r[n].close       = StringToDouble(FileReadString(h));
      r[n].tick_volume = (long)StringToInteger(FileReadString(h));
      r[n].spread      = (int)StringToInteger(FileReadString(h));
      r[n].real_volume = 0;
      n++;
      if(n == 200000 || FileIsEnding(h))
        {
         if(CustomRatesUpdate(InpSymbol, r) < 0)
            PrintFormat("CustomRatesUpdate failed, error %d", GetLastError());
         total += n;
         n = 0;
         ArrayResize(r, 0, 100000);
         Comment(StringFormat("%s: %d M1 bars imported", InpSymbol, total));
        }
     }
   if(n > 0 && CustomRatesUpdate(InpSymbol, r) >= 0)
      total += n;
   FileClose(h);
   PrintFormat("%s: %d M1 bars imported", InpSymbol, total);
   return total > 0;
  }

bool ImportTicks(void)
  {
   string mask = InpFolder + InpSymbol + "_ticks_*.bin", file;
   string files[];
   long fh = FileFindFirst(mask, file, FILE_COMMON);
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("no tick files %s", mask);
      return false;
     }
   do
     {
      int k = ArraySize(files);
      ArrayResize(files, k + 1);
      files[k] = file;
     }
   while(FileFindNext(fh, file));
   FileFindClose(fh);
   ArraySort(files);
   long total = 0;
   for(int f = 0; f < ArraySize(files); f++)
     {
      int h = FileOpen(InpFolder + files[f], FILE_READ | FILE_BIN | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE)
         continue;
      STickRec rec[];
      MqlTick  ticks[];
      while(!FileIsEnding(h))
        {
         int n = (int)FileReadArray(h, rec, 0, 1000000);
         if(n <= 0)
            break;
         ArrayResize(ticks, n);
         for(int i = 0; i < n; i++)
           {
            ZeroMemory(ticks[i]);
            ticks[i].time     = (datetime)(rec[i].msc / 1000);
            ticks[i].time_msc = rec[i].msc;
            ticks[i].bid      = rec[i].bid;
            ticks[i].ask      = rec[i].ask;
            ticks[i].flags    = TICK_FLAG_BID | TICK_FLAG_ASK;
           }
         if(CustomTicksReplace(InpSymbol, ticks[0].time_msc, ticks[n - 1].time_msc, ticks) < 0)
            PrintFormat("%s: CustomTicksReplace failed, error %d", files[f], GetLastError());
         total += n;
         Comment(StringFormat("%s: %s  %I64d ticks imported", InpSymbol, files[f], total));
        }
      FileClose(h);
      PrintFormat("%s: %s done (%I64d ticks so far)", InpSymbol, files[f], total);
     }
   return total > 0;
  }

void OnStart()
  {
   if(!SetUp())
      return;
   if(InpBars)
      ImportBars();
   if(InpTicks)
      ImportTicks();
   Comment("");
   PrintFormat("%s ready - use it in the Strategy Tester like any symbol", InpSymbol);
  }
//+------------------------------------------------------------------+
