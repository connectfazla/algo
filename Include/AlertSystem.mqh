//+------------------------------------------------------------------+
//|                                              AlertSystem.mqh     |
//|                              Swift Algo Bot - Alert Manager      |
//|                    Popup, sound, push, and email alerts           |
//+------------------------------------------------------------------+
#property copyright "Swift Algo Bot"
#property strict

//+------------------------------------------------------------------+
class CAlertSystem
{
private:
   bool           m_enablePopup;
   bool           m_enableSound;
   bool           m_enablePush;
   bool           m_enableEmail;
   string         m_soundBuy;
   string         m_soundSell;
   string         m_emailTo;
   string         m_prefix;

   datetime       m_lastAlertTime;
   int            m_lastAlertDir;
   int            m_cooldownSeconds;

   bool           CanAlert(int direction);

public:
                  CAlertSystem();
                 ~CAlertSystem() {}

   void           Init(bool popup, bool sound, bool push, bool email,
                       string soundBuy, string soundSell,
                       string emailTo, string prefix, int cooldownSec);

   void           SendBuyAlert(string symbol, ENUM_TIMEFRAMES tf, double price, int confluence);
   void           SendSellAlert(string symbol, ENUM_TIMEFRAMES tf, double price, int confluence);
   void           SendCustomAlert(string message);
};

//+------------------------------------------------------------------+
CAlertSystem::CAlertSystem()
{
   m_enablePopup = true;
   m_enableSound = true;
   m_enablePush = false;
   m_enableEmail = false;
   m_soundBuy = "alert.wav";
   m_soundSell = "alert2.wav";
   m_emailTo = "";
   m_prefix = "SwiftAlgo";
   m_lastAlertTime = 0;
   m_lastAlertDir = 0;
   m_cooldownSeconds = 60;
}

//+------------------------------------------------------------------+
void CAlertSystem::Init(bool popup, bool sound, bool push, bool email,
                        string soundBuy, string soundSell,
                        string emailTo, string prefix, int cooldownSec)
{
   m_enablePopup = popup;
   m_enableSound = sound;
   m_enablePush = push;
   m_enableEmail = email;
   m_soundBuy = soundBuy;
   m_soundSell = soundSell;
   m_emailTo = emailTo;
   m_prefix = prefix;
   m_cooldownSeconds = cooldownSec;
   m_lastAlertTime = 0;
   m_lastAlertDir = 0;
}

//+------------------------------------------------------------------+
bool CAlertSystem::CanAlert(int direction)
{
   datetime now = TimeCurrent();
   if(direction == m_lastAlertDir && (now - m_lastAlertTime) < m_cooldownSeconds)
      return false;

   m_lastAlertTime = now;
   m_lastAlertDir = direction;
   return true;
}

//+------------------------------------------------------------------+
void CAlertSystem::SendBuyAlert(string symbol, ENUM_TIMEFRAMES tf, double price, int confluence)
{
   if(!CanAlert(1)) return;

   string tfStr = EnumToString(tf);
   string msg = StringFormat("[%s] BUY Signal | %s %s | Price: %s | Confluence: %d/7",
                             m_prefix, symbol, tfStr,
                             DoubleToString(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
                             confluence);

   if(m_enablePopup) Alert(msg);
   if(m_enableSound) PlaySound(m_soundBuy);
   if(m_enablePush)  SendNotification(msg);
   if(m_enableEmail && m_emailTo != "")
      SendMail(m_prefix + " BUY Signal - " + symbol, msg);

   Print(msg);
}

//+------------------------------------------------------------------+
void CAlertSystem::SendSellAlert(string symbol, ENUM_TIMEFRAMES tf, double price, int confluence)
{
   if(!CanAlert(-1)) return;

   string tfStr = EnumToString(tf);
   string msg = StringFormat("[%s] SELL Signal | %s %s | Price: %s | Confluence: %d/7",
                             m_prefix, symbol, tfStr,
                             DoubleToString(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
                             MathAbs(confluence));

   if(m_enablePopup) Alert(msg);
   if(m_enableSound) PlaySound(m_soundSell);
   if(m_enablePush)  SendNotification(msg);
   if(m_enableEmail && m_emailTo != "")
      SendMail(m_prefix + " SELL Signal - " + symbol, msg);

   Print(msg);
}

//+------------------------------------------------------------------+
void CAlertSystem::SendCustomAlert(string message)
{
   string msg = "[" + m_prefix + "] " + message;
   if(m_enablePopup) Alert(msg);
   if(m_enablePush)  SendNotification(msg);
   Print(msg);
}
//+------------------------------------------------------------------+
