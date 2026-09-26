//+------------------------------------------------------------------+
//|                                                      Profile.mqh |
//|  Per-symbol parameter profile: a .set file whose values replace  |
//|  the EA inputs for that one symbol.                              |
//|                                                                  |
//|  File: Common\Files\ClaudeEA\profiles\<SYMBOL>.set               |
//|  Format: the tester's own .set (Inputs -> right-click -> Save)   |
//|  or plain "InpName=value" lines (ANSI or UTF-16). Only the names |
//|  present override; everything else keeps the EA input.           |
//|  AddText() adds "key=value;..." pairs (the Pair inputs of one    |
//|  set, v4.52); they beat the file. Text keys that the EA never    |
//|  reads are reported by UnusedText() (typos show on the health).  |
//+------------------------------------------------------------------+
#ifndef CLAUDE_PROFILE_MQH
#define CLAUDE_PROFILE_MQH

#define PROFILE_DIR "ClaudeEA\\profiles\\"

class CProfile
  {
private:
   string            m_keys[];
   string            m_vals[];
   bool              m_text[];       // key came from AddText (pair settings), not from the file
   bool              m_used[];       // key was read while building the config
   string            m_file;
   int               m_textCount;

   int               Index(const string key) const
     {
      for(int i = 0; i < ArraySize(m_keys); i++)
         if(m_keys[i] == key)
            return i;
      return -1;
     }

   int               Find(const string key)
     {
      int i = Index(key);
      if(i >= 0)
         m_used[i] = true;
      return i;
     }

   void              Put(const string key, const string val, const bool text)
     {
      int i = Index(key);
      if(i < 0)
        {
         i = ArraySize(m_keys);
         ArrayResize(m_keys, i + 1);
         ArrayResize(m_vals, i + 1);
         ArrayResize(m_text, i + 1);
         ArrayResize(m_used, i + 1);
        }
      m_keys[i] = key;
      m_vals[i] = val;
      m_text[i] = text;
      m_used[i] = false;
     }

   bool              Read(const string name, const int enc)
     {
      int h = FileOpen(name, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | enc);
      if(h == INVALID_HANDLE)
         return false;
      ArrayResize(m_keys, 0);
      ArrayResize(m_vals, 0);
      ArrayResize(m_text, 0);
      ArrayResize(m_used, 0);
      while(!FileIsEnding(h))
        {
         string line = FileReadString(h);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(line == "" || StringGetCharacter(line, 0) == ';')
            continue;
         int eq = StringFind(line, "=");
         if(eq <= 0)
            continue;
         string key = StringSubstr(line, 0, eq);
         string val = StringSubstr(line, eq + 1);
         int bar = StringFind(val, "||");                  // tester format: value||start||step||stop||Y/N
         if(bar >= 0)
            val = StringSubstr(val, 0, bar);
         StringTrimRight(key);
         StringTrimLeft(val);
         Put(key, val, false);
        }
      FileClose(h);
      return ArraySize(m_keys) > 0 && StringFind(m_keys[0], "Inp") == 0;
     }

public:
                     CProfile(void) : m_file(""), m_textCount(0) {}

   //--- "key=value;key=value" (the "Inp" prefix is optional); returns the bad items ("" = all fine)
   string            AddText(const string text)
     {
      string bad = "", items[];
      int n = StringSplit(text, ';', items);
      for(int i = 0; i < n; i++)
        {
         string it = items[i];
         StringTrimLeft(it);
         StringTrimRight(it);
         if(it == "")
            continue;
         int eq = StringFind(it, "=");
         if(eq <= 0)
           {
            bad += "'" + it + "' ";
            continue;
           }
         string key = StringSubstr(it, 0, eq), val = StringSubstr(it, eq + 1);
         StringTrimRight(key);
         StringTrimLeft(val);
         if(StringFind(key, "Inp") != 0)
            key = "Inp" + key;
         Put(key, val, true);
         m_textCount++;
        }
      return bad;
     }

   //--- pair-settings keys the EA never read (unknown names / typos)
   string            UnusedText(void) const
     {
      string r = "";
      for(int i = 0; i < ArraySize(m_keys); i++)
         if(m_text[i] && !m_used[i])
            r += (r == "" ? "" : ", ") + m_keys[i];
      return r;
     }

   int               TextCount(void) const { return m_textCount; }

   //--- true if a profile for the symbol was found and read
   bool              Load(const string symbol)
     {
      m_file = PROFILE_DIR + symbol + ".set";
      if(!FileIsExist(m_file, FILE_COMMON))
         return false;
      return Read(m_file, FILE_UNICODE) || Read(m_file, FILE_ANSI);
     }

   string            File(void) const  { return m_file; }
   int               Count(void) const { return ArraySize(m_keys); }
   bool              Has(const string key) const { return Index(key) >= 0; }

   double            D(const string key, const double def)
     {
      int i = Find(key);
      return i < 0 ? def : StringToDouble(m_vals[i]);
     }

   long              L(const string key, const long def)
     {
      int i = Find(key);
      return i < 0 ? def : StringToInteger(m_vals[i]);
     }

   bool              B(const string key, const bool def)
     {
      int i = Find(key);
      if(i < 0)
         return def;
      string v = m_vals[i];
      StringToLower(v);
      return v == "true" || v == "1";
     }

   string            S(const string key, const string def)
     {
      int i = Find(key);
      return i < 0 ? def : m_vals[i];
     }
  };

#endif
//+------------------------------------------------------------------+
