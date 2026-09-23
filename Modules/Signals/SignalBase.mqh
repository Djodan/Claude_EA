//+------------------------------------------------------------------+
//|                                                   SignalBase.mqh |
//|  Base class for every signal module.                             |
//|                                                                  |
//|  To add a new module:                                            |
//|   1. Derive from CSeriesModule (bar-based) or CSignalModule.     |
//|   2. In Update(), set m_last (signal on the last closed bar)     |
//|      and m_bias (+1 / -1 / 0 current directional state).         |
//|   3. Filters override Allows() (or AllowsAt() in CSeriesModule)  |
//|      - directional filters can just rely on the bias.            |
//|   4. Register it in Claude.mq5 with g_signals.Add(...) as a      |
//|      ROLE_TRIGGER or ROLE_FILTER.                                |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALBASE_MQH
#define CLAUDE_SIGNALBASE_MQH

#include "../Core/Defines.mqh"
#include "../Visual/ChartDrawer.mqh"

class CSignalModule
  {
protected:
   string            m_name;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ENUM_TIMEFRAMES   m_ownTf;     // PERIOD_CURRENT = use the EA's signal timeframe
   ENUM_MODULE_ROLE  m_role;
   bool              m_ready;
   SSignal           m_last;
   int               m_bias;

public:
                     CSignalModule(const string name)
      : m_name(name), m_symbol(""), m_tf(PERIOD_CURRENT), m_ownTf(PERIOD_CURRENT), m_role(ROLE_TRIGGER), m_ready(false), m_bias(0)
     {
      m_last.Reset();
     }
   virtual          ~CSignalModule(void) {}

   //--- lifecycle
   virtual bool      Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      m_symbol = symbol;
      m_tf     = (m_ownTf != PERIOD_CURRENT) ? m_ownTf : tf;
      if(m_tf == PERIOD_CURRENT)
         m_tf = (ENUM_TIMEFRAMES)Period();
      return true;
     }
   virtual void      Deinit(void) {}

   //--- recompute on closed bars; return false if not enough data yet
   virtual bool      Update(void) = 0;

   //--- all signals within the module's loaded history (for drawing on attach)
   virtual int       History(SSignal &out[]) { ArrayResize(out, 0); return 0; }

   //--- bias as it was known at time t (used to filter historic trigger signals)
   virtual int       BiasAt(const datetime t) { return m_bias; }

   //--- filter decision: may a trigger signal in 'dir' pass?
   //    historic = evaluate as of time t instead of the latest closed bar
   virtual bool      Allows(const ENUM_SIGNAL_DIR dir, const bool historic, const datetime t)
     {
      int bias = historic ? BiasAt(t) : m_bias;
      return bias == (int)dir;
     }

   //--- short text for the dashboard
   virtual string    Status(void)
     {
      if(!m_ready)
         return "waiting for data";
      return m_bias > 0 ? "UP" : (m_bias < 0 ? "DOWN" : "FLAT");
     }

   //--- optional module-specific chart overlay (lines, zones, ...)
   virtual void      DrawOverlay(CChartDrawer &drawer) {}

   //--- accessors
   string            Name(void)  const { return m_name; }
   void              Name(const string name) { m_name = name; }
   ENUM_MODULE_ROLE  Role(void)  const { return m_role; }
   void              Role(const ENUM_MODULE_ROLE role) { m_role = role; }
   void              Timeframe(const ENUM_TIMEFRAMES tf) { m_ownTf = tf; }   // call before Init
   ENUM_TIMEFRAMES   Timeframe(void) const { return m_tf; }
   bool              Ready(void) const { return m_ready; }
   int               Bias(void)  const { return m_bias; }
   void              Last(SSignal &out) const { out = m_last; }
  };

#endif
//+------------------------------------------------------------------+
