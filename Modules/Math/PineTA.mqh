//+------------------------------------------------------------------+
//|                                                       PineTA.mqh |
//|  Ports of TradingView ta.* functions with Pine semantics.        |
//|                                                                  |
//|  All arrays are chronological (index 0 = oldest bar).            |
//|  Values that Pine would return as na are set to PINE_NA.         |
//|  MT5 built-ins differ (iATR is an SMA of TR, iMA EMA is seeded   |
//|  with the first price), so these are used for exact parity.      |
//+------------------------------------------------------------------+
#ifndef CLAUDE_PINETA_MQH
#define CLAUDE_PINETA_MQH

#include "../Core/Defines.mqh"

class CPineTA
  {
private:
   static void       Fill(double &out[], const int n)
     {
      ArrayResize(out, n);
      ArrayInitialize(out, PINE_NA);
     }

   //--- simple average of src[i-len+1 .. i]; PINE_NA if any value is missing
   static double     WindowSMA(const double &src[], const int i, const int len)
     {
      if(len < 1 || i - len + 1 < 0)
         return PINE_NA;
      double sum = 0.0;
      for(int j = i - len + 1; j <= i; j++)
        {
         if(IsNA(src[j]))
            return PINE_NA;
         sum += src[j];
        }
      return sum / len;
     }

   //--- exponential average seeded with an SMA (pine_ema / pine_rma)
   static void       SeededEMA(const double &src[], const int n, const int len, const double alpha, double &out[])
     {
      Fill(out, n);
      if(len < 1)
         return;
      double prev = PINE_NA;
      for(int i = 0; i < n; i++)
        {
         if(IsNA(prev))
            out[i] = WindowSMA(src, i, len);
         else
            if(IsNA(src[i]))
               out[i] = prev;
            else
               out[i] = alpha * src[i] + (1.0 - alpha) * prev;
         prev = out[i];
        }
     }

public:
   static bool       IsNA(const double v) { return v == PINE_NA || !MathIsValidNumber(v); }

   //--- ta.sma
   static void       SMA(const double &src[], const int n, const int len, double &out[])
     {
      Fill(out, n);
      for(int i = len - 1; i < n; i++)
         out[i] = WindowSMA(src, i, len);
     }

   //--- ta.ema
   static void       EMA(const double &src[], const int n, const int len, double &out[])
     {
      SeededEMA(src, n, len, 2.0 / (len + 1.0), out);
     }

   //--- ta.rma (Wilder)
   static void       RMA(const double &src[], const int n, const int len, double &out[])
     {
      SeededEMA(src, n, len, 1.0 / len, out);
     }

   //--- ta.wma (linear weights, newest bar weighted highest)
   static void       WMA(const double &src[], const int n, const int len, double &out[])
     {
      Fill(out, n);
      if(len < 1)
         return;
      double norm = len * (len + 1) / 2.0;
      for(int i = len - 1; i < n; i++)
        {
         double sum = 0.0;
         bool   ok  = true;
         for(int k = 0; k < len; k++)
           {
            double v = src[i - len + 1 + k];
            if(IsNA(v))
              {
               ok = false;
               break;
              }
            sum += v * (k + 1);
           }
         if(ok)
            out[i] = sum / norm;
        }
     }

   //--- ta.hma: wma(2*wma(src, len/2) - wma(src, len), floor(sqrt(len)))
   static void       HMA(const double &src[], const int n, const int len, double &out[])
     {
      int halfLen = MathMax(1, len / 2);
      int sqrtLen = MathMax(1, (int)MathFloor(MathSqrt(len)));
      double half[], full[], diff[];
      WMA(src, n, halfLen, half);
      WMA(src, n, len, full);
      Fill(diff, n);
      for(int i = 0; i < n; i++)
         if(!IsNA(half[i]) && !IsNA(full[i]))
            diff[i] = 2.0 * half[i] - full[i];
      WMA(diff, n, sqrtLen, out);
     }

   //--- ta.alma(src, len, offset, sigma), floor = false
   static void       ALMA(const double &src[], const int n, const int len, const double offset, const double sigma, double &out[])
     {
      Fill(out, n);
      if(len < 1 || sigma <= 0.0)
         return;
      double m = offset * (len - 1);
      double s = len / sigma;
      double w[];
      ArrayResize(w, len);
      double norm = 0.0;
      for(int k = 0; k < len; k++)        // k = 0 is the oldest bar in the window
        {
         w[k]  = MathExp(-((k - m) * (k - m)) / (2.0 * s * s));
         norm += w[k];
        }
      for(int i = len - 1; i < n; i++)
        {
         double sum = 0.0;
         bool   ok  = true;
         for(int k = 0; k < len; k++)
           {
            double v = src[i - len + 1 + k];
            if(IsNA(v))
              {
               ok = false;
               break;
              }
            sum += v * w[k];
           }
         if(ok)
            out[i] = sum / norm;
        }
     }

   //--- ta.tr(true): first bar uses high - low
   static void       TrueRange(const double &high[], const double &low[], const double &close[], const int n, double &out[])
     {
      Fill(out, n);
      for(int i = 0; i < n; i++)
        {
         double hl = high[i] - low[i];
         if(i == 0)
           {
            out[i] = hl;
            continue;
           }
         double hc = MathAbs(high[i] - close[i - 1]);
         double lc = MathAbs(low[i]  - close[i - 1]);
         out[i] = MathMax(hl, MathMax(hc, lc));
        }
     }

   //--- ta.atr = rma(tr, len)
   static void       ATR(const double &high[], const double &low[], const double &close[], const int n, const int len, double &out[])
     {
      double tr[];
      TrueRange(high, low, close, n, tr);
      RMA(tr, n, len, out);
     }
  };

#endif
//+------------------------------------------------------------------+
