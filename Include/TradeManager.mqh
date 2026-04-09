//+------------------------------------------------------------------+
//|                                             TradeManager.mqh     |
//|                      Swift Algo Bot - Trade Execution & Risk     |
//|           Position management, lot sizing, SL/TP, trailing       |
//+------------------------------------------------------------------+
#property copyright "Swift Algo Bot"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/OrderInfo.mqh>

//+------------------------------------------------------------------+
class CTradeManager
{
private:
   CTrade         m_trade;
   CPositionInfo  m_position;
   CSymbolInfo    m_symbolInfo;
   CAccountInfo   m_accountInfo;

   string         m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   ulong          m_magic;
   int            m_slippage;

   // Risk parameters
   double         m_riskPercent;
   double         m_fixedLots;
   bool           m_useFixedLots;
   double         m_maxLots;
   double         m_minLots;

   // SL/TP
   double         m_slMultiplier;
   double         m_tpMultiplier;
   bool           m_useATRStops;
   int            m_fixedSLPoints;
   int            m_fixedTPPoints;

   // Trailing stop
   bool           m_useTrailing;
   double         m_trailATRMultiplier;
   int            m_trailFixedPoints;
   bool           m_useATRTrailing;
   double         m_trailStartATR;

   // Break-even
   bool           m_useBreakEven;
   double         m_breakEvenATR;
   int            m_breakEvenOffset;

   // Filters
   double         m_maxSpread;
   int            m_maxPositions;
   int            m_tradingStartHour;
   int            m_tradingEndHour;
   bool           m_tradeSunday;
   bool           m_tradeFriday;

   // State
   int            m_totalBuys;
   int            m_totalSells;
   double         m_totalProfit;
   int            m_totalTrades;
   int            m_winTrades;

   double         CalculateLotSize(double slPoints);
   bool           CheckSpread();
   bool           CheckTradingHours();
   bool           CheckMaxPositions();
   int            CountPositions(ENUM_POSITION_TYPE type);

public:
                  CTradeManager();
                 ~CTradeManager() {}

   bool           Init(string symbol, ENUM_TIMEFRAMES tf, ulong magic, int slippage,
                       double riskPct, double fixedLots, bool useFixed,
                       double maxLots, double minLots,
                       double slMult, double tpMult, bool useATRStops,
                       int fixedSL, int fixedTP,
                       bool useTrail, double trailATR, int trailFixed, bool useATRTrail, double trailStart,
                       bool useBE, double beATR, int beOffset,
                       double maxSpread, int maxPos,
                       int startHour, int endHour, bool tradeSun, bool tradeFri);

   bool           OpenBuy(double atr);
   bool           OpenSell(double atr);
   void           CloseAllBuys();
   void           CloseAllSells();
   void           CloseAll();
   void           ManageTrailingStop(double atr);
   void           ManageBreakEven(double atr);
   bool           CanTrade();

   // Info accessors
   int            GetBuyCount()     { return CountPositions(POSITION_TYPE_BUY); }
   int            GetSellCount()    { return CountPositions(POSITION_TYPE_SELL); }
   double         GetFloatingPL();
   int            GetTotalTrades()  { return m_totalTrades; }
   int            GetWinTrades()    { return m_winTrades; }
   double         GetWinRate()      { return (m_totalTrades > 0) ? (double)m_winTrades / m_totalTrades * 100.0 : 0; }
   double         GetTotalProfit()  { return m_totalProfit; }
   double         GetCurrentSpread();
   bool           HasOpenPositions();
};

//+------------------------------------------------------------------+
CTradeManager::CTradeManager()
{
   m_totalBuys = 0;
   m_totalSells = 0;
   m_totalProfit = 0;
   m_totalTrades = 0;
   m_winTrades = 0;
}

//+------------------------------------------------------------------+
bool CTradeManager::Init(string symbol, ENUM_TIMEFRAMES tf, ulong magic, int slippage,
                         double riskPct, double fixedLots, bool useFixed,
                         double maxLots, double minLots,
                         double slMult, double tpMult, bool useATRStops,
                         int fixedSL, int fixedTP,
                         bool useTrail, double trailATR, int trailFixed, bool useATRTrail, double trailStart,
                         bool useBE, double beATR, int beOffset,
                         double maxSpread, int maxPos,
                         int startHour, int endHour, bool tradeSun, bool tradeFri)
{
   m_symbol = symbol;
   m_timeframe = tf;
   m_magic = magic;
   m_slippage = slippage;

   m_riskPercent = riskPct;
   m_fixedLots = fixedLots;
   m_useFixedLots = useFixed;
   m_maxLots = maxLots;
   m_minLots = minLots;

   m_slMultiplier = slMult;
   m_tpMultiplier = tpMult;
   m_useATRStops = useATRStops;
   m_fixedSLPoints = fixedSL;
   m_fixedTPPoints = fixedTP;

   m_useTrailing = useTrail;
   m_trailATRMultiplier = trailATR;
   m_trailFixedPoints = trailFixed;
   m_useATRTrailing = useATRTrail;
   m_trailStartATR = trailStart;

   m_useBreakEven = useBE;
   m_breakEvenATR = beATR;
   m_breakEvenOffset = beOffset;

   m_maxSpread = maxSpread;
   m_maxPositions = maxPos;
   m_tradingStartHour = startHour;
   m_tradingEndHour = endHour;
   m_tradeSunday = tradeSun;
   m_tradeFriday = tradeFri;

   if(!m_symbolInfo.Name(m_symbol))
   {
      Print("TradeManager: Failed to set symbol info for ", m_symbol);
      return false;
   }

   m_trade.SetExpertMagicNumber(m_magic);
   m_trade.SetDeviationInPoints(m_slippage);
   m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   m_trade.SetAsyncMode(false);

   return true;
}

//+------------------------------------------------------------------+
double CTradeManager::CalculateLotSize(double slPoints)
{
   if(m_useFixedLots)
      return MathMax(m_minLots, MathMin(m_fixedLots, m_maxLots));

   if(slPoints <= 0) slPoints = 100;

   m_symbolInfo.Refresh();

   double tickValue = m_symbolInfo.TickValue();
   double tickSize  = m_symbolInfo.TickSize();
   double balance   = m_accountInfo.Balance();
   double riskMoney = balance * m_riskPercent / 100.0;

   if(tickValue <= 0 || tickSize <= 0) return m_minLots;

   double lotStep   = m_symbolInfo.LotsStep();
   double lots      = riskMoney / (slPoints / tickSize * tickValue);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(m_minLots, MathMin(lots, m_maxLots));

   double maxByMargin = m_symbolInfo.LotsMax();
   lots = MathMin(lots, maxByMargin);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
bool CTradeManager::CheckSpread()
{
   m_symbolInfo.Refresh();
   double spread = m_symbolInfo.Spread() * m_symbolInfo.Point();
   double spreadPips = m_symbolInfo.Spread();
   return (spreadPips <= m_maxSpread);
}

//+------------------------------------------------------------------+
bool CTradeManager::CheckTradingHours()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   if(!m_tradeSunday && dt.day_of_week == 0) return false;
   if(!m_tradeFriday && dt.day_of_week == 5) return false;
   if(dt.day_of_week == 6) return false;

   if(m_tradingStartHour <= m_tradingEndHour)
      return (dt.hour >= m_tradingStartHour && dt.hour < m_tradingEndHour);
   else
      return (dt.hour >= m_tradingStartHour || dt.hour < m_tradingEndHour);
}

//+------------------------------------------------------------------+
bool CTradeManager::CheckMaxPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
            count++;
      }
   }
   return (count < m_maxPositions);
}

//+------------------------------------------------------------------+
int CTradeManager::CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic && m_position.PositionType() == type)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
bool CTradeManager::CanTrade()
{
   return CheckSpread() && CheckTradingHours() && CheckMaxPositions();
}

//+------------------------------------------------------------------+
bool CTradeManager::OpenBuy(double atr)
{
   if(!CanTrade()) return false;

   m_symbolInfo.Refresh();
   double ask = m_symbolInfo.Ask();
   double point = m_symbolInfo.Point();
   int digits = (int)m_symbolInfo.Digits();

   double slDist, tpDist;
   if(m_useATRStops)
   {
      slDist = atr * m_slMultiplier;
      tpDist = atr * m_tpMultiplier;
   }
   else
   {
      slDist = m_fixedSLPoints * point;
      tpDist = m_fixedTPPoints * point;
   }

   double sl = NormalizeDouble(ask - slDist, digits);
   double tp = NormalizeDouble(ask + tpDist, digits);

   double lots = CalculateLotSize(slDist);

   if(m_trade.Buy(lots, m_symbol, ask, sl, tp, "SwiftAlgo BUY"))
   {
      m_totalTrades++;
      Print(StringFormat("SwiftAlgo: BUY %.2f lots @ %s | SL: %s | TP: %s",
            lots, DoubleToString(ask, digits), DoubleToString(sl, digits), DoubleToString(tp, digits)));
      return true;
   }
   else
   {
      Print("SwiftAlgo: Buy failed - ", m_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
bool CTradeManager::OpenSell(double atr)
{
   if(!CanTrade()) return false;

   m_symbolInfo.Refresh();
   double bid = m_symbolInfo.Bid();
   double point = m_symbolInfo.Point();
   int digits = (int)m_symbolInfo.Digits();

   double slDist, tpDist;
   if(m_useATRStops)
   {
      slDist = atr * m_slMultiplier;
      tpDist = atr * m_tpMultiplier;
   }
   else
   {
      slDist = m_fixedSLPoints * point;
      tpDist = m_fixedTPPoints * point;
   }

   double sl = NormalizeDouble(bid + slDist, digits);
   double tp = NormalizeDouble(bid - tpDist, digits);

   double lots = CalculateLotSize(slDist);

   if(m_trade.Sell(lots, m_symbol, bid, sl, tp, "SwiftAlgo SELL"))
   {
      m_totalTrades++;
      Print(StringFormat("SwiftAlgo: SELL %.2f lots @ %s | SL: %s | TP: %s",
            lots, DoubleToString(bid, digits), DoubleToString(sl, digits), DoubleToString(tp, digits)));
      return true;
   }
   else
   {
      Print("SwiftAlgo: Sell failed - ", m_trade.ResultRetcodeDescription());
      return false;
   }
}

//+------------------------------------------------------------------+
void CTradeManager::CloseAllBuys()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic &&
            m_position.PositionType() == POSITION_TYPE_BUY)
         {
            double profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            if(m_trade.PositionClose(m_position.Ticket()))
            {
               m_totalProfit += profit;
               if(profit > 0) m_winTrades++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void CTradeManager::CloseAllSells()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic &&
            m_position.PositionType() == POSITION_TYPE_SELL)
         {
            double profit = m_position.Profit() + m_position.Swap() + m_position.Commission();
            if(m_trade.PositionClose(m_position.Ticket()))
            {
               m_totalProfit += profit;
               if(profit > 0) m_winTrades++;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
void CTradeManager::CloseAll()
{
   CloseAllBuys();
   CloseAllSells();
}

//+------------------------------------------------------------------+
void CTradeManager::ManageTrailingStop(double atr)
{
   if(!m_useTrailing) return;

   m_symbolInfo.Refresh();
   double point = m_symbolInfo.Point();
   int digits = (int)m_symbolInfo.Digits();

   double trailDist = m_useATRTrailing ? (atr * m_trailATRMultiplier) : (m_trailFixedPoints * point);
   double startDist = atr * m_trailStartATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != m_symbol || m_position.Magic() != m_magic) continue;

      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = m_symbolInfo.Bid();
         if(bid - openPrice < startDist) continue;

         double newSL = NormalizeDouble(bid - trailDist, digits);
         if(newSL > currentSL && newSL < bid)
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = m_symbolInfo.Ask();
         if(openPrice - ask < startDist) continue;

         double newSL = NormalizeDouble(ask + trailDist, digits);
         if((currentSL == 0 || newSL < currentSL) && newSL > ask)
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
void CTradeManager::ManageBreakEven(double atr)
{
   if(!m_useBreakEven) return;

   m_symbolInfo.Refresh();
   double point = m_symbolInfo.Point();
   int digits = (int)m_symbolInfo.Digits();
   double beDist = atr * m_breakEvenATR;
   double beOffset = m_breakEvenOffset * point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != m_symbol || m_position.Magic() != m_magic) continue;

      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = m_symbolInfo.Bid();
         double beSL = NormalizeDouble(openPrice + beOffset, digits);
         if(bid - openPrice >= beDist && currentSL < beSL)
            m_trade.PositionModify(m_position.Ticket(), beSL, currentTP);
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = m_symbolInfo.Ask();
         double beSL = NormalizeDouble(openPrice - beOffset, digits);
         if(openPrice - ask >= beDist && (currentSL == 0 || currentSL > beSL))
            m_trade.PositionModify(m_position.Ticket(), beSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
double CTradeManager::GetFloatingPL()
{
   double pl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
            pl += m_position.Profit() + m_position.Swap() + m_position.Commission();
      }
   }
   return pl;
}

//+------------------------------------------------------------------+
double CTradeManager::GetCurrentSpread()
{
   m_symbolInfo.Refresh();
   return m_symbolInfo.Spread();
}

//+------------------------------------------------------------------+
bool CTradeManager::HasOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+
