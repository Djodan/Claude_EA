//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|  Simple on-chart text panel. The EA passes in whatever lines it  |
//|  wants shown; the panel resizes to fit.                          |
//+------------------------------------------------------------------+
#ifndef CLAUDE_DASHBOARD_MQH
#define CLAUDE_DASHBOARD_MQH

class CDashboard
  {
private:
   string            m_prefix;
   bool              m_enabled;
   int               m_x;
   int               m_y;
   int               m_fontSize;
   int               m_lines;
   color             m_textColor;
   color             m_bgColor;

   string            LineName(const int i) const { return m_prefix + "line_" + IntegerToString(i); }

public:
                     CDashboard(void)
      : m_prefix("CLD_dash_"), m_enabled(false), m_x(10), m_y(20), m_fontSize(9), m_lines(0),
        m_textColor(clrWhite), m_bgColor(C'25,25,30') {}

   void              Init(const string prefix, const bool enabled, const int x, const int y, const int fontSize)
     {
      m_prefix   = prefix;
      m_x        = x;
      m_y        = y;
      m_fontSize = fontSize;
      m_enabled  = enabled && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE)) &&
                   !MQLInfoInteger(MQL_OPTIMIZATION);
     }

   bool              Enabled(void) const { return m_enabled; }

   void              Show(const string &lines[])
     {
      color none[];
      Show(lines, none);
     }

   //--- colours[i] overrides the colour of line i (clrNONE = default)
   void              Show(const string &lines[], const color &colours[])
     {
      if(!m_enabled)
         return;
      int n       = ArraySize(lines);
      int lineH   = (int)MathRound(m_fontSize * 1.9);
      int maxLen  = 0;
      for(int i = 0; i < n; i++)
         maxLen = MathMax(maxLen, StringLen(lines[i]));
      int width   = (int)MathRound(maxLen * m_fontSize * 0.78) + 20;
      int height  = n * lineH + 12;

      string bg = m_prefix + "bg";
      if(ObjectFind(0, bg) < 0)
        {
         ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
        }
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, m_bgColor);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDimGray);

      for(int i = 0; i < n; i++)
        {
         string name = LineName(i);
         if(ObjectFind(0, name) < 0)
           {
            ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
           }
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x + 10);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + 6 + i * lineH);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_fontSize);
         color c = (i < ArraySize(colours) && colours[i] != clrNONE) ? colours[i] : (i == 0 ? clrGold : m_textColor);
         ObjectSetInteger(0, name, OBJPROP_COLOR, c);
         ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
        }
      for(int i = n; i < m_lines; i++)   // remove lines no longer used
         ObjectDelete(0, LineName(i));
      m_lines = n;
     }

   void              Clear(void) { ObjectsDeleteAll(0, m_prefix); m_lines = 0; }
  };

#endif
//+------------------------------------------------------------------+
