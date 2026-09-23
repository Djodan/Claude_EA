//+------------------------------------------------------------------+
//|                                                    GuardBase.mqh |
//|  Trade guards decide whether a NEW position may be opened right  |
//|  now (session, spread, daily limits, ...). They never block      |
//|  closing positions.                                              |
//|                                                                  |
//|  To add a guard: derive from CGuard, implement CanOpen() (set    |
//|  m_status to explain the decision) and register it in Claude.mq5 |
//|  with g_guards.Add(...).                                         |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDBASE_MQH
#define CLAUDE_GUARDBASE_MQH

#include "../Core/Defines.mqh"

class CGuard
  {
protected:
   string            m_name;
   string            m_symbol;
   ulong             m_magic;
   string            m_status;

public:
                     CGuard(const string name) : m_name(name), m_symbol(""), m_magic(0), m_status("") {}
   virtual          ~CGuard(void) {}

   virtual bool      Init(const string symbol, const ulong magic)
     {
      m_symbol = symbol;
      m_magic  = magic;
      return true;
     }
   virtual void      Deinit(void) {}

   //--- may a new position be opened now? (sets m_status)
   virtual bool      CanOpen(void) = 0;

   //--- called every tick (e.g. to flatten when a limit is hit)
   virtual void      OnTick(void) {}

   string            Name(void)   const { return m_name; }
   string            Status(void) const { return m_status; }
  };

#endif
//+------------------------------------------------------------------+
