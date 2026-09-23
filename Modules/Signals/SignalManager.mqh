//+------------------------------------------------------------------+
//|                                                SignalManager.mqh |
//|  Owns the signal modules and combines them into one decision:    |
//|   - the first TRIGGER module that fires provides the signal      |
//|   - every FILTER module must Allow() that direction              |
//+------------------------------------------------------------------+
#ifndef CLAUDE_SIGNALMANAGER_MQH
#define CLAUDE_SIGNALMANAGER_MQH

#include "SignalBase.mqh"

class CSignalManager
  {
private:
   CSignalModule    *m_modules[];

   bool              FiltersAgree(const ENUM_SIGNAL_DIR dir, const bool historic, const datetime t)
     {
      for(int i = 0; i < ArraySize(m_modules); i++)
        {
         if(m_modules[i].Role() != ROLE_FILTER)
            continue;
         if(!m_modules[i].Allows(dir, historic, t))
            return false;
        }
      return true;
     }

public:
                    ~CSignalManager(void) { Deinit(); }

   //--- takes ownership of the module
   bool              Add(CSignalModule *module, const ENUM_MODULE_ROLE role)
     {
      if(CheckPointer(module) == POINTER_INVALID)
         return false;
      module.Role(role);
      int n = ArraySize(m_modules);
      ArrayResize(m_modules, n + 1);
      m_modules[n] = module;
      return true;
     }

   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      for(int i = 0; i < ArraySize(m_modules); i++)
         if(!m_modules[i].Init(symbol, tf))
           {
            PrintFormat("SignalManager: module %s failed to initialise", m_modules[i].Name());
            return false;
           }
      return true;
     }

   void              Deinit(void)
     {
      for(int i = 0; i < ArraySize(m_modules); i++)
        {
         if(CheckPointer(m_modules[i]) == POINTER_INVALID)
            continue;
         m_modules[i].Deinit();
         if(CheckPointer(m_modules[i]) == POINTER_DYNAMIC)
            delete m_modules[i];
        }
      ArrayResize(m_modules, 0);
     }

   //--- update all modules; returns true when a combined signal is produced
   bool              Update(SSignal &out)
     {
      out.Reset();
      bool allReady = true;
      for(int i = 0; i < ArraySize(m_modules); i++)
         if(!m_modules[i].Update())
            allReady = false;
      if(!allReady)
         return false;

      for(int i = 0; i < ArraySize(m_modules); i++)
        {
         if(m_modules[i].Role() != ROLE_TRIGGER)
            continue;
         SSignal s;
         m_modules[i].Last(s);
         if(s.dir == SIG_NONE)
            continue;
         if(!FiltersAgree(s.dir, false, s.closeTime))
            continue;
         out = s;
         return true;
        }
      return false;
     }

   //--- first trigger's signal on the last closed bar, ignoring filters
   //    (used to exit positions on flips that filters block from entering)
   bool              RawTrigger(SSignal &out)
     {
      out.Reset();
      for(int i = 0; i < ArraySize(m_modules); i++)
        {
         if(m_modules[i].Role() != ROLE_TRIGGER || !m_modules[i].Ready())
            continue;
         m_modules[i].Last(out);
         if(out.dir != SIG_NONE)
            return true;
        }
      return false;
     }

   //--- historic combined signals (for drawing on attach)
   int               History(SSignal &out[])
     {
      ArrayResize(out, 0);
      int count = 0;
      for(int i = 0; i < ArraySize(m_modules); i++)
        {
         if(m_modules[i].Role() != ROLE_TRIGGER || !m_modules[i].Ready())
            continue;
         SSignal hist[];
         int n = m_modules[i].History(hist);
         for(int k = 0; k < n; k++)
           {
            if(!FiltersAgree(hist[k].dir, true, hist[k].closeTime))
               continue;
            ArrayResize(out, count + 1, 64);
            out[count++] = hist[k];
           }
        }
      return count;
     }

   void              DrawOverlays(CChartDrawer &drawer)
     {
      for(int i = 0; i < ArraySize(m_modules); i++)
         if(m_modules[i].Ready())
            m_modules[i].DrawOverlay(drawer);
     }

   //--- one line per module for the dashboard
   int               Statuses(string &lines[])
     {
      int n = ArraySize(m_modules);
      ArrayResize(lines, n);
      for(int i = 0; i < n; i++)
         lines[i] = StringFormat("%s [%s] %s: %s", m_modules[i].Name(),
                                 m_modules[i].Role() == ROLE_TRIGGER ? "trigger" : "filter",
                                 StringSubstr(EnumToString(m_modules[i].Timeframe()), 7), m_modules[i].Status());
      return n;
     }

   int               Total(void) const { return ArraySize(m_modules); }
   CSignalModule    *At(const int i)   { return (i >= 0 && i < ArraySize(m_modules)) ? m_modules[i] : NULL; }
  };

#endif
//+------------------------------------------------------------------+
