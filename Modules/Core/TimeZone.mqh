//+------------------------------------------------------------------+
//|                                                     TimeZone.mqh |
//|  Makes session times broker-independent.                         |
//|                                                                  |
//|  All session inputs (Asian range, entry window, EOD close) are   |
//|  in REFERENCE time = "New York close" time, GMT+2 in winter and  |
//|  GMT+3 during US daylight saving (e.g. Alpari). The EA converts  |
//|  broker server time to reference time using the server timezone  |
//|  chosen in the inputs, including daylight-saving switches.       |
//|  The strategy tester has no real clock, so the model is used in  |
//|  backtests too; on a live chart the EA checks it and warns.      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_TIMEZONE_MQH
#define CLAUDE_TIMEZONE_MQH

enum ENUM_SERVER_TZ
  {
   TZ_NY_CLOSE,   // GMT+2/+3, US DST (Alpari, IC Markets, Pepperstone...)
   TZ_UK,         // GMT+0/+1, UK DST (London)
   TZ_CET,        // GMT+1/+2, EU DST (Central Europe)
   TZ_GMT,        // GMT+0 fixed
   TZ_GMT2,       // GMT+2 fixed
   TZ_GMT3        // GMT+3 fixed
  };

class CTimeZone
  {
private:
   static ENUM_SERVER_TZ s_server;
   static long       s_cacheDay;      // server day of the cached delta
   static int        s_cacheDelta;    // reference - server, seconds

   static datetime   MakeUtc(const int year, const int month, const int day, const int hour)
     {
      MqlDateTime d;
      d.year = year; d.mon = month; d.day = day; d.hour = hour; d.min = 0; d.sec = 0;
      return StructToTime(d);
     }

   //--- n-th Sunday of a month (n >= 1), 0:00 of that day
   static datetime   NthSunday(const int year, const int month, const int n)
     {
      datetime first = MakeUtc(year, month, 1, 0);
      MqlDateTime d;
      TimeToStruct(first, d);
      int offset = (7 - d.day_of_week) % 7;           // days to the first Sunday
      return first + (offset + 7 * (n - 1)) * 86400;
     }

   static datetime   LastSunday(const int year, const int month)
     {
      int nm = month == 12 ? 1 : month + 1, ny = month == 12 ? year + 1 : year;
      datetime next = MakeUtc(ny, nm, 1, 0);
      MqlDateTime d;
      TimeToStruct(next - 86400, d);                  // last day of the month
      return next - 86400 - d.day_of_week * 86400;
     }

   //--- US DST: 2nd Sunday of March 07:00 UTC -> 1st Sunday of November 06:00 UTC
   static bool       UsDst(const datetime utc)
     {
      MqlDateTime d;
      TimeToStruct(utc, d);
      datetime start = NthSunday(d.year, 3, 2) + 7 * 3600;
      datetime end   = NthSunday(d.year, 11, 1) + 6 * 3600;
      return utc >= start && utc < end;
     }

   //--- EU/UK DST: last Sunday of March 01:00 UTC -> last Sunday of October 01:00 UTC
   static bool       EuDst(const datetime utc)
     {
      MqlDateTime d;
      TimeToStruct(utc, d);
      datetime start = LastSunday(d.year, 3) + 3600;
      datetime end   = LastSunday(d.year, 10) + 3600;
      return utc >= start && utc < end;
     }

public:
   static void       Server(const ENUM_SERVER_TZ tz) { s_server = tz; s_cacheDay = -1; }
   static ENUM_SERVER_TZ Server(void)                { return s_server; }

   //--- UTC offset in hours of a timezone at a UTC instant
   static int        OffsetHours(const ENUM_SERVER_TZ tz, const datetime utc)
     {
      switch(tz)
        {
         case TZ_NY_CLOSE: return UsDst(utc) ? 3 : 2;
         case TZ_UK:       return EuDst(utc) ? 1 : 0;
         case TZ_CET:      return EuDst(utc) ? 2 : 1;
         case TZ_GMT2:     return 2;
         case TZ_GMT3:     return 3;
         default:          return 0;
        }
     }

   //--- broker server time -> UTC
   static datetime   ServerToUtc(const datetime t)
     {
      int off = OffsetHours(s_server, t - 2 * 3600);  // first guess, then refine
      off = OffsetHours(s_server, t - off * 3600);
      return t - off * 3600;
     }

   //--- UTC -> broker server time
   static datetime   UtcToServer(const datetime utc) { return utc + OffsetHours(s_server, utc) * 3600; }

   //--- broker server time -> reference (NY-close) time; cached per server day
   static datetime   ServerToRef(const datetime t)
     {
      if(s_server == TZ_NY_CLOSE)
         return t;
      long day = (long)(t / 86400);
      if(day != s_cacheDay)
        {
         datetime utc = ServerToUtc(t);
         s_cacheDelta = (OffsetHours(TZ_NY_CLOSE, utc) - OffsetHours(s_server, utc)) * 3600;
         s_cacheDay   = day;
        }
      return t + s_cacheDelta;
     }

   //--- server hour at which a reference (NY-close) day starts = gold's daily break (17:00 New York)
   static int        ExpectedBreakHour(const ENUM_SERVER_TZ tz, const datetime utcNear)
     {
      datetime refNow = utcNear + OffsetHours(TZ_NY_CLOSE, utcNear) * 3600;
      datetime utc    = (refNow - refNow % 86400) - OffsetHours(TZ_NY_CLOSE, utcNear) * 3600;
      datetime local  = utc + OffsetHours(tz, utc) * 3600;
      return (int)((local % 86400) / 3600);
     }

   //--- works in the tester too: find the hour with the fewest M1 bars on Mon-Thu over ~4 weeks
   //    (XAUUSD pauses for 1 h every day at 17:00 New York) and compare with the input.
   //    Returns false only when the data clearly contradicts the chosen timezone.
   static bool       CheckHistory(const string symbol, string &msg)
     {
      msg = "";
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int n = CopyRates(symbol, PERIOD_M1, 1, 28 * 1440, r);
      if(n < 5 * 1380)
        {
         msg = "not enough M1 history to verify the timezone";
         return true;
        }
      int cnt[24];
      ArrayInitialize(cnt, 0);
      for(int i = 0; i < n; i++)
        {
         MqlDateTime d;
         TimeToStruct(r[i].time, d);
         if(d.day_of_week >= 1 && d.day_of_week <= 4)
            cnt[d.hour]++;
        }
      int minH = 0, maxC = 0;
      for(int h = 0; h < 24; h++)
        {
         if(cnt[h] < cnt[minH])
            minH = h;
         maxC = MathMax(maxC, cnt[h]);
        }
      if(maxC == 0 || cnt[minH] > maxC * 0.5)
        {
         msg = "no clear daily break in the price data - timezone not verified";
         return true;                              // not confident either way
        }
      datetime utcNow   = ServerToUtc(r[n - 1].time);
      int      expected = ExpectedBreakHour(s_server, utcNow);
      msg = StringFormat("daily break in data at %02d:00 server, %s expects %02d:00", minH, EnumToString(s_server), expected);
      if(minH == expected)
         return true;
      string fits = "";
      for(int tz = TZ_NY_CLOSE; tz <= TZ_GMT3; tz++)
         if(ExpectedBreakHour((ENUM_SERVER_TZ)tz, utcNow) == minH)
            fits += (fits == "" ? "" : " / ") + EnumToString((ENUM_SERVER_TZ)tz);
      msg += fits == "" ? "" : " - use " + fits;
      return false;
     }

   //--- live chart only: compare the model with the real server offset
   static bool       Check(string &msg)
     {
      if(MQLInfoInteger(MQL_TESTER))
         return true;
      datetime gmt = TimeGMT();
      int real  = (int)MathRound((double)(TimeTradeServer() - gmt) / 3600.0);
      int model = OffsetHours(s_server, gmt);
      msg = StringFormat("server is GMT%+d, input %s = GMT%+d", real, EnumToString(s_server), model);
      if(real != model)
        {
         string fits = "";
         for(int tz = TZ_NY_CLOSE; tz <= TZ_GMT3; tz++)
            if(OffsetHours((ENUM_SERVER_TZ)tz, gmt) == real)
               fits += (fits == "" ? "" : " / ") + EnumToString((ENUM_SERVER_TZ)tz);
         msg += fits == "" ? " - no preset matches" : " - use " + fits;
        }
      return real == model;
     }
  };

ENUM_SERVER_TZ CTimeZone::s_server     = TZ_NY_CLOSE;
long           CTimeZone::s_cacheDay   = -1;
int            CTimeZone::s_cacheDelta = 0;

#endif
//+------------------------------------------------------------------+
