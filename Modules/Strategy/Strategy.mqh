//+------------------------------------------------------------------+
//|                                                     Strategy.mqh |
//|  One self-contained strategy of the portfolio:                   |
//|    signal modules (trigger + filters) on its own timeframe,      |
//|    its own magic number, trade/risk settings and position        |
//|    management. Guards are shared across strategies.              |
//|                                                                  |
//|  To add a strategy: create a CStrategy, add signal and position  |
//|  modules, Init() it and push it into the EA's strategy list.     |
//+------------------------------------------------------------------+
#ifndef CLAUDE_STRATEGY_MQH
#define CLAUDE_STRATEGY_MQH

#include "../Core/NewBar.mqh"
#include "../Math/AtrProvider.mqh"
#include "../Signals/SignalManager.mqh"
#include "../Manage/PositionManager.mqh"
#include "../Trade/RiskManager.mqh"
#include "../Trade/TradeManager.mqh"
#include "../Guards/GuardManager.mqh"

class CStrategy
  {
private:
   string            m_name;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ulong             m_magic;
   bool              m_exitOnFilteredFlip;
   CSignalManager    m_signals;
   CPositionManager  m_positions;
   CRiskManager      m_risk;
   CTradeManager     m_trader;
   CAtrProvider      m_atr;
   CNewBar           m_newBar;
   SSignal           m_lastSignal;

public:
                     CStrategy(const string name) : m_name(name), m_symbol(""), m_tf(PERIOD_CURRENT), m_magic(0),
                     m_exitOnFilteredFlip(false) { m_lastSignal.Reset(); }

   //--- build (before Init); modules are owned by the strategy
   bool              AddSignal(CSignalModule *module, const ENUM_MODULE_ROLE role) { return m_signals.Add(module, role); }
   bool              AddPositionModule(CPositionModule *module) { return m_positions.Add(module); }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf, const ulong magic, const STradeSettings &trade,
                          const SRiskSettings &risk, const int atrLen, const bool exitOnFilteredFlip, CGuardManager *guards)
     {
      m_symbol = symbol;
      m_tf     = (tf == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
      m_magic  = magic;
      m_exitOnFilteredFlip = exitOnFilteredFlip;

      STradeSettings t = trade;
      t.magic   = magic;
      t.comment = m_name;

      if(!m_signals.Init(symbol, m_tf))
         return false;
      m_atr.Init(symbol, m_tf, atrLen);
      if(!m_positions.Init(symbol, magic, m_tf, t.deviation, GetPointer(m_atr)))
         return false;
      m_risk.Init(symbol, risk);
      if(!m_trader.Init(symbol, t, GetPointer(m_risk), guards))
         return false;
      m_newBar.Init(symbol, m_tf);
      SSignal ignored;
      m_signals.Update(ignored);                 // prime with history; never trade the attach bar
      return true;
     }

   void              Deinit(void)
     {
      m_signals.Deinit();
      m_positions.Deinit();
     }

   //--- returns true when a (filtered) signal fired on this tick
   bool              OnTick(SSignal &fired)
     {
      bool got = false;
      if(m_newBar.IsNew())
        {
         m_atr.Update();
         SSignal sig, raw;
         got = m_signals.Update(sig);
         if(!got && m_exitOnFilteredFlip && m_signals.RawTrigger(raw))
            m_trader.OnExitSignal(raw);
         if(got)
           {
            m_lastSignal = sig;
            fired = sig;
            m_trader.OnSignal(sig);
           }
        }
      m_positions.OnTick();
      return got;
     }

   int               History(SSignal &out[]) { return m_signals.History(out); }
   void              DrawOverlays(CChartDrawer &drawer) { m_signals.DrawOverlays(drawer); }

   //--- dashboard lines
   void              Statuses(string &lines[])
     {
      string part[];
      m_signals.Statuses(part);
      int n = ArraySize(part);
      ArrayResize(lines, n + 2);
      lines[0] = StringFormat("%s  #%I64u  %s  %s", m_name, m_magic, StringSubstr(EnumToString(m_tf), 7),
                              m_positions.Summary());
      for(int i = 0; i < n; i++)
         lines[i + 1] = "  " + part[i];
      lines[n + 1] = m_lastSignal.dir == SIG_NONE ? "  last signal: -" :
                     StringFormat("  last signal: %s @ %s %s", SignalDirToString(m_lastSignal.dir),
                                  DoubleToString(m_lastSignal.price, _Digits),
                                  TimeToString(m_lastSignal.closeTime, TIME_DATE | TIME_MINUTES));
     }

   string            Name(void)  const { return m_name; }
   ulong             Magic(void) const { return m_magic; }
   bool              TradingEnabled(void) const { return m_trader.Enabled(); }
  };

#endif
//+------------------------------------------------------------------+
