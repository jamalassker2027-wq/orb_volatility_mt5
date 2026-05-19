//+------------------------------------------------------------------+
//| Volatility_Breakout_Pro.mq5                                      |
//| Example breakout EA with risk-management features                |
//| No guarantee of profitability                                    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input double ForexLotSize=0.10;
input double OtherLotSize=0.01;
input int ATRPeriod=14;
input int EMAFast=50;
input int EMASlow=200;
input double ATRMultiplierSL=2.5;
input double RiskReward=3.0;
input double ProfitTargetPerLot=100.0;
input int MaxPositionsPerSymbol=1;
input ulong MagicNumber=888888;

CTrade trade;
int atrHandle, fastHandle, slowHandle;

double GetLotSize()
{
   string s=_Symbol;

   if(StringFind(s,"XAU")>=0 || StringFind(s,"XAG")>=0 ||
      StringFind(s,"BTC")>=0 || StringFind(s,"ETH")>=0 ||
      StringFind(s,"US30")>=0 || StringFind(s,"NAS")>=0)
      return OtherLotSize;

   return ForexLotSize;
}

int CountPositionsForSymbol()
{
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      count++;
   }

   return count;
}

double DynamicStop()
{
   double atr[1];

   if(CopyBuffer(atrHandle,0,0,1,atr)<1)
      return 100*_Point;

   double stopLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
   double spread=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);

   return MathMax(atr[0]*ATRMultiplierSL,
                  MathMax(stopLevel,freezeLevel)+spread*10.0);
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      double profit=PositionGetDouble(POSITION_PROFIT);
      double volume=PositionGetDouble(POSITION_VOLUME);

      if(profit>=volume*ProfitTargetPerLot)
      {
         trade.PositionClose(ticket);
         continue;
      }

      double tp=PositionGetDouble(POSITION_TP);
      double sl=PositionGetDouble(POSITION_SL);
      double dist=DynamicStop();

      ENUM_POSITION_TYPE pos=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(pos==POSITION_TYPE_BUY)
      {
         double newSL=NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_BID)-dist,_Digits);
         if(newSL>sl) trade.PositionModify(ticket,newSL,tp);
      }
      else
      {
         double newSL=NormalizeDouble(SymbolInfoDouble(_Symbol,SYMBOL_ASK)+dist,_Digits);
         if(sl==0 || newSL<sl) trade.PositionModify(ticket,newSL,tp);
      }
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);

   atrHandle=iATR(_Symbol,_Period,ATRPeriod);
   fastHandle=iMA(_Symbol,_Period,EMAFast,0,MODE_EMA,PRICE_CLOSE);
   slowHandle=iMA(_Symbol,_Period,EMASlow,0,MODE_EMA,PRICE_CLOSE);

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   ManagePositions();

   if(CountPositionsForSymbol()>=MaxPositionsPerSymbol)
      return;

   double fast[2], slow[2];

   if(CopyBuffer(fastHandle,0,0,2,fast)<2) return;
   if(CopyBuffer(slowHandle,0,0,2,slow)<2) return;

   double high=iHigh(_Symbol,_Period,1);
   double low=iLow(_Symbol,_Period,1);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double slDist=DynamicStop();

   bool upTrend=fast[0]>slow[0];
   bool downTrend=fast[0]<slow[0];

   if(upTrend && ask>high)
   {
      trade.Buy(GetLotSize(),
                _Symbol,
                ask,
                ask-slDist,
                ask+slDist*RiskReward,
                "BreakoutBuy");
   }

   if(downTrend && bid<low)
   {
      trade.Sell(GetLotSize(),
                 _Symbol,
                 bid,
                 bid+slDist,
                 bid-slDist*RiskReward,
                 "BreakoutSell");
   }
}
