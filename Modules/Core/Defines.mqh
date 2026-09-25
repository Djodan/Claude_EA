//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|  Shared enums and structs used by every Claude EA module.        |
//+------------------------------------------------------------------+
#ifndef CLAUDE_DEFINES_MQH
#define CLAUDE_DEFINES_MQH

// Pine's "na" value
#define PINE_NA EMPTY_VALUE

//--- Signal direction (event on a closed bar)
enum ENUM_SIGNAL_DIR
  {
   SIG_SELL = -1,  // Sell
   SIG_NONE =  0,  // None
   SIG_BUY  =  1   // Buy
  };

//--- How a signal module participates in the final decision
enum ENUM_MODULE_ROLE
  {
   ROLE_TRIGGER,   // Trigger (fires signals)
   ROLE_FILTER     // Filter (bias must agree)
  };

//--- DJ Trend basis moving-average type
enum ENUM_BASIS_TYPE
  {
   BASIS_EMA,      // EMA
   BASIS_SMA,      // SMA
   BASIS_HMA,      // HMA
   BASIS_ALMA      // ALMA
  };

//--- What the EA is allowed to do with signals
enum ENUM_EA_TRADE_MODE
  {
   EA_TRADE_OFF,         // Signals / alerts only
   EA_TRADE_LONG_ONLY,   // Long only
   EA_TRADE_SHORT_ONLY,  // Short only
   EA_TRADE_BOTH         // Long and short
  };

enum ENUM_SL_MODE
  {
   SL_NONE,        // No stop loss
   SL_ATR,         // ATR multiple
   SL_POINTS,      // Fixed points
   SL_SIGNAL       // Signal's own stop (fallback ATR)
  };

enum ENUM_TP_MODE
  {
   TP_NONE,        // No take profit
   TP_ATR,         // ATR multiple
   TP_POINTS,      // Fixed points
   TP_RR           // Risk:Reward (needs SL)
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED,          // Fixed lots
   LOT_RISK_PERCENT    // % of equity at risk (needs SL)
  };

//--- A signal produced on a closed bar
struct SSignal
  {
   ENUM_SIGNAL_DIR   dir;
   datetime          barTime;     // open time of the signal bar
   datetime          closeTime;   // time the signal bar closed (decision time)
   double            price;       // close of the signal bar
   double            high;
   double            low;
   double            atr;         // volatility at the signal bar (for SL/TP/labels)
   double            sl;          // suggested stop price from the module (0 = none)
   double            tp;          // suggested target price from the module (0 = none)
   double            level;       // price the signal is based on (e.g. breakout level; 0 = none)
   datetime          expiry;      // last time the signal may still be acted on (0 = none)
   string            source;      // module name

   void              Reset(void)
     {
      dir       = SIG_NONE;
      barTime   = 0;
      closeTime = 0;
      price     = 0.0;
      high      = 0.0;
      low       = 0.0;
      atr       = 0.0;
      sl        = 0.0;
      tp        = 0.0;
      level     = 0.0;
      expiry    = 0;
      source    = "";
     }
  };

string SignalDirToString(const ENUM_SIGNAL_DIR dir)
  {
   if(dir == SIG_BUY)
      return "BUY";
   if(dir == SIG_SELL)
      return "SELL";
   return "NONE";
  }

#endif
//+------------------------------------------------------------------+
