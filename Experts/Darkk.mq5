//+------------------------------------------------------------------+
//|                                                        Darkk.mq5 |
//|                                              XAUUSD M15 aggressive |
//|     Trend + EMA cross + MACD confirm | ATR SL/TP | equity risk   |
//+------------------------------------------------------------------+
#property copyright "darkk"
#property link      ""
#property version   "1.01"
#property strict
#property description "darkk — XAUUSD M15 auto-trader. HIGH RISK / high reward profile."
#property description "Attach to XAUUSD M15. Enable Algo Trading. Test on demo first."

#include <Trade/Trade.mqh>

//--- General
input ulong    InpMagic           = 91001;
input int      InpSlippagePts     = 30;

//--- Strategy (M15 gold)
//--- 0 = strict (EMA cross + MACD + trend) — rare | 1 = trend+MACD (default, more trades) | 2 = cross+MACD only
input int      InpEntryMode       = 1;
input int      InpEMAFast         = 8;
input int      InpEMASlow         = 21;
input int      InpEMATrend        = 55;
input int      InpATRPeriod       = 14;
input int      InpMACDFast        = 12;
input int      InpMACDSlow        = 26;
input int      InpMACDSignal      = 9;

//--- Risk / reward (aggressive defaults — reduce for live)
input double   InpRiskPercent     = 3.0;     // % equity risked at SL (HIGH)
input double   InpSL_ATR_Mult     = 1.65;   // stop distance
input double   InpTP_ATR_Mult     = 5.0;    // take-profit distance (wide target)
input bool     InpUseFixedLots   = false;
input double   InpFixedLots      = 0.1;
input double   InpMaxLots        = 10.0;
input double   InpMinLots        = 0.01;

//--- Management
input bool     InpUseBreakeven   = true;
input double   InpBE_RR          = 0.45;    // move SL to BE after this fraction of initial SL distance in profit
input bool     InpUseTrail       = true;
input double   InpTrail_ATR_Mult = 1.15;
input double   InpTrailStartRR   = 1.2;    // start trailing after this R multiple

//--- Filters
input int      InpMaxSpreadPts   = 0;      // 0 = off (many gold feeds > 55 pts — was blocking all trades)
input bool     InpRequireGold    = true;   // block if symbol not XAU/GOLD
input int      InpTradeStartHour = 0;      // server hour [0..23]
input int      InpTradeEndHour   = 24;     // 24 = end of day

//--- Panel
input bool     InpShowPanel      = true;
input int      InpPanelX         = 16;
input int      InpPanelY         = 24;
input bool     InpDebugPrint     = false;  // log why no trade / order errors

CTrade         g_trade;
int            hEMAf, hEMAs, hEMAt, hATR, hMACD;
datetime       g_lastBar = 0;
ulong          g_posTicket = 0;
int            g_posType = -1;
string         g_panel = "DARKK_PANEL_";

//+------------------------------------------------------------------+
bool IsGoldSymbol()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "xau") >= 0 ||
           StringFind(_Symbol, "GOLD") >= 0 || StringFind(_Symbol, "gold") >= 0);
}

double PipSizePrice()
{
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0) pt = _Point;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(IsGoldSymbol())
      return (dg >= 3) ? pt * 100.0 : pt * 10.0;
   return (dg == 3 || dg == 5) ? pt * 10.0 : pt;
}

double NormalizeVol(double v)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   v = MathFloor(v / step) * step;
   if(v < vmin) v = vmin;
   if(v > vmax) v = vmax;
   if(v > InpMaxLots) v = MathFloor(InpMaxLots / step) * step;
   return NormalizeDouble(v, 8);
}

double LotsFromRisk(const double entry, const double sl, const bool isBuy)
{
   if(InpUseFixedLots)
      return NormalizeVol(InpFixedLots);

   double dist = MathAbs(entry - sl);
   double tickSz = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
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
   if(vol < InpMinLots) vol = InpMinLots;
   return NormalizeVol(vol);
}

bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   return ((long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPts);
}

bool HourOK()
{
   if(InpTradeStartHour == 0 && InpTradeEndHour >= 24) return true;
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int h = (int)t.hour;
   if(InpTradeStartHour < InpTradeEndHour)
      return (h >= InpTradeStartHour && h < InpTradeEndHour);
   return (h >= InpTradeStartHour || h < InpTradeEndHour);
}

bool IsOurPosition()
{
   if(g_posTicket == 0) return false;
   if(!PositionSelectByTicket(g_posTicket)) return false;
   return ((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
}

void ScanPosition()
{
   g_posTicket = 0;
   g_posType = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      g_posTicket = tk;
      g_posType = (int)PositionGetInteger(POSITION_TYPE);
      return;
   }
}

void CloseOurPosition()
{
   if(g_posTicket > 0 && PositionSelectByTicket(g_posTicket))
      g_trade.PositionClose(g_posTicket);
   g_posTicket = 0;
   g_posType = -1;
}

void CreatePanel()
{
   if(!InpShowPanel) return;
   ObjectCreate(0, g_panel + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XSIZE, 280);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YSIZE, 72);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BGCOLOR, C'12,8,18');
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_COLOR, C'180,130,40');

   ObjectCreate(0, g_panel + "T", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_XDISTANCE, InpPanelX + 12);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_YDISTANCE, InpPanelY + 8);
   ObjectSetString(0, g_panel + "T", OBJPROP_TEXT, "DARKK");
   ObjectSetString(0, g_panel + "T", OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, g_panel + "T", OBJPROP_FONTSIZE, 18);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_COLOR, C'220,170,60');

   ObjectCreate(0, g_panel + "S", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_XDISTANCE, InpPanelX + 12);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_YDISTANCE, InpPanelY + 38);
   ObjectSetString(0, g_panel + "S", OBJPROP_TEXT, "XAUUSD M15 · HIGH RISK");
   ObjectSetString(0, g_panel + "S", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "S", OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_COLOR, clrSilver);

   ObjectCreate(0, g_panel + "L", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_XDISTANCE, InpPanelX + 12);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_YDISTANCE, InpPanelY + 54);
   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "L", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "L", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_COLOR, clrWhite);
}

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

bool TerminalAllowsTrading()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      if(InpDebugPrint) Print("darkk: enable Algo Trading (toolbar) + allow automated trading");
      return false;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      if(InpDebugPrint) Print("darkk: EA trading not allowed (check account / button)");
      return false;
   }
   return true;
}

bool SymbolAllowsTrade()
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      if(InpDebugPrint) Print("darkk: symbol trade disabled");
      return false;
   }
   return true;
}

void UpdatePanelLine()
{
   if(!InpShowPanel) return;
   string s = _Symbol + "  " + EnumToString((ENUM_TIMEFRAMES)Period());
   s += "  |  Eq " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
   if(g_posType == (int)POSITION_TYPE_BUY)
      s += "  |  LONG";
   else if(g_posType == (int)POSITION_TYPE_SELL)
      s += "  |  SHORT";
   else
      s += "  |  FLAT";
   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, s);
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
   hATR  = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   hMACD = iMACD(_Symbol, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(hEMAf == INVALID_HANDLE || hEMAs == INVALID_HANDLE || hEMAt == INVALID_HANDLE ||
      hATR == INVALID_HANDLE || hMACD == INVALID_HANDLE)
   {
      Print("darkk: indicator init failed");
      return(INIT_FAILED);
   }

   if(InpRequireGold && !IsGoldSymbol())
      Print("darkk: symbol does not look like gold — trading blocked. Set InpRequireGold=false to override.");

   ObjectsDeleteAll(0, g_panel);
   CreatePanel();
   ScanPosition();
   Print("darkk v1.01 | ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)Period()),
         " | entryMode=", InpEntryMode, " | risk%=", InpRiskPercent,
         " | maxSpreadPts=", InpMaxSpreadPts, " (0=off) | goldReq=", InpRequireGold);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEMAf);
   IndicatorRelease(hEMAs);
   IndicatorRelease(hEMAt);
   IndicatorRelease(hATR);
   IndicatorRelease(hMACD);
   ObjectsDeleteAll(0, g_panel);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ScanPosition();
   ManagePosition();
   UpdatePanelLine();

   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bt == g_lastBar) return;
   g_lastBar = bt;

   if(InpRequireGold && !IsGoldSymbol())
   {
      if(InpDebugPrint) Print("darkk: blocked — not a gold symbol (or set InpRequireGold=false)");
      return;
   }
   if(!SpreadOK())
   {
      if(InpDebugPrint) Print("darkk: blocked — spread ", SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), " > ", InpMaxSpreadPts);
      return;
   }
   if(!HourOK())
   {
      if(InpDebugPrint) Print("darkk: blocked — outside trading hours");
      return;
   }
   if(!TerminalAllowsTrading() || !SymbolAllowsTrade())
      return;
   if(!AllowNewTrade()) return;

   if(iBars(_Symbol, PERIOD_CURRENT) < InpEMATrend + 5)
      return;

   double ef[3], es[3], et[3], atr[1], m0[3], m1[3];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   ArraySetAsSeries(m0, true);
   ArraySetAsSeries(m1, true);

   if(CopyBuffer(hEMAf, 0, 1, 3, ef) < 3 || CopyBuffer(hEMAs, 0, 1, 3, es) < 3 ||
      CopyBuffer(hEMAt, 0, 1, 2, et) < 2 || CopyBuffer(hATR, 0, 1, 1, atr) < 1 ||
      CopyBuffer(hMACD, 0, 1, 3, m0) < 3 || CopyBuffer(hMACD, 1, 1, 3, m1) < 3)
      return;

   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool crossUp   = (ef[1] > es[1] && ef[2] <= es[2]);
   bool crossDown = (ef[1] < es[1] && ef[2] >= es[2]);
   bool macdBull  = (m0[1] > m1[1]);
   bool macdBear  = (m0[1] < m1[1]);
   bool trendLong  = (ef[1] > es[1] && c1 > et[1]);
   bool trendShort = (ef[1] < es[1] && c1 < et[1]);

   bool buySig  = false;
   bool sellSig = false;
   if(InpEntryMode == 0)
   {
      buySig  = crossUp && c1 > et[1] && macdBull;
      sellSig = crossDown && c1 < et[1] && macdBear;
   }
   else if(InpEntryMode == 1)
   {
      buySig  = trendLong && macdBull;
      sellSig = trendShort && macdBear;
   }
   else
   {
      buySig  = crossUp && macdBull;
      sellSig = crossDown && macdBear;
   }

   if(g_posType == (int)POSITION_TYPE_BUY && sellSig)
      CloseOurPosition();
   if(g_posType == (int)POSITION_TYPE_SELL && buySig)
      CloseOurPosition();

   ScanPosition();
   if(g_posTicket != 0) return;

   double a = atr[0];
   if(a <= 0) return;

   if(buySig)
      OpenTrade(true, a);
   else if(sellSig)
      OpenTrade(false, a);
}

bool AllowNewTrade()
{
   return (g_posTicket == 0);
}

void OpenTrade(const bool buy, const double atrVal)
{
   double px = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(buy)
   {
      sl = NormalizeDouble(px - atrVal * InpSL_ATR_Mult, _Digits);
      tp = (InpTP_ATR_Mult > 0) ? NormalizeDouble(px + atrVal * InpTP_ATR_Mult, _Digits) : 0;
   }
   else
   {
      sl = NormalizeDouble(px + atrVal * InpSL_ATR_Mult, _Digits);
      tp = (InpTP_ATR_Mult > 0) ? NormalizeDouble(px - atrVal * InpTP_ATR_Mult, _Digits) : 0;
   }

   double lots = LotsFromRisk(px, sl, buy);
   string cmt = "darkk";

   bool ok = buy ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cmt) : g_trade.Sell(lots, _Symbol, 0, sl, tp, cmt);
   if(!ok)
   {
      Print("darkk: order failed ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
      Print("darkk: check margin, symbol settings, filling mode. Lots=", lots);
   }
   else
   {
      PrintFormat("darkk: %s %.2f lots SL=%.5f TP=%.5f risk=%.1f%%", buy ? "BUY" : "SELL", lots, sl, tp, InpRiskPercent);
      ScanPosition();
   }
}

void ManagePosition()
{
   if(!IsOurPosition()) return;
   if(!PositionSelectByTicket(g_posTicket)) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   int    typ  = (int)PositionGetInteger(POSITION_TYPE);

   double atr[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   double a = atr[0];

   double pip = PipSizePrice();
   if(pip <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double slDist = 0;
   if(typ == POSITION_TYPE_BUY && sl > 0 && sl < open)
      slDist = (open - sl) / pip;
   else if(typ == POSITION_TYPE_SELL && sl > 0 && sl > open)
      slDist = (sl - open) / pip;

   double profitPips = 0;
   if(typ == POSITION_TYPE_BUY)
      profitPips = (bid - open) / pip;
   else
      profitPips = (open - ask) / pip;

   if(InpUseBreakeven && slDist > 0 && profitPips >= slDist * InpBE_RR)
   {
      double nsl;
      if(typ == POSITION_TYPE_BUY)
         nsl = NormalizeDouble(open - _Point * 5, _Digits);
      else
         nsl = NormalizeDouble(open + _Point * 5, _Digits);
      bool better = (typ == POSITION_TYPE_BUY) ? (nsl > sl) : (nsl < sl);
      if(better)
         g_trade.PositionModify(g_posTicket, nsl, tp);
   }

   if(InpUseTrail && slDist > 0 && profitPips >= slDist * InpTrailStartRR)
   {
      double dist = a * InpTrail_ATR_Mult;
      if(typ == POSITION_TYPE_BUY)
      {
         double nsl = NormalizeDouble(bid - dist, _Digits);
         if(nsl > sl && nsl < bid)
            g_trade.PositionModify(g_posTicket, nsl, tp);
      }
      else
      {
         double nsl = NormalizeDouble(ask + dist, _Digits);
         if(sl == 0 || nsl < sl)
            if(nsl > ask)
               g_trade.PositionModify(g_posTicket, nsl, tp);
      }
   }
}

//+------------------------------------------------------------------+
