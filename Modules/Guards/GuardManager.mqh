//+------------------------------------------------------------------+
//|                                                 GuardManager.mqh |
//|  Owns the trade guards; a position may open only if all pass.    |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDMANAGER_MQH
#define CLAUDE_GUARDMANAGER_MQH

#include "GuardBase.mqh"

class CGuardManager
  {
private:
   CGuard           *m_guards[];

public:
                    ~CGuardManager(void) { Deinit(); }

   //--- takes ownership of the guard
   bool              Add(CGuard *guard)
     {
      if(CheckPointer(guard) == POINTER_INVALID)
         return false;
      int n = ArraySize(m_guards);
      ArrayResize(m_guards, n + 1);
      m_guards[n] = guard;
      return true;
     }

   bool              Init(const string symbol, const ulong magic)
     {
      for(int i = 0; i < ArraySize(m_guards); i++)
         if(!m_guards[i].Init(symbol, magic))
           {
            PrintFormat("GuardManager: guard %s failed to initialise", m_guards[i].Name());
            return false;
           }
      return true;
     }

   void              Deinit(void)
     {
      for(int i = 0; i < ArraySize(m_guards); i++)
        {
         if(CheckPointer(m_guards[i]) == POINTER_INVALID)
            continue;
         m_guards[i].Deinit();
         if(CheckPointer(m_guards[i]) == POINTER_DYNAMIC)
            delete m_guards[i];
        }
      ArrayResize(m_guards, 0);
     }

   //--- all guards must pass; reason names the first one that blocks
   bool              CanOpen(string &reason)
     {
      reason = "";
      for(int i = 0; i < ArraySize(m_guards); i++)
         if(!m_guards[i].CanOpen())
           {
            reason = m_guards[i].Name() + ": " + m_guards[i].Status();
            return false;
           }
      return true;
     }

   void              OnTick(void)
     {
      for(int i = 0; i < ArraySize(m_guards); i++)
         m_guards[i].OnTick();
     }

   //--- one line per guard for the dashboard
   int               Statuses(string &lines[])
     {
      int n = ArraySize(m_guards);
      ArrayResize(lines, n);
      for(int i = 0; i < n; i++)
        {
         bool ok = m_guards[i].CanOpen();
         lines[i] = StringFormat("%s: %s %s", m_guards[i].Name(), ok ? "OK" : "BLOCK", m_guards[i].Status());
        }
      return n;
     }

   int               Total(void) const { return ArraySize(m_guards); }
  };

#endif
//+------------------------------------------------------------------+
