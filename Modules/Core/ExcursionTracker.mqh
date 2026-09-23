//+------------------------------------------------------------------+
//|                                             ExcursionTracker.mqh |
//|  Records, per position, the maximum favourable (MFE) and adverse |
//|  (MAE) price excursion and the initial stop distance (1R), so    |
//|  the trade export can show how far trades ran before closing.    |
//|  Call OnTick() every tick; data stays after positions close.     |
//+------------------------------------------------------------------+
#ifndef CLAUDE_EXCURSIONTRACKER_MQH
#define CLAUDE_EXCURSIONTRACKER_MQH

class CExcursionTracker
  {
private:
   string            m_symbol;
   ulong             m_baseMagic;
   ulong             m_ids[];
   double            m_mfe[];
   double            m_mae[];
   double            m_risk[];
   int               m_count;
   int               m_last;          // cache of the last looked-up index

   int               Find(const ulong id)
     {
      if(m_last >= 0 && m_last < m_count && m_ids[m_last] == id)
         return m_last;
      for(int i = m_count - 1; i >= 0; i--)
         if(m_ids[i] == id)
           {
            m_last = i;
            return i;
           }
      return -1;
     }

public:
                     CExcursionTracker(void) : m_symbol(""), m_baseMagic(0), m_count(0), m_last(-1) {}

   void              Init(const string symbol, const ulong baseMagic)
     {
      m_symbol    = symbol;
      m_baseMagic = baseMagic;
     }

   void              OnTick(void)
     {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
         if(magic < m_baseMagic || magic >= m_baseMagic + 100)
            continue;
         ulong  id    = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         bool   buy   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double move  = buy ? bid - open : open - ask;   // + = in profit
         int i = Find(id);
         if(i < 0)
           {
            ArrayResize(m_ids, m_count + 1, 256);
            ArrayResize(m_mfe, m_count + 1, 256);
            ArrayResize(m_mae, m_count + 1, 256);
            ArrayResize(m_risk, m_count + 1, 256);
            i = m_count++;
            m_ids[i]  = id;
            m_mfe[i]  = 0.0;
            m_mae[i]  = 0.0;
            double sl = PositionGetDouble(POSITION_SL);
            m_risk[i] = sl > 0.0 ? MathAbs(open - sl) : 0.0;
            m_last    = i;
           }
         if(move > m_mfe[i])
            m_mfe[i] = move;
         if(-move > m_mae[i])
            m_mae[i] = -move;
        }
     }

   //--- false if the position was never seen
   bool              Get(const ulong id, double &mfe, double &mae, double &risk)
     {
      int i = Find(id);
      if(i < 0)
         return false;
      mfe  = m_mfe[i];
      mae  = m_mae[i];
      risk = m_risk[i];
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
