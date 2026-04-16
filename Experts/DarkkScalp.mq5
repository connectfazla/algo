//+------------------------------------------------------------------+
//|                                      DarkkScalp_Aggressive_v2.mq5 |
//|                     XAU aggressive scalper — M1/M5 cent account  |
//|        More trades + daily target stop + daily loss protection    |
//+------------------------------------------------------------------+
#property copyright "darkk"
#property link      ""
#property version   "2.01"
#property strict
#property description "DarkkScalp Aggressive: XAU M1/M5 scalper using EMA trend + RSI pullback."
#property description "Designed for cent/micro accounts. Aggressive risk. Use demo/backtest first."

#include <Trade/Trade.mqh>

//====================================================================
// IMPORTANT DEFAULTS
// If your cent account shows $10 as 1000 balance, then:
// - 200 profit target = around $2 real money
// - 300 loss limit    = around $3 real money
// If your account shows $10 as 10.00 balance, change target to 2.0.
//====================================================================

//--- General
input ulong    InpMagic              = 91004;
input int      InpSlippagePts        = 60;
input string   InpTradeSymbol        = "";       // Empty = use chart symbol. Set e.g. XAUUSD to always trade gold
input bool     InpRequireGold        = true;     // If true, init fails unless trade symbol is gold/XAU
input bool     InpDebugPrint         = false;

//--- Aggressive risk / lots
input double   InpRiskPercent        = 3.00;     // Aggressive: % equity risked at SL per trade
input bool     InpUseFixedLots       = false;    // true = ignore risk % and use fixed lot
input double   InpFixedLots          = 0.01;
input double   InpMaxLots            = 3.00;
input double   InpMinLots            = 0.01;
input bool     InpForceMinLot        = true;     // If risk calc is below min lot, still trade min lot

//--- Daily account protection
input bool     InpUseDailyProfitStop = true;
input double   InpDailyProfitTarget  = 200.0;    // Cent acct: 200 = approx $2 if $10 shows as 1000
input bool     InpUseDailyLossStop   = true;
input double   InpDailyLossLimit     = 300.0;    // Cent acct: 300 = approx $3 if $10 shows as 1000
input int      InpMaxTradesPerDay    = 35;       // Prevents unlimited overtrading

//--- R:R and volatility
input int      InpATRPeriod          = 14;
input double   InpSL_ATR_Mult        = 0.60;     // Tight SL for scalping
input double   InpTP_ATR_Mult        = 1.20;     // 2R target vs SL
input double   InpMinATR             = 0.0;      // 0 = off. Use if market is too flat
input double   InpMaxATR             = 0.0;      // 0 = off. Use if news volatility is too wild

//--- Indicators
input int      InpEMAFast            = 5;
input int      InpEMASlow            = 13;
input int      InpEMATrend           = 34;
input int      InpRSIPeriod          = 14;
input int      InpADXPeriod          = 14;
input bool     InpUseADXFilter       = false;    // OFF = more trades. ON = cleaner but fewer trades
input double   InpADXMin             = 16.0;

//--- RSI bands, loosened for more entries
input double   InpRSILongMin         = 35.0;
input double   InpRSILongMax         = 70.0;
input double   InpRSIShortMin        = 30.0;
input double   InpRSIShortMax        = 65.0;
input double   InpRSIPullbackLvl     = 52.0;

//--- Entry behavior
input int      InpCooldownBars       = 0;        // 0 = maximum entries, 1 = safer
input bool     InpUseCandleConfirm   = false;    // true = fewer but cleaner trades
input bool     InpUseEMATouchPullback= true;     // More entries using EMA pullback/touch logic

//--- Spread and session filters
input int      InpMaxSpreadPts       = 300;      // XAU spread filter. Adjust to broker digits
input bool     InpUseSession         = true;
input int      InpSessStart          = 7;        // Server time
input int      InpSessEnd            = 21;       // Server time

//--- Trade management
input bool     InpUseBE              = true;
input double   InpBE_AtRR            = 0.45;     // Move SL near BE earlier
input double   InpBE_OffsetPts       = 5;        // Small offset around entry
input bool     InpUseTrail           = true;
input double   InpTrailAfterRR       = 0.75;
input double   InpTrailATRMult       = 0.35;

//--- Panel
input bool     InpShowPanel          = true;
input int      InpPanelX             = 16;
input int      InpPanelY             = 24;

CTrade         g_trade;
int            hEMAf, hEMAs, hEMAt, hRSI, hATR, hADX;
datetime       g_lastBarTime         = 0;
ulong          g_posTicket           = 0;
int            g_posType             = -1;
datetime       g_lastEntryTime       = 0;
string         g_panel               = "DARKK_SCALP_AGG_";
string         g_sym                 = "";
int            g_symDigits           = 0;
double         g_symPt               = 0.0;

//+------------------------------------------------------------------+
bool IsGoldSymbol(const string sym)
{
   string s = sym;
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

      string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(sym != g_sym) continue;

      long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
      if((ulong)magic != InpMagic) continue;

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
bool DailyLimitsOK()
{
   int entries = 0;
   double p = TodayProfit(entries);

   if(InpMaxTradesPerDay > 0 && entries >= InpMaxTradesPerDay)
   {
      if(InpDebugPrint) Print("Daily max trades reached: ", entries);
      return false;
   }

   if(InpUseDailyProfitStop && p >= InpDailyProfitTarget)
   {
      if(InpDebugPrint) Print("Daily profit target reached: ", DoubleToString(p, 2));
      return false;
   }

   if(InpUseDailyLossStop && p <= -InpDailyLossLimit)
   {
      if(InpDebugPrint) Print("Daily loss limit reached: ", DoubleToString(p, 2));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
double NormalizeVol(double v)
{
   double step = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);

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
   double tickSz  = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);

   if(dist <= 0 || tickSz <= 0 || tickVal <= 0)
      return NormalizeVol(InpMinLots);

   double lossPerLot = (dist / tickSz) * tickVal;
   if(lossPerLot <= 0)
      return NormalizeVol(InpMinLots);

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0)
      return NormalizeVol(InpMinLots);

   double riskMoney = eq * (InpRiskPercent / 100.0);
   double vol = riskMoney / lossPerLot;

   double brokerMin = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double hardMin = MathMax(brokerMin, InpMinLots);

   if(vol < hardMin && !InpForceMinLot)
      return 0.0;

   return NormalizeVol(vol);
}

//+------------------------------------------------------------------+
void ApplyFillingMode()
{
   const long fm = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
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
   long sp = (long)SymbolInfoInteger(g_sym, SYMBOL_SPREAD);
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
void ScanPosition()
{
   g_posTicket = 0;
   g_posType = -1;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      g_posTicket = tk;
      g_posType = (int)PositionGetInteger(POSITION_TYPE);
      return;
   }
}

//+------------------------------------------------------------------+
bool CooldownOK()
{
   if(InpCooldownBars <= 0) return true;
   if(g_lastEntryTime == 0) return true;

   int sh = iBarShift(g_sym, PERIOD_CURRENT, g_lastEntryTime, false);
   if(sh < 0) return true;

   return (sh >= InpCooldownBars);
}

//+------------------------------------------------------------------+
bool StopsDistanceOK(const bool buy, const double px, const double sl, const double tp)
{
   int stopsLevel = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * g_symPt;

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
void PanelCreate()
{
   if(!InpShowPanel) return;

   ObjectCreate(0, g_panel + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XSIZE, 355);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YSIZE, 92);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BGCOLOR, C'10,14,22');
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_COLOR, C'70,160,120');

   ObjectCreate(0, g_panel + "T", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_YDISTANCE, InpPanelY + 6);
   ObjectSetString(0, g_panel + "T", OBJPROP_TEXT, "DARKK SCALP AGGRESSIVE v2");
   ObjectSetString(0, g_panel + "T", OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, g_panel + "T", OBJPROP_FONTSIZE, 13);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_COLOR, C'120,230,170');

   ObjectCreate(0, g_panel + "S", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_YDISTANCE, InpPanelY + 34);
   ObjectSetString(0, g_panel + "S", OBJPROP_TEXT, "XAU M1/M5 | aggressive | daily target/loss protection");
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
   ObjectSetInteger(0, g_panel + "D", OBJPROP_YDISTANCE, InpPanelY + 72);
   ObjectSetString(0, g_panel + "D", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "D", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "D", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "D", OBJPROP_COLOR, clrWhite);
}

//+------------------------------------------------------------------+
void PanelUpdate()
{
   if(!InpShowPanel) return;

   int entries = 0;
   double p = TodayProfit(entries);

   string pos = "FLAT";
   if(g_posType == POSITION_TYPE_BUY)  pos = "LONG";
   if(g_posType == POSITION_TYPE_SELL) pos = "SHORT";

   string s = g_sym + " " + EnumToString((ENUM_TIMEFRAMES)Period());
   if(g_sym != _Symbol)
      s += " | chart " + _Symbol;
   s += " | Risk " + DoubleToString(InpRiskPercent, 2) + "%";
   s += " | " + pos;

   string d = "Today P/L " + DoubleToString(p, 2);
   d += " | Trades " + IntegerToString(entries);
   d += " | Spread " + IntegerToString((int)SymbolInfoInteger(g_sym, SYMBOL_SPREAD));

   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, s);
   ObjectSetString(0, g_panel + "D", OBJPROP_TEXT, d);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym = InpTradeSymbol;
   StringTrimLeft(g_sym);
   StringTrimRight(g_sym);
   if(StringLen(g_sym) == 0)
      g_sym = _Symbol;

   if(!SymbolSelect(g_sym, true))
   {
      Print("DarkkScalp: cannot select symbol '", g_sym, "'. Check spelling (e.g. XAUUSD) and Market Watch.");
      return INIT_FAILED;
   }

   g_symDigits = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_symPt = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(g_symPt <= 0.0)
      g_symPt = _Point;

   if(InpRequireGold && !IsGoldSymbol(g_sym))
   {
      Print("DarkkScalp: InpRequireGold=true but trade symbol is not gold/XAU: ", g_sym,
            ". Set InpTradeSymbol to your broker's gold (e.g. XAUUSD) or attach the EA to a gold chart.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber((int)InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePts);
   ApplyFillingMode();

   hEMAf = iMA(g_sym, PERIOD_CURRENT, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMAs = iMA(g_sym, PERIOD_CURRENT, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hEMAt = iMA(g_sym, PERIOD_CURRENT, InpEMATrend, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(g_sym, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hATR  = iATR(g_sym, PERIOD_CURRENT, InpATRPeriod);
   hADX  = iADX(g_sym, PERIOD_CURRENT, InpADXPeriod);

   if(hEMAf == INVALID_HANDLE || hEMAs == INVALID_HANDLE || hEMAt == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("DarkkScalp Aggressive: indicator init failed");
      return INIT_FAILED;
   }

   ObjectsDeleteAll(0, g_panel);
   PanelCreate();
   ScanPosition();

   Print("DarkkScalp Aggressive v2.01 loaded | TRADE=", g_sym,
         (g_sym != _Symbol ? " | CHART=" + _Symbol : ""),
         " | TF=", EnumToString((ENUM_TIMEFRAMES)Period()),
         " | Risk%=", DoubleToString(InpRiskPercent, 2),
         " | Daily target=", DoubleToString(InpDailyProfitTarget, 2),
         " | Daily loss=", DoubleToString(InpDailyLossLimit, 2));

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
void OnTick()
{
   ScanPosition();
   ManageTrades();
   PanelUpdate();

   datetime bt = iTime(g_sym, PERIOD_CURRENT, 0);
   if(bt == g_lastBarTime) return;
   g_lastBarTime = bt;

   if(InpRequireGold && !IsGoldSymbol(g_sym))
   {
      if(InpDebugPrint) Print("Not a gold/XAU symbol: ", g_sym);
      return;
   }

   if(!TerminalOk()) return;
   if(!SpreadOK()) return;
   if(!SessionOK()) return;
   if(!DailyLimitsOK()) return;
   if(g_posTicket != 0) return;
   if(!CooldownOK()) return;

   if(iBars(g_sym, PERIOD_CURRENT) < InpEMATrend + 20) return;

   double ef[4], es[4], et[4], rsi[4], atr[1], adx[2];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(hEMAf, 0, 1, 4, ef) < 4 ||
      CopyBuffer(hEMAs, 0, 1, 4, es) < 4 ||
      CopyBuffer(hEMAt, 0, 1, 4, et) < 4 ||
      CopyBuffer(hRSI,  0, 1, 4, rsi) < 4 ||
      CopyBuffer(hATR,  0, 1, 1, atr) < 1 ||
      CopyBuffer(hADX,  0, 1, 2, adx) < 2)
      return;

   double c1 = iClose(g_sym, PERIOD_CURRENT, 1);
   double o1 = iOpen(g_sym, PERIOD_CURRENT, 1);
   double l1 = iLow(g_sym, PERIOD_CURRENT, 1);
   double h1 = iHigh(g_sym, PERIOD_CURRENT, 1);

   double a = atr[0];
   if(a <= 0) return;
   if(InpMinATR > 0 && a < InpMinATR) return;
   if(InpMaxATR > 0 && a > InpMaxATR) return;

   bool adxOK = (!InpUseADXFilter) || (adx[1] >= InpADXMin);

   bool candleBull = (c1 > o1);
   bool candleBear = (c1 < o1);
   bool candleOKBuy  = (!InpUseCandleConfirm) || candleBull;
   bool candleOKSell = (!InpUseCandleConfirm) || candleBear;

   // Trend
   bool trendLong  = (ef[1] > es[1] && c1 > et[1]);
   bool trendShort = (ef[1] < es[1] && c1 < et[1]);

   // Pullback logic: RSI pullback OR price touches slow EMA area.
   bool emaTouchLong  = InpUseEMATouchPullback && (l1 <= es[1] || l1 <= ef[1]);
   bool emaTouchShort = InpUseEMATouchPullback && (h1 >= es[1] || h1 >= ef[1]);

   bool pullbackL = (rsi[2] < InpRSIPullbackLvl) || emaTouchLong;
   bool pullbackS = (rsi[2] > (100.0 - InpRSIPullbackLvl)) || emaTouchShort;

   // Momentum continuation after pullback.
   bool rsiLongOK  = (rsi[1] > InpRSILongMin  && rsi[1] < InpRSILongMax  && rsi[1] >= rsi[2]);
   bool rsiShortOK = (rsi[1] > InpRSIShortMin && rsi[1] < InpRSIShortMax && rsi[1] <= rsi[2]);

   bool buySig  = trendLong  && pullbackL && rsiLongOK  && adxOK && candleOKBuy;
   bool sellSig = trendShort && pullbackS && rsiShortOK && adxOK && candleOKSell;

   if(InpDebugPrint)
   {
      PrintFormat("Signals | buy=%d sell=%d | RSI1=%.2f RSI2=%.2f | ATR=%.2f | ADX=%.2f",
                  buySig, sellSig, rsi[1], rsi[2], a, adx[1]);
   }

   if(buySig)
      OpenOrder(true, a);
   else if(sellSig)
      OpenOrder(false, a);
}

//+------------------------------------------------------------------+
void OpenOrder(const bool buy, const double atrVal)
{
   double px = buy ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(px <= 0) return;

   double sl, tp;

   if(buy)
   {
      sl = NormalizeDouble(px - atrVal * InpSL_ATR_Mult, g_symDigits);
      tp = NormalizeDouble(px + atrVal * InpTP_ATR_Mult, g_symDigits);
   }
   else
   {
      sl = NormalizeDouble(px + atrVal * InpSL_ATR_Mult, g_symDigits);
      tp = NormalizeDouble(px - atrVal * InpTP_ATR_Mult, g_symDigits);
   }

   if(!StopsDistanceOK(buy, px, sl, tp))
   {
      if(InpDebugPrint) Print("Stops too close for broker rules. Trade skipped.");
      return;
   }

   double lots = LotsFromRisk(px, sl);
   if(lots <= 0)
   {
      if(InpDebugPrint) Print("Calculated lot below minimum and ForceMinLot=false. Trade skipped.");
      return;
   }

   string cmt = "DarkkScalp_Agg_v2";
   bool ok = buy ? g_trade.Buy(lots, g_sym, 0, sl, tp, cmt)
                 : g_trade.Sell(lots, g_sym, 0, sl, tp, cmt);

   if(!ok)
   {
      Print("Order failed: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   }
   else
   {
      g_lastEntryTime = iTime(g_sym, PERIOD_CURRENT, 0);
      PrintFormat("%s opened | lots=%.2f | SL=%.5f | TP=%.5f | RR=%.2f",
                  buy ? "BUY" : "SELL",
                  lots,
                  sl,
                  tp,
                  InpTP_ATR_Mult / InpSL_ATR_Mult);
      ScanPosition();
   }
}

//+------------------------------------------------------------------+
void ManageTrades()
{
   if(g_posTicket == 0 || !PositionSelectByTicket(g_posTicket)) return;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) return;
   if(PositionGetString(POSITION_SYMBOL) != g_sym) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   int typ     = (int)PositionGetInteger(POSITION_TYPE);

   double atr[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   double a = atr[0];
   if(a <= 0) return;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return;

   double slDist = MathAbs(open - sl);
   if(slDist <= 0) return;

   double profitDist = 0.0;
   if(typ == POSITION_TYPE_BUY)
      profitDist = bid - open;
   else
      profitDist = open - ask;

   double r = profitDist / slDist;

   // Break-even protection (long: SL below entry; short: SL above entry).
   if(InpUseBE && r >= InpBE_AtRR)
   {
      double nsl;
      if(typ == POSITION_TYPE_BUY)
         nsl = NormalizeDouble(open - g_symPt * InpBE_OffsetPts, g_symDigits);
      else
         nsl = NormalizeDouble(open + g_symPt * InpBE_OffsetPts, g_symDigits);

      bool better = (typ == POSITION_TYPE_BUY) ? (nsl > sl && nsl < bid)
                                               : ((sl == 0 || nsl < sl) && nsl > ask);
      if(better)
         g_trade.PositionModify(g_posTicket, nsl, tp);
   }

   // ATR trailing stop.
   if(InpUseTrail && r >= InpTrailAfterRR)
   {
      double dist = a * InpTrailATRMult;

      if(typ == POSITION_TYPE_BUY)
      {
         double nsl = NormalizeDouble(bid - dist, g_symDigits);
         if(nsl > sl && nsl < bid)
            g_trade.PositionModify(g_posTicket, nsl, tp);
      }
      else
      {
         double nsl = NormalizeDouble(ask + dist, g_symDigits);
         if((sl == 0 || nsl < sl) && nsl > ask)
            g_trade.PositionModify(g_posTicket, nsl, tp);
      }
   }
}
//+------------------------------------------------------------------+
