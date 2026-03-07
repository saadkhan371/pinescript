//+------------------------------------------------------------------+
//|                                              GainzAlgo_EA.mq5    |
//|                        GainzAlgo EA - Optimized for 1m XAUUSD   |
//|                    Converted from Pine Script for MetaTrader 5   |
//+------------------------------------------------------------------+
#property copyright "GainzAlgo EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Preset ==="
enum ENUM_PRESET
{
   PRESET_ESSENTIAL,   // Essential (Conservative)
   PRESET_PROFICIENT,   // Proficient (Balanced)
   PRESET_ALPHA         // Alpha (Aggressive)
};

input ENUM_PRESET InpPreset = PRESET_ALPHA;

input group "=== Indicators ==="
input int   InpEmaFastLen   = 5;    // Fast EMA Length
input int   InpEmaSlowLen   = 13;   // Slow EMA Length
input int   InpEmaTrendLen  = 34;   // Trend EMA Length
input int   InpRsiLen       = 7;    // RSI Length
input int   InpRsiOB        = 72;   // RSI Overbought
input int   InpRsiOS        = 28;   // RSI Oversold
input int   InpAtrLen       = 14;   // ATR Length

input group "=== Risk Management ==="
input bool  InpUseAtrMult   = true;  // Use ATR for SL/TP
input double InpTpMult      = 2.0;   // Take Profit (x ATR) manual
input double InpSlMult      = 1.0;   // Stop Loss (x ATR) manual
input bool  InpUseCompounding = false;  // Enable Compounding (lot size grows with balance)
input double InpLotSize     = 0.01;  // Fixed Lot Size (when compounding OFF)
input double InpCompoundingPercent = 1.0; // Risk % of balance per trade (when compounding ON)
input int   InpMagic        = 123456; // Magic Number

input group "=== Display ==="
input bool  InpShowSignals  = true;  // Show BUY/SELL Arrows

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
int            handleEmaFast, handleEmaSlow, handleEmaTrend;
int            handleRsi, handleAtr;
double         presetTP, presetSL, presetRSIThresh;
datetime       lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   // Set filling mode based on symbol
   long fillMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Create indicator handles
   handleEmaFast  = iMA(_Symbol, PERIOD_CURRENT, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaSlow  = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   handleEmaTrend = iMA(_Symbol, PERIOD_CURRENT, InpEmaTrendLen, 0, MODE_EMA, PRICE_CLOSE);
   handleRsi      = iRSI(_Symbol, PERIOD_CURRENT, InpRsiLen, PRICE_CLOSE);
   handleAtr      = iATR(_Symbol, PERIOD_CURRENT, InpAtrLen);

   if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE || 
      handleEmaTrend == INVALID_HANDLE || handleRsi == INVALID_HANDLE || handleAtr == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return INIT_FAILED;
   }

   // Set preset values
   SetPresetValues();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEmaFast != INVALID_HANDLE)  IndicatorRelease(handleEmaFast);
   if(handleEmaSlow != INVALID_HANDLE)  IndicatorRelease(handleEmaSlow);
   if(handleEmaTrend != INVALID_HANDLE) IndicatorRelease(handleEmaTrend);
   if(handleRsi != INVALID_HANDLE)      IndicatorRelease(handleRsi);
   if(handleAtr != INVALID_HANDLE)      IndicatorRelease(handleAtr);
}

//+------------------------------------------------------------------+
//| Set preset-based SL/TP multipliers                               |
//+------------------------------------------------------------------+
void SetPresetValues()
{
   switch(InpPreset)
   {
      case PRESET_ESSENTIAL:
         presetTP = 2.2;
         presetSL = 1.8;
         presetRSIThresh = 3.0;
         break;
      case PRESET_PROFICIENT:
         presetTP = 1.8;
         presetSL = 1.2;
         presetRSIThresh = 5.0;
         break;
      case PRESET_ALPHA:
      default:
         presetTP = 1.4;
         presetSL = 1.0;
         presetRSIThresh = 8.0;
         break;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only trade on new bar (confirmed bar close - no repainting)
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime)
      return;
   lastBarTime = currentBarTime;

   // Get indicator values (use bar 1 = previous closed bar)
   double emaFast[], emaSlow[], emaTrend[], rsi[], atr[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(emaTrend, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(handleEmaFast, 0, 1, 3, emaFast) < 3) return;
   if(CopyBuffer(handleEmaSlow, 0, 1, 3, emaSlow) < 3) return;
   if(CopyBuffer(handleEmaTrend, 0, 1, 3, emaTrend) < 3) return;
   if(CopyBuffer(handleRsi, 0, 1, 3, rsi) < 3) return;
   if(CopyBuffer(handleAtr, 0, 1, 3, atr) < 3) return;

   double close0 = iClose(_Symbol, PERIOD_CURRENT, 1);  // Bar that just closed
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 2);  // Previous bar
   double high1  = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1   = iLow(_Symbol, PERIOD_CURRENT, 1);

   // Index: 0=bar that just closed, 1=bar-2, 2=bar-3
   double emaF0 = emaFast[0], emaF1 = emaFast[1], emaF2 = emaFast[2];
   double emaS0 = emaSlow[0], emaS1 = emaSlow[1];
   double emaT0 = emaTrend[0];
   double rsi0 = rsi[0];
   double atr0 = atr[0] > 0 ? atr[0] : (high1 - low1);

   double effTP = InpUseAtrMult ? presetTP : InpTpMult;
   double effSL = InpUseAtrMult ? presetSL : InpSlMult;

   // Trend detection
   bool bullishTrend = (emaF0 > emaS0 && emaS0 > emaT0);
   bool bearishTrend = (emaF0 < emaS0 && emaS0 < emaT0);
   bool priceAboveTrend = (close0 > emaT0);
   bool priceBelowTrend = (close0 < emaT0);

   // Entry conditions (crossover: prev < level, current > level)
   bool longCrossover  = (emaF1 < emaS1 && emaF0 > emaS0);
   bool longPullback   = (close0 > emaF0 && emaF0 > emaS0 && rsi0 > InpRsiOS && rsi0 < (InpRsiOB - presetRSIThresh));
   bool longBounce     = (close1 < emaFast[1] && close0 > emaF0 && emaF0 > emaS0);  // crossover(close, emaFast)
   bool longCondition  = bullishTrend && priceAboveTrend && (longCrossover || longPullback || longBounce) && rsi0 < InpRsiOB;

   bool shortCrossover = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortPullback  = (close0 < emaF0 && emaF0 < emaS0 && rsi0 < InpRsiOB && rsi0 > (InpRsiOS + presetRSIThresh));
   bool shortBounce    = (close1 > emaFast[1] && close0 < emaF0 && emaF0 < emaS0);   // crossunder(close, emaFast)
   bool shortCondition = bearishTrend && priceBelowTrend && (shortCrossover || shortPullback || shortBounce) && rsi0 > InpRsiOS;

   // Exit conditions (trend reversal)
   bool longExitTrend  = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortExitTrend = (emaF1 < emaS1 && emaF0 > emaS0);

   // Calculate SL/TP levels (use close of bar that just closed)
   double longSL = close0 - atr0 * effSL;
   double longTP = close0 + atr0 * effTP;
   double shortSL = close0 + atr0 * effSL;
   double shortTP = close0 - atr0 * effTP;

   // Normalize prices
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   longSL   = NormalizeDouble(longSL, digits);
   longTP   = NormalizeDouble(longTP, digits);
   shortSL  = NormalizeDouble(shortSL, digits);
   shortTP  = NormalizeDouble(shortTP, digits);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Get current position
   int posType = GetPositionType();

   // Long Position Entry
   if(longCondition && posType <= 0)
   {
      if(posType < 0)
         CloseAllPositions();
      
      double buyLots = CalculateLotSize(ask, longSL);
      if(trade.Buy(buyLots, _Symbol, ask, longSL, longTP, "GainzAlgo BUY"))
      {
         if(InpShowSignals)
            DrawArrow(1, "BUY", longTP, longSL);
         Alert("BUY - ", _Symbol, " | Entry: ", ask, " | SL: ", longSL, " | TP: ", longTP);
      }
   }

   // Short Position Entry
   if(shortCondition && posType >= 0)
   {
      if(posType > 0)
         CloseAllPositions();
      
      double sellLots = CalculateLotSize(bid, shortSL);
      if(trade.Sell(sellLots, _Symbol, bid, shortSL, shortTP, "GainzAlgo SELL"))
      {
         if(InpShowSignals)
            DrawArrow(-1, "SELL", shortTP, shortSL);
         Alert("SELL - ", _Symbol, " | Entry: ", bid, " | SL: ", shortSL, " | TP: ", shortTP);
      }
   }

   // Trend reversal exit
   if(posType > 0 && longExitTrend && !longCondition)
      CloseAllPositions();
   if(posType < 0 && shortExitTrend && !shortCondition)
      CloseAllPositions();
}

//+------------------------------------------------------------------+
//| Get current position type: 1=long, -1=short, 0=none               |
//+------------------------------------------------------------------+
int GetPositionType()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY)  return 1;
            if(posInfo.PositionType() == POSITION_TYPE_SELL) return -1;
         }
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Calculate lot size (fixed or compounding)                         |
//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice)
{
   if(!InpUseCompounding)
      return InpLotSize;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpCompoundingPercent / 100.0;
   double slDistance = MathAbs(entryPrice - slPrice);
   
   if(slDistance <= 0) return InpLotSize;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(tickSize <= 0 || point <= 0) return InpLotSize;

   double lotValue = tickValue * (point / tickSize);
   double slPoints = slDistance / point;
   double moneyPerLot = slPoints * lotValue;
   
   if(moneyPerLot <= 0) return InpLotSize;

   double lots = riskMoney / moneyPerLot;

   // Apply lot limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Close all positions for this EA                                   |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
            trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Draw BUY/SELL arrow on chart                                      |
//+------------------------------------------------------------------+
void DrawArrow(int direction, string text, double tp, double sl)
{
   datetime time = iTime(_Symbol, PERIOD_CURRENT, 1);
   double price = (direction > 0) ? iLow(_Symbol, PERIOD_CURRENT, 1) : iHigh(_Symbol, PERIOD_CURRENT, 1);
   
   string labelName = "GainzAlgo_" + IntegerToString(time) + "_" + text;
   
   if(ObjectFind(0, labelName) >= 0)
      ObjectDelete(0, labelName);

   if(ObjectCreate(0, labelName, OBJ_ARROW, 0, time, price))
   {
      ObjectSetInteger(0, labelName, OBJPROP_ARROWCODE, direction > 0 ? 233 : 234);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, direction > 0 ? clrLime : clrRed);
      ObjectSetInteger(0, labelName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, labelName, OBJPROP_ANCHOR, direction > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      
      // Create TP/SL label
      string tpSlName = "GainzAlgo_TS_" + IntegerToString(time) + "_" + text;
      if(ObjectFind(0, tpSlName) >= 0) ObjectDelete(0, tpSlName);
      double labelPrice = (direction > 0) ? price - (iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1)) * 0.3 
                                       : price + (iHigh(_Symbol, PERIOD_CURRENT, 1) - iLow(_Symbol, PERIOD_CURRENT, 1)) * 0.3;
      if(ObjectCreate(0, tpSlName, OBJ_TEXT, 0, time, labelPrice))
      {
         ObjectSetString(0, tpSlName, OBJPROP_TEXT, "TP: " + DoubleToString(tp, 2) + "  SL: " + DoubleToString(sl, 2));
         ObjectSetInteger(0, tpSlName, OBJPROP_COLOR, clrSilver);
         ObjectSetInteger(0, tpSlName, OBJPROP_FONTSIZE, 8);
      }
   }
}

//+------------------------------------------------------------------+
