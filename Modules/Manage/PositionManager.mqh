//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|  Runs every position module over this EA's open positions.       |
//|  Modules run in registration order and share one SPosition, so   |
//|  e.g. a partial close is visible to the trailing module after it.|
//+------------------------------------------------------------------+
#ifndef CLAUDE_POSITIONMANAGER_MQH
#define CLAUDE_POSITIONMANAGER_MQH

#include "PositionModule.mqh"

class CPositionManager
  {
private:
   CPositionModule  *m_modules[];
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;

public:
                     CPositionManager(void) : m_symbol(""), m_magic(0) {}
                    ~CPositionManager(void) { Deinit(); }

   //--- takes ownership of the module
   bool              Add(CPositionModule *module)
     {
      if(CheckPointer(module) == POINTER_INVALID)
         return false;
      int n = ArraySize(m_modules);
      ArrayResize(m_modules, n + 1);
      m_modules[n] = module;
      return true;
     }

   bool              Init(const string symbol, const ulong magic, const ENUM_TIMEFRAMES tf, const int deviation, CAtrProvider *atr)
     {
      m_symbol = symbol;
      m_magic  = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviation);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      for(int i = 0; i < ArraySize(m_modules); i++)
         if(!m_modules[i].Init(symbol, magic, tf, GetPointer(m_trade), atr))
           {
            PrintFormat("PositionManager: module %s failed to initialise", m_modules[i].Name());
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

   void              OnTick(void)
     {
      if(ArraySize(m_modules) == 0)
         return;

      // collect tickets first - modules may close positions while we iterate
      ulong tickets[];
      int   count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         ArrayResize(tickets, count + 1, 8);
         tickets[count++] = ticket;
        }

      for(int k = 0; k < count; k++)
        {
         if(!PositionSelectByTicket(tickets[k]))
            continue;
         SPosition pos;
         pos.ticket   = tickets[k];
         pos.type     = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         pos.open     = PositionGetDouble(POSITION_PRICE_OPEN);
         pos.sl       = PositionGetDouble(POSITION_SL);
         pos.tp       = PositionGetDouble(POSITION_TP);
         pos.volume   = PositionGetDouble(POSITION_VOLUME);
         pos.openTime = (datetime)PositionGetInteger(POSITION_TIME);
         pos.price    = pos.type == POSITION_TYPE_BUY ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                                      : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         pos.closed   = false;

         for(int i = 0; i < ArraySize(m_modules) && !pos.closed; i++)
            m_modules[i].Manage(pos);
        }
     }

   //--- summary for the dashboard
   string            Summary(void)
     {
      int    n   = 0;
      double pnl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         n++;
         pnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      return StringFormat("Positions: %d  floating %.2f %s", n, pnl, AccountInfoString(ACCOUNT_CURRENCY));
     }

   int               Total(void) const { return ArraySize(m_modules); }
   string            ModuleName(const int i) const { return m_modules[i].Name(); }
  };

#endif
//+------------------------------------------------------------------+
