//+------------------------------------------------------------------+
//|                                             GuardDailyLimits.mqh |
//|  Per-day risk limits for this EA (all strategies, base magic):   |
//|   - max daily loss %     (closed + floating, vs. day-start bal.) |
//|   - daily profit target %                                        |
//|   - max trades opened per day                                    |
//|  Optionally flattens this EA's positions when a P/L limit hits.  |
//|  Once a limit is hit, trading stays halted until the next day.   |
//+------------------------------------------------------------------+
#ifndef CLAUDE_GUARDDAILYLIMITS_MQH
#define CLAUDE_GUARDDAILYLIMITS_MQH

#include <Trade/Trade.mqh>
#include "GuardBase.mqh"

struct SGuardDailySettings
  {
   double            maxLossPct;      // 0 = off
   double            profitTargetPct; // 0 = off
   int               maxTrades;       // 0 = off
   bool              closeOnLimit;
  };

class CGuardDailyLimits : public CGuard
  {
private:
   SGuardDailySettings m_cfg;
   CTrade            m_trade;
   datetime          m_day;
   datetime          m_lastRefresh;
   bool              m_halted;
   string            m_haltReason;
   double            m_closedPnl;
   double            m_floatPnl;
   int               m_trades;

   //--- any strategy of this EA: magic in [base, base + 100)
   bool              IsOurs(const string symbol, const long magic) const
     {
      return symbol == m_symbol && (ulong)magic >= m_magic && (ulong)magic < m_magic + 100;
     }

   void              Refresh(void)
     {
      datetime day = iTime(m_symbol, PERIOD_D1, 0);
      if(day == 0)
         day = TimeCurrent() - TimeCurrent() % 86400;
      if(day != m_day)
        {
         m_day        = day;
         m_halted     = false;
         m_haltReason = "";
        }

      m_closedPnl = 0.0;
      m_trades    = 0;
      if(HistorySelect(m_day, TimeCurrent() + 60))
        {
         for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
           {
            ulong deal = HistoryDealGetTicket(i);
            if(deal == 0 || !IsOurs(HistoryDealGetString(deal, DEAL_SYMBOL), HistoryDealGetInteger(deal, DEAL_MAGIC)))
               continue;
            long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_IN)
               m_trades++;
            m_closedPnl += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                           HistoryDealGetDouble(deal, DEAL_COMMISSION);
           }
        }

      m_floatPnl = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            continue;
         m_floatPnl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      m_lastRefresh = TimeCurrent();
     }

   double            DayPnlPct(void) const
     {
      double startBalance = AccountInfoDouble(ACCOUNT_BALANCE) - m_closedPnl;
      if(startBalance <= 0.0)
         return 0.0;
      return (m_closedPnl + m_floatPnl) / startBalance * 100.0;
     }

   //--- returns true and sets the halt reason if a P/L limit is hit
   bool              PnlLimitHit(void)
     {
      double pct = DayPnlPct();
      if(m_cfg.maxLossPct > 0.0 && pct <= -m_cfg.maxLossPct)
        {
         m_haltReason = StringFormat("daily loss %.2f%% hit", pct);
         return true;
        }
      if(m_cfg.profitTargetPct > 0.0 && pct >= m_cfg.profitTargetPct)
        {
         m_haltReason = StringFormat("daily target %.2f%% hit", pct);
         return true;
        }
      return false;
     }

   void              CloseAll(void)
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !IsOurs(PositionGetString(POSITION_SYMBOL), PositionGetInteger(POSITION_MAGIC)))
            continue;
         if(!m_trade.PositionClose(ticket))
            PrintFormat("%s: close #%I64u failed, retcode %u", m_name, ticket, m_trade.ResultRetcode());
        }
     }

public:
                     CGuardDailyLimits(void)
      : CGuard("DailyLimits"), m_day(0), m_lastRefresh(0), m_halted(false), m_haltReason(""),
        m_closedPnl(0.0), m_floatPnl(0.0), m_trades(0)
     {
      m_cfg.maxLossPct      = 0.0;
      m_cfg.profitTargetPct = 0.0;
      m_cfg.maxTrades       = 0;
      m_cfg.closeOnLimit    = false;
     }

   void              Configure(const SGuardDailySettings &cfg) { m_cfg = cfg; }

   virtual bool      Init(const string symbol, const ulong magic)
     {
      CGuard::Init(symbol, magic);
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      Refresh();
      return true;
     }

   virtual bool      CanOpen(void)
     {
      Refresh();
      if(!m_halted && PnlLimitHit())
         m_halted = true;
      m_status = StringFormat("day P/L %.2f%%, trades %d", DayPnlPct(), m_trades);
      if(m_halted)
        {
         m_status = m_haltReason;
         return false;
        }
      if(m_cfg.maxTrades > 0 && m_trades >= m_cfg.maxTrades)
        {
         m_status = StringFormat("max %d trades/day reached", m_cfg.maxTrades);
         return false;
        }
      return true;
     }

   //--- check P/L limits every few seconds and flatten if configured
   virtual void      OnTick(void)
     {
      if(m_cfg.maxLossPct <= 0.0 && m_cfg.profitTargetPct <= 0.0)
         return;
      if(TimeCurrent() - m_lastRefresh < 5 && iTime(m_symbol, PERIOD_D1, 0) == m_day)
         return;
      Refresh();
      if(m_halted || !PnlLimitHit())
         return;
      m_halted = true;
      PrintFormat("%s: %s - trading halted for today", m_name, m_haltReason);
      if(m_cfg.closeOnLimit)
         CloseAll();
     }
  };

#endif
//+------------------------------------------------------------------+
