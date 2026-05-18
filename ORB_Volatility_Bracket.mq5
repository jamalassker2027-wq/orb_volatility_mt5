//+------------------------------------------------------------------+
//|                                    OpeningRange_ATR_Breakout.mq5 |
//|                                  Copyright 2026, Quant Algorithmic|
//+------------------------------------------------------------------+
#property copyright "Quant Algorithmic"
#property version   "1.20"

// === Input Parameters ===
input string    Inp_Section1       = "══════ Opening Range ══════";
input int       Inp_StartHour      = 9;          // Session Start Hour (MUST MATCH YOUR BROKER CLOCK)
input int       Inp_StartMin       = 30;         // Session Start Minute
input int       Inp_EndHour        = 9;          // Session End Hour
input int       Inp_EndMin         = 45;         // Session End Minute
input ENUM_TIMEFRAMES Inp_RangeTF  = PERIOD_M15; // Structural Range Timeframe

input string    Inp_Section2       = "══════ Volatility Bracket ══════";
input int       Inp_AtrPeriod      = 14;          // ATR Period Baseline
input double    Inp_TpAtrMultiplier= 0.45;        // Take Profit ATR Factor (73% Strike Target)
input double    Inp_SlAtrMultiplier= 1.10;        // Stop Loss ATR Factor (Volatility Protection)

input string    Inp_Section4       = "══════ Risk Management ══════";
input double    Inp_FixedLot       = 0.1;         // Trade Execution Lot Size
input ulong     Inp_MagicNumber    = 999222;      // Unique Tracking ID

// --- Global Engine Variables ---
int            g_atrHandle;
int            g_currentDayID;

// --- Day Session Ranges ---
double          g_orHigh;
double          g_orLow;
bool            g_rangeMatured;
datetime        g_lastTradeDay; 
string          g_engineStatus;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   g_atrHandle = iATR(_Symbol, PERIOD_M15, Inp_AtrPeriod);
   if(g_atrHandle == INVALID_HANDLE) {
      Print("❌ Critical error creating Technical ATR Filter Handle.");
      return(INIT_FAILED);
   }

   g_currentDayID       = -1;
   g_orHigh             = 0.0;
   g_orLow              = 0.0;
   g_rangeMatured       = false;
   g_lastTradeDay       = 0;
   g_engineStatus       = "Initializing Engine Context...";

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(g_atrHandle);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function with live tick breakout monitoring          |
//+------------------------------------------------------------------+
void OnTick() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt); 
   
   // --- DAILY SESSION RESET LOGIC ---
   if(dt.day != g_currentDayID) {
      g_currentDayID       = dt.day;
      g_orHigh             = 0.0;
      g_orLow              = 0.0;
      g_rangeMatured       = false;
      PrintFormat("🌅 Fresh day session detected: %02d/%02d/%04d. Resetting tracking baselines.", dt.day, dt.mon, dt.year);
   }

   // --- CONSTRUCT AND LOCK OPENING RANGE BY TIME ---
   if(!g_rangeMatured) {
      g_engineStatus = StringFormat("STATUS: Awaiting Range Lock Window (%02d:%02d to %02d:%02d)\nYour Broker Clock Is At: %02d:%02d", 
                                    Inp_StartHour, Inp_StartMin, Inp_EndHour, Inp_EndMin, dt.hour, dt.min);
                                    
      if(dt.hour > Inp_EndHour || (dt.hour == Inp_EndHour && dt.min >= Inp_EndMin)) {
         
         MqlDateTime today = dt;
         today.hour = Inp_StartHour; today.min = Inp_StartMin; today.sec = 0;
         datetime startSession = StructToTime(today);
         
         today.hour = Inp_EndHour; today.min = Inp_EndMin; today.sec = 0;
         datetime endSession = StructToTime(today);
         
         int startShift = iBarShift(_Symbol, Inp_RangeTF, startSession, false);
         int endShift   = iBarShift(_Symbol, Inp_RangeTF, endSession, false);
         int barsInRange = startShift - endShift;
         
         if(barsInRange > 0) {
            double highestBuffer[], lowestBuffer[];
            
            ArraySetAsSeries(highestBuffer, true);
            ArraySetAsSeries(lowestBuffer, true);
            
            if(CopyHigh(_Symbol, Inp_RangeTF, endShift, barsInRange, highestBuffer) == barsInRange &&
               CopyLow(_Symbol, Inp_RangeTF, endShift, barsInRange, lowestBuffer) == barsInRange) {
               
               g_orHigh = highestBuffer[ArrayMaximum(highestBuffer, 0, barsInRange)];
               g_orLow  = lowestBuffer[ArrayMinimum(lowestBuffer, 0, barsInRange)];
               
               g_rangeMatured = true;
               PrintFormat("📊 Range Fixed Success -> High: %0.5f | Low: %0.5f", g_orHigh, g_orLow);
            }
         }
      }
      Comment(StringFormat("⚙️ 73%% ATR BREAKOUT MONITOR\n%s", g_engineStatus));
      return; 
   }

   // --- GUARD CLAUSES ---
   if(CountActivePositions() > 0) {
      Comment("⚙️ 73% ATR BREAKOUT MONITOR\nSTATUS: Open Target running. Execution engine locked.");
      return;
   }
   
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00");
   if(g_lastTradeDay >= todayStart) {
      Comment("⚙️ 73% ATR BREAKOUT MONITOR\nSTATUS: Daily session limit filled. Circuit breaker active.");
      return;
   }

   // --- LIVE SPREAD & PRICE TRACKING ---
   double live_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double live_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Fetch Contemporary Volatility Data
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer) < 1) return;
   double current_atr = atrBuffer[0];

   Comment(StringFormat("⚙️ 73%% ATR BREAKOUT ENGINE WATCHING\n📈 Range High Bound: %0.5f\n📉 Range Low Bound:  %0.5f\n📊 Dynamic ATR(14):   %0.5f\n💎 Market Ask Price:  %0.5f\n💸 Market Bid Price:  %0.5f", 
           g_orHigh, g_orLow, current_atr, live_ask, live_bid));

   // 1. 🟢 DYNAMIC BREAKOUT LONG (Live Ask price breaks above Range High)
   if(live_ask > g_orHigh) {
      double sl = live_ask - (current_atr * Inp_SlAtrMultiplier);
      double tp = live_ask + (current_atr * Inp_TpAtrMultiplier);
      
      PrintFormat("🎯 BREAKOUT LONG TRIGGERED: Live Ask (%0.5f) exceeded High boundary (%0.5f)", live_ask, g_orHigh);
      SendMarketOrder(ORDER_TYPE_BUY, live_ask, sl, tp);
      g_lastTradeDay = TimeCurrent();
   }
   
   // 2. 🔴 DYNAMIC BREAKOUT SHORT (Live Bid price drops below Range Low)
   if(live_bid < g_orLow) {
      double sl = live_bid + (current_atr * Inp_SlAtrMultiplier);
      double tp = live_bid - (current_atr * Inp_TpAtrMultiplier);
      
      PrintFormat("🎯 BREAKOUT SHORT TRIGGERED: Live Bid (%0.5f) breached Low boundary (%0.5f)", live_bid, g_orLow);
      SendMarketOrder(ORDER_TYPE_SELL, live_bid, sl, tp);
      g_lastTradeDay = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| High-Reliability Two-Stage Execution Engine                      |
//+------------------------------------------------------------------+
void SendMarketOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp) {
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   
   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = Inp_FixedLot;
   request.type         = orderType;
   request.price        = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl           = 0.0; // Send initial naked execution for standard ECN accounts
   request.tp           = 0.0;
   request.deviation    = 30;
   request.magic        = Inp_MagicNumber;
   request.comment      = "73_ORB_Bracket"; 
   
   long fillFlags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillFlags & SYMBOL_FILLING_FOK) != 0)     request.type_filling = ORDER_FILLING_FOK;
   else if((fillFlags & SYMBOL_FILLING_IOC) != 0) request.type_filling = ORDER_FILLING_IOC;
   else                                           request.type_filling = ORDER_FILLING_RETURN;
   
   ResetLastError();
   if(!OrderSend(request, result)) {
      PrintFormat("⚠️ Market execution order rejected by exchange server. Error: %d", GetLastError());
      return;
   }
   
   PrintFormat("🔥 Primary Transaction confirmed. Ticket: %d. Processing modification loop...", result.order);
   
   // Secure loop to wait briefly for server synchronization, then drop brackets in place
   for(int attempt = 0; attempt < 10; attempt++) {
      Sleep(100); 
      
      for(int i = 0; i < PositionsTotal(); i++) {
         ulong positionTicket = PositionGetTicket(i);
         if(PositionSelectByTicket(positionTicket)) {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber) {
               
               MqlTradeRequest modifyRequest = {};
               MqlTradeResult  modifyResult  = {};
               
               modifyRequest.action   = TRADE_ACTION_SLTP;
               modifyRequest.position = positionTicket;
               modifyRequest.symbol   = _Symbol;
               modifyRequest.sl       = NormalizeDouble(sl, _Digits);
               modifyRequest.tp       = NormalizeDouble(tp, _Digits);
               modifyRequest.magic    = Inp_MagicNumber;
               modifyRequest.comment  = "ORB_Brackets_Active"; 
               
               if(OrderSend(modifyRequest, modifyResult)) {
                  Print("✅ Volatility Brackets successfully attached to active order.");
                  return;
               }
            }
         }
      }
   }
   Print("⚠️ Modification loop timeout. Brackets could not be applied automatically.");
}

//+------------------------------------------------------------------+
//| Count active trade positions matching our Magic Number            |
//+------------------------------------------------------------------+
int CountActivePositions() {
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == Inp_MagicNumber) {
            count++;
         }
      }
   }
   return count;
}