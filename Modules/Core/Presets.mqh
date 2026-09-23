//+------------------------------------------------------------------+
//|                                                      Presets.mqh |
//|  Named test configurations. Optimise the "Preset" input over     |
//|  its range in the Strategy Tester to backtest all of them in one |
//|  run. PRESET_CUSTOM uses the inputs exactly as set.              |
//|  Presets only switch strategies / guards on and off - every      |
//|  other setting comes from the inputs.                            |
//|  Research/PROGRESS.md records what each round tested and why.    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_PRESETS_MQH
#define CLAUDE_PRESETS_MQH

#include "Config.mqh"

//--- Round 4 (M1/M2): screen strategy combinations; guards come from the inputs
enum ENUM_EA_PRESET
  {
   PRESET_CUSTOM   = 0,  // 0 Custom (use inputs)
   PRESET_TREND    = 1,  // 1 S1 Trend
   PRESET_BREAKOUT = 2,  // 2 S2 Breakout
   PRESET_PULLBACK = 3,  // 3 S3 Pullback
   PRESET_T_B      = 4,  // 4 Trend + Breakout
   PRESET_T_P      = 5,  // 5 Trend + Pullback
   PRESET_B_P      = 6,  // 6 Breakout + Pullback
   PRESET_ALL      = 7   // 7 All strategies
  };

void ApplyPreset(const ENUM_EA_PRESET preset, SEAConfig &c)
  {
   if(preset == PRESET_CUSTOM)
      return;
   c.trend.s.enabled = (preset == PRESET_TREND || preset == PRESET_T_B || preset == PRESET_T_P || preset == PRESET_ALL);
   c.brk.s.enabled   = (preset == PRESET_BREAKOUT || preset == PRESET_T_B || preset == PRESET_B_P || preset == PRESET_ALL);
   c.pb.s.enabled    = (preset == PRESET_PULLBACK || preset == PRESET_T_P || preset == PRESET_B_P || preset == PRESET_ALL);
  }

#endif
//+------------------------------------------------------------------+
