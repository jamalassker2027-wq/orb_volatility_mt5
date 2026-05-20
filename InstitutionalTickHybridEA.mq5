
//+------------------------------------------------------------------+
//| InstitutionalTickHybridEA.mq5                                   |
//| FIXED VERSION - ATR + Trading Activation Fix                    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================
// INPUTS
//====================================================
input ulong  MagicNumber            = 880001;

input double ForexLot               = 0.10;
input double GoldLot                = 0.01;

input int    EMAFastPeriod          = 20;
input int    EMATrendPeriod         = 200;
input int    ATRPeriod              = 14;
input double ATRMultiplierSL        = 2.0;
input double ATRTrailingMultiplier  = 1.5;

input int    TickBufferSize         = 30;
input double ZScoreThreshold        = 1.3;
input int    CooldownSeconds        = 10;
input int    MaxPositionsPerSymbol  = 3;

input double MaxSpreadPoints        = 40;
input double MinATRPointsForex      = 15;
input double MinATRPointsGold       = 150;

input double ProfitTargetPerLot     = 20.0;
input bool   UseBreakeven           = true;
input double BreakevenOffsetPoints  = 10;
input bool   EnableDebug            = true;

//====================================================
// GLOBALS
//====================================================



double TickBuffer[];
datetime LastTradeTime = 0;

int emaFastHandle;
int emaTrendHandle;
int atrHandle;

//====================================================
// INIT
//====================================================
int OnInit()
{
   ArrayResize(TickBuffer, TickBufferSize);

   emaFastHandle  = iMA(_Symbol,_Period,EMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   emaTrendHandle = iMA(_Symbol,_Period,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   atrHandle      = iATR(_Symbol,_Period,ATRPeriod);

   if(emaFastHandle==INVALID_HANDLE || emaTrendHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE)
   {
      Print("Indicator init failed");
      return INIT_FAILED;
   }

   Print("EA FIXED VERSION INITIALIZED");
   return INIT_SUCCEEDED;
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaTrendHandle);
   IndicatorRelease(atrHandle);
}

//====================================================
// ON TICK
//====================================================
void OnTick()
{
   UpdateTickBuffer();

   ManagePositions();

   if(!CanTrade())
      return;

   if(CountPositionsBySymbol() >= MaxPositionsPerSymbol)
      return;

   double z = CalculateZScore();
   double emaFast = GetEMA(emaFastHandle);
   double emaTrend = GetEMA(emaTrendHandle);
   double atr = GetATR();

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   bool bullish = bid > emaTrend;
   bool bearish = bid < emaTrend;

   // 🔥 FIX 1: REMOVE STRICT MOMENTUM REQUIREMENT
   bool reversalBuy  = (z < -1.0);
   bool reversalSell = (z >  1.0);

   // 🔥 FIX 2: LOOSER ENTRY LOGIC
   if(bullish && reversalBuy)
      OpenBuy(atr);

   if(bearish && reversalSell)
      OpenSell(atr);
}

//====================================================
// UPDATE TICKS
//====================================================
void UpdateTickBuffer()
{
   for(int i=TickBufferSize-1;i>0;i--)
      TickBuffer[i]=TickBuffer[i-1];

   TickBuffer[0]=SymbolInfoDouble(_Symbol,SYMBOL_BID);
}

//====================================================
// Z SCORE
//====================================================
double CalculateZScore()
{
   double sum=0;
   for(int i=0;i<TickBufferSize;i++) sum+=TickBuffer[i];

   double mean=sum/TickBufferSize;

   double var=0;
   for(int i=0;i<TickBufferSize;i++)
      var += MathPow(TickBuffer[i]-mean,2);

   var/=TickBufferSize;

   double std=MathSqrt(var);
   if(std==0) return 0;

   return (TickBuffer[0]-mean)/std;
}

//====================================================
// INDICATORS
//====================================================
double GetEMA(int handle)
{
   double buf[];
   if(CopyBuffer(handle,0,0,1,buf)<=0) return 0;
   return buf[0];
}

double GetATR()
{
   double buf[];
   if(CopyBuffer(atrHandle,0,0,1,buf)<=0) return 0;
   return buf[0];
}

//====================================================
// CAN TRADE (FIXED ATR LOGIC)
//====================================================
bool CanTrade()
{
   double spread = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

   if(spread > MaxSpreadPoints)
   {
      Debug("Spread too high");
      return false;
   }

   double atrPoints = GetATR()/_Point;

   string sym=_Symbol;
   StringToUpper(sym);

   double minATR = MinATRPointsForex;

   if(StringFind(sym,"XAU")>=0 || StringFind(sym,"GOLD")>=0)
      minATR = MinATRPointsGold;

   if(atrPoints < minATR)
   {
      Debug("ATR too low: " + DoubleToString(atrPoints,1));
      return false;
   }

   if(TimeCurrent()-LastTradeTime < CooldownSeconds)
      return false;

   return true;
}

//====================================================
// OPEN BUY
//====================================================
void OpenBuy(double atr)
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl=ask-(atr*ATRMultiplierSL);

   AdjustStopsForBroker(sl,true);

   double lot=GetLotSize();

   trade.SetExpertMagicNumber(MagicNumber);

   if(trade.Buy(lot,_Symbol,ask,sl,0,"BUY"))
      LastTradeTime=TimeCurrent();
}

//====================================================
// OPEN SELL
//====================================================
void OpenSell(double atr)
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=bid+(atr*ATRMultiplierSL);

   AdjustStopsForBroker(sl,false);

   double lot=GetLotSize();

   trade.SetExpertMagicNumber(MagicNumber);

   if(trade.Sell(lot,_Symbol,bid,sl,0,"SELL"))
      LastTradeTime=TimeCurrent();
}

//====================================================
// LOT SIZE
//====================================================
double GetLotSize()
{
   string s=_Symbol;
   StringToUpper(s);

   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0)
      return GoldLot;

   return ForexLot;
}

//====================================================
// POSITION COUNT
//====================================================
int CountPositionsBySymbol()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!PositionSelectByTicket(t)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      c++;
   }
   return c;
}

//====================================================
// POSITION MANAGEMENT
//====================================================
void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(!PositionSelectByTicket(t)) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double vol=PositionGetDouble(POSITION_VOLUME);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double profit=PositionGetDouble(POSITION_PROFIT);

      double atr=GetATR();
      double target=vol*ProfitTargetPerLot;

      if(profit>=target)
      {
         trade.PositionClose(t);
         continue;
      }

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type==POSITION_TYPE_BUY)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double newSL=bid-(atr*ATRTrailingMultiplier);

         if(newSL>sl)
            trade.PositionModify(t,newSL,0);
      }

      if(type==POSITION_TYPE_SELL)
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double newSL=ask+(atr*ATRTrailingMultiplier);

         if(sl==0 || newSL<sl)
            trade.PositionModify(t,newSL,0);
      }
   }
}

//====================================================
// BROKER SAFETY
//====================================================
void AdjustStopsForBroker(double &sl,bool buy)
{
   double stop=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double freeze=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;

   double min=MathMax(stop,freeze);

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(buy && (ask-sl)<min)
      sl=ask-(min+10*_Point);

   if(!buy && (sl-bid)<min)
      sl=bid+(min+10*_Point);
}

//====================================================
// DEBUG
//====================================================
void Debug(string txt)
{
   if(EnableDebug)
      Print("[",_Symbol,"] ",txt);
}
//+------------------------------------------------------------------+
