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

//--- 1-7: original S1-S3 combinations (round 4) · 8-11: intraday strategies (round 15)
enum ENUM_EA_PRESET
  {
   PRESET_CUSTOM   = 0,  // 0 Custom (use inputs)
   PRESET_TREND    = 1,  // 1 S1 Trend
   PRESET_BREAKOUT = 2,  // 2 S2 Asian Breakout (best_2026)
   PRESET_PULLBACK = 3,  // 3 S3 Pullback
   PRESET_T_B      = 4,  // 4 Trend + Breakout
   PRESET_T_P      = 5,  // 5 Trend + Pullback
   PRESET_B_P      = 6,  // 6 Breakout + Pullback
   PRESET_ALL      = 7,  // 7 S1 + S2 + S3
   PRESET_VWAP     = 8,  // 8 S5 VWAP trend pullback (intraday)
   PRESET_PBO      = 9,  // 9 S6 Pullback-window breakout (intraday)
   PRESET_VWAP_PBO = 10, // 10 S5 + S6 (intraday)
   PRESET_INTRA_BRK= 11, // 11 S5 + S6 + S2 Asian breakout
   PRESET_SCALP_MR = 12, // 12 Scalper: mean reversion
   PRESET_SCALP_MO = 13, // 13 Scalper: momentum burst
   PRESET_SCALP    = 14, // 14 Scalper: mean reversion + momentum
   PRESET_SCALP_PBO= 15  // 15 Scalper + S6 pullback breakout
  };

void ApplyPreset(const ENUM_EA_PRESET preset, SEAConfig &c)
  {
   if(preset == PRESET_CUSTOM)
      return;
   c.trend.s.enabled = (preset == PRESET_TREND || preset == PRESET_T_B || preset == PRESET_T_P || preset == PRESET_ALL);
   c.brk.s.enabled   = (preset == PRESET_BREAKOUT || preset == PRESET_T_B || preset == PRESET_B_P || preset == PRESET_ALL ||
                        preset == PRESET_INTRA_BRK);
   c.pb.s.enabled    = (preset == PRESET_PULLBACK || preset == PRESET_T_P || preset == PRESET_B_P || preset == PRESET_ALL);
   c.vw.s.enabled    = (preset == PRESET_VWAP || preset == PRESET_VWAP_PBO || preset == PRESET_INTRA_BRK);
   c.pbo.s.enabled   = (preset == PRESET_PBO || preset == PRESET_VWAP_PBO || preset == PRESET_INTRA_BRK || preset == PRESET_SCALP_PBO);
   c.mr.s.enabled    = (preset == PRESET_SCALP_MR || preset == PRESET_SCALP || preset == PRESET_SCALP_PBO);
   c.mo.s.enabled    = (preset == PRESET_SCALP_MO || preset == PRESET_SCALP || preset == PRESET_SCALP_PBO);
  }

#endif
//+------------------------------------------------------------------+
