//+------------------------------------------------------------------+
//|                                                Dashboard.mqh     |
//|                           Swift Algo Bot - On-Chart Dashboard    |
//|                Real-time panel with trend, signals, indicators   |
//+------------------------------------------------------------------+
#property copyright "Swift Algo Bot"
#property strict

#include "SignalEngine.mqh"
#include "TradeManager.mqh"

#define DASH_PREFIX     "SwiftDash_"
#define DASH_FONT       "Consolas"
#define DASH_FONT_TITLE "Segoe UI Semibold"

//+------------------------------------------------------------------+
class CDashboard
{
private:
   int            m_x;
   int            m_y;
   int            m_width;
   int            m_lineHeight;
   int            m_fontSize;
   int            m_titleSize;
   color          m_bgColor;
   color          m_borderColor;
   color          m_textColor;
   color          m_titleColor;
   color          m_bullColor;
   color          m_bearColor;
   color          m_neutralColor;
   bool           m_visible;
   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   void           CreateLabel(string name, int xOff, int yOff, string text,
                              color clr, int fontSize, string font, ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER);
   void           CreateRectangle(string name, int xOff, int yOff, int w, int h, color clr, color border);
   void           UpdateLabel(string name, string text, color clr);
   string         TrendText(ENUM_TREND trend);
   color          TrendColor(ENUM_TREND trend);
   string         SignalText(ENUM_SIGNAL signal);
   color          SignalColor(ENUM_SIGNAL signal);
   string         SubSignalIcon(int val);
   color          SubSignalColor(int val);

public:
                  CDashboard();
                 ~CDashboard();

   void           Init(int x, int y, int width, string symbol, ENUM_TIMEFRAMES tf,
                       color bg, color border, color text, color title,
                       color bull, color bear, color neutral);
   void           Create();
   void           Update(CSignalEngine &engine, CTradeManager &tradeMgr);
   void           Remove();
   void           Toggle();
   bool           IsVisible() { return m_visible; }
};

//+------------------------------------------------------------------+
CDashboard::CDashboard()
{
   m_x = 20;
   m_y = 30;
   m_width = 280;
   m_lineHeight = 22;
   m_fontSize = 9;
   m_titleSize = 11;
   m_visible = true;
}

//+------------------------------------------------------------------+
CDashboard::~CDashboard()
{
   Remove();
}

//+------------------------------------------------------------------+
void CDashboard::Init(int x, int y, int width, string symbol, ENUM_TIMEFRAMES tf,
                      color bg, color border, color text, color title,
                      color bull, color bear, color neutral)
{
   m_x = x;
   m_y = y;
   m_width = width;
   m_symbol = symbol;
   m_timeframe = tf;
   m_bgColor = bg;
   m_borderColor = border;
   m_textColor = text;
   m_titleColor = title;
   m_bullColor = bull;
   m_bearColor = bear;
   m_neutralColor = neutral;
}

//+------------------------------------------------------------------+
void CDashboard::CreateLabel(string name, int xOff, int yOff, string text,
                             color clr, int fontSize, string font, ENUM_ANCHOR_POINT anchor)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, m_x + xOff);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, m_y + yOff);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, anchor);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, font);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void CDashboard::CreateRectangle(string name, int xOff, int yOff, int w, int h, color clr, color border)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) >= 0) ObjectDelete(0, objName);

   ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, m_x + xOff);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, m_y + yOff);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
void CDashboard::UpdateLabel(string name, string text, color clr)
{
   string objName = DASH_PREFIX + name;
   if(ObjectFind(0, objName) >= 0)
   {
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   }
}

//+------------------------------------------------------------------+
string CDashboard::TrendText(ENUM_TREND trend)
{
   switch(trend)
   {
      case TREND_UP:   return "▲ BULLISH";
      case TREND_DOWN: return "▼ BEARISH";
      default:         return "◆ RANGING";
   }
}

//+------------------------------------------------------------------+
color CDashboard::TrendColor(ENUM_TREND trend)
{
   switch(trend)
   {
      case TREND_UP:   return m_bullColor;
      case TREND_DOWN: return m_bearColor;
      default:         return m_neutralColor;
   }
}

//+------------------------------------------------------------------+
string CDashboard::SignalText(ENUM_SIGNAL signal)
{
   switch(signal)
   {
      case SIGNAL_BUY:  return "● BUY";
      case SIGNAL_SELL: return "● SELL";
      default:          return "○ WAIT";
   }
}

//+------------------------------------------------------------------+
color CDashboard::SignalColor(ENUM_SIGNAL signal)
{
   switch(signal)
   {
      case SIGNAL_BUY:  return m_bullColor;
      case SIGNAL_SELL: return m_bearColor;
      default:          return m_neutralColor;
   }
}

//+------------------------------------------------------------------+
string CDashboard::SubSignalIcon(int val)
{
   if(val > 0) return "▲";
   if(val < 0) return "▼";
   return "—";
}

//+------------------------------------------------------------------+
color CDashboard::SubSignalColor(int val)
{
   if(val > 0) return m_bullColor;
   if(val < 0) return m_bearColor;
   return m_neutralColor;
}

//+------------------------------------------------------------------+
void CDashboard::Create()
{
   if(!m_visible) return;

   int totalHeight = m_lineHeight * 24 + 10;

   CreateRectangle("bg", 0, 0, m_width, totalHeight, m_bgColor, m_borderColor);

   int row = 0;
   int pad = 10;

   // Title
   CreateLabel("title", pad, pad + row * m_lineHeight, "⚡ SWIFT ALGO BOT", m_titleColor, m_titleSize, DASH_FONT_TITLE);
   row++;
   CreateLabel("symbol", pad, pad + row * m_lineHeight,
               m_symbol + " | " + EnumToString(m_timeframe), m_textColor, m_fontSize, DASH_FONT);
   row++;

   // Separator
   CreateLabel("sep1", pad, pad + row * m_lineHeight, "─────────────────────────────", clrDimGray, 8, DASH_FONT);
   row++;

   // Trend & Signal
   CreateLabel("trendLbl",  pad, pad + row * m_lineHeight, "Trend:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("trendVal",  pad + 120, pad + row * m_lineHeight, "...", m_neutralColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("signalLbl", pad, pad + row * m_lineHeight, "Signal:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("signalVal", pad + 120, pad + row * m_lineHeight, "...", m_neutralColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("confLbl",   pad, pad + row * m_lineHeight, "Confluence:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("confVal",   pad + 120, pad + row * m_lineHeight, "0/7", m_neutralColor, m_fontSize, DASH_FONT);
   row++;

   // Separator
   CreateLabel("sep2", pad, pad + row * m_lineHeight, "─────────────────────────────", clrDimGray, 8, DASH_FONT);
   row++;

   // Sub-signals
   string labels[] = {"EMA Cross", "RSI", "MACD", "Bollinger", "ADX", "Stochastic", "Price Action"};
   string ids[]    = {"ema", "rsi", "macd", "bb", "adx", "stoch", "pa"};

   for(int i = 0; i < 7; i++)
   {
      CreateLabel(ids[i] + "Lbl", pad, pad + row * m_lineHeight, labels[i] + ":", m_textColor, m_fontSize, DASH_FONT);
      CreateLabel(ids[i] + "Val", pad + 120, pad + row * m_lineHeight, "—", m_neutralColor, m_fontSize, DASH_FONT);
      row++;
   }

   // Separator
   CreateLabel("sep3", pad, pad + row * m_lineHeight, "─────────────────────────────", clrDimGray, 8, DASH_FONT);
   row++;

   // Key values
   CreateLabel("rsiLbl2",  pad, pad + row * m_lineHeight, "RSI:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("rsiVal2",  pad + 120, pad + row * m_lineHeight, "...", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("atrLbl2",  pad, pad + row * m_lineHeight, "ATR:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("atrVal2",  pad + 120, pad + row * m_lineHeight, "...", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("adxLbl2",  pad, pad + row * m_lineHeight, "ADX:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("adxVal2",  pad + 120, pad + row * m_lineHeight, "...", m_textColor, m_fontSize, DASH_FONT);
   row++;

   // Separator
   CreateLabel("sep4", pad, pad + row * m_lineHeight, "─────────────────────────────", clrDimGray, 8, DASH_FONT);
   row++;

   // Trade stats
   CreateLabel("posLbl",   pad, pad + row * m_lineHeight, "Positions:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("posVal",   pad + 120, pad + row * m_lineHeight, "0B / 0S", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("plLbl",    pad, pad + row * m_lineHeight, "Floating P/L:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("plVal",    pad + 120, pad + row * m_lineHeight, "$0.00", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("totalLbl", pad, pad + row * m_lineHeight, "Total P/L:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("totalVal", pad + 120, pad + row * m_lineHeight, "$0.00", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("wrLbl",    pad, pad + row * m_lineHeight, "Win Rate:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("wrVal",    pad + 120, pad + row * m_lineHeight, "0%", m_textColor, m_fontSize, DASH_FONT);
   row++;
   CreateLabel("sprdLbl",  pad, pad + row * m_lineHeight, "Spread:", m_textColor, m_fontSize, DASH_FONT);
   CreateLabel("sprdVal",  pad + 120, pad + row * m_lineHeight, "...", m_textColor, m_fontSize, DASH_FONT);
   row++;

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void CDashboard::Update(CSignalEngine &engine, CTradeManager &tradeMgr)
{
   if(!m_visible || !engine.IsInitialized()) return;

   ENUM_TREND trend = engine.GetTrend(1);
   ENUM_SIGNAL signal = engine.GetSignal(1);
   int conf = engine.GetConfluenceScore(1);

   UpdateLabel("trendVal", TrendText(trend), TrendColor(trend));
   UpdateLabel("signalVal", SignalText(signal), SignalColor(signal));

   int absConf = MathAbs(conf);
   color confClr = (absConf >= 4) ? m_bullColor : (absConf >= 2) ? m_neutralColor : m_textColor;
   if(conf < 0) confClr = (absConf >= 4) ? m_bearColor : confClr;
   UpdateLabel("confVal", IntegerToString(absConf) + "/7", confClr);

   // Sub-signals
   int ema = engine.CheckEMACross(1);
   int rsi = engine.CheckRSI(1);
   int macd = engine.CheckMACD(1);
   int bb = engine.CheckBB(1);
   int adx = engine.CheckADXTrend(1);
   int stoch = engine.CheckStoch(1);
   int pa = engine.CheckPriceAction(1);

   UpdateLabel("emaVal",   SubSignalIcon(ema),   SubSignalColor(ema));
   UpdateLabel("rsiVal",   SubSignalIcon(rsi),   SubSignalColor(rsi));
   UpdateLabel("macdVal",  SubSignalIcon(macd),  SubSignalColor(macd));
   UpdateLabel("bbVal",    SubSignalIcon(bb),     SubSignalColor(bb));
   UpdateLabel("adxVal",   SubSignalIcon(adx),   SubSignalColor(adx));
   UpdateLabel("stochVal", SubSignalIcon(stoch), SubSignalColor(stoch));
   UpdateLabel("paVal",    SubSignalIcon(pa),    SubSignalColor(pa));

   // Key values
   int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
   double rsiVal = engine.GetRSI(1);
   double atrVal = engine.GetATR(1);
   double adxVal = engine.GetADX(1);

   color rsiClr = (rsiVal > 70) ? m_bearColor : (rsiVal < 30) ? m_bullColor : m_textColor;
   UpdateLabel("rsiVal2", DoubleToString(rsiVal, 1), rsiClr);
   UpdateLabel("atrVal2", DoubleToString(atrVal, digits), m_textColor);
   UpdateLabel("adxVal2", DoubleToString(adxVal, 1) +
               ((adxVal >= 25) ? " (Strong)" : " (Weak)"),
               (adxVal >= 25) ? m_bullColor : m_neutralColor);

   // Trade stats
   int buys = tradeMgr.GetBuyCount();
   int sells = tradeMgr.GetSellCount();
   UpdateLabel("posVal", IntegerToString(buys) + "B / " + IntegerToString(sells) + "S",
               (buys + sells > 0) ? m_bullColor : m_textColor);

   double floatPL = tradeMgr.GetFloatingPL();
   color plClr = (floatPL > 0) ? m_bullColor : (floatPL < 0) ? m_bearColor : m_textColor;
   UpdateLabel("plVal", "$" + DoubleToString(floatPL, 2), plClr);

   double totalPL = tradeMgr.GetTotalProfit() + floatPL;
   color totClr = (totalPL > 0) ? m_bullColor : (totalPL < 0) ? m_bearColor : m_textColor;
   UpdateLabel("totalVal", "$" + DoubleToString(totalPL, 2), totClr);

   double wr = tradeMgr.GetWinRate();
   color wrClr = (wr >= 55) ? m_bullColor : (wr >= 40) ? m_neutralColor : m_bearColor;
   int totalT = tradeMgr.GetTotalTrades();
   UpdateLabel("wrVal", DoubleToString(wr, 1) + "% (" + IntegerToString(totalT) + " trades)", wrClr);

   double spread = tradeMgr.GetCurrentSpread();
   UpdateLabel("sprdVal", DoubleToString(spread, 1) + " pts", m_textColor);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void CDashboard::Remove()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, DASH_PREFIX) == 0)
         ObjectDelete(0, name);
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void CDashboard::Toggle()
{
   m_visible = !m_visible;
   if(m_visible)
      Create();
   else
      Remove();
}
//+------------------------------------------------------------------+
