//+------------------------------------------------------------------+
//|                                                  DarkkScalp.mq5 |
//|                                        XAU scalper — lower risk |
//|   More frequent setups | SL < TP (favorable R) | M5/M15 ready |
//+------------------------------------------------------------------+
#property copyright "darkk"
#property link      ""
#property version   "1.01"
#property strict
#property description "darkk SCALP: pullback momentum on EMA trend + RSI."
#property description "Use XAUUSD M5 or M15. Moderate risk % — not a get-rich-quick bot."

#include <Trade/Trade.mqh>

//--- General
input ulong    InpMagic           = 91003;
input int      InpSlippagePts     = 40;

//--- Scalper risk (moderate — not high risk)
input double   InpRiskPercent     = 0.65;    // % equity at SL per trade
input bool     InpUseFixedLots    = false;
input double   InpFixedLots       = 0.05;
input double   InpMaxLots         = 3.0;
input double   InpMinLots         = 0.01;

//--- R:R — SL tighter than TP (expectancy needs reasonable win rate)
input double   InpSL_ATR_Mult     = 0.88;    // stop distance vs ATR(14)
input double   InpTP_ATR_Mult     = 1.18;    // target distance (TP > SL → positive RR if WR ok)

//--- Indicators
input int      InpEMAFast         = 5;
input int      InpEMASlow         = 13;
input int      InpEMATrend        = 34;
input int      InpRSIPeriod       = 14;
input int      InpATRPeriod       = 14;
input int      InpADXPeriod       = 14;
input bool     InpUseADXFilter    = true;    // ADX > min → fewer chop trades
input double   InpADXMin          = 18.0;

//--- RSI bands (avoid chasing extremes)
input double   InpRSILongMin      = 38.0;
input double   InpRSILongMax      = 66.0;
input double   InpRSIShortMin     = 34.0;
input double   InpRSIShortMax     = 62.0;
input double   InpRSIPullbackLvl  = 52.0;    // prior bar RSI below this = pullback

//--- Trade frequency
input int      InpCooldownBars    = 2;      // min bars between new entries (same symbol)
input int      InpMaxSpreadPts    = 0;      // 0 = off
input bool     InpRequireGold     = true;
input bool     InpUseSession      = false;  // if true, restrict hours
input int      InpSessStart       = 7;
input int      InpSessEnd         = 21;

//--- Management
input bool     InpUseBE           = true;
input double   InpBE_AtRR         = 0.55;    // lock BE after this R
input bool     InpUseTrail        = true;
input double   InpTrailAfterRR    = 0.85;
input double   InpTrailATRMult    = 0.42;

//--- Panel / debug
input bool     InpShowPanel       = true;
input int      InpPanelX          = 16;
input int      InpPanelY          = 24;
input bool     InpDebugPrint      = false;

CTrade         g_trade;
int            hEMAf, hEMAs, hEMAt, hRSI, hATR, hADX;
datetime       g_lastBarTime      = 0;
ulong          g_posTicket        = 0;
int            g_posType          = -1;
datetime       g_lastEntryTime    = 0;
string         g_panel            = "DARKK_SCALP_";

//+------------------------------------------------------------------+
bool IsGoldSymbol()
{
   return (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "xau") >= 0 ||
           StringFind(_Symbol, "GOLD") >= 0 || StringFind(_Symbol, "gold") >= 0);
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

double LotsFromRisk(const double entry, const double sl)
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

bool TerminalOk()
{
   return (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 && MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
}

bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   return ((long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= InpMaxSpreadPts);
}

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

bool CooldownOK()
{
   if(InpCooldownBars <= 0) return true;
   if(g_lastEntryTime == 0) return true;
   int sh = iBarShift(_Symbol, PERIOD_CURRENT, g_lastEntryTime, false);
   if(sh < 0) return true;
   return (sh >= InpCooldownBars);
}

void ClosePosition()
{
   if(g_posTicket > 0 && PositionSelectByTicket(g_posTicket))
      g_trade.PositionClose(g_posTicket);
   g_posTicket = 0;
   g_posType = -1;
}

void PanelCreate()
{
   if(!InpShowPanel) return;
   ObjectCreate(0, g_panel + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_YSIZE, 78);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BGCOLOR, C'10,14,22');
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_panel + "BG", OBJPROP_COLOR, C'60,140,100');

   ObjectCreate(0, g_panel + "T", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_YDISTANCE, InpPanelY + 6);
   ObjectSetString(0, g_panel + "T", OBJPROP_TEXT, "DARKK SCALP");
   ObjectSetString(0, g_panel + "T", OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, g_panel + "T", OBJPROP_FONTSIZE, 15);
   ObjectSetInteger(0, g_panel + "T", OBJPROP_COLOR, C'120,220,160');

   ObjectCreate(0, g_panel + "S", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_YDISTANCE, InpPanelY + 34);
   ObjectSetString(0, g_panel + "S", OBJPROP_TEXT, "XAU · moderate risk · TP>SL");
   ObjectSetString(0, g_panel + "S", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "S", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "S", OBJPROP_COLOR, clrSilver);

   ObjectCreate(0, g_panel + "L", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_YDISTANCE, InpPanelY + 54);
   ObjectSetString(0, g_panel + "L", OBJPROP_TEXT, "");
   ObjectSetString(0, g_panel + "L", OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, g_panel + "L", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, g_panel + "L", OBJPROP_COLOR, clrWhite);
}

void PanelUpdate()
{
   if(!InpShowPanel) return;
   string s = _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)Period());
   s += " | R " + DoubleToString(InpRiskPercent, 2) + "%";
   s += " | " + (g_posType == (int)POSITION_TYPE_BUY ? "LONG" : (g_posType == (int)POSITION_TYPE_SELL ? "SHORT" : "FLAT"));
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
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   hATR  = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);
   hADX  = iADX(_Symbol, PERIOD_CURRENT, InpADXPeriod);

   if(hEMAf == INVALID_HANDLE || hEMAs == INVALID_HANDLE || hEMAt == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("DarkkScalp: indicator init failed");
      return(INIT_FAILED);
   }

   ObjectsDeleteAll(0, g_panel);
   PanelCreate();
   ScanPosition();
   Print("DarkkScalp v1.00 | ", _Symbol, " | risk%=", InpRiskPercent,
         " SLxATR=", InpSL_ATR_Mult, " TPxATR=", InpTP_ATR_Mult,
         " (TP>SL for favorable RR)");
   return(INIT_SUCCEEDED);
}

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

   datetime bt = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bt == g_lastBarTime) return;
   g_lastBarTime = bt;

   if(InpRequireGold && !IsGoldSymbol())
   {
      if(InpDebugPrint) Print("DarkkScalp: not gold symbol");
      return;
   }
   if(!SpreadOK() || !SessionOK() || !TerminalOk())
      return;
   if(g_posTicket != 0) return;
   if(!CooldownOK()) return;

   if(iBars(_Symbol, PERIOD_CURRENT) < InpEMATrend + 10) return;

   double ef[3], es[3], et[3], rsi[3], atr[1], adx[2];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   ArraySetAsSeries(et, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);

   if(CopyBuffer(hEMAf, 0, 1, 3, ef) < 3 || CopyBuffer(hEMAs, 0, 1, 3, es) < 3 ||
      CopyBuffer(hEMAt, 0, 1, 2, et) < 2 || CopyBuffer(hRSI, 0, 1, 3, rsi) < 3 ||
      CopyBuffer(hATR, 0, 1, 1, atr) < 1 || CopyBuffer(hADX, 0, 1, 2, adx) < 2)
      return;

   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);

   bool adxOK = (!InpUseADXFilter) || (adx[1] >= InpADXMin);

   // Pullback long: trend up, prior RSI showed dip, RSI now rising inside band
   bool trendLong  = (ef[1] > es[1] && c1 > et[1]);
   bool pullbackL  = (rsi[2] < InpRSIPullbackLvl);
   bool rsiLongOK  = (rsi[1] > InpRSILongMin && rsi[1] < InpRSILongMax && rsi[1] > rsi[2]);
   bool buySig     = trendLong && pullbackL && rsiLongOK && adxOK;

   bool trendShort = (ef[1] < es[1] && c1 < et[1]);
   bool pullbackS  = (rsi[2] > (100.0 - InpRSIPullbackLvl));
   bool rsiShortOK = (rsi[1] > InpRSIShortMin && rsi[1] < InpRSIShortMax && rsi[1] < rsi[2]);
   bool sellSig    = trendShort && pullbackS && rsiShortOK && adxOK;

   double a = atr[0];
   if(a <= 0) return;

   if(buySig)
      OpenOrder(true, a);
   else if(sellSig)
      OpenOrder(false, a);
}

void OpenOrder(const bool buy, const double atrVal)
{
   double px = buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp;
   if(buy)
   {
      sl = NormalizeDouble(px - atrVal * InpSL_ATR_Mult, _Digits);
      tp = NormalizeDouble(px + atrVal * InpTP_ATR_Mult, _Digits);
   }
   else
   {
      sl = NormalizeDouble(px + atrVal * InpSL_ATR_Mult, _Digits);
      tp = NormalizeDouble(px - atrVal * InpTP_ATR_Mult, _Digits);
   }

   double lots = LotsFromRisk(px, sl);
   string cmt = "DarkkScalp";

   bool ok = buy ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cmt) : g_trade.Sell(lots, _Symbol, 0, sl, tp, cmt);
   if(!ok)
      Print("DarkkScalp: order failed ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
   else
   {
      g_lastEntryTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      PrintFormat("DarkkScalp: %s lots=%.2f SL=%.5f TP=%.5f (TP/SL dist ratio ~%.2f)",
                  buy ? "BUY" : "SELL", lots, sl, tp, InpTP_ATR_Mult / InpSL_ATR_Mult);
      ScanPosition();
   }
}

void ManageTrades()
{
   if(g_posTicket == 0 || !PositionSelectByTicket(g_posTicket)) return;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) return;

   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   int    typ  = (int)PositionGetInteger(POSITION_TYPE);

   double atr[1];
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   double a = atr[0];

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0) pt = _Point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double slDist = MathAbs(open - sl);
   if(slDist <= 0) return;

   double profitDist = 0;
   if(typ == POSITION_TYPE_BUY)
      profitDist = bid - open;
   else
      profitDist = open - ask;

   double r = profitDist / slDist;

   if(InpUseBE && r >= InpBE_AtRR)
   {
      double nsl;
      if(typ == POSITION_TYPE_BUY)
         nsl = NormalizeDouble(open - pt * 5, _Digits);
      else
         nsl = NormalizeDouble(open + pt * 5, _Digits);
      bool better = (typ == POSITION_TYPE_BUY) ? (nsl > sl) : (nsl < sl);
      if(better)
         g_trade.PositionModify(g_posTicket, nsl, tp);
   }

   if(InpUseTrail && r >= InpTrailAfterRR)
   {
      double dist = a * InpTrailATRMult;
      if(typ == POSITION_TYPE_BUY)
      {
         double nsl = NormalizeDouble(bid - dist, _Digits);
         if(nsl > sl && nsl < bid)
            g_trade.PositionModify(g_posTicket, nsl, tp);
      }
      else
      {
         double nsl = NormalizeDouble(ask + dist, _Digits);
         if((sl == 0 || nsl < sl) && nsl > ask)
            g_trade.PositionModify(g_posTicket, nsl, tp);
      }
   }
}

//+------------------------------------------------------------------+
