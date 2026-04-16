//+------------------------------------------------------------------+
//|                                           DarkkScalp_Ultra_v3.mq5 |
//|              XAU ultra-aggressive scalper — M1/M5 cent account   |
//|      More trade modes + multi entries + recovery risk + controls  |
//+------------------------------------------------------------------+
#property copyright "darkk"
#property link      ""
#property version   "3.00"
#property strict
#property description "DarkkScalp Ultra v3: aggressive XAU scalper for cent/micro accounts."
#property description "Adds multi-position entries, breakout/crossover modes, recovery risk, basket control."
#property description "High risk. Backtest/demo first. Not a guaranteed profit system."

#include <Trade/Trade.mqh>

//====================================================================
// CENT ACCOUNT NOTE
// If your broker shows $10 real money as 1000 balance:
// - 200 profit target = about $2 real money
// - 300 loss limit    = about $3 real money
// If your broker shows $10 as 10.00, use 2.0 and 3.0 instead.
//====================================================================

//--- General
input ulong    InpMagic                    = 91005;
input int      InpSlippagePts              = 80;
input bool     InpRequireGold              = true;
input bool     InpDebugPrint               = false;

//--- Ultra aggressive risk / lots
input double   InpRiskPercent              = 5.00;     // aggressive base risk per trade
input bool     InpUseFixedLots             = false;    // true = ignore risk % and use fixed lot
input double   InpFixedLots                = 0.01;
input double   InpMaxLots                  = 5.00;
input double   InpMinLots                  = 0.01;
input bool     InpForceMinLot              = true;     // if calculated lot is below min, still trade min lot

//--- Optional recovery / profit boost
input bool     InpUseRecoveryMode          = true;     // increases risk after previous closed loss
input double   InpRecoveryMultiplier       = 1.35;     // 5% -> 6.75% after a loss
input double   InpMaxRiskPercent           = 9.00;     // hard cap for boosted risk
input bool     InpUseProfitBoost           = true;     // increases risk slightly after daily profit is positive
input double   InpProfitBoostAfter         = 200.0;    // cent acct: after around $2 real profit
input double   InpProfitBoostMultiplier    = 1.20;

//--- Daily account protection
input bool     InpUseDailyProfitStop       = true;
input double   InpDailyProfitTarget        = 600.0;    // cent acct: approx $6 if $10 shows as 1000
input bool     InpUseDailyLossStop         = true;
input double   InpDailyLossLimit           = 700.0;    // cent acct: approx $7 if $10 shows as 1000
input int      InpMaxTradesPerDay          = 120;      // higher = more trades
input bool     InpCloseAllAtDailyLimit     = true;     // close open trades if daily target/loss is hit
input bool     InpUseEquityDDStop          = true;     // emergency account protection
input double   InpMaxEquityDDPercent       = 35.0;     // stop trading if equity DD from balance is too high

//--- Multi-position behavior
input int      InpMaxOpenPositions         = 4;        // total open positions for this EA/symbol
input int      InpMaxPositionsPerSide      = 3;        // max buy or sell positions
input bool     InpAllowHedge               = false;    // false = do not hold buys and sells together
input bool     InpCloseOppositeOnSignal    = true;     // close opposite side when new signal appears
input int      InpMaxEntriesPerBar         = 2;        // allows scaling on the same candle
input bool     InpEntryOnNewBarOnly        = false;    // false = more trades, true = safer/cleaner
input int      InpMinSecondsBetweenEntries = 45;       // protects from machine-gun entries

//--- R:R and volatility
input int      InpATRPeriod                = 14;
input double   InpSL_ATR_Mult              = 0.52;     // tighter SL = more aggressive
input double   InpTP_ATR_Mult              = 1.18;     // target remains bigger than SL
input double   InpMinATR                   = 0.0;      // 0 = off
input double   InpMaxATR                   = 0.0;      // 0 = off
input bool     InpUseSwingStop             = true;     // use recent swing if it gives more logical SL
input int      InpSwingBars                = 4;
input double   InpSwingBufferATR           = 0.10;

//--- Indicators
input int      InpEMAFast                  = 5;
input int      InpEMASlow                  = 13;
input int      InpEMATrend                 = 34;
input int      InpRSIPeriod                = 14;
input int      InpADXPeriod                = 14;
input bool     InpUseADXFilter             = false;    // OFF = more trades
input double   InpADXMin                   = 14.0;

//--- RSI bands, aggressive
input double   InpRSILongMin               = 32.0;
input double   InpRSILongMax               = 74.0;
input double   InpRSIShortMin              = 26.0;
input double   InpRSIShortMax              = 68.0;
input double   InpRSIPullbackLvl           = 53.0;

//--- Entry modes
input bool     InpUsePullbackEntry         = true;     // EMA trend + RSI/EMA pullback
input bool     InpUseEMATouchPullback      = true;     // price touch EMA = more entries
input bool     InpUseBreakoutEntry         = true;     // momentum breakout mode
input int      InpBreakoutBars             = 5;
input double   InpBreakoutRSIMaxBuy        = 78.0;
input double   InpBreakoutRSIMinSell       = 22.0;
input bool     InpUseCrossEntry            = true;     // EMA fast/slow crossover mode
input bool     InpUseCandleConfirm         = false;    // true = fewer but cleaner trades

//--- Spread and session filters
input int      InpMaxSpreadPts             = 350;      // adjust to broker digits
input bool     InpUseSession               = true;
input int      InpSessStart                = 6;        // server time
input int      InpSessEnd                  = 22;       // server time

//--- Trade management
input bool     InpUseBE                    = true;
input double   InpBE_AtRR                  = 0.38;     // earlier BE for aggressive entries
input double   InpBE_OffsetPts             = 8;
input bool     InpUseTrail                 = true;
input double   InpTrailAfterRR             = 0.65;
input double   InpTrailATRMult             = 0.32;
input bool     InpUseOppositeExit          = true;     // exit open trade if opposite signal appears
input bool     InpUseBasketProfitClose     = true;     // close all when combined open profit reaches target
input double   InpBasketProfitMoney        = 120.0;    // cent acct: approx $1.20 if $10 shows as 1000
input bool     InpUseBasketLossClose       = true;
input double   InpBasketLossMoney          = 250.0;    // cent acct: approx $2.50 if $10 shows as 1000

//--- Panel
input bool     InpShowPanel                = true;
input int      InpPanelX                   = 16;
input int      InpPanelY                   = 24;

CTrade         g_trade;
int            hEMAf, hEMAs, hEMAt, hRSI, hATR, hADX;
datetime       g_lastBarTime               = 0;
datetime       g_lastEntryTime             = 0;
int            g_entriesThisBar            = 0;
string         g_panel                     = "DARKK_SCALP_ULTRA_";

// cached signal for management
bool           g_lastBuySignal             = false;
bool           g_lastSellSignal            = false;

//+------------------------------------------------------------------+
bool IsGoldSymbol()
{
   string s = _Symbol;
   StringToLower(s);
   return (StringFind(s, "xau") >= 0 || StringFind(s, "gold") >= 0);
}

//+------------------------------------------------------------------+
datetime DayStart()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0;
   t.min  = 0;
   t.sec  = 0;
   return StructToTime(t);
}

//+------------------------------------------------------------------+
double TodayProfit(int &entriesToday)
{
   entriesToday = 0;
   double profit = 0.0;
   datetime from = DayStart();
   datetime to   = TimeCurrent();

   if(!HistorySelect(from, to))
      return 0.0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;

      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;

      int entry = (int)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
         entriesToday++;

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         profit += HistoryDealGetDouble(deal, DEAL_PROFIT);
         profit += HistoryDealGetDouble(deal, DEAL_SWAP);
         profit += HistoryDealGetDouble(deal, DEAL_COMMISSION);
      }
   }
   return profit;
}

//+------------------------------------------------------------------+
double LastClosedProfit()
{
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;

      int entry = (int)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
      {
         double p = HistoryDealGetDouble(deal, DEAL_PROFIT)
                  + HistoryDealGetDouble(deal, DEAL_SWAP)
                  + HistoryDealGetDouble(deal, DEAL_COMMISSION);
         return p;
      }
   }
   return 0.0;
}

//+------------------------------------------------------------------+
double CurrentRiskPercent()
{
   double risk = InpRiskPercent;

   if(InpUseRecoveryMode && LastClosedProfit() < 0.0)
      risk *= InpRecoveryMultiplier;

   int entries = 0;
   double today = TodayProfit(entries);
   if(InpUseProfitBoost && today >= InpProfitBoostAfter)
      risk *= InpProfitBoostMultiplier;

   if(risk > InpMaxRiskPercent)
      risk = InpMaxRiskPercent;

   if(risk < 0.01)
      risk = 0.01;

   return risk;
}

//+------------------------------------------------------------------+
int CountPositions(const int typeFilter = -1)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      int typ = (int)PositionGetInteger(POSITION_TYPE);
      if(typeFilter == -1 || typ == typeFilter)
         c++;
   }
   return c;
}

//+------------------------------------------------------------------+
double OpenProfit()
{
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      p += PositionGetDouble(POSITION_PROFIT);
      p += PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

//+------------------------------------------------------------------+
void ClosePositionsByType(const int typeFilter = -1)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      int typ = (int)PositionGetInteger(POSITION_TYPE);
      if(typeFilter == -1 || typ == typeFilter)
         g_trade.PositionClose(tk);
   }
}

//+------------------------------------------------------------------+
bool EquityDDOK()
{
   if(!InpUseEquityDDStop) return true;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0) return true;

   double dd = (bal - eq) / bal * 100.0;
   if(dd >= InpMaxEquityDDPercent)
   {
      if(InpCloseAllAtDailyLimit)
         ClosePositionsByType(-1);
      if(InpDebugPrint) Print("Emergency equity DD stop hit: ", DoubleToString(dd, 2), "%");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool DailyLimitsOK()
{
   int entries = 0;
   double p = TodayProfit(entries);

   if(InpMaxTradesPerDay > 0 && entries >= InpMaxTradesPerDay)
      return false;

   if(InpUseDailyProfitStop && p >= InpDailyProfitTarget)
   {
      if(InpCloseAllAtDailyLimit)
         ClosePositionsByType(-1);
      return false;
   }

   if(InpUseDailyLossStop && p <= -InpDailyLossLimit)
   {
      if(InpCloseAllAtDailyLimit)
         ClosePositionsByType(-1);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
double NormalizeVol(double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0) step = 0.01;
   if(vmin <= 0) vmin = InpMinLots;
   if(vmax <= 0) vmax = InpMaxLots;

   double hardMin = MathMax(vmin, InpMinLots);
   double hardMax = MathMin(vmax, InpMaxLots);

   v = MathFloor(v / step) * step;
   if(v < hardMin) v = hardMin;
   if(v > hardMax) v = MathFloor(hardMax / step) * step;

   return NormalizeDouble(v, 8);
}

//+------------------------------------------------------------------+
double LotsFromRisk(const double entry, const double sl)
{
   if(InpUseFixedLots)
      return NormalizeVol(InpFixedLots);

   double dist = MathAbs(entry - sl);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(dist <= 0 || tickSz <= 0 || tickVal <= 0)
      return NormalizeVol(InpMinLots);

   double lossPerLot = (dist / tickSz) * tickVal;
   if(lossPerLot <= 0)
      return NormalizeVol(InpMinLots);

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0)
      return NormalizeVol(InpMinLots);

   double riskMoney = eq * (CurrentRiskPercent() / 100.0);
   double vol = riskMoney / lossPerLot;

   double brokerMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double hardMin = MathMax(brokerMin, InpMinLots);

   if(vol < hardMin && !InpForceMinLot)
      return 0.0;

   return NormalizeVol(vol);
}

//+------------------------------------------------------------------+
void ApplyFillingMode()
{
   const long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fm & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
bool TerminalOk()
{
   return (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 &&
           MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
}

//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   long sp = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (sp <= InpMaxSpreadPts);
}

//+------------------------------------------------------------------+
bool SessionOK()
{
   if(!InpUseSession) return true;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int h = (int)t.hour;

   if(InpSessStart < InpSessEnd)
      return (h >= InpSessStart && h < InpSessEnd);

   return (h >= InpSessStart || h < InpSessEnd);
}

//+------------------------------------------------------------------+
bool CooldownOK()
{
   if(InpMinSecondsBetweenEntries > 0 && g_lastEntryTime > 0)
   {
      if((TimeCurrent() - g_lastEntryTime) < InpMinSecondsBetweenEntries)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
bool StopsDistanceOK(const bool buy, const double px, const double sl, const double tp)
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;

   if(minDist <= 0) return true;

   if(buy)
   {
      if((px - sl) < minDist) return false;
      if((tp - px) < minDist) return false;
   }
   else
   {
      if((sl - px) < minDist) return false;
      if((px - tp) < minDist) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
double HighestHigh(const int startShift, const int count)
{
   double mx = -100000000.0;
   for(int i = startShift; i < startShift + count; i++)
   {
      double h = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(h > mx) mx = h;
   }
   return mx;
}

//+------------------------------------------------------------------+
double LowestLow(const int startShift, const int count)
{
   double mn = 100000000.0;
   for(int i = startShift; i < startShift + count; i++)
   {
      double l = iLow(_Symbol, PERIOD_CURRENT, i);
      if(l < mn) mn = l;
   }
   return mn;
}

//+------------------------------------------------------------------+
void PanelCreate()
{
   if(!InpShowPanel) return;

   ObjectCreate(0, g_panel + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XSIZE, 395);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YSIZE, 105);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BGCOLOR, C'10,14,22');
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_COLOR, C'80,170,120');

   ObjectCreate(0, g_panel + "T", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_YDISTANCE, InpPanelY + 6);
   ObjectSetString(0, g_panel + "T", OBJPROP_TEXT, "DARKK SCALP ULTRA v3");
   ObjectSetString(0, g_panel + "T", OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, g_panel + "T", OBJPROP_FONTSIZE, 13);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_COLOR, C'120,230,170');

   ObjectCreate(0, g_panel + "S", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_YDISTANCE, InpPanelY + 34);
   ObjectSetString(0, g_panel + "S", OBJPROP_TEXT, "XAU M1/M5 | pullback + breakout + cross | multi-entry");
   ObjectSetString(0, g_panel + "S", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "S", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_COLOR, clrSilver);

   ObjectCreate(0, g_panel + "L", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_YDISTANCE, InpPanelY + 56);
   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "L", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "L", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_COLOR, clrWhite);

   ObjectCreate(0, g_panel + "D", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "D", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "D", OBJPROP_YDISTANCE, InpPanelY + 74);
   ObjectSetString(0, g_panel + "D", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "D", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "D", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "D", OBJPROP_COLOR, clrWhite);

   ObjectCreate(0, g_panel + "E", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "E", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "E", OBJPROP_YDISTANCE, InpPanelY + 90);
   ObjectSetString(0, g_panel + "E", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "E", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "E", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "E", OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
void PanelUpdate()
{
   if(!InpShowPanel) return;

   int entries = 0;
   double p = TodayProfit(entries);
   int buys  = CountPositions(POSITION_TYPE_BUY);
   int sells = CountPositions(POSITION_TYPE_SELL);

   string s = _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)Period());
   s += " | Risk " + DoubleToString(CurrentRiskPercent(), 2) + "%";
   s += " | B/S " + IntegerToString(buys) + "/" + IntegerToString(sells);

   string d = "Today P/L " + DoubleToString(p, 2);
   d += " | Open P/L " + DoubleToString(OpenProfit(), 2);
   d += " | Trades " + IntegerToString(entries);

   string e = "Spread " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   e += " | Bar entries " + IntegerToString(g_entriesThisBar);
   e += " | Signals B/S " + IntegerToString((int)g_lastBuySignal) + "/" + IntegerToString((int)g_lastSellSignal);

   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, s);
   ObjectSetString(0, g_panel + "D", OBJPROP_TEXT, d);
   ObjectSetString(0, g_panel + "E", OBJPROP_TEXT, e);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber((int)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePts);
   ApplyFillingMode();

   hEMAf = iMA(_Symbol, PERIOD_CURRENT, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMAs = iMA(_Symbol, PERIOD_CURRENT, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hEMAt = iMA(_Symbol, PERIOD_CURRENT, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   hADX  = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);

   if(hEMAf == INVALID_HANDLE || hEMAs == INVALID_HANDLE || hEMAt == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("DarkkScalp Ultra: indicator init failed");
      return INIT_FAILED;
   }

   ObjectsDeleteAll(0, g_panel);
   PanelCreate();

   Print("DarkkScalp Ultra v3 loaded | ", _Symbol,
         " | TF=", EnumToString((ENUM_TIMEFRAMES)Period()),
         " | Base risk%=", DoubleToString(InpRiskPercent, 2),
         " | Max open=", IntegerToString(InpMaxOpenPositions));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hEMAf);
   IndicatorRelease(hEMAs);
   IndicatorRelease(hEMAt);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
   IndicatorRelease(hADX);
   ObjectsDeleteAll(0, g_panel);
}

//+------------------------------------------------------------------+
bool BuildSignals(bool &buySig, bool &sellSig, double &atrVal)
{
   buySig = false;
   sellSig = false;
   atrVal = 0.0;

   if(iBars(_Symbol, PERIOD_CURRENT) < InpEMATrend + InpBreakoutBars + 20)
      return false;

   double ef[5], es[5], et[5], rsi[5], atr[1], adx[2];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(hEMAf, 0, 1, 5, ef) < 5 ||
      CopyBuffer(hEMAs, 0, 1, 5, es) < 5 ||
      CopyBuffer(hEMAt, 0, 1, 5, et) < 5 ||
      CopyBuffer(hRSI,  0, 1, 5, rsi) < 5 ||
      CopyBuffer(hATR,  0, 1, 1, atr) < 1 ||
      CopyBuffer(hADX,  0, 1, 2, adx) < 2)
      return false;

   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh(_Symbol, PERIOD_CURRENT, 1);

   atrVal = atr[0];
   if(atrVal <= 0) return false;
   if(InpMinATR > 0 && atrVal < InpMinATR) return false;
   if(InpMaxATR > 0 && atrVal > InpMaxATR) return false;

   bool adxOK = (!InpUseADXFilter) || (adx[1] >= InpADXMin);

   bool candleBull = (c1 > o1);
   bool candleBear = (c1 < o1);
   bool candleOKBuy  = (!InpUseCandleConfirm) || candleBull;
   bool candleOKSell = (!InpUseCandleConfirm) || candleBear;

   bool trendLong  = (ef[1] > es[1] && c1 > et[1]);
   bool trendShort = (ef[1] < es[1] && c1 < et[1]);

   bool emaTouchLong  = InpUseEMATouchPullback && (l1 <= es[1] || l1 <= ef[1]);
   bool emaTouchShort = InpUseEMATouchPullback && (h1 >= es[1] || h1 >= ef[1]);

   bool pullbackL = (rsi[2] < InpRSIPullbackLvl) || emaTouchLong;
   bool pullbackS = (rsi[2] > (100.0 - InpRSIPullbackLvl)) || emaTouchShort;

   bool rsiLongOK  = (rsi[1] > InpRSILongMin  && rsi[1] < InpRSILongMax  && rsi[1] >= rsi[2]);
   bool rsiShortOK = (rsi[1] > InpRSIShortMin && rsi[1] < InpRSIShortMax && rsi[1] <= rsi[2]);

   bool pullBuy  = InpUsePullbackEntry && trendLong  && pullbackL && rsiLongOK;
   bool pullSell = InpUsePullbackEntry && trendShort && pullbackS && rsiShortOK;

   double highBreak = HighestHigh(2, InpBreakoutBars);
   double lowBreak  = LowestLow(2, InpBreakoutBars);

   bool breakBuy  = InpUseBreakoutEntry && trendLong  && c1 > highBreak && rsi[1] < InpBreakoutRSIMaxBuy;
   bool breakSell = InpUseBreakoutEntry && trendShort && c1 < lowBreak  && rsi[1] > InpBreakoutRSIMinSell;

   bool crossBuy  = InpUseCrossEntry && c1 > et[1] && ef[1] > es[1] && ef[2] <= es[2] && rsi[1] > 45.0;
   bool crossSell = InpUseCrossEntry && c1 < et[1] && ef[1] < es[1] && ef[2] >= es[2] && rsi[1] < 55.0;

   buySig  = (pullBuy  || breakBuy  || crossBuy)  && adxOK && candleOKBuy;
   sellSig = (pullSell || breakSell || crossSell) && adxOK && candleOKSell;

   if(buySig && sellSig)
   {
      // conflict protection: follow EMA trend direction only
      if(trendLong && !trendShort) sellSig = false;
      else if(trendShort && !trendLong) buySig = false;
      else { buySig = false; sellSig = false; }
   }

   return true;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool isNewBar = (bt != g_lastBarTime);
   if(isNewBar)
   {
      g_lastBarTime = bt;
      g_entriesThisBar = 0;
   }

   bool buySig = false;
   bool sellSig = false;
   double atrVal = 0.0;
   BuildSignals(buySig, sellSig, atrVal);
   g_lastBuySignal = buySig;
   g_lastSellSignal = sellSig;

   ManageTrades(buySig, sellSig);
   ManageBasket();
   PanelUpdate();

   if(InpEntryOnNewBarOnly && !isNewBar) return;

   if(InpRequireGold && !IsGoldSymbol()) return;
   if(!TerminalOk()) return;
   if(!SpreadOK()) return;
   if(!SessionOK()) return;
   if(!EquityDDOK()) return;
   if(!DailyLimitsOK()) return;
   if(!CooldownOK()) return;
   if(g_entriesThisBar >= InpMaxEntriesPerBar) return;

   int total = CountPositions(-1);
   int buys  = CountPositions(POSITION_TYPE_BUY);
   int sells = CountPositions(POSITION_TYPE_SELL);

   if(total >= InpMaxOpenPositions) return;

   if(buySig)
   {
      if(!InpAllowHedge && sells > 0)
      {
         if(InpCloseOppositeOnSignal) ClosePositionsByType(POSITION_TYPE_SELL);
         else return;
      }
      if(CountPositions(POSITION_TYPE_BUY) < InpMaxPositionsPerSide)
         OpenOrder(true, atrVal);
   }
   else if(sellSig)
   {
      if(!InpAllowHedge && buys > 0)
      {
         if(InpCloseOppositeOnSignal) ClosePositionsByType(POSITION_TYPE_BUY);
         else return;
      }
      if(CountPositions(POSITION_TYPE_SELL) < InpMaxPositionsPerSide)
         OpenOrder(false, atrVal);
   }
}

//+------------------------------------------------------------------+
void OpenOrder(const bool buy, const double atrVal)
{
   if(atrVal <= 0) return;

   double px = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(px <= 0) return;

   double sl, tp;

   if(buy)
   {
      sl = px - atrVal * InpSL_ATR_Mult;
      if(InpUseSwingStop)
      {
         double swing = LowestLow(1, InpSwingBars) - atrVal * InpSwingBufferATR;
         // use swing only when it is not absurdly far
         if(swing < px && MathAbs(px - swing) <= atrVal * (InpSL_ATR_Mult + 0.45))
            sl = swing;
      }
      tp = px + MathAbs(px - sl) * (InpTP_ATR_Mult / InpSL_ATR_Mult);
   }
   else
   {
      sl = px + atrVal * InpSL_ATR_Mult;
      if(InpUseSwingStop)
      {
         double swing = HighestHigh(1, InpSwingBars) + atrVal * InpSwingBufferATR;
         if(swing > px && MathAbs(px - swing) <= atrVal * (InpSL_ATR_Mult + 0.45))
            sl = swing;
      }
      tp = px - MathAbs(px - sl) * (InpTP_ATR_Mult / InpSL_ATR_Mult);
   }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   if(!StopsDistanceOK(buy, px, sl, tp))
   {
      if(InpDebugPrint) Print("Stops too close. Trade skipped.");
      return;
   }

   double lots = LotsFromRisk(px, sl);
   if(lots <= 0)
   {
      if(InpDebugPrint) Print("Lot below minimum. Trade skipped.");
      return;
   }

   string cmt = "DarkkScalp_Ultra_v3";
   bool ok = buy ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cmt)
                 : g_trade.Sell(lots, _Symbol, 0, sl, tp, cmt);

   if(!ok)
   {
      Print("Order failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   }
   else
   {
      g_lastEntryTime = TimeCurrent();
      g_entriesThisBar++;
      PrintFormat("%s opened | lots=%.2f | risk=%.2f%% | SL=%.5f | TP=%.5f",
                  buy ? "BUY" : "SELL",
                  lots,
                  CurrentRiskPercent(),
                  sl,
                  tp);
   }
}

//+------------------------------------------------------------------+
void ManageBasket()
{
   double p = OpenProfit();

   if(InpUseBasketProfitClose && p >= InpBasketProfitMoney)
   {
      ClosePositionsByType(-1);
      return;
   }

   if(InpUseBasketLossClose && p <= -InpBasketLossMoney)
   {
      ClosePositionsByType(-1);
      return;
   }
}

//+------------------------------------------------------------------+
void ManageTrades(const bool buySig, const bool sellSig)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      int typ     = (int)PositionGetInteger(POSITION_TYPE);

      if(InpUseOppositeExit)
      {
         if(typ == POSITION_TYPE_BUY && sellSig)
         {
            g_trade.PositionClose(tk);
            continue;
         }
         if(typ == POSITION_TYPE_SELL && buySig)
         {
            g_trade.PositionClose(tk);
            continue;
         }
      }

      double atr[1];
      if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) continue;
      double a = atr[0];
      if(a <= 0) continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0) continue;

      double slDist = MathAbs(open - sl);
      if(slDist <= 0) continue;

      double profitDist = 0.0;
      if(typ == POSITION_TYPE_BUY)
         profitDist = bid - open;
      else
         profitDist = open - ask;

      double r = profitDist / slDist;

      // Break-even protection.
      if(InpUseBE && r >= InpBE_AtRR)
      {
         double nsl;
         if(typ == POSITION_TYPE_BUY)
            nsl = NormalizeDouble(open + _Point * InpBE_OffsetPts, _Digits);
         else
            nsl = NormalizeDouble(open - _Point * InpBE_OffsetPts, _Digits);

         bool better = (typ == POSITION_TYPE_BUY) ? (nsl > sl && nsl < bid)
                                                  : ((sl == 0 || nsl < sl) && nsl > ask);
         if(better)
            g_trade.PositionModify(tk, nsl, tp);
      }

      // ATR trailing stop.
      if(InpUseTrail && r >= InpTrailAfterRR)
      {
         double dist = a * InpTrailATRMult;

         if(typ == POSITION_TYPE_BUY)
         {
            double nsl = NormalizeDouble(bid - dist, _Digits);
            if(nsl > sl && nsl < bid)
               g_trade.PositionModify(tk, nsl, tp);
         }
         else
         {
            double nsl = NormalizeDouble(ask + dist, _Digits);
            if((sl == 0 || nsl < sl) && nsl > ask)
               g_trade.PositionModify(tk, nsl, tp);
         }
      }
   }
}
//+------------------------------------------------------------------+
