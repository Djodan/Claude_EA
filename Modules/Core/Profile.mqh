//+------------------------------------------------------------------+
//|                                                      Profile.mqh |
//|  Per-symbol parameter profile: a .set file whose values replace  |
//|  the EA inputs for that one symbol.                              |
//|                                                                  |
//|  File: Common\Files\ClaudeEA\profiles\<SYMBOL>.set               |
//|  Format: the tester's own .set (Inputs -> right-click -> Save)   |
//|  or plain "InpName=value" lines (ANSI or UTF-16). Only the names |
//|  present override; everything else keeps the EA input.           |
//+------------------------------------------------------------------+
#ifndef CLAUDE_PROFILE_MQH
#define CLAUDE_PROFILE_MQH

#define PROFILE_DIR "ClaudeEA\\profiles\\"

class CProfile
  {
private:
   string            m_keys[];
   string            m_vals[];
   string            m_file;

   int               Find(const string key) const
     {
      for(int i = 0; i < ArraySize(m_keys); i++)
         if(m_keys[i] == key)
            return i;
      return -1;
     }

   bool              Read(const string name, const int enc)
     {
      int h = FileOpen(name, FILE_READ | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | enc);
      if(h == INVALID_HANDLE)
         return false;
      ArrayResize(m_keys, 0);
      ArrayResize(m_vals, 0);
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
         int n = ArraySize(m_keys);
         ArrayResize(m_keys, n + 1);
         ArrayResize(m_vals, n + 1);
         m_keys[n] = key;
         m_vals[n] = val;
        }
      FileClose(h);
      return ArraySize(m_keys) > 0 && StringFind(m_keys[0], "Inp") == 0;
     }

public:
                     CProfile(void) : m_file("") {}

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
   bool              Has(const string key) const { return Find(key) >= 0; }

   double            D(const string key, const double def) const
     {
      int i = Find(key);
      return i < 0 ? def : StringToDouble(m_vals[i]);
     }

   long              L(const string key, const long def) const
     {
      int i = Find(key);
      return i < 0 ? def : StringToInteger(m_vals[i]);
     }

   bool              B(const string key, const bool def) const
     {
      int i = Find(key);
      if(i < 0)
         return def;
      string v = m_vals[i];
      StringToLower(v);
      return v == "true" || v == "1";
     }

   string            S(const string key, const string def) const
     {
      int i = Find(key);
      return i < 0 ? def : m_vals[i];
     }
  };

#endif
//+------------------------------------------------------------------+
