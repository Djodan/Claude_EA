//+------------------------------------------------------------------+
//|                                                  ChartDrawer.mqh |
//|  All chart objects created by the EA go through this class so    |
//|  they share one prefix and can be cleaned up together.           |
//+------------------------------------------------------------------+
#ifndef CLAUDE_CHARTDRAWER_MQH
#define CLAUDE_CHARTDRAWER_MQH

#include "../Core/Defines.mqh"

struct SDrawSettings
  {
   bool              enabled;       // any drawing at all (signals or overlays)
   bool              drawSignals;   // BUY / SELL labels
   string            buyText;
   string            sellText;
   color             buyColor;
   color             sellColor;
   int               fontSize;
   bool              drawHistory;
  };

class CChartDrawer
  {
private:
   string            m_prefix;
   SDrawSettings     m_cfg;
   bool              m_canDraw;

   string            SignalName(const SSignal &s, const string part) const
     {
      return m_prefix + "sig_" + s.source + "_" + IntegerToString((long)s.barTime) + "_" + part;
     }

public:
                     CChartDrawer(void) : m_prefix("CLD_"), m_canDraw(false) {}

   void              Init(const string prefix, const SDrawSettings &cfg)
     {
      m_prefix  = prefix;
      m_cfg     = cfg;
      // skip object work in non-visual backtests / optimisation
      m_canDraw = m_cfg.enabled &&
                  (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) &&
                  !MQLInfoInteger(MQL_OPTIMIZATION);
     }

   bool              CanDraw(void)     const { return m_canDraw; }
   bool              DrawHistory(void) const { return m_canDraw && m_cfg.drawSignals && m_cfg.drawHistory; }
   string            Prefix(void)      const { return m_prefix; }

   //--- BUY label below the low, SELL label above the high (offset by 1 ATR, like the Pine script)
   void              DrawSignal(const SSignal &s)
     {
      if(!m_canDraw || !m_cfg.drawSignals || s.dir == SIG_NONE)
         return;

      bool   isBuy = (s.dir == SIG_BUY);
      color  clr   = isBuy ? m_cfg.buyColor : m_cfg.sellColor;
      double arrowPrice = isBuy ? s.low : s.high;
      double textPrice  = isBuy ? s.low - s.atr : s.high + s.atr;

      string arrow = SignalName(s, "arrow");
      if(ObjectFind(0, arrow) < 0)
         ObjectCreate(0, arrow, OBJ_ARROW, 0, s.barTime, arrowPrice);
      ObjectSetInteger(0, arrow, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, arrow, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, arrow, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, arrow, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrow, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrow, OBJPROP_HIDDEN, true);

      string text = SignalName(s, "text");
      if(ObjectFind(0, text) < 0)
         ObjectCreate(0, text, OBJ_TEXT, 0, s.barTime, textPrice);
      ObjectSetString(0, text, OBJPROP_TEXT, isBuy ? m_cfg.buyText : m_cfg.sellText);
      ObjectSetString(0, text, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, text, OBJPROP_FONTSIZE, m_cfg.fontSize);
      ObjectSetInteger(0, text, OBJPROP_ANCHOR, isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetInteger(0, text, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, text, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, text, OBJPROP_HIDDEN, true);
      ObjectSetString(0, text, OBJPROP_TOOLTIP,
                      StringFormat("%s %s @ %s", s.source, SignalDirToString(s.dir),
                                   DoubleToString(s.price, _Digits)));
     }

   //--- straight line segment (used by modules for overlays such as a basis line)
   void              DrawSegment(const string name, const datetime t1, const double p1,
                                 const datetime t2, const double p2, const color clr, const int width = 2)
     {
      if(!m_canDraw)
         return;
      string full = m_prefix + name;
      if(ObjectFind(0, full) < 0)
        {
         ObjectCreate(0, full, OBJ_TREND, 0, t1, p1, t2, p2);
         ObjectSetInteger(0, full, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, full, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, full, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, full, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, full, OBJPROP_BACK, true);
        }
      else
        {
         ObjectMove(0, full, 0, t1, p1);
         ObjectMove(0, full, 1, t2, p2);
        }
      ObjectSetInteger(0, full, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, full, OBJPROP_WIDTH, width);
     }

   void              Delete(const string name) { ObjectDelete(0, m_prefix + name); }
   void              Clear(void)               { ObjectsDeleteAll(0, m_prefix); }
   void              Redraw(void)              { if(m_canDraw) ChartRedraw(0); }
  };

#endif
//+------------------------------------------------------------------+
