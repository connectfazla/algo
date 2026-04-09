//+------------------------------------------------------------------+
//|                                              SwiftAlgoBot.mq5    |
//|                        Swift Algo Bot - MT5 Expert Advisor       |
//|            Multi-confluence automated trading system              |
//+------------------------------------------------------------------+
#property copyright   "Swift Algo Bot"
#property link        ""
#property version     "1.00"
#property description "Swift Algo Bot - Automated trading EA with multi-indicator confluence, "
#property description "ATR-based risk management, trailing stops, and real-time dashboard."
#property strict

#include "../Include/SignalEngine.mqh"
#include "../Include/TradeManager.mqh"
#include "../Include/Dashboard.mqh"
#include "../Include/AlertSystem.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//--- General
input string   Sep0                = "══════ GENERAL ══════";          // ─── General Settings ───
input ulong    InpMagicNumber      = 202604;                           // Magic Number
input int      InpSlippage          = 10;                               // Max Slippage (points)

//--- Signal Engine: EMA
input string   Sep1                = "══════ EMA SETTINGS ══════";     // ─── EMA Settings ───
input int      InpEMAFastPeriod    = 9;                                // Fast EMA Period
input int      InpEMASlowPeriod    = 21;                               // Slow EMA Period
input int      InpEMATrendPeriod   = 50;                               // Trend EMA Period

//--- Signal Engine: RSI
input string   Sep2                = "══════ RSI SETTINGS ══════";     // ─── RSI Settings ───
input int      InpRSIPeriod        = 14;                               // RSI Period
input double   InpRSIOverbought    = 70;                               // RSI Overbought Level
input double   InpRSIOversold      = 30;                               // RSI Oversold Level

//--- Signal Engine: MACD
input string   Sep3                = "══════ MACD SETTINGS ══════";    // ─── MACD Settings ───
input int      InpMACDFast         = 12;                               // MACD Fast Period
input int      InpMACDSlow         = 26;                               // MACD Slow Period
input int      InpMACDSignal       = 9;                                // MACD Signal Period

//--- Signal Engine: Bollinger / ADX / Stochastic
input string   Sep4                = "══════ OTHER INDICATORS ══════"; // ─── Other Indicators ───
input int      InpBBPeriod         = 20;                               // Bollinger Period
input double   InpBBDeviation      = 2.0;                              // Bollinger Deviation
input int      InpADXPeriod        = 14;                               // ADX Period
input double   InpADXMinStrength   = 20;                               // ADX Min Trend Strength
input int      InpStochK           = 14;                               // Stochastic %K Period
input int      InpStochD           = 3;                                // Stochastic %D Period
input int      InpStochSlowing     = 3;                                // Stochastic Slowing
input int      InpATRPeriod        = 14;                               // ATR Period

//--- Signal Confluence
input string   Sep5                = "══════ SIGNAL ══════";           // ─── Signal Settings ───
input int      InpMinConfluence    = 3;                                // Min Confluence Score (1-7)
input bool     InpCloseOnReverse   = true;                             // Close On Reverse Signal

//--- Risk Management
input string   Sep6                = "══════ RISK MANAGEMENT ══════";  // ─── Risk Management ───
input double   InpRiskPercent      = 1.0;                              // Risk Per Trade (%)
input bool     InpUseFixedLots     = false;                            // Use Fixed Lot Size
input double   InpFixedLots        = 0.01;                             // Fixed Lot Size
input double   InpMaxLots          = 5.0;                              // Maximum Lots
input double   InpMinLots          = 0.01;                             // Minimum Lots

//--- Stop Loss / Take Profit
input string   Sep7                = "══════ SL / TP ══════";          // ─── SL / TP Settings ───
input bool     InpUseATRStops      = true;                             // Use ATR-Based SL/TP
input double   InpSLMultiplier     = 1.5;                              // ATR SL Multiplier
input double   InpTPMultiplier     = 2.5;                              // ATR TP Multiplier
input int      InpFixedSL          = 200;                              // Fixed SL (points) if not ATR
input int      InpFixedTP          = 400;                              // Fixed TP (points) if not ATR

//--- Trailing Stop
input string   Sep8                = "══════ TRAILING STOP ══════";    // ─── Trailing Stop ───
input bool     InpUseTrailing      = true;                             // Enable Trailing Stop
input bool     InpUseATRTrailing   = true;                             // ATR-Based Trailing
input double   InpTrailATRMult     = 1.0;                              // ATR Trailing Multiplier
input int      InpTrailFixedPts    = 150;                              // Fixed Trail (points) if not ATR
input double   InpTrailStartATR    = 1.0;                              // Trail Starts After (ATR mult)

//--- Break Even
input string   Sep9                = "══════ BREAK EVEN ══════";       // ─── Break Even ───
input bool     InpUseBreakEven     = true;                             // Enable Break Even
input double   InpBEATRMult        = 1.0;                              // Break Even After (ATR mult)
input int      InpBEOffset         = 5;                                // Break Even Offset (points)

//--- Filters
input string   Sep10               = "══════ FILTERS ══════";          // ─── Trade Filters ───
input double   InpMaxSpread        = 30;                               // Max Spread (points)
input int      InpMaxPositions     = 1;                                // Max Open Positions
input int      InpStartHour        = 0;                                // Trading Start Hour (server)
input int      InpEndHour          = 24;                               // Trading End Hour (server)
input bool     InpTradeSunday      = false;                            // Trade on Sunday
input bool     InpTradeFriday      = true;                             // Trade on Friday

//--- Alerts
input string   Sep11               = "══════ ALERTS ══════";           // ─── Alert Settings ───
input bool     InpAlertPopup       = true;                             // Popup Alerts
input bool     InpAlertSound       = true;                             // Sound Alerts
input bool     InpAlertPush        = false;                            // Push Notifications
input bool     InpAlertEmail       = false;                            // Email Alerts
input string   InpSoundBuy         = "alert.wav";                      // Buy Sound File
input string   InpSoundSell        = "alert2.wav";                     // Sell Sound File
input string   InpEmailTo          = "";                               // Email Recipient
input int      InpAlertCooldown    = 60;                               // Alert Cooldown (seconds)

//--- Dashboard
input string   Sep12               = "══════ DASHBOARD ══════";        // ─── Dashboard Settings ───
input bool     InpShowDashboard    = true;                             // Show Dashboard
input int      InpDashX            = 20;                               // Dashboard X Position
input int      InpDashY            = 30;                               // Dashboard Y Position
input int      InpDashWidth        = 280;                              // Dashboard Width
input color    InpDashBG           = C'20,20,30';                      // Background Color
input color    InpDashBorder       = C'50,50,70';                      // Border Color
input color    InpDashText         = C'180,180,200';                   // Text Color
input color    InpDashTitle        = C'255,255,255';                   // Title Color
input color    InpBullColor        = C'0,200,120';                     // Bullish Color
input color    InpBearColor        = C'255,60,60';                     // Bearish Color
input color    InpNeutralColor     = C'255,200,50';                    // Neutral Color

//+------------------------------------------------------------------+
//| Global Objects                                                    |
//+------------------------------------------------------------------+
CSignalEngine  g_signalEngine;
CTradeManager  g_tradeMgr;
CDashboard     g_dashboard;
CAlertSystem   g_alerts;

datetime       g_lastBarTime = 0;
bool           g_initialized = false;

//+------------------------------------------------------------------+
int OnInit()
{
   if(!g_signalEngine.Init(_Symbol, _Period,
                           InpEMAFastPeriod, InpEMASlowPeriod, InpEMATrendPeriod,
                           InpRSIPeriod, InpRSIOverbought, InpRSIOversold,
                           InpMACDFast, InpMACDSlow, InpMACDSignal,
                           InpATRPeriod, InpBBPeriod, InpBBDeviation,
                           InpADXPeriod, InpADXMinStrength,
                           InpStochK, InpStochD, InpStochSlowing,
                           InpMinConfluence))
   {
      Print("SwiftAlgoBot: Failed to initialize Signal Engine");
      return INIT_FAILED;
   }

   if(!g_tradeMgr.Init(_Symbol, _Period, InpMagicNumber, InpSlippage,
                       InpRiskPercent, InpFixedLots, InpUseFixedLots,
                       InpMaxLots, InpMinLots,
                       InpSLMultiplier, InpTPMultiplier, InpUseATRStops,
                       InpFixedSL, InpFixedTP,
                       InpUseTrailing, InpTrailATRMult, InpTrailFixedPts, InpUseATRTrailing, InpTrailStartATR,
                       InpUseBreakEven, InpBEATRMult, InpBEOffset,
                       InpMaxSpread, InpMaxPositions,
                       InpStartHour, InpEndHour, InpTradeSunday, InpTradeFriday))
   {
      Print("SwiftAlgoBot: Failed to initialize Trade Manager");
      return INIT_FAILED;
   }

   g_alerts.Init(InpAlertPopup, InpAlertSound, InpAlertPush, InpAlertEmail,
                 InpSoundBuy, InpSoundSell, InpEmailTo, "SwiftAlgo", InpAlertCooldown);

   if(InpShowDashboard)
   {
      g_dashboard.Init(InpDashX, InpDashY, InpDashWidth, _Symbol, _Period,
                       InpDashBG, InpDashBorder, InpDashText, InpDashTitle,
                       InpBullColor, InpBearColor, InpNeutralColor);
      g_dashboard.Create();
   }

   g_initialized = true;
   g_lastBarTime = 0;

   Print("═══════════════════════════════════════════");
   Print("  ⚡ Swift Algo Bot v1.00 Initialized");
   Print("  Symbol: ", _Symbol, " | TF: ", EnumToString(_Period));
   Print("  Risk: ", InpRiskPercent, "% | Min Confluence: ", InpMinConfluence, "/7");
   Print("  ATR Stops: ", InpUseATRStops ? "ON" : "OFF",
         " | SL: ", InpSLMultiplier, "x | TP: ", InpTPMultiplier, "x");
   Print("  Trailing: ", InpUseTrailing ? "ON" : "OFF",
         " | Break Even: ", InpUseBreakEven ? "ON" : "OFF");
   Print("═══════════════════════════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_signalEngine.Deinit();
   g_dashboard.Remove();

   Print("⚡ Swift Algo Bot stopped. Reason: ", reason);
   Print("  Total Trades: ", g_tradeMgr.GetTotalTrades(),
         " | Win Rate: ", DoubleToString(g_tradeMgr.GetWinRate(), 1), "%",
         " | Total P/L: $", DoubleToString(g_tradeMgr.GetTotalProfit(), 2));
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized || !g_signalEngine.IsInitialized()) return;

   double atr = g_signalEngine.GetATR(1);

   // Per-tick management (runs every tick)
   g_tradeMgr.ManageTrailingStop(atr);
   g_tradeMgr.ManageBreakEven(atr);

   // New bar detection (signal logic runs once per bar)
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool isNewBar = (currentBarTime != g_lastBarTime);

   if(isNewBar)
   {
      g_lastBarTime = currentBarTime;
      ProcessSignals(atr);
   }

   // Update dashboard (throttled to avoid overload)
   static datetime lastDashUpdate = 0;
   if(InpShowDashboard && TimeCurrent() - lastDashUpdate >= 1)
   {
      g_dashboard.Update(g_signalEngine, g_tradeMgr);
      lastDashUpdate = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
void ProcessSignals(double atr)
{
   ENUM_SIGNAL signal = g_signalEngine.GetSignal(1);
   int confluence = g_signalEngine.GetConfluenceScore(1);
   double price = iClose(_Symbol, _Period, 1);

   if(signal == SIGNAL_BUY)
   {
      if(InpCloseOnReverse && g_tradeMgr.GetSellCount() > 0)
         g_tradeMgr.CloseAllSells();

      if(g_tradeMgr.GetBuyCount() == 0)
      {
         if(g_tradeMgr.OpenBuy(atr))
         {
            g_alerts.SendBuyAlert(_Symbol, _Period, price, confluence);
         }
      }
   }
   else if(signal == SIGNAL_SELL)
   {
      if(InpCloseOnReverse && g_tradeMgr.GetBuyCount() > 0)
         g_tradeMgr.CloseAllBuys();

      if(g_tradeMgr.GetSellCount() == 0)
      {
         if(g_tradeMgr.OpenSell(atr))
         {
            g_alerts.SendSellAlert(_Symbol, _Period, price, MathAbs(confluence));
         }
      }
   }
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      // Press 'D' to toggle dashboard
      if(lparam == 68)
      {
         g_dashboard.Toggle();
         if(g_dashboard.IsVisible())
            g_dashboard.Update(g_signalEngine, g_tradeMgr);
      }
      // Press 'X' to close all positions (emergency)
      if(lparam == 88)
      {
         g_tradeMgr.CloseAll();
         g_alerts.SendCustomAlert("All positions closed manually (emergency)");
      }
   }
}
//+------------------------------------------------------------------+
