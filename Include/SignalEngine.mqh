//+------------------------------------------------------------------+
//|                                              SignalEngine.mqh    |
//|                              Swift Algo Bot - Signal Engine      |
//|                  Multi-indicator confluence signal generator      |
//+------------------------------------------------------------------+
#property copyright "Swift Algo Bot"
#property strict

#include <Indicators/Trend.mqh>
#include <Indicators/Oscilators.mqh>

enum ENUM_SIGNAL
{
   SIGNAL_NONE   = 0,
   SIGNAL_BUY    = 1,
   SIGNAL_SELL   = -1
};

enum ENUM_TREND
{
   TREND_NONE    = 0,
   TREND_UP      = 1,
   TREND_DOWN    = -1
};

//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   // Indicator handles
   int            m_emaFastHandle;
   int            m_emaSlowHandle;
   int            m_emaTrendHandle;
   int            m_rsiHandle;
   int            m_macdHandle;
   int            m_atrHandle;
   int            m_bbHandle;
   int            m_adxHandle;
   int            m_stochHandle;
   int            m_volumeHandle;

   // Parameters
   int            m_emaFastPeriod;
   int            m_emaSlowPeriod;
   int            m_emaTrendPeriod;
   int            m_rsiPeriod;
   int            m_macdFast;
   int            m_macdSlow;
   int            m_macdSignal;
   int            m_atrPeriod;
   int            m_bbPeriod;
   double         m_bbDeviation;
   int            m_adxPeriod;
   int            m_stochK;
   int            m_stochD;
   int            m_stochSlowing;

   // Filter thresholds
   double         m_rsiOverbought;
   double         m_rsiOversold;
   double         m_adxMinStrength;
   int            m_minConfluence;

   // Cached values
   double         m_emaFast[];
   double         m_emaSlow[];
   double         m_emaTrend[];
   double         m_rsi[];
   double         m_macdMain[];
   double         m_macdSignalLine[];
   double         m_macdHist[];
   double         m_atr[];
   double         m_bbUpper[];
   double         m_bbMiddle[];
   double         m_bbLower[];
   double         m_adx[];
   double         m_adxPlus[];
   double         m_adxMinus[];
   double         m_stochMain[];
   double         m_stochSignalLine[];

   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   bool           m_initialized;

   bool           CopyBuffersSafe(int bars);

public:
                  CSignalEngine();
                 ~CSignalEngine();

   bool           Init(string symbol, ENUM_TIMEFRAMES timeframe,
                       int emaFast, int emaSlow, int emaTrend,
                       int rsiPeriod, double rsiOB, double rsiOS,
                       int macdFast, int macdSlow, int macdSignal,
                       int atrPeriod, int bbPeriod, double bbDev,
                       int adxPeriod, double adxMinStr,
                       int stochK, int stochD, int stochSlowing,
                       int minConfluence);

   void           Deinit();

   ENUM_SIGNAL    GetSignal(int shift);
   ENUM_TREND     GetTrend(int shift);
   int            GetConfluenceScore(int shift);

   // Accessor methods for dashboard
   double         GetEMAFast(int shift);
   double         GetEMASlow(int shift);
   double         GetEMATrend(int shift);
   double         GetRSI(int shift);
   double         GetMACDMain(int shift);
   double         GetMACDSignal(int shift);
   double         GetMACDHist(int shift);
   double         GetATR(int shift);
   double         GetBBUpper(int shift);
   double         GetBBMiddle(int shift);
   double         GetBBLower(int shift);
   double         GetADX(int shift);
   double         GetADXPlus(int shift);
   double         GetADXMinus(int shift);
   double         GetStochMain(int shift);
   double         GetStochSignal(int shift);
   bool           IsInitialized() { return m_initialized; }

   // Sub-signal checks
   int            CheckEMACross(int shift);
   int            CheckRSI(int shift);
   int            CheckMACD(int shift);
   int            CheckBB(int shift);
   int            CheckADXTrend(int shift);
   int            CheckStoch(int shift);
   int            CheckPriceAction(int shift);
};

//+------------------------------------------------------------------+
CSignalEngine::CSignalEngine()
{
   m_initialized = false;
   m_emaFastHandle = INVALID_HANDLE;
   m_emaSlowHandle = INVALID_HANDLE;
   m_emaTrendHandle = INVALID_HANDLE;
   m_rsiHandle = INVALID_HANDLE;
   m_macdHandle = INVALID_HANDLE;
   m_atrHandle = INVALID_HANDLE;
   m_bbHandle = INVALID_HANDLE;
   m_adxHandle = INVALID_HANDLE;
   m_stochHandle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
CSignalEngine::~CSignalEngine()
{
   Deinit();
}

//+------------------------------------------------------------------+
bool CSignalEngine::Init(string symbol, ENUM_TIMEFRAMES timeframe,
                         int emaFast, int emaSlow, int emaTrend,
                         int rsiPeriod, double rsiOB, double rsiOS,
                         int macdFast, int macdSlow, int macdSignal,
                         int atrPeriod, int bbPeriod, double bbDev,
                         int adxPeriod, double adxMinStr,
                         int stochK, int stochD, int stochSlowing,
                         int minConfluence)
{
   m_symbol = symbol;
   m_timeframe = timeframe;
   m_emaFastPeriod = emaFast;
   m_emaSlowPeriod = emaSlow;
   m_emaTrendPeriod = emaTrend;
   m_rsiPeriod = rsiPeriod;
   m_rsiOverbought = rsiOB;
   m_rsiOversold = rsiOS;
   m_macdFast = macdFast;
   m_macdSlow = macdSlow;
   m_macdSignal = macdSignal;
   m_atrPeriod = atrPeriod;
   m_bbPeriod = bbPeriod;
   m_bbDeviation = bbDev;
   m_adxPeriod = adxPeriod;
   m_adxMinStrength = adxMinStr;
   m_stochK = stochK;
   m_stochD = stochD;
   m_stochSlowing = stochSlowing;
   m_minConfluence = minConfluence;

   m_emaFastHandle  = iMA(m_symbol, m_timeframe, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_emaSlowHandle  = iMA(m_symbol, m_timeframe, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_emaTrendHandle = iMA(m_symbol, m_timeframe, m_emaTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_rsiHandle      = iRSI(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
   m_macdHandle     = iMACD(m_symbol, m_timeframe, m_macdFast, m_macdSlow, m_macdSignal, PRICE_CLOSE);
   m_atrHandle      = iATR(m_symbol, m_timeframe, m_atrPeriod);
   m_bbHandle       = iBands(m_symbol, m_timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
   m_adxHandle      = iADX(m_symbol, m_timeframe, m_adxPeriod);
   m_stochHandle    = iStochastic(m_symbol, m_timeframe, m_stochK, m_stochD, m_stochSlowing, MODE_SMA, STO_LOWHIGH);

   if(m_emaFastHandle == INVALID_HANDLE || m_emaSlowHandle == INVALID_HANDLE ||
      m_emaTrendHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE ||
      m_macdHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE ||
      m_bbHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE ||
      m_stochHandle == INVALID_HANDLE)
   {
      Print("SignalEngine: Failed to create indicator handles");
      return false;
   }

   ArraySetAsSeries(m_emaFast, true);
   ArraySetAsSeries(m_emaSlow, true);
   ArraySetAsSeries(m_emaTrend, true);
   ArraySetAsSeries(m_rsi, true);
   ArraySetAsSeries(m_macdMain, true);
   ArraySetAsSeries(m_macdSignalLine, true);
   ArraySetAsSeries(m_macdHist, true);
   ArraySetAsSeries(m_atr, true);
   ArraySetAsSeries(m_bbUpper, true);
   ArraySetAsSeries(m_bbMiddle, true);
   ArraySetAsSeries(m_bbLower, true);
   ArraySetAsSeries(m_adx, true);
   ArraySetAsSeries(m_adxPlus, true);
   ArraySetAsSeries(m_adxMinus, true);
   ArraySetAsSeries(m_stochMain, true);
   ArraySetAsSeries(m_stochSignalLine, true);

   m_initialized = true;
   return true;
}

//+------------------------------------------------------------------+
void CSignalEngine::Deinit()
{
   if(m_emaFastHandle != INVALID_HANDLE)  { IndicatorRelease(m_emaFastHandle);  m_emaFastHandle = INVALID_HANDLE; }
   if(m_emaSlowHandle != INVALID_HANDLE)  { IndicatorRelease(m_emaSlowHandle);  m_emaSlowHandle = INVALID_HANDLE; }
   if(m_emaTrendHandle != INVALID_HANDLE) { IndicatorRelease(m_emaTrendHandle); m_emaTrendHandle = INVALID_HANDLE; }
   if(m_rsiHandle != INVALID_HANDLE)      { IndicatorRelease(m_rsiHandle);      m_rsiHandle = INVALID_HANDLE; }
   if(m_macdHandle != INVALID_HANDLE)     { IndicatorRelease(m_macdHandle);     m_macdHandle = INVALID_HANDLE; }
   if(m_atrHandle != INVALID_HANDLE)      { IndicatorRelease(m_atrHandle);      m_atrHandle = INVALID_HANDLE; }
   if(m_bbHandle != INVALID_HANDLE)       { IndicatorRelease(m_bbHandle);       m_bbHandle = INVALID_HANDLE; }
   if(m_adxHandle != INVALID_HANDLE)      { IndicatorRelease(m_adxHandle);      m_adxHandle = INVALID_HANDLE; }
   if(m_stochHandle != INVALID_HANDLE)    { IndicatorRelease(m_stochHandle);    m_stochHandle = INVALID_HANDLE; }
   m_initialized = false;
}

//+------------------------------------------------------------------+
bool CSignalEngine::CopyBuffersSafe(int bars)
{
   if(!m_initialized) return false;
   if(bars < 3) bars = 3;

   bool ok = true;
   ok &= (CopyBuffer(m_emaFastHandle, 0, 0, bars, m_emaFast) == bars);
   ok &= (CopyBuffer(m_emaSlowHandle, 0, 0, bars, m_emaSlow) == bars);
   ok &= (CopyBuffer(m_emaTrendHandle, 0, 0, bars, m_emaTrend) == bars);
   ok &= (CopyBuffer(m_rsiHandle, 0, 0, bars, m_rsi) == bars);
   ok &= (CopyBuffer(m_macdHandle, 0, 0, bars, m_macdMain) == bars);
   ok &= (CopyBuffer(m_macdHandle, 1, 0, bars, m_macdSignalLine) == bars);
   ok &= (CopyBuffer(m_macdHandle, 2, 0, bars, m_macdHist) == bars);
   ok &= (CopyBuffer(m_atrHandle, 0, 0, bars, m_atr) == bars);
   ok &= (CopyBuffer(m_bbHandle, 0, 0, bars, m_bbMiddle) == bars);
   ok &= (CopyBuffer(m_bbHandle, 1, 0, bars, m_bbUpper) == bars);
   ok &= (CopyBuffer(m_bbHandle, 2, 0, bars, m_bbLower) == bars);
   ok &= (CopyBuffer(m_adxHandle, 0, 0, bars, m_adx) == bars);
   ok &= (CopyBuffer(m_adxHandle, 1, 0, bars, m_adxPlus) == bars);
   ok &= (CopyBuffer(m_adxHandle, 2, 0, bars, m_adxMinus) == bars);
   ok &= (CopyBuffer(m_stochHandle, 0, 0, bars, m_stochMain) == bars);
   ok &= (CopyBuffer(m_stochHandle, 1, 0, bars, m_stochSignalLine) == bars);

   return ok;
}

//+------------------------------------------------------------------+
// EMA crossover: +1 bullish cross, -1 bearish cross, 0 no cross
//+------------------------------------------------------------------+
int CSignalEngine::CheckEMACross(int shift)
{
   if(!CopyBuffersSafe(shift + 3)) return 0;

   bool fastAboveNow  = m_emaFast[shift] > m_emaSlow[shift];
   bool fastAbovePrev = m_emaFast[shift + 1] > m_emaSlow[shift + 1];
   bool aboveTrend    = m_emaFast[shift] > m_emaTrend[shift];

   if(fastAboveNow && !fastAbovePrev && aboveTrend)
      return 1;
   if(!fastAboveNow && fastAbovePrev && !aboveTrend)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// RSI filter: +1 oversold bounce, -1 overbought rejection, 0 neutral
//+------------------------------------------------------------------+
int CSignalEngine::CheckRSI(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return 0;

   double rsiNow  = m_rsi[shift];
   double rsiPrev = m_rsi[shift + 1];

   if(rsiPrev < m_rsiOversold && rsiNow >= m_rsiOversold)
      return 1;
   if(rsiPrev > m_rsiOverbought && rsiNow <= m_rsiOverbought)
      return -1;

   if(rsiNow > 40 && rsiNow < 60)
      return 0;
   if(rsiNow <= 40)
      return 1;
   if(rsiNow >= 60)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// MACD histogram crossover
//+------------------------------------------------------------------+
int CSignalEngine::CheckMACD(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return 0;

   double histNow  = m_macdHist[shift];
   double histPrev = m_macdHist[shift + 1];

   if(histNow > 0 && histPrev <= 0)
      return 1;
   if(histNow < 0 && histPrev >= 0)
      return -1;

   if(histNow > 0 && histNow > histPrev)
      return 1;
   if(histNow < 0 && histNow < histPrev)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// Bollinger Band position
//+------------------------------------------------------------------+
int CSignalEngine::CheckBB(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return 0;

   double close = iClose(m_symbol, m_timeframe, shift);
   double closePrev = iClose(m_symbol, m_timeframe, shift + 1);

   if(closePrev <= m_bbLower[shift + 1] && close > m_bbLower[shift])
      return 1;
   if(closePrev >= m_bbUpper[shift + 1] && close < m_bbUpper[shift])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// ADX trend strength filter
//+------------------------------------------------------------------+
int CSignalEngine::CheckADXTrend(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return 0;

   if(m_adx[shift] < m_adxMinStrength)
      return 0;

   if(m_adxPlus[shift] > m_adxMinus[shift])
      return 1;
   if(m_adxMinus[shift] > m_adxPlus[shift])
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// Stochastic crossover
//+------------------------------------------------------------------+
int CSignalEngine::CheckStoch(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return 0;

   double kNow = m_stochMain[shift];
   double dNow = m_stochSignalLine[shift];
   double kPrev = m_stochMain[shift + 1];
   double dPrev = m_stochSignalLine[shift + 1];

   if(kPrev < dPrev && kNow > dNow && kNow < 30)
      return 1;
   if(kPrev > dPrev && kNow < dNow && kNow > 70)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
// Price action: engulfing candle detection
//+------------------------------------------------------------------+
int CSignalEngine::CheckPriceAction(int shift)
{
   double openNow  = iOpen(m_symbol, m_timeframe, shift);
   double closeNow = iClose(m_symbol, m_timeframe, shift);
   double highNow  = iHigh(m_symbol, m_timeframe, shift);
   double lowNow   = iLow(m_symbol, m_timeframe, shift);

   double openPrev  = iOpen(m_symbol, m_timeframe, shift + 1);
   double closePrev = iClose(m_symbol, m_timeframe, shift + 1);

   bool bullishEngulf = (closePrev < openPrev) &&
                        (closeNow > openNow) &&
                        (closeNow > openPrev) &&
                        (openNow < closePrev);

   bool bearishEngulf = (closePrev > openPrev) &&
                        (closeNow < openNow) &&
                        (closeNow < openPrev) &&
                        (openNow > closePrev);

   if(bullishEngulf) return 1;
   if(bearishEngulf) return -1;

   return 0;
}

//+------------------------------------------------------------------+
// Confluence score: sums all sub-signals (-7 to +7)
//+------------------------------------------------------------------+
int CSignalEngine::GetConfluenceScore(int shift)
{
   int score = 0;
   score += CheckEMACross(shift);
   score += CheckRSI(shift);
   score += CheckMACD(shift);
   score += CheckBB(shift);
   score += CheckADXTrend(shift);
   score += CheckStoch(shift);
   score += CheckPriceAction(shift);
   return score;
}

//+------------------------------------------------------------------+
ENUM_SIGNAL CSignalEngine::GetSignal(int shift)
{
   int score = GetConfluenceScore(shift);

   if(score >= m_minConfluence)
      return SIGNAL_BUY;
   if(score <= -m_minConfluence)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
ENUM_TREND CSignalEngine::GetTrend(int shift)
{
   if(!CopyBuffersSafe(shift + 2)) return TREND_NONE;

   double close = iClose(m_symbol, m_timeframe, shift);

   bool aboveFast  = close > m_emaFast[shift];
   bool aboveSlow  = close > m_emaSlow[shift];
   bool aboveTrend = close > m_emaTrend[shift];
   bool fastAboveSlow = m_emaFast[shift] > m_emaSlow[shift];

   if(aboveFast && aboveSlow && aboveTrend && fastAboveSlow)
      return TREND_UP;
   if(!aboveFast && !aboveSlow && !aboveTrend && !fastAboveSlow)
      return TREND_DOWN;

   return TREND_NONE;
}

//+------------------------------------------------------------------+
// Accessor methods
//+------------------------------------------------------------------+
double CSignalEngine::GetEMAFast(int shift)    { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_emaFast)) ? m_emaFast[shift] : 0; }
double CSignalEngine::GetEMASlow(int shift)    { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_emaSlow)) ? m_emaSlow[shift] : 0; }
double CSignalEngine::GetEMATrend(int shift)   { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_emaTrend)) ? m_emaTrend[shift] : 0; }
double CSignalEngine::GetRSI(int shift)        { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_rsi)) ? m_rsi[shift] : 0; }
double CSignalEngine::GetMACDMain(int shift)   { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_macdMain)) ? m_macdMain[shift] : 0; }
double CSignalEngine::GetMACDSignal(int shift) { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_macdSignalLine)) ? m_macdSignalLine[shift] : 0; }
double CSignalEngine::GetMACDHist(int shift)   { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_macdHist)) ? m_macdHist[shift] : 0; }
double CSignalEngine::GetATR(int shift)        { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_atr)) ? m_atr[shift] : 0; }
double CSignalEngine::GetBBUpper(int shift)    { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_bbUpper)) ? m_bbUpper[shift] : 0; }
double CSignalEngine::GetBBMiddle(int shift)   { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_bbMiddle)) ? m_bbMiddle[shift] : 0; }
double CSignalEngine::GetBBLower(int shift)    { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_bbLower)) ? m_bbLower[shift] : 0; }
double CSignalEngine::GetADX(int shift)        { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_adx)) ? m_adx[shift] : 0; }
double CSignalEngine::GetADXPlus(int shift)    { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_adxPlus)) ? m_adxPlus[shift] : 0; }
double CSignalEngine::GetADXMinus(int shift)   { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_adxMinus)) ? m_adxMinus[shift] : 0; }
double CSignalEngine::GetStochMain(int shift)  { CopyBuffersSafe(shift+1); return (shift < ArraySize(m_stochMain)) ? m_stochMain[shift] : 0; }
double CSignalEngine::GetStochSignal(int shift){ CopyBuffersSafe(shift+1); return (shift < ArraySize(m_stochSignalLine)) ? m_stochSignalLine[shift] : 0; }
//+------------------------------------------------------------------+
