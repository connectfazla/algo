//+------------------------------------------------------------------+
//|                                          FX_MILLIONAIRES_EA.mq5 |
//|                                    Converted from Pine Script v6 |
//|                         + Partial TP (ATR or pip) + capped SL vs ATR |
//|                         + Breakeven + trail after configurable %   |
//|                         + Emergency max-loss exit (pip budget)     |
//|                         + Smart Money Strategy (EMA9/20 + Sweep + OB)|
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property version   "2.41"
#property strict
#property description "EA: MACD strategy OR Smart Money (Liquidity Sweep + Order Block)"
#property description "v2.41: stricter entries, SL cap vs ATR, max-loss exit, earlier BE/trail"

#include <Trade/Trade.mqh>

//--- input parameters (original MACD strategy)
input int      fastLen       = 12;
input int      slowLen       = 26;
input int      sigLen        = 9;
input int      emaTrendLen   = 200;
input int      rsiLen        = 14;
input int      atrLen        = 14;
input double   slMult        = 2.0;      // Base SL distance (ATR); capped by MaxSL_ATR_Cap below
input double   tpMult        = 0.0;      // 0 = no fixed TP (partials + trail); try 4–6 for hard TP tests
input double   lotSize       = 0.1;
input int      magicNumber   = 202403;
input int      MinConfirmation = 72;     // Higher = fewer trades, higher selectivity (MACD mode)
input color    PanelColor    = clrBlack;
input color    TextColor     = clrWhite;
input int      PanelX        = 10;
input int      PanelY        = 30;

//--- Partial TP parameters (in pips, cumulative percentages of original lot)
//--- If UseAtrPartialTp=true, thresholds below use ATR-at-entry multiples instead (recommended XAU M15)
input double   PartialPip1   = 20;       // fallback pip thresholds when ATR partials off (gold “pip” = 0.10)
input double   PartialPip2   = 45;
input double   PartialPip3   = 80;
input double   PartialPip4   = 120;
input double   PartialPct1   = 30;       // Bank more at first target (higher realized win rate)
input double   PartialPct2   = 55;       // cumulative % after second threshold
input double   PartialPct3   = 75;       // cumulative % after third threshold
input double   PartialPct4   = 100;      // cumulative % after fourth threshold

//--- Breakeven parameters
input bool     UseBreakeven  = true;     // Enable breakeven when profit reaches fraction of initial SL
input double   BreakevenFraction = 0.38; // Lower = move to BE sooner (cuts give-back / large losers)

//--- Trailing stop parameters (NEW)
input bool     UseTrailingAfterPartial = true;   // Trailing after partial volume >= TrailActivateAtPct%
input int      TrailActivateAtPct    = 25;        // e.g. 25 = start trailing after first 25% closed (was 50%)
input double   TrailPips     = 22;               // Trailing distance when TrailUseAtr=false (gold pips)

//--- Smart Money Strategy parameters
input bool     UseSmartMoneyStrategy = true;   // Enable the new strategy (overrides StrategyMode)
input int      StrategyMode = 2;               // 1 = Original MACD, 2 = Smart Money
input int      emaFast       = 9;
input int      emaSlow       = 20;
input int      sweepLookback = 36;             // M15 XAU: slightly wider swing context
input int      obLookback    = 15;             // Bars back to find Order Block
input double   obEntryZone   = 0.618;          // Fibonacci retracement for OB entry
input double   minSweepSize  = 0.42;           // Stricter sweeps = fewer false signals (Smart Money)
input bool     RequireOBConfluence = true;     // Must have an Order Block
input bool     RequireFVGConfluence = false;   // Also require FVG
input int      MinSmartMoneyConf = 82;         // Min confidence % to take SM entry (higher win selectivity)
input bool     UseEMA200FilterSM = true;       // SM longs only above EMA200, shorts only below

//--- XAUUSD M15: ATR-based exits + trade filters (maximize adaptability vs fixed pips)
input bool     UseAtrPartialTp   = true;       // Partial levels = multiple of ATR at entry (bar 1)
input double   PartialAtr1       = 0.75;       // Earlier first partial = bank winners faster
input double   PartialAtr2       = 1.75;
input double   PartialAtr3       = 2.9;
input double   PartialAtr4       = 4.2;
input bool     TrailUseAtr       = true;       // Trail distance = TrailAtrMult * current ATR (bar 1)
input double   TrailAtrMult      = 1.25;
input bool     UseSessionFilter  = true;       // Block new entries outside hours (GMT or server)
input bool     SessionUseGMT     = true;       // true: SessionStart/End are GMT; false: broker server time
input int      SessionStartHour  = 7;          // London–NY window friendly to XAU (inclusive)
input int      SessionEndHour    = 21;
input int      MaxSpreadPoints   = 0;          // 0 = disabled; else max SYMBOL_SPREAD for new entries

//--- Loss control (caps oversized stops & hard stop on deep float loss)
input double   MaxSL_ATR_Cap     = 2.55;       // Max entry→SL distance in ATR (stops huge OB/structure risk)
input double   MinSL_ATR_Floor   = 0.7;        // Min SL distance in ATR (0 = off); avoids micro-stops
input int      MaxLossPipsCut    = 320;        // 0 = off; force-close if open loss exceeds this many “pips”

//--- global variables
CTrade         trade;
int            macdHandle, ema200Handle, rsiHandle, atrHandle;
int            ema9Handle, ema20Handle;
datetime       lastBarTime = 0;
bool           isBuyActive = false, isSellActive = false;
ulong          buyTicket = 0, sellTicket = 0;
double         buyOpenPrice = 0, sellOpenPrice = 0;
double         buySL = 0, sellSL = 0;
double         buyTP = 0, sellTP = 0;

//--- Partial TP tracking variables
double         buyOriginalLot = 0;
double         sellOriginalLot = 0;
double         buyClosedFraction = 0;
double         sellClosedFraction = 0;
double         buyMaxProfitPips = 0;
double         sellMaxProfitPips = 0;

//--- Breakeven tracking variables
bool           buyBreakevenTriggered = false;
bool           sellBreakevenTriggered = false;
double         buyInitialSLPips = 0;
double         sellInitialSLPips = 0;

//--- Trailing stop tracking variables (NEW)
bool           buyTrailingActive = false;
bool           sellTrailingActive = false;
double         buyTrailingBestPrice = 0;   // highest price reached for buy
double         sellTrailingBestPrice = 0;  // lowest price reached for sell

//--- Smart Money dynamic variables
double         swingHigh[], swingLow[];
double         lastSweepHighPrice = 0, lastSweepLowPrice = 0;
datetime       lastSweepHighTime = 0, lastSweepLowTime = 0;
double         orderBlockHigh = 0, orderBlockLow = 0;
datetime       orderBlockTime = 0;
bool           fvgDetected = false;
double         fvgHigh = 0, fvgLow = 0;
double         currentConfidence = 0;

//--- display objects
string         panelName = "FX_MILLIONAIRES_PANEL_";
string         signalStrengthName = "SIGNAL_STRENGTH_";

//--- Partial TP thresholds and cumulative fractions
double         partialPips[4];
double         partialCumFrac[4];
double         partialAtrMult[4];
double         buyEntryATR  = 0;
double         sellEntryATR = 0;
double         trailActivateFraction = 0.25;

//+------------------------------------------------------------------+
bool SymbolIsGoldOrMetal()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "xau") >= 0 ||
           StringFind(_Symbol, "GOLD") >= 0 || StringFind(_Symbol, "gold") >= 0);
}

//+------------------------------------------------------------------+
//| Pip size in price units (FX 3/5 vs 2/4; XAU often 0.10 per “pip”) |
//+------------------------------------------------------------------+
double PipSizeInPrice()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0)
      pt = _Point;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(SymbolIsGoldOrMetal())
   {
      if(dg >= 3)
         return pt * 100.0;
      return pt * 10.0;
   }
   if(dg == 3 || dg == 5)
      return pt * 10.0;
   return pt;
}

//+------------------------------------------------------------------+
bool CopyAtrPrevBar(double &out)
{
   double b[];
   ArraySetAsSeries(b, true);
   if(atrHandle == INVALID_HANDLE)
      return false;
   if(CopyBuffer(atrHandle, 0, 1, 1, b) < 1)
      return false;
   out = b[0];
   return (out > 0);
}

//+------------------------------------------------------------------+
int CurrentFilterHour()
{
   datetime t = SessionUseGMT ? TimeGMT() : TimeCurrent();
   MqlDateTime st;
   TimeToStruct(t, st);
   return (int)st.hour;
}

//+------------------------------------------------------------------+
bool IsWithinSessionHours()
{
   int h = CurrentFilterHour();
   if(SessionStartHour == SessionEndHour)
      return true;
   if(SessionStartHour < SessionEndHour)
      return (h >= SessionStartHour && h <= SessionEndHour);
   return (h >= SessionStartHour || h <= SessionEndHour);
}

//+------------------------------------------------------------------+
bool AllowNewEntries()
{
   if(UseSessionFilter && !IsWithinSessionHours())
      return false;
   if(MaxSpreadPoints > 0)
   {
      long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(sp > MaxSpreadPoints)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool BuyPartialThresholdHit(const int idx, const double currentBid, double &outProfitPips)
{
   double pip = PipSizeInPrice();
   if(pip > 0)
      outProfitPips = (currentBid - buyOpenPrice) / pip;
   else
      outProfitPips = 0;

   if(UseAtrPartialTp && buyEntryATR > 0)
      return ((currentBid - buyOpenPrice) >= partialAtrMult[idx] * buyEntryATR);
   if(pip <= 0)
      return false;
   return (outProfitPips >= partialPips[idx]);
}

//+------------------------------------------------------------------+
bool SellPartialThresholdHit(const int idx, const double currentAsk, double &outProfitPips)
{
   double pip = PipSizeInPrice();
   if(pip > 0)
      outProfitPips = (sellOpenPrice - currentAsk) / pip;
   else
      outProfitPips = 0;

   if(UseAtrPartialTp && sellEntryATR > 0)
      return ((sellOpenPrice - currentAsk) >= partialAtrMult[idx] * sellEntryATR);
   if(pip <= 0)
      return false;
   return (outProfitPips >= partialPips[idx]);
}

//+------------------------------------------------------------------+
double TrailingDistancePrice()
{
   if(TrailUseAtr)
   {
      double a = 0;
      if(CopyAtrPrevBar(a))
         return MathMax(a * TrailAtrMult, _Point * 2);
   }
   double pip = PipSizeInPrice();
   if(pip <= 0)
      return _Point * 10;
   return TrailPips * pip;
}

//+------------------------------------------------------------------+
//| Cap / floor stop distance vs ATR (prevents huge OB-based risk)    |
//+------------------------------------------------------------------+
double NormalizeStopWithAtrCap(const double entry, double sl, const bool isBuy, const double atr)
{
   if(atr <= 0 || sl <= 0)
      return NormalizeDouble(sl, _Digits);
   if(MaxSL_ATR_Cap <= 0 && MinSL_ATR_Floor <= 0)
      return NormalizeDouble(sl, _Digits);

   const double maxDist = (MaxSL_ATR_Cap > 0) ? atr * MaxSL_ATR_Cap : 1.0e100;

   double dist = isBuy ? (entry - sl) : (sl - entry);
   if(dist <= 0)
      return NormalizeDouble(sl, _Digits);

   if(dist > maxDist)
      sl = isBuy ? (entry - maxDist) : (entry + maxDist);

   if(MinSL_ATR_Floor > 0)
   {
      double minDist = atr * MinSL_ATR_Floor;
      dist = isBuy ? (entry - sl) : (sl - entry);
      if(dist < minDist)
         sl = isBuy ? (entry - minDist) : (entry + minDist);
   }
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
void EmergencyCloseBuy(const string reason)
{
   if(buyTicket > 0 && PositionSelectByTicket(buyTicket))
      trade.PositionClose(buyTicket);
   isBuyActive = false;
   buyTicket = 0;
   buyOriginalLot = 0;
   buyClosedFraction = 0;
   buyMaxProfitPips = 0;
   buyTrailingActive = false;
   buyEntryATR = 0;
   Print("BUY ", reason);
}

//+------------------------------------------------------------------+
void EmergencyCloseSell(const string reason)
{
   if(sellTicket > 0 && PositionSelectByTicket(sellTicket))
      trade.PositionClose(sellTicket);
   isSellActive = false;
   sellTicket = 0;
   sellOriginalLot = 0;
   sellClosedFraction = 0;
   sellMaxProfitPips = 0;
   sellTrailingActive = false;
   sellEntryATR = 0;
   Print("SELL ", reason);
}

//+------------------------------------------------------------------+
void ManageEmergencyMaxLoss()
{
   if(MaxLossPipsCut <= 0)
      return;
   double pip = PipSizeInPrice();
   if(pip <= 0)
      return;

   if(isBuyActive && buyTicket > 0 && PositionSelectByTicket(buyTicket))
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double lossPips = (bid - buyOpenPrice) / pip;
      if(lossPips <= -(double)MaxLossPipsCut)
         EmergencyCloseBuy("max loss exit");
   }
   if(isSellActive && sellTicket > 0 && PositionSelectByTicket(sellTicket))
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (sellOpenPrice - ask) / pip;
      if(profitPips <= -(double)MaxLossPipsCut)
         EmergencyCloseSell("max loss exit");
   }
}

//+------------------------------------------------------------------+
//| Convert open SL distance to pips using current pip definition    |
//+------------------------------------------------------------------+
double StopLossDistancePips(const double openPrice, const double slPrice, const bool isBuy)
{
   double pip = PipSizeInPrice();
   if(pip <= 0)
      return 0;
   if(isBuy)
   {
      if(slPrice <= 0 || slPrice >= openPrice)
         return 0;
      return (openPrice - slPrice) / pip;
   }
   if(slPrice <= 0 || slPrice <= openPrice)
      return 0;
   return (slPrice - openPrice) / pip;
}

//+------------------------------------------------------------------+
//| Resolve position ticket after CTrade market open (not order id)   |
//+------------------------------------------------------------------+
ulong PositionTicketFromLastDeal(const ENUM_POSITION_TYPE wantType)
{
   ulong dealTicket = trade.ResultDeal();
   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
   {
      long posId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(posId > 0)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong t = PositionGetTicket(i);
            if(t == 0 || !PositionSelectByTicket(t))
               continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
               continue;
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != wantType)
               continue;
            if((long)PositionGetInteger(POSITION_IDENTIFIER) == posId)
               return t;
         }
      }
   }
   return FindOpenPositionTicket(wantType);
}

//+------------------------------------------------------------------+
//| Fallback: newest matching position on symbol/magic/type         |
//+------------------------------------------------------------------+
ulong FindOpenPositionTicket(const ENUM_POSITION_TYPE wantType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == wantType)
         return t;
   }
   return 0;
}

//+------------------------------------------------------------------+
bool SwingPriceMatches(const double a, const double b)
{
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5.0;
   if(tol <= 0)
      tol = _Point * 5.0;
   return (MathAbs(a - b) <= tol);
}

//+------------------------------------------------------------------+
int ActiveStrategyMode()
{
   if(!UseSmartMoneyStrategy)
      return 1;
   return StrategyMode;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(10);

   // Initialize partial TP arrays
   partialPips[0] = PartialPip1;
   partialPips[1] = PartialPip2;
   partialPips[2] = PartialPip3;
   partialPips[3] = PartialPip4;
   partialCumFrac[0] = PartialPct1 / 100.0;
   partialCumFrac[1] = PartialPct2 / 100.0;
   partialCumFrac[2] = PartialPct3 / 100.0;
   partialCumFrac[3] = PartialPct4 / 100.0;
   // Validate increasing order (cumulative %)
   for(int i=1; i<4; i++)
      if(partialCumFrac[i] <= partialCumFrac[i-1])
      {
         Print("Partial TP percentages must be increasing (cumulative). Using defaults: 0.25,0.50,0.75,1.00");
         partialCumFrac[0]=0.25; partialCumFrac[1]=0.50; partialCumFrac[2]=0.75; partialCumFrac[3]=1.00;
         break;
      }
   // Validate pip thresholds non-decreasing
   for(int j=1; j<4; j++)
      if(partialPips[j] < partialPips[j-1])
      {
         Print("Partial TP pip levels must be non-decreasing. Resetting to 20,45,80,120.");
         partialPips[0]=20; partialPips[1]=45; partialPips[2]=80; partialPips[3]=120;
         break;
      }

   partialAtrMult[0] = PartialAtr1;
   partialAtrMult[1] = PartialAtr2;
   partialAtrMult[2] = PartialAtr3;
   partialAtrMult[3] = PartialAtr4;
   for(int k=1; k<4; k++)
      if(partialAtrMult[k] < partialAtrMult[k-1])
      {
         Print("Partial ATR multiples must be non-decreasing. Resetting to 0.75,1.75,2.9,4.2.");
         partialAtrMult[0]=0.75; partialAtrMult[1]=1.75; partialAtrMult[2]=2.9; partialAtrMult[3]=4.2;
         break;
      }

   int tap = TrailActivateAtPct;
   if(tap < 5)  tap = 5;
   if(tap > 90) tap = 90;
   trailActivateFraction = tap / 100.0;

   // Original indicators
   macdHandle = iMACD(_Symbol, PERIOD_CURRENT, fastLen, slowLen, sigLen, PRICE_CLOSE);
   ema200Handle = iMA(_Symbol, PERIOD_CURRENT, emaTrendLen, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, rsiLen, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, atrLen);

   ema9Handle = iMA(_Symbol, PERIOD_CURRENT, emaFast, 0, MODE_EMA, PRICE_CLOSE);
   ema20Handle = iMA(_Symbol, PERIOD_CURRENT, emaSlow, 0, MODE_EMA, PRICE_CLOSE);

   if(macdHandle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE ||
      ema9Handle == INVALID_HANDLE || ema20Handle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
   }

   ArrayResize(swingHigh, sweepLookback+2);
   ArrayResize(swingLow, sweepLookback+2);
   ArrayInitialize(swingHigh, 0);
   ArrayInitialize(swingLow, 0);

   // Recover any existing positions
   RecoverExistingPositions();

   CreateDisplayPanel();
   PrintFormat("FX_MILLIONAIRES v2.41 %s | TF=%s | pip=%.5f | trail@%.0f%% | maxSL=%.2f*ATR | maxLossPips=%d",
               _Symbol, EnumToString(Period()), PipSizeInPrice(),
               trailActivateFraction * 100.0, MaxSL_ATR_Cap, MaxLossPipsCut);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Recover positions on startup                                     |
//+------------------------------------------------------------------+
void RecoverExistingPositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY && !isBuyActive)
      {
         isBuyActive = true;
         buyTicket = ticket;
         buyOpenPrice = openPrice;
         buySL = sl;
         buyTP = tp;
         buyOriginalLot = volume;
         buyClosedFraction = 0;
         buyMaxProfitPips = 0;
         buyBreakevenTriggered = false;
         buyTrailingActive = false;
         buyTrailingBestPrice = 0;
         buyInitialSLPips = StopLossDistancePips(buyOpenPrice, buySL, true);
         if(!CopyAtrPrevBar(buyEntryATR))
            buyEntryATR = 0;
      }
      else if(type == POSITION_TYPE_SELL && !isSellActive)
      {
         isSellActive = true;
         sellTicket = ticket;
         sellOpenPrice = openPrice;
         sellSL = sl;
         sellTP = tp;
         sellOriginalLot = volume;
         sellClosedFraction = 0;
         sellMaxProfitPips = 0;
         sellBreakevenTriggered = false;
         sellTrailingActive = false;
         sellTrailingBestPrice = 0;
         sellInitialSLPips = StopLossDistancePips(sellOpenPrice, sellSL, false);
         if(!CopyAtrPrevBar(sellEntryATR))
            sellEntryATR = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(macdHandle);
   IndicatorRelease(ema200Handle);
   IndicatorRelease(rsiHandle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(ema9Handle);
   IndicatorRelease(ema20Handle);

   ObjectsDeleteAll(0, panelName);
   ObjectsDeleteAll(0, signalStrengthName);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- Manage Partial Take Profit (every tick)
   ManagePartialTakeProfit();

   // --- Manage Breakeven (every tick)
   if(UseBreakeven)
      ManageBreakeven();

   ManageEmergencyMaxLoss();

   // --- Manage Trailing Stop (every tick) - only if active
   if(UseTrailingAfterPartial)
      ManageTrailingStop();

   // --- new bar check for signal generation
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
   {
      UpdateDisplay();
      return;
   }
   lastBarTime = currentBarTime;

   UpdatePositionStatus();

   // --- Strategy selection
   if(ActiveStrategyMode() == 1)
      ProcessOriginalStrategy();
   else
      ProcessSmartMoneyStrategy();

   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| Manage Partial Take Profit                                       |
//+------------------------------------------------------------------+
void ManagePartialTakeProfit()
{
   double pipSize = PipSizeInPrice();
   const bool pipOk = (pipSize > 0);

   // --- BUY position
   if(isBuyActive && buyTicket > 0 && PositionSelectByTicket(buyTicket))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double profitPips = pipOk ? (currentPrice - buyOpenPrice) / pipSize : 0;

      if(profitPips > buyMaxProfitPips)
         buyMaxProfitPips = profitPips;

      for(int i=0; i<4; i++)
      {
         double markPips = 0;
         if(!BuyPartialThresholdHit(i, currentPrice, markPips) || buyClosedFraction >= partialCumFrac[i])
            continue;

         double targetFrac = partialCumFrac[i];
         double volumeToClose = buyOriginalLot * (targetFrac - buyClosedFraction);
         volumeToClose = NormalizeDouble(volumeToClose, 2);

         if(volumeToClose > 0 && volumeToClose <= PositionGetDouble(POSITION_VOLUME))
         {
            if(trade.PositionClosePartial(buyTicket, volumeToClose))
            {
               double oldClosedFraction = buyClosedFraction;
               buyClosedFraction = targetFrac;
               if(UseAtrPartialTp && buyEntryATR > 0)
                  PrintFormat("Partial TP (ATR): closed %.2f lots (%.0f%%) at +%.2f ATR (~%.1f pips)",
                              volumeToClose, targetFrac*100,
                              (currentPrice - buyOpenPrice) / buyEntryATR, markPips);
               else
                  PrintFormat("Partial TP: closed %.2f lots (%.0f%%) at +%.1f pips",
                              volumeToClose, targetFrac*100, markPips);

               if(UseTrailingAfterPartial && !buyTrailingActive && oldClosedFraction < trailActivateFraction && buyClosedFraction >= trailActivateFraction)
               {
                  buyTrailingActive = true;
                  buyTrailingBestPrice = currentPrice;
                     Print("Trailing stop activated for BUY (partial threshold reached)");
               }

               if(buyClosedFraction >= 0.999)
               {
                  isBuyActive = false;
                  buyTicket = 0;
                  buyOriginalLot = 0;
                  buyClosedFraction = 0;
                  buyMaxProfitPips = 0;
                  buyTrailingActive = false;
                  buyEntryATR = 0;
                  Print("BUY position fully closed by partial TP");
               }
               break;
            }
            else
               Print("Partial TP failed: ", trade.ResultRetcodeDescription());
         }
      }
   }

   // --- SELL position
   if(isSellActive && sellTicket > 0 && PositionSelectByTicket(sellTicket))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = pipOk ? (sellOpenPrice - currentPrice) / pipSize : 0;

      if(profitPips > sellMaxProfitPips)
         sellMaxProfitPips = profitPips;

      for(int i=0; i<4; i++)
      {
         double markPips = 0;
         if(!SellPartialThresholdHit(i, currentPrice, markPips) || sellClosedFraction >= partialCumFrac[i])
            continue;

         double targetFrac = partialCumFrac[i];
         double volumeToClose = sellOriginalLot * (targetFrac - sellClosedFraction);
         volumeToClose = NormalizeDouble(volumeToClose, 2);

         if(volumeToClose > 0 && volumeToClose <= PositionGetDouble(POSITION_VOLUME))
         {
            if(trade.PositionClosePartial(sellTicket, volumeToClose))
            {
               double oldClosedFraction = sellClosedFraction;
               sellClosedFraction = targetFrac;
               if(UseAtrPartialTp && sellEntryATR > 0)
                  PrintFormat("Partial TP (ATR): closed %.2f lots (%.0f%%) at +%.2f ATR (~%.1f pips)",
                              volumeToClose, targetFrac*100,
                              (sellOpenPrice - currentPrice) / sellEntryATR, markPips);
               else
                  PrintFormat("Partial TP: closed %.2f lots (%.0f%%) at +%.1f pips",
                              volumeToClose, targetFrac*100, markPips);

               if(UseTrailingAfterPartial && !sellTrailingActive && oldClosedFraction < trailActivateFraction && sellClosedFraction >= trailActivateFraction)
               {
                  sellTrailingActive = true;
                  sellTrailingBestPrice = currentPrice;
                     Print("Trailing stop activated for SELL (partial threshold reached)");
               }

               if(sellClosedFraction >= 0.999)
               {
                  isSellActive = false;
                  sellTicket = 0;
                  sellOriginalLot = 0;
                  sellClosedFraction = 0;
                  sellMaxProfitPips = 0;
                  sellTrailingActive = false;
                  sellEntryATR = 0;
                  Print("SELL position fully closed by partial TP");
               }
               break;
            }
            else
               Print("Partial TP failed: ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Breakeven                                                 |
//+------------------------------------------------------------------+
void ManageBreakeven()
{
   double pipSize = PipSizeInPrice();
   if(pipSize <= 0)
      return;

   // BUY breakeven
   if(isBuyActive && buyTicket > 0 && !buyBreakevenTriggered && buyInitialSLPips > 0)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double profitPips = (currentPrice - buyOpenPrice) / pipSize;
      double triggerPips = buyInitialSLPips * BreakevenFraction;

      if(profitPips >= triggerPips)
      {
         double newSL = NormalizeDouble(buyOpenPrice + _Point * 5, _Digits);
         if(trade.PositionModify(buyTicket, newSL, buyTP))
         {
            buyBreakevenTriggered = true;
            buySL = newSL;
            PrintFormat("BUY breakeven triggered at %.1f pips profit", profitPips);
         }
      }
   }

   // SELL breakeven
   if(isSellActive && sellTicket > 0 && !sellBreakevenTriggered && sellInitialSLPips > 0)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPips = (sellOpenPrice - currentPrice) / pipSize;
      double triggerPips = sellInitialSLPips * BreakevenFraction;

      if(profitPips >= triggerPips)
      {
         double newSL = NormalizeDouble(sellOpenPrice - _Point * 5, _Digits);
         if(trade.PositionModify(sellTicket, newSL, sellTP))
         {
            sellBreakevenTriggered = true;
            sellSL = newSL;
            PrintFormat("SELL breakeven triggered at %.1f pips profit", profitPips);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop (activated after 50% partial close)         |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double trailDistance = TrailingDistancePrice();
   if(trailDistance <= 0)
      return;

   // --- BUY trailing
   if(isBuyActive && buyTrailingActive && buyTicket > 0 && PositionSelectByTicket(buyTicket))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Update best price (highest since trailing activated)
      if(currentPrice > buyTrailingBestPrice)
         buyTrailingBestPrice = currentPrice;

      double newSL = NormalizeDouble(buyTrailingBestPrice - trailDistance, _Digits);
      double currentSL = PositionGetDouble(POSITION_SL);

      // Only modify if new SL is higher than current SL (improves stop)
      if(newSL > currentSL + _Point)
      {
         if(trade.PositionModify(buyTicket, newSL, buyTP))
         {
            buySL = newSL;
            double pip = PipSizeInPrice();
            double eqPips = (pip > 0) ? trailDistance / pip : 0;
            if(TrailUseAtr)
               PrintFormat("BUY trailing -> %.5f (dist %.2f = ~%.1f pips, ATR mult %.2f)", newSL, trailDistance, eqPips, TrailAtrMult);
            else
               PrintFormat("BUY trailing -> %.5f (~%.1f pips fixed)", newSL, eqPips);
         }
      }
   }

   // --- SELL trailing
   if(isSellActive && sellTrailingActive && sellTicket > 0 && PositionSelectByTicket(sellTicket))
   {
      double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // Update best price (lowest since trailing activated)
      if(currentPrice < sellTrailingBestPrice)
         sellTrailingBestPrice = currentPrice;

      double newSL = NormalizeDouble(sellTrailingBestPrice + trailDistance, _Digits);
      double currentSL = PositionGetDouble(POSITION_SL);

      if(newSL < currentSL - _Point)
      {
         if(trade.PositionModify(sellTicket, newSL, sellTP))
         {
            sellSL = newSL;
            double pip = PipSizeInPrice();
            double eqPips = (pip > 0) ? trailDistance / pip : 0;
            if(TrailUseAtr)
               PrintFormat("SELL trailing -> %.5f (dist %.2f = ~%.1f pips, ATR mult %.2f)", newSL, trailDistance, eqPips, TrailAtrMult);
            else
               PrintFormat("SELL trailing -> %.5f (~%.1f pips fixed)", newSL, eqPips);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Original MACD + RSI + EMA200 strategy                            |
//+------------------------------------------------------------------+
void ProcessOriginalStrategy()
{
   double macdMain[3], macdSignal[3];
   double ema200[1], rsi[1], atr[1];

   if(CopyBuffer(macdHandle, 0, 1, 3, macdMain) < 3 ||
      CopyBuffer(macdHandle, 1, 1, 3, macdSignal) < 3 ||
      CopyBuffer(ema200Handle, 0, 1, 1, ema200) < 1 ||
      CopyBuffer(rsiHandle, 0, 1, 1, rsi) < 1 ||
      CopyBuffer(atrHandle, 0, 1, 1, atr) < 1)
      return;

   double closePrev = GetClose(1);

   bool macdCrossover  = (macdMain[2] <= macdSignal[2] && macdMain[1] > macdSignal[1]);
   bool macdCrossunder = (macdMain[2] >= macdSignal[2] && macdMain[1] < macdSignal[1]);
   bool macdBullish    = (macdMain[1] > macdSignal[1]);
   bool macdBearish    = (macdMain[1] < macdSignal[1]);

   bool trendBull = (closePrev > ema200[0]);
   bool trendBear = (closePrev < ema200[0]);

   bool rsiBullish = (rsi[0] > 50 && rsi[0] < 66);
   bool rsiBearish = (rsi[0] < 50 && rsi[0] > 34);
   double rsiStrength = MathAbs(rsi[0] - 50) / 20;

   double macdStrength = MathAbs(macdMain[1] - macdSignal[1]) / (atr[0] + _Point);

   double buyConfirmation = 0;
   double sellConfirmation = 0;

   if(trendBull) buyConfirmation += 30;
   if(trendBear) sellConfirmation += 30;

   if(macdBullish) buyConfirmation += 30 * MathMin(macdStrength * 2, 1);
   if(macdBearish) sellConfirmation += 30 * MathMin(macdStrength * 2, 1);

   if(rsiBullish) buyConfirmation += 25 * rsiStrength;
   if(rsiBearish) sellConfirmation += 25 * rsiStrength;

   if(macdCrossover) buyConfirmation += 15;
   if(macdCrossunder) sellConfirmation += 15;

   buyConfirmation = MathMin(buyConfirmation, 100);
   sellConfirmation = MathMin(sellConfirmation, 100);

   bool buySignal  = (buyConfirmation >= MinConfirmation) && macdCrossover && trendBull;
   bool sellSignal = (sellConfirmation >= MinConfirmation) && macdCrossunder && trendBear;

   if(buySignal)
   {
      if(isSellActive) ClosePosition(sellTicket);
      if(!isBuyActive && AllowNewEntries())
         OpenBuy(atr[0]);
   }

   if(sellSignal)
   {
      if(isBuyActive) ClosePosition(buyTicket);
      if(!isSellActive && AllowNewEntries())
         OpenSell(atr[0]);
   }

   UpdateSignalStrength(buyConfirmation, sellConfirmation);
}

//+------------------------------------------------------------------+
//| Smart Money Strategy                                             |
//+------------------------------------------------------------------+
void ProcessSmartMoneyStrategy()
{
   double atr[1];
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) < 1)
      return;

   double ema200SM[1];
   double closePrev = 0;
   if(UseEMA200FilterSM)
   {
      if(CopyBuffer(ema200Handle, 0, 1, 1, ema200SM) < 1)
         return;
      closePrev = GetClose(1);
   }

   DetectSwingPoints();
   bool sweepHigh = DetectSweep(true, atr[0]);
   bool sweepLow  = DetectSweep(false, atr[0]);

   bool obFound = false;
   if(sweepHigh)
      obFound = FindOrderBlock(true, atr[0]);
   if(sweepLow)
      obFound = FindOrderBlock(false, atr[0]);

   fvgDetected = false;
   if(RequireFVGConfluence)
      fvgDetected = DetectFVG(sweepHigh, sweepLow);

   double ema9[2], ema20[2];
   ArraySetAsSeries(ema9, true);
   ArraySetAsSeries(ema20, true);
   if(CopyBuffer(ema9Handle, 0, 0, 2, ema9) < 2 ||
      CopyBuffer(ema20Handle, 0, 0, 2, ema20) < 2)
      return;

   bool trendUp   = (ema9[0] > ema20[0]);
   bool trendDown = (ema9[0] < ema20[0]);

   bool buySignal = false, sellSignal = false;
   double buyConf = 0, sellConf = 0;

   if(sweepHigh && obFound && trendUp)
   {
      if(!RequireFVGConfluence || (RequireFVGConfluence && fvgDetected))
      {
         buySignal = true;
         buyConf = 70 + (obFound ? 20 : 0) + (trendUp ? 10 : 0);
         if(RequireFVGConfluence && fvgDetected) buyConf += 10;
      }
   }
   if(sweepLow && obFound && trendDown)
   {
      if(!RequireFVGConfluence || (RequireFVGConfluence && fvgDetected))
      {
         sellSignal = true;
         sellConf = 70 + (obFound ? 20 : 0) + (trendDown ? 10 : 0);
         if(RequireFVGConfluence && fvgDetected) sellConf += 10;
      }
   }

   if(UseEMA200FilterSM)
   {
      if(buySignal && closePrev <= ema200SM[0])
         buySignal = false;
      if(sellSignal && closePrev >= ema200SM[0])
         sellSignal = false;
   }

   if(buySignal && buyConf < (double)MinSmartMoneyConf)
      buySignal = false;
   if(sellSignal && sellConf < (double)MinSmartMoneyConf)
      sellSignal = false;

   double confidence = MathMax(buyConf, sellConf);
   confidence = MathMin(confidence, 100);
   currentConfidence = confidence;

   if(buySignal && !isBuyActive)
   {
      if(isSellActive) ClosePosition(sellTicket);
      if(AllowNewEntries())
         OpenSmartMoneyBuy(atr[0]);
   }
   if(sellSignal && !isSellActive)
   {
      if(isBuyActive) ClosePosition(buyTicket);
      if(AllowNewEntries())
         OpenSmartMoneySell(atr[0]);
   }

   UpdateSmartMoneyDisplay(sweepHigh, sweepLow, obFound, confidence);
}

//+------------------------------------------------------------------+
//| Open Buy (Original)                                              |
//+------------------------------------------------------------------+
void OpenBuy(double atrValue)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(entryPrice - atrValue * slMult, _Digits);
   sl = NormalizeStopWithAtrCap(entryPrice, sl, true, atrValue);
   double tp = 0;
   if(tpMult > 0)
      tp = NormalizeDouble(entryPrice + atrValue * tpMult, _Digits);

   if(trade.Buy(lotSize, _Symbol, 0, sl, tp, "FX Millionaires Buy"))
   {
      buyTicket = PositionTicketFromLastDeal(POSITION_TYPE_BUY);
      isBuyActive = true;
      buyOpenPrice = entryPrice;
      buySL = sl;
      buyTP = tp;
      buyOriginalLot = lotSize;
      buyClosedFraction = 0;
      buyMaxProfitPips = 0;
      buyBreakevenTriggered = false;
      buyTrailingActive = false;
      buyTrailingBestPrice = 0;
      buyInitialSLPips = StopLossDistancePips(buyOpenPrice, buySL, true);
      if(!CopyAtrPrevBar(buyEntryATR))
         buyEntryATR = atrValue;
      if(buyTicket == 0)
         Print("Warning: BUY opened but position ticket not resolved; partial/BE/trail may fail until next tick.");
   }
   else
      Print("Buy failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Open Sell (Original)                                             |
//+------------------------------------------------------------------+
void OpenSell(double atrValue)
{
   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(entryPrice + atrValue * slMult, _Digits);
   sl = NormalizeStopWithAtrCap(entryPrice, sl, false, atrValue);
   double tp = 0;
   if(tpMult > 0)
      tp = NormalizeDouble(entryPrice - atrValue * tpMult, _Digits);

   if(trade.Sell(lotSize, _Symbol, 0, sl, tp, "FX Millionaires Sell"))
   {
      sellTicket = PositionTicketFromLastDeal(POSITION_TYPE_SELL);
      isSellActive = true;
      sellOpenPrice = entryPrice;
      sellSL = sl;
      sellTP = tp;
      sellOriginalLot = lotSize;
      sellClosedFraction = 0;
      sellMaxProfitPips = 0;
      sellBreakevenTriggered = false;
      sellTrailingActive = false;
      sellTrailingBestPrice = 0;
      sellInitialSLPips = StopLossDistancePips(sellOpenPrice, sellSL, false);
      if(!CopyAtrPrevBar(sellEntryATR))
         sellEntryATR = atrValue;
      if(sellTicket == 0)
         Print("Warning: SELL opened but position ticket not resolved; partial/BE/trail may fail until next tick.");
   }
   else
      Print("Sell failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Open Smart Money Buy                                             |
//+------------------------------------------------------------------+
void OpenSmartMoneyBuy(double atrValue)
{
   if(RequireOBConfluence && (orderBlockHigh == 0 || orderBlockLow == 0))
      return;

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(orderBlockHigh > 0 && orderBlockLow > 0)
   {
      double obRange = orderBlockHigh - orderBlockLow;
      double retrace = orderBlockLow + obRange * obEntryZone;
      if(retrace > entryPrice) entryPrice = retrace;
   }

   double sl = (orderBlockLow > 0) ? orderBlockLow - atrValue*0.5 : entryPrice - atrValue*slMult;
   sl = NormalizeDouble(sl, _Digits);
   sl = NormalizeStopWithAtrCap(entryPrice, sl, true, atrValue);
   double tp = 0;
   if(tpMult > 0)
      tp = NormalizeDouble(entryPrice + atrValue * tpMult, _Digits);

   if(!trade.Buy(lotSize, _Symbol, 0, sl, tp, "SM Buy"))
   {
      Print("Smart Money BUY failed: ", trade.ResultRetcodeDescription());
      return;
   }

   buyTicket = PositionTicketFromLastDeal(POSITION_TYPE_BUY);
   isBuyActive = true;
   buyOpenPrice = entryPrice;
   buySL = sl;
   buyTP = tp;
   buyOriginalLot = lotSize;
   buyClosedFraction = 0;
   buyMaxProfitPips = 0;
   buyBreakevenTriggered = false;
   buyTrailingActive = false;
   buyTrailingBestPrice = 0;
   buyInitialSLPips = StopLossDistancePips(buyOpenPrice, buySL, true);
   if(!CopyAtrPrevBar(buyEntryATR))
      buyEntryATR = atrValue;
   Print("Smart Money BUY order placed");
}

//+------------------------------------------------------------------+
//| Open Smart Money Sell                                            |
//+------------------------------------------------------------------+
void OpenSmartMoneySell(double atrValue)
{
   if(RequireOBConfluence && (orderBlockHigh == 0 || orderBlockLow == 0))
      return;

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(orderBlockHigh > 0 && orderBlockLow > 0)
   {
      double obRange = orderBlockHigh - orderBlockLow;
      double retrace = orderBlockHigh - obRange * obEntryZone;
      if(retrace < entryPrice) entryPrice = retrace;
   }

   double sl = (orderBlockHigh > 0) ? orderBlockHigh + atrValue*0.5 : entryPrice + atrValue*slMult;
   sl = NormalizeDouble(sl, _Digits);
   sl = NormalizeStopWithAtrCap(entryPrice, sl, false, atrValue);
   double tp = 0;
   if(tpMult > 0)
      tp = NormalizeDouble(entryPrice - atrValue * tpMult, _Digits);

   if(!trade.Sell(lotSize, _Symbol, 0, sl, tp, "SM Sell"))
   {
      Print("Smart Money SELL failed: ", trade.ResultRetcodeDescription());
      return;
   }

   sellTicket = PositionTicketFromLastDeal(POSITION_TYPE_SELL);
   isSellActive = true;
   sellOpenPrice = entryPrice;
   sellSL = sl;
   sellTP = tp;
   sellOriginalLot = lotSize;
   sellClosedFraction = 0;
   sellMaxProfitPips = 0;
   sellBreakevenTriggered = false;
   sellTrailingActive = false;
   sellTrailingBestPrice = 0;
   sellInitialSLPips = StopLossDistancePips(sellOpenPrice, sellSL, false);
   if(!CopyAtrPrevBar(sellEntryATR))
      sellEntryATR = atrValue;
   Print("Smart Money SELL order placed");
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
   bool wasBuyActive = isBuyActive;
   bool wasSellActive = isSellActive;
   isBuyActive = false; isSellActive = false;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) &&
         PositionGetInteger(POSITION_MAGIC) == magicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            isBuyActive = true;
            if(buyTicket != ticket)
            {
               buyTicket = ticket;
               buyOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               buySL = PositionGetDouble(POSITION_SL);
               buyTP = PositionGetDouble(POSITION_TP);
               if(!wasBuyActive)
               {
                  buyOriginalLot = PositionGetDouble(POSITION_VOLUME);
                  buyClosedFraction = 0;
                  buyMaxProfitPips = 0;
                  buyBreakevenTriggered = false;
                  buyTrailingActive = false;
                  buyTrailingBestPrice = 0;
                  buyInitialSLPips = StopLossDistancePips(buyOpenPrice, buySL, true);
                  if(!CopyAtrPrevBar(buyEntryATR))
                     buyEntryATR = 0;
               }
            }
            else
            {
               buyOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               buySL = PositionGetDouble(POSITION_SL);
               buyTP = PositionGetDouble(POSITION_TP);
            }
         }
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            isSellActive = true;
            if(sellTicket != ticket)
            {
               sellTicket = ticket;
               sellOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               sellSL = PositionGetDouble(POSITION_SL);
               sellTP = PositionGetDouble(POSITION_TP);
               if(!wasSellActive)
               {
                  sellOriginalLot = PositionGetDouble(POSITION_VOLUME);
                  sellClosedFraction = 0;
                  sellMaxProfitPips = 0;
                  sellBreakevenTriggered = false;
                  sellTrailingActive = false;
                  sellTrailingBestPrice = 0;
                  sellInitialSLPips = StopLossDistancePips(sellOpenPrice, sellSL, false);
                  if(!CopyAtrPrevBar(sellEntryATR))
                     sellEntryATR = 0;
               }
            }
            else
            {
               sellOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
               sellSL = PositionGetDouble(POSITION_SL);
               sellTP = PositionGetDouble(POSITION_TP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close position helper                                            |
//+------------------------------------------------------------------+
void ClosePosition(ulong ticket)
{
   if(ticket > 0 && PositionSelectByTicket(ticket))
      if(trade.PositionClose(ticket))
         Print("Closed position ", ticket);
}

//+------------------------------------------------------------------+
//| Remaining helper functions (GetClose, GetHigh, GetLow, GetTime,  |
//| DetectSwingPoints, DetectSweep, FindOrderBlock, DetectFVG)       |
//+------------------------------------------------------------------+

double GetClose(int shift)
{
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, PERIOD_CURRENT, shift, 1, close) == 1)
      return close[0];
   return 0;
}

double GetHigh(int shift)
{
   double high[];
   ArraySetAsSeries(high, true);
   if(CopyHigh(_Symbol, PERIOD_CURRENT, shift, 1, high) == 1)
      return high[0];
   return 0;
}

double GetLow(int shift)
{
   double low[];
   ArraySetAsSeries(low, true);
   if(CopyLow(_Symbol, PERIOD_CURRENT, shift, 1, low) == 1)
      return low[0];
   return 0;
}

datetime GetTime(int shift)
{
   datetime time[];
   ArraySetAsSeries(time, true);
   if(CopyTime(_Symbol, PERIOD_CURRENT, shift, 1, time) == 1)
      return time[0];
   return 0;
}

void DetectSwingPoints()
{
   double highs[];
   double lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   int barsNeeded = sweepLookback + 2;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barsNeeded, highs) < barsNeeded ||
      CopyLow(_Symbol, PERIOD_CURRENT, 0, barsNeeded, lows) < barsNeeded)
      return;

   for(int i = 2; i <= sweepLookback; i++)
   {
      if(highs[i] > highs[i+1] && highs[i] > highs[i-1])
         swingHigh[i] = highs[i];
      else
         swingHigh[i] = 0;

      if(lows[i] < lows[i+1] && lows[i] < lows[i-1])
         swingLow[i] = lows[i];
      else
         swingLow[i] = 0;
   }
}

bool DetectSweep(bool buySweep, double atrValue)
{
   double currentPrice = buySweep ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sweepThreshold = atrValue * minSweepSize;
   bool swept = false;

   for(int i = 1; i <= sweepLookback; i++)
   {
      if(buySweep && swingHigh[i] > 0 && currentPrice > swingHigh[i] + sweepThreshold)
      {
         lastSweepHighPrice = swingHigh[i];
         lastSweepHighTime = GetTime(i);
         swept = true;
         break;
      }
      if(!buySweep && swingLow[i] > 0 && currentPrice < swingLow[i] - sweepThreshold)
      {
         lastSweepLowPrice = swingLow[i];
         lastSweepLowTime = GetTime(i);
         swept = true;
         break;
      }
   }
   return swept;
}

bool FindOrderBlock(bool bullish, double atrValue)
{
   if(bullish && lastSweepHighPrice == 0) return false;
   if(!bullish && lastSweepLowPrice == 0) return false;

   for(int i = 1; i <= obLookback; i++)
   {
      if(bullish && swingHigh[i] > 0 && SwingPriceMatches(swingHigh[i], lastSweepHighPrice))
      {
         orderBlockHigh = GetHigh(i);
         orderBlockLow  = GetLow(i);
         orderBlockTime = GetTime(i);
         return true;
      }
      if(!bullish && swingLow[i] > 0 && SwingPriceMatches(swingLow[i], lastSweepLowPrice))
      {
         orderBlockHigh = GetHigh(i);
         orderBlockLow  = GetLow(i);
         orderBlockTime = GetTime(i);
         return true;
      }
   }
   return false;
}

bool DetectFVG(bool sweepHigh, bool sweepLow)
{
   for(int i = 1; i <= 5; i++)
   {
      double high1 = GetHigh(i);
      double low1  = GetLow(i);
      double high2 = GetHigh(i+2);
      double low2  = GetLow(i+2);

      if(sweepHigh && low1 > high2)
      {
         fvgHigh = low1;
         fvgLow  = high2;
         return true;
      }
      if(sweepLow && high1 < low2)
      {
         fvgHigh = high1;
         fvgLow  = low2;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Display functions                                                |
//+------------------------------------------------------------------+
void CreateDisplayPanel()
{
   int w = 420, h = 250;
   ObjectCreate(0, panelName+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panelName+"BG", OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, panelName+"BG", OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, panelName+"BG", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, panelName+"BG", OBJPROP_YSIZE, h);
   ObjectSetInteger(0, panelName+"BG", OBJPROP_BGCOLOR, PanelColor);

   string labels[] = {"Strategy:","Account:","Balance:","Equity:","Position:","Entry:","Current:","P/L:","SL:","TP:","Partial:","Breakeven:","Trailing:","Signal:"};
   int yStart = PanelY+25;
   for(int i=0; i<14; i++)
   {
      ObjectCreate(0, panelName+"LBL"+IntegerToString(i), OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, panelName+"LBL"+IntegerToString(i), OBJPROP_XDISTANCE, PanelX+10);
      ObjectSetInteger(0, panelName+"LBL"+IntegerToString(i), OBJPROP_YDISTANCE, yStart+i*13);
      ObjectSetString(0, panelName+"LBL"+IntegerToString(i), OBJPROP_TEXT, labels[i]);
      ObjectSetInteger(0, panelName+"LBL"+IntegerToString(i), OBJPROP_COLOR, TextColor);

      ObjectCreate(0, panelName+"VAL"+IntegerToString(i), OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, panelName+"VAL"+IntegerToString(i), OBJPROP_XDISTANCE, PanelX+120);
      ObjectSetInteger(0, panelName+"VAL"+IntegerToString(i), OBJPROP_YDISTANCE, yStart+i*13);
      ObjectSetString(0, panelName+"VAL"+IntegerToString(i), OBJPROP_TEXT, "---");
      ObjectSetInteger(0, panelName+"VAL"+IntegerToString(i), OBJPROP_COLOR, TextColor);
   }
}

void UpdateDisplay()
{
   ObjectSetString(0, panelName+"VAL1", OBJPROP_TEXT, AccountInfoString(ACCOUNT_NAME));
   ObjectSetString(0, panelName+"VAL2", OBJPROP_TEXT, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   ObjectSetString(0, panelName+"VAL3", OBJPROP_TEXT, DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));

   string stratName = (ActiveStrategyMode() == 1) ? "MACD" : "Smart Money";
   if(SymbolIsGoldOrMetal())
      stratName = "XAU " + stratName;
   if(UseSessionFilter)
      stratName += IsWithinSessionHours() ? " |Sess" : " |OUT";
   if(MaxSpreadPoints > 0)
   {
      long sp = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(sp > MaxSpreadPoints)
         stratName += " |Spr!";
   }
   ObjectSetString(0, panelName+"VAL0", OBJPROP_TEXT, stratName);

   double pipDisp = PipSizeInPrice();
   if(pipDisp <= 0) pipDisp = _Point;

   string posType="None", entry="---", curr="---", pl="---", sl="---", tp="---", partial="---", be="Inactive", trail="Inactive";
   if(isBuyActive)
   {
      posType="BUY"; entry=DoubleToString(buyOpenPrice,_Digits);
      curr=DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_BID),_Digits);
      double pips = (SymbolInfoDouble(_Symbol,SYMBOL_BID)-buyOpenPrice)/pipDisp;
      pl=DoubleToString(pips,1)+" pips"; sl=DoubleToString(buySL,_Digits); tp=DoubleToString(buyTP,_Digits);
      partial = DoubleToString(buyClosedFraction*100,0)+"% "+(UseAtrPartialTp ? "ATR" : "pip");
      be = buyBreakevenTriggered ? "Triggered" : "Pending";
      trail = buyTrailingActive ? (TrailUseAtr ? "On ATR" : "On pip") : "Off";
   }
   else if(isSellActive)
   {
      posType="SELL"; entry=DoubleToString(sellOpenPrice,_Digits);
      curr=DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_ASK),_Digits);
      double pips = (sellOpenPrice-SymbolInfoDouble(_Symbol,SYMBOL_ASK))/pipDisp;
      pl=DoubleToString(pips,1)+" pips"; sl=DoubleToString(sellSL,_Digits); tp=DoubleToString(sellTP,_Digits);
      partial = DoubleToString(sellClosedFraction*100,0)+"% "+(UseAtrPartialTp ? "ATR" : "pip");
      be = sellBreakevenTriggered ? "Triggered" : "Pending";
      trail = sellTrailingActive ? (TrailUseAtr ? "On ATR" : "On pip") : "Off";
   }

   ObjectSetString(0, panelName+"VAL4", OBJPROP_TEXT, posType);
   ObjectSetString(0, panelName+"VAL5", OBJPROP_TEXT, entry);
   ObjectSetString(0, panelName+"VAL6", OBJPROP_TEXT, curr);
   ObjectSetString(0, panelName+"VAL7", OBJPROP_TEXT, pl);
   ObjectSetString(0, panelName+"VAL8", OBJPROP_TEXT, sl);
   ObjectSetString(0, panelName+"VAL9", OBJPROP_TEXT, tp);
   ObjectSetString(0, panelName+"VAL10", OBJPROP_TEXT, partial);
   ObjectSetString(0, panelName+"VAL11", OBJPROP_TEXT, be);
   ObjectSetString(0, panelName+"VAL12", OBJPROP_TEXT, trail);

   if(StringFind(pl,"-")>=0) ObjectSetInteger(0, panelName+"VAL7", OBJPROP_COLOR, clrRed);
   else if(pl!="---") ObjectSetInteger(0, panelName+"VAL7", OBJPROP_COLOR, clrLimeGreen);
}

void UpdateSignalStrength(double buy, double sell)
{
   string txt = "Buy: "+DoubleToString(buy,1)+"% | Sell: "+DoubleToString(sell,1)+"%";
   if(!AllowNewEntries())
      txt += " | wait";
   ObjectSetString(0, panelName+"VAL13", OBJPROP_TEXT, txt);
   if(buy>=MinConfirmation) ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrLimeGreen);
   else if(sell>=MinConfirmation) ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrRed);
   else ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrYellow);
}

void UpdateSmartMoneyDisplay(bool sweepH, bool sweepL, bool obFound, double conf)
{
   string info = "";
   if(sweepH) info += "Sweep High ";
   if(sweepL) info += "Sweep Low ";
   if(obFound) info += "OB Found ";
   info += "Conf: "+DoubleToString(conf,0)+"%";
   if(!AllowNewEntries())
      info += " wait";
   ObjectSetString(0, panelName+"VAL13", OBJPROP_TEXT, info);
   if(conf>=70) ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrLimeGreen);
   else if(conf>=50) ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrYellow);
   else ObjectSetInteger(0, panelName+"VAL13", OBJPROP_COLOR, clrRed);
}
//+------------------------------------------------------------------+
