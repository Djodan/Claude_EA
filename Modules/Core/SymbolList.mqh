//+------------------------------------------------------------------+
//|                                                   SymbolList.mqh |
//|  Parses the "Symbols" input into per-symbol specs.               |
//|                                                                  |
//|  Syntax: comma-separated symbols, each with optional overrides   |
//|    "XAUUSD, EURUSD:spread=0.00020;slip=0.00030;risk=0.5"         |
//|  keys: spread / slip (price), risk (S1-S4 %), srisk (scalper %), |
//|        irisk (intraday %). Empty list = the chart symbol.        |
//|  Broker suffixes are resolved automatically (EURUSD -> EURUSD.a).|
//|  slot N > 0 keeps only the Nth symbol of the list, so the tester |
//|  can optimise "InpSymbolSlot" to run the pairs one by one.       |
//|  ParsePairs(): the 5 Pair inputs (v4.52) - on/off, symbol and a  |
//|  "key=value;..." text with that pair's own settings.             |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SYMBOLLIST_MQH
#define CLAUDE_SYMBOLLIST_MQH

struct SSymbolSpec
  {
   string            name;      // resolved broker symbol
   double            spread;    // max spread in price (-1 = scale the chart input by price)
   double            slip;      // max slippage in price (-1 = scale the chart input by price)
   double            risk;      // risk % for S1-S4 (0 = input)
   double            sRisk;     // risk % for the scalper engines (0 = input)
   double            iRisk;     // risk % for the intraday engines (0 = input)
   string            settings;  // pair's own inputs "InpX=v;..." (Pair inputs), applied like a profile
  };

class CSymbolList
  {
private:
   static string     Trim(const string s)
     {
      string r = s;
      StringTrimLeft(r);
      StringTrimRight(r);
      return r;
     }

   static void       Init(SSymbolSpec &s, const string name)
     {
      s.name     = name;
      s.spread   = -1.0;
      s.slip     = -1.0;
      s.risk     = 0.0;
      s.sRisk    = 0.0;
      s.iRisk    = 0.0;
      s.settings = "";
     }

   //--- the short override keys; false = not one of them
   static bool       ShortKey(SSymbolSpec &s, string key, const double v)
     {
      StringToLower(key);
      if(key == "spread")
         s.spread = v;
      else if(key == "slip")
         s.slip = v;
      else if(key == "risk")
         s.risk = v;
      else if(key == "srisk")
         s.sRisk = v;
      else if(key == "irisk")
         s.iRisk = v;
      else
         return false;
      return true;
     }

   static bool       Listed(const SSymbolSpec &out[], const string name)
     {
      for(int k = 0; k < ArraySize(out); k++)
         if(out[k].name == name)
            return true;
      return false;
     }

public:
   //--- broker symbol for a name: exact, then prefix match (suffix), then contains
   static string     Resolve(const string raw)
     {
      string s = Trim(raw);
      if(s == "")
         return "";
      bool custom;
      if(SymbolExist(s, custom))
        {
         SymbolSelect(s, true);
         return s;
        }
      int n = SymbolsTotal(false);
      for(int pass = 0; pass < 2; pass++)
         for(int i = 0; i < n; i++)
           {
            string c = SymbolName(i, false);
            int at = StringFind(c, s);
            if(pass == 0 ? at == 0 : at > 0)
              {
               SymbolSelect(c, true);
               return c;
              }
           }
      return "";
     }

   //--- current price, falling back to the last daily close before the first tick
   static double     Price(const string symbol)
     {
      double p = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(p <= 0.0)
         p = iClose(symbol, PERIOD_D1, 0);
      return p;
     }

   static bool       Parse(const string list, const int slot, SSymbolSpec &out[], string &err)
     {
      ArrayResize(out, 0);
      err = "";
      string src = Trim(list);
      if(src == "")
         src = _Symbol;
      string items[];
      int n = StringSplit(src, ',', items);
      int pos = 0;
      for(int i = 0; i < n; i++)
        {
         string parts[];
         if(StringSplit(items[i], ':', parts) < 1 || Trim(parts[0]) == "")
            continue;
         pos++;
         if(slot > 0 && pos != slot)
            continue;
         SSymbolSpec s;
         Init(s, Resolve(parts[0]));
         if(s.name == "")
           {
            err += "symbol '" + Trim(parts[0]) + "' not found; ";
            continue;
           }
         if(Listed(out, s.name))
            continue;
         if(ArraySize(parts) > 1)
           {
            string kv[];
            int nk = StringSplit(parts[1], ';', kv);
            for(int k = 0; k < nk; k++)
              {
               string p[];
               if(StringSplit(kv[k], '=', p) != 2)
                 {
                  if(Trim(kv[k]) != "")
                     err += s.name + ": bad override '" + Trim(kv[k]) + "'; ";
                  continue;
                 }
               string key = Trim(p[0]);
               if(!ShortKey(s, key, StringToDouble(Trim(p[1]))))
                  err += s.name + ": unknown key '" + key + "'; ";
              }
           }
         int m = ArraySize(out);
         ArrayResize(out, m + 1);
         out[m] = s;
        }
      if(slot > 0 && ArraySize(out) == 0 && err == "")
         err = StringFormat("symbol slot %d is beyond the list (%d symbols)", slot, pos);
      return ArraySize(out) > 0;
     }

   //--- Pair inputs: pair i is used when on[i] and sym[i] set; settings[i] = "key=value;..." (short keys
   //--- spread/slip/risk/srisk/irisk go to the spec, everything else is that pair's own input value)
   static bool       ParsePairs(const bool &on[], const string &sym[], const string &settings[], const int slot,
                                SSymbolSpec &out[], string &err)
     {
      ArrayResize(out, 0);
      err = "";
      int pos = 0;
      for(int i = 0; i < ArraySize(on); i++)
        {
         if(!on[i])
            continue;
         if(Trim(sym[i]) == "")
           {
            err += StringFormat("pair %d is on but has no symbol; ", i + 1);
            continue;
           }
         pos++;
         if(slot > 0 && pos != slot)
            continue;
         SSymbolSpec s;
         Init(s, Resolve(sym[i]));
         if(s.name == "")
           {
            err += StringFormat("pair %d: symbol '%s' not found; ", i + 1, Trim(sym[i]));
            continue;
           }
         if(Listed(out, s.name))
           {
            err += StringFormat("pair %d: %s is listed twice - second one ignored; ", i + 1, s.name);
            continue;
           }
         string kv[];
         int nk = StringSplit(settings[i], ';', kv);
         for(int k = 0; k < nk; k++)
           {
            string p[];
            if(StringSplit(kv[k], '=', p) == 2 && ShortKey(s, Trim(p[0]), StringToDouble(Trim(p[1]))))
               continue;
            if(Trim(kv[k]) != "")
               s.settings += Trim(kv[k]) + ";";
           }
         int m = ArraySize(out);
         ArrayResize(out, m + 1);
         out[m] = s;
        }
      if(slot > 0 && ArraySize(out) == 0 && err == "")
         err = StringFormat("symbol slot %d is beyond the pairs switched on (%d)", slot, pos);
      return ArraySize(out) > 0;
     }
  };

#endif
//+------------------------------------------------------------------+
