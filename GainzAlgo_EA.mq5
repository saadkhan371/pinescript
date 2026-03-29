//+------------------------------------------------------------------+
//|                                              GainzAlgo_EA.mq5    |
//|              GainzAlgo EA - XAUUSD M1 | $100 investment         |
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
   PRESET_MICRO,       // Micro (Small profit, $100 scalping)
   PRESET_ESSENTIAL,   // Essential (Conservative)
   PRESET_PROFICIENT,  // Proficient (Balanced)
   PRESET_ALPHA        // Alpha (Aggressive)
};

input ENUM_PRESET InpPreset = PRESET_MICRO;

input group "=== Indicators ==="
input int   InpEmaFastLen   = 5;    // Fast EMA Length
input int   InpEmaSlowLen   = 13;   // Slow EMA Length
input int   InpEmaTrendLen  = 34;   // Trend EMA Length
input int   InpRsiLen       = 7;    // RSI Length
input int   InpRsiOB        = 72;   // RSI Overbought
input int   InpRsiOS        = 28;   // RSI Oversold
input int   InpAtrLen       = 14;   // ATR Length

input group "=== Symbol ==="
input string InpSymbol      = "XAUUSDm";   // Symbol (XAUUSDm in MT5 for Gold, $100 setup)
input bool   InpMultiSymbol = false;  // Trade multiple symbols
input string InpSymbolList  = "XAUUSDm";  // Symbols (comma-separated, when Multi ON)

input group "=== Strategy Tester ==="
input double InpInitialDeposit = 100;  // Initial Deposit ($100 – set Tester Deposit to match)

input group "=== Risk Management ==="
input bool  InpUseAtrMult   = true;  // Use ATR for SL/TP
input double InpTpMult      = 2.0;   // Take Profit (x ATR) manual
input double InpSlMult      = 1.0;   // Stop Loss (x ATR) manual
input bool  InpUseCompounding = false;  // Enable Compounding (lot size grows with balance)
input bool  InpUseMarginBasedLot = true;   // Auto lot to fit margin (ON = no "not enough money")
input double InpLotSize     = 0.01;   // Lot size (0.01 for EURUSDm $100; fixed when margin-based gives 0)
input double InpCompoundingPercent = 0.5; // Risk % per trade when compounding (0.5% = $0.50 on $100)
input int   InpMaxPositions = 1;  // Max open positions per direction (1 = 75% strategy)
input int   InpMagic        = 123456; // Magic Number

input group "=== Timeframe ==="
enum ENUM_TIMEFRAME_MODE
{
   TF_CURRENT,   // Current chart timeframe
   TF_M1         // M1 only (recommended for scalping)
};

input ENUM_TIMEFRAME_MODE InpTimeframe = TF_M1;  // Timeframe mode (M1 for $100 scalping)
input bool   InpUseM5Trend = true;   // M5 trend filter (75% strategy: only trade with M5 trend)
input int    InpM5TrendBars = 2;      // M5 trend confirmation (2 = require 2 bars in trend)
input bool   InpCandleConfirm = true; // Candle confirmation (bar close in trade direction)
input double InpMinSLPoints = 0;     // Min SL distance (points, 0=off; e.g. 30 for XAUUSD)

input group "=== Display ==="
input bool  InpShowSignals  = true;  // Show BUY/SELL Arrows
input bool  InpShowTPSLLabels = false;  // Show TP/SL text labels
input bool  InpShowPositionDashboard = true;  // Show Position Table (Entry/SL/TP/Risk:Reward) in corner
input bool  InpDebugMode    = true;  // Debug: full logs + profit per trade | OFF: live, errors only

//+------------------------------------------------------------------+
//| Symbol data for multi-symbol mode                                |
//+------------------------------------------------------------------+
struct SymbolData
{
   string   symbol;
   int      hEmaFast, hEmaSlow, hEmaTrend, hRsi, hAtr;
   int      hM5Trend;
   datetime lastBarTime;
   bool     lastLongCond;
   bool     lastShortCond;
};

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
ENUM_TIMEFRAMES periodToUse;
CPositionInfo   posInfo;
int             handleEmaFast, handleEmaSlow, handleEmaTrend;
int             handleRsi, handleAtr;
int             handleM5Trend = INVALID_HANDLE;
double          presetTP, presetSL, presetRSIThresh;
datetime        lastBarTime = 0;
double          initialBalance = 0;
string          g_symbols[];      // Symbols to trade
int             g_symbolCount = 0;
bool            g_marginWarned = false;  // One-time leverage warning
bool            g_lastLongCond = false;
bool            g_lastShortCond = false;
SymbolData      g_multiData[];    // Per-symbol data for multi mode
// Position dashboard (professional Entry/SL/TP/R:R display)
double          g_dashEntry = 0, g_dashSL = 0, g_dashTP = 0;
int             g_dashDir = 0;    // 1=long, -1=short, 0=none

//+------------------------------------------------------------------+
//| Parse symbol list into array                                      |
//+------------------------------------------------------------------+
void ParseSymbolList()
{
   ArrayResize(g_symbols, 0);
   g_symbolCount = 0;
   string list = InpMultiSymbol ? InpSymbolList : InpSymbol;
   if(StringLen(list) == 0)
   {
      ArrayResize(g_symbols, 1);
      g_symbols[0] = _Symbol;
      g_symbolCount = 1;
      return;
   }
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      if(StringLen(parts[i]) > 0)
      {
         if(!SymbolSelect(parts[i], true))
            Print("Warning: Symbol ", parts[i], " not in Market Watch - adding");
         SymbolSelect(parts[i], true);
         ArrayResize(g_symbols, g_symbolCount + 1);
         g_symbols[g_symbolCount++] = parts[i];
      }
   }
   if(g_symbolCount == 0)
   {
      ArrayResize(g_symbols, 1);
      g_symbols[0] = _Symbol;
      g_symbolCount = 1;
   }
}

//+------------------------------------------------------------------+
//| Return true if symbol has valid data (exists in this tester mode) |
//+------------------------------------------------------------------+
bool SymbolAvailable(string symbol)
{
   if(StringLen(symbol) == 0) return false;
   if(SymbolInfoInteger(symbol, SYMBOL_EXIST) != 1) return false;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   return (bid > 0);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   // Set timeframe: M1 or current chart
   periodToUse = (InpTimeframe == TF_M1) ? PERIOD_M1 : PERIOD_CURRENT;

   // Build symbol list
   ParseSymbolList();

   // In "Math calculations" mode symbol info is not loaded - fallback to chart symbol
   if(!InpMultiSymbol && g_symbolCount > 0 && !SymbolAvailable(g_symbols[0]))
   {
      if(SymbolAvailable(_Symbol))
      {
         Print("Symbol ", g_symbols[0], " not available in this tester mode. Using chart symbol: ", _Symbol);
         g_symbols[0] = _Symbol;
      }
      else
      {
         Print("Error: Symbol ", g_symbols[0], " not available. Use Tester mode 'Open prices only' or 'Every tick', not 'Math calculations'.");
         return INIT_FAILED;
      }
   }

   if(InpMultiSymbol && g_symbolCount > 1)
   {
      // Multi-symbol: create handles per symbol
      ArrayResize(g_multiData, g_symbolCount);
      for(int i = 0; i < g_symbolCount; i++)
      {
         string sym = g_symbols[i];
         g_multiData[i].symbol = sym;
         g_multiData[i].lastBarTime = 0;
         g_multiData[i].hEmaFast  = iMA(sym, periodToUse, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
         g_multiData[i].hEmaSlow  = iMA(sym, periodToUse, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
         g_multiData[i].hEmaTrend = iMA(sym, periodToUse, InpEmaTrendLen, 0, MODE_EMA, PRICE_CLOSE);
         g_multiData[i].hRsi      = iRSI(sym, periodToUse, InpRsiLen, PRICE_CLOSE);
         g_multiData[i].hAtr      = iATR(sym, periodToUse, InpAtrLen);
         g_multiData[i].hM5Trend  = iMA(sym, PERIOD_M5, 34, 0, MODE_EMA, PRICE_CLOSE);
         g_multiData[i].lastLongCond  = false;
         g_multiData[i].lastShortCond = false;
         if(g_multiData[i].hEmaFast == INVALID_HANDLE || g_multiData[i].hEmaSlow == INVALID_HANDLE ||
            g_multiData[i].hEmaTrend == INVALID_HANDLE || g_multiData[i].hRsi == INVALID_HANDLE || g_multiData[i].hAtr == INVALID_HANDLE)
         {
            Print("Error creating handles for ", sym);
            return INIT_FAILED;
         }
      }
      // Chart handles unused in multi mode
      handleEmaFast = handleEmaSlow = handleEmaTrend = handleRsi = handleAtr = INVALID_HANDLE;
   }
   else
   {
      // Single symbol: use chart symbol or first from list
      string sym = g_symbols[0];
      if(!SymbolAvailable(sym) && SymbolAvailable(_Symbol))
         sym = g_symbols[0] = _Symbol;
      long fillMode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
      if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         trade.SetTypeFilling(ORDER_FILLING_RETURN);
      handleEmaFast  = iMA(sym, periodToUse, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
      handleEmaSlow  = iMA(sym, periodToUse, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
      handleEmaTrend = iMA(sym, periodToUse, InpEmaTrendLen, 0, MODE_EMA, PRICE_CLOSE);
      handleRsi      = iRSI(sym, periodToUse, InpRsiLen, PRICE_CLOSE);
      handleAtr      = iATR(sym, periodToUse, InpAtrLen);
      handleM5Trend  = iMA(sym, PERIOD_M5, 34, 0, MODE_EMA, PRICE_CLOSE);
      if(handleEmaFast == INVALID_HANDLE || handleEmaSlow == INVALID_HANDLE ||
         handleEmaTrend == INVALID_HANDLE || handleRsi == INVALID_HANDLE || handleAtr == INVALID_HANDLE)
      {
         Print("Error creating indicator handles for ", sym, ". Use Tester mode 'Open prices only' or 'Every tick' (not 'Math calculations').");
         return INIT_FAILED;
      }
   }

   SetPresetValues();
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("GainzAlgo EA initialized | Symbols: ", g_symbolCount, " (", (InpMultiSymbol ? "multi" : "single"), ") | Timeframe: ", (periodToUse == PERIOD_M1 ? "M1" : "Chart"), " | Preset: ", EnumToString(InpPreset));
   Print("=== STRATEGY TESTER | Initial Deposit (param): ", DoubleToString(InpInitialDeposit, 2), " | Actual Balance: ", DoubleToString(initialBalance, 2), " ", AccountInfoString(ACCOUNT_CURRENCY), " ===");
   if(MathAbs(initialBalance - InpInitialDeposit) > 0.01)
      Print(">>> Set Strategy Tester Deposit to ", DoubleToString(InpInitialDeposit, 0), " to match <<<");
   if(g_symbolCount > 0)
   {
      string symList = "";
      for(int i = 0; i < g_symbolCount; i++) symList += (i > 0 ? "," : "") + g_symbols[i];
      Print(">>> Trading: ", symList, " <<<");
      double marginNeed = 0;
      double price = SymbolInfoDouble(g_symbols[0], SYMBOL_ASK);
      if(OrderCalcMargin(ORDER_TYPE_BUY, g_symbols[0], InpLotSize, price, marginNeed) && marginNeed > initialBalance * 0.9)
         Print(">>> For $100 + ", DoubleToString(InpLotSize, 2), " lot set Strategy Tester LEVERAGE to Unlimited or 1:100 (not 1:1) <<<");
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");  // Clear position dashboard
   // Strategy Tester summary log
   double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double totalProfit = finalBalance - initialBalance;
   double profitPct = (initialBalance > 0) ? (totalProfit / initialBalance * 100.0) : 0;
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   
   Print("═══════════════════════════════════════════════════════════");
   Print("       GAINZALGO EA - STRATEGY TESTER RESULTS");
   Print("═══════════════════════════════════════════════════════════");
   Print("  Initial Deposit (param):   ", DoubleToString(InpInitialDeposit, 2), " ", currency);
   Print("  Actual Start Balance:     ", DoubleToString(initialBalance, 2), " ", currency);
   Print("  Final Balance:              ", DoubleToString(finalBalance, 2), " ", currency);
   Print("  Total Profit/Loss:          ", DoubleToString(totalProfit, 2), " ", currency, " (", DoubleToString(profitPct, 2), "%)");
   Print("═══════════════════════════════════════════════════════════");

   // Remove all EA chart objects to avoid IO error 233 on shutdown
   long chartId = ChartID();
   if(chartId != 0)
   {
      for(int i = ObjectsTotal(chartId, 0, -1) - 1; i >= 0; i--)
      {
         string name = ObjectName(chartId, i, 0, -1);
         if(StringFind(name, "GainzAlgo_") == 0)
            ObjectDelete(chartId, name);
      }
   }

   if(InpMultiSymbol && g_symbolCount > 1)
   {
      for(int i = 0; i < g_symbolCount; i++)
      {
         if(g_multiData[i].hEmaFast != INVALID_HANDLE)  IndicatorRelease(g_multiData[i].hEmaFast);
         if(g_multiData[i].hEmaSlow != INVALID_HANDLE)  IndicatorRelease(g_multiData[i].hEmaSlow);
         if(g_multiData[i].hEmaTrend != INVALID_HANDLE) IndicatorRelease(g_multiData[i].hEmaTrend);
         if(g_multiData[i].hRsi != INVALID_HANDLE)      IndicatorRelease(g_multiData[i].hRsi);
         if(g_multiData[i].hAtr != INVALID_HANDLE)      IndicatorRelease(g_multiData[i].hAtr);
         if(g_multiData[i].hM5Trend != INVALID_HANDLE)  IndicatorRelease(g_multiData[i].hM5Trend);
      }
   }
   else
   {
      if(handleEmaFast != INVALID_HANDLE)  IndicatorRelease(handleEmaFast);
      if(handleEmaSlow != INVALID_HANDLE)  IndicatorRelease(handleEmaSlow);
      if(handleEmaTrend != INVALID_HANDLE) IndicatorRelease(handleEmaTrend);
      if(handleRsi != INVALID_HANDLE)      IndicatorRelease(handleRsi);
      if(handleAtr != INVALID_HANDLE)      IndicatorRelease(handleAtr);
      if(handleM5Trend != INVALID_HANDLE)  IndicatorRelease(handleM5Trend);
   }
}

//+------------------------------------------------------------------+
//| Set preset-based SL/TP multipliers                               |
//+------------------------------------------------------------------+
void SetPresetValues()
{
   switch(InpPreset)
   {
      case PRESET_MICRO:
         presetTP = 1.0;   // Small profit (tight TP)
         presetSL = 0.8;
         presetRSIThresh = 6.0;
         break;
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
//| Process one symbol (single or multi mode)                         |
//+------------------------------------------------------------------+
void ProcessSymbol(string symbol, int hEmaF, int hEmaS, int hEmaT, int hRsi, int hAtr, datetime &lastBar,
                   int hM5Trend, bool &inOutLastLong, bool &inOutLastShort)
{
   datetime currentBarTime = iTime(symbol, periodToUse, 0);
   if(currentBarTime == lastBar) return;
   lastBar = currentBarTime;

   double emaFast[], emaSlow[], emaTrend[], rsi[], atr[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(emaTrend, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hEmaF, 0, 1, 3, emaFast) < 3) return;
   if(CopyBuffer(hEmaS, 0, 1, 3, emaSlow) < 3) return;
   if(CopyBuffer(hEmaT, 0, 1, 3, emaTrend) < 3) return;
   if(CopyBuffer(hRsi, 0, 1, 3, rsi) < 3) return;
   if(CopyBuffer(hAtr, 0, 1, 3, atr) < 3) return;

   double close0 = iClose(symbol, periodToUse, 1);
   double close1 = iClose(symbol, periodToUse, 2);
   double high1  = iHigh(symbol, periodToUse, 1);
   double low1   = iLow(symbol, periodToUse, 1);
   if(close0 <= 0 || high1 <= 0 || low1 <= 0) return;

   double emaF0 = emaFast[0], emaF1 = emaFast[1];
   double emaS0 = emaSlow[0], emaS1 = emaSlow[1];
   double emaT0 = emaTrend[0];
   double rsi0 = rsi[0];
   double atr0 = atr[0] > 0 ? atr[0] : (high1 - low1);

   double effTP = InpUseAtrMult ? presetTP : InpTpMult;
   double effSL = InpUseAtrMult ? presetSL : InpSlMult;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double slDist = atr0 * effSL;
   if(InpMinSLPoints > 0 && point > 0 && slDist < InpMinSLPoints * point)
      slDist = InpMinSLPoints * point;

   bool bullishTrend = (emaF0 > emaS0 && emaS0 > emaT0);
   bool bearishTrend = (emaF0 < emaS0 && emaS0 < emaT0);
   bool priceAboveTrend = (close0 > emaT0);
   bool priceBelowTrend = (close0 < emaT0);

   bool longCrossover  = (emaF1 < emaS1 && emaF0 > emaS0);
   bool longPullback   = (close0 > emaF0 && emaF0 > emaS0 && rsi0 > InpRsiOS && rsi0 < (InpRsiOB - presetRSIThresh));
   bool longBounce     = (close1 < emaFast[1] && close0 > emaF0 && emaF0 > emaS0);
   bool longCondition  = bullishTrend && priceAboveTrend && (longCrossover || longPullback || longBounce) && rsi0 < InpRsiOB;

   bool shortCrossover = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortPullback  = (close0 < emaF0 && emaF0 < emaS0 && rsi0 < InpRsiOB && rsi0 > (InpRsiOS + presetRSIThresh));
   bool shortBounce    = (close1 > emaFast[1] && close0 < emaF0 && emaF0 < emaS0);
   bool shortCondition = bearishTrend && priceBelowTrend && (shortCrossover || shortPullback || shortBounce) && rsi0 > InpRsiOS;

   // M5 trend filter (75% strategy: require N bars in trend to avoid false signals)
   bool m5Bullish = true, m5Bearish = true;
   if(InpUseM5Trend && hM5Trend != INVALID_HANDLE)
   {
      int m5Bars = (InpM5TrendBars < 1) ? 1 : MathMin(InpM5TrendBars, 10);
      double m5MA[];
      ArraySetAsSeries(m5MA, true);
      if(CopyBuffer(hM5Trend, 0, 1, m5Bars, m5MA) >= m5Bars)
      {
         int barsBull = 0, barsBear = 0;
         for(int b = 0; b < m5Bars; b++)
         {
            double c = iClose(symbol, PERIOD_M5, 1 + b);
            if(c > m5MA[b]) barsBull++;
            if(c < m5MA[b]) barsBear++;
         }
         m5Bullish = (barsBull >= m5Bars);
         m5Bearish = (barsBear >= m5Bars);
      }
   }

   // Candle confirmation: signal bar must close in trade direction (reduces false breakouts)
   bool candleLong  = true, candleShort = true;
   if(InpCandleConfirm)
   {
      double open1 = iOpen(symbol, periodToUse, 1);
      candleLong  = (close0 > open1);
      candleShort = (close0 < open1);
   }

   // New signal only: enter when condition just became true (not every bar)
   bool newLong  = longCondition && !inOutLastLong && m5Bullish && candleLong;
   bool newShort = shortCondition && !inOutLastShort && m5Bearish && candleShort;

   bool longExitTrend  = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortExitTrend = (emaF1 < emaS1 && emaF0 > emaS0);

   // TP >= SL distance (better R:R for 75%+ win rate strategy); min SL in points avoids noise stop-outs
   double longTP  = close0 + atr0 * effTP;
   double longSL  = close0 - slDist;
   double shortTP = close0 - atr0 * effTP;
   double shortSL = close0 + slDist;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   longSL   = NormalizeDouble(longSL, digits);
   longTP   = NormalizeDouble(longTP, digits);
   shortSL  = NormalizeDouble(shortSL, digits);
   shortTP  = NormalizeDouble(shortTP, digits);

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   int longCount = GetPositionCount(symbol, POSITION_TYPE_BUY);
   int shortCount = GetPositionCount(symbol, POSITION_TYPE_SELL);

   if(symbol == _Symbol && (longCondition || shortCondition))
   {
      g_dashEntry = close0;
      if(longCondition) { g_dashSL = longSL; g_dashTP = longTP; g_dashDir = 1; }
      else              { g_dashSL = shortSL; g_dashTP = shortTP; g_dashDir = -1; }
   }

   if(InpShowSignals && symbol == _Symbol && !MQLInfoInteger(MQL_TESTER))
   {
      CleanupOldObjects();
      if(longCondition) DrawArrow(symbol, 1, "BUY", longTP, longSL);
      if(shortCondition) DrawArrow(symbol, -1, "SELL", shortTP, shortSL);
   }

   // Set fill mode for this symbol before trade
   long fillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   if(newLong && longCount < InpMaxPositions)
   {
      if(shortCount > 0)
         CloseAllPositions(symbol);
      else
      {
         double buyLots = CalculateLotSize(symbol, ask, longSL);
         if(buyLots > 0)
         {
            if(!HasEnoughMargin(symbol, buyLots, ask, ORDER_TYPE_BUY))
            {
               if(!g_marginWarned) { Print(">>> Set Strategy Tester LEVERAGE to Unlimited or 1:100 (not 1:1) for $100 + 0.01 lot <<<"); g_marginWarned = true; }
            }
            else
            {
               if(InpDebugMode) Print("[GainzAlgo] Signal BUY ", symbol, " | lots=", buyLots);
               if(trade.Buy(buyLots, symbol, ask, longSL, longTP, "GainzAlgo BUY"))
               {
                  if(InpDebugMode) Print(">>> BUY opened ", symbol, " lots ", buyLots, " @ ", ask);
               }
               else if(InpDebugMode) Print(">>> BUY failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
         }
      }
   }

   if(newShort && shortCount < InpMaxPositions)
   {
      if(longCount > 0)
         CloseAllPositions(symbol);
      else
      {
         double sellLots = CalculateLotSize(symbol, bid, shortSL);
         if(sellLots > 0)
         {
            if(!HasEnoughMargin(symbol, sellLots, bid, ORDER_TYPE_SELL))
            {
               if(!g_marginWarned) { Print(">>> Set Strategy Tester LEVERAGE to Unlimited or 1:100 (not 1:1) for $100 + 0.01 lot <<<"); g_marginWarned = true; }
            }
            else
            {
               if(InpDebugMode) Print("[GainzAlgo] Signal SELL ", symbol, " | lots=", sellLots);
               if(trade.Sell(sellLots, symbol, bid, shortSL, shortTP, "GainzAlgo SELL"))
               {
                  if(InpDebugMode) Print(">>> SELL opened ", symbol, " lots ", sellLots, " @ ", bid);
               }
               else if(InpDebugMode) Print(">>> SELL failed: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
            }
         }
      }
   }

   if(longCount > 0 && longExitTrend && !longCondition)
      CloseAllPositions(symbol);
   if(shortCount > 0 && shortExitTrend && !shortCondition)
      CloseAllPositions(symbol);

   inOutLastLong  = longCondition;
   inOutLastShort = shortCondition;
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpMultiSymbol && g_symbolCount > 1)
   {
      for(int i = 0; i < g_symbolCount; i++)
         ProcessSymbol(g_multiData[i].symbol, g_multiData[i].hEmaFast, g_multiData[i].hEmaSlow, g_multiData[i].hEmaTrend,
                       g_multiData[i].hRsi, g_multiData[i].hAtr, g_multiData[i].lastBarTime,
                       g_multiData[i].hM5Trend, g_multiData[i].lastLongCond, g_multiData[i].lastShortCond);
   }
   else
   {
      ProcessSymbol(g_symbols[0], handleEmaFast, handleEmaSlow, handleEmaTrend, handleRsi, handleAtr, lastBarTime,
                    handleM5Trend, g_lastLongCond, g_lastShortCond);
   }

   if(InpShowPositionDashboard && !MQLInfoInteger(MQL_TESTER))
      UpdatePositionDashboard();
}

//+------------------------------------------------------------------+
//| Position dashboard: Entry, SL, TP, Risk, Reward, R:R (professional rule) |
//+------------------------------------------------------------------+
void UpdatePositionDashboard()
{
   if(!InpShowPositionDashboard) { Comment(""); return; }

   double entry = 0, sl = 0, tp = 0;
   int    dir   = 0;   // 1=long, -1=short

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagic) continue;
      entry = posInfo.PriceOpen();
      sl    = posInfo.StopLoss();
      tp    = posInfo.TakeProfit();
      dir   = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      break;
   }

   if(dir == 0 && g_dashDir != 0)
   {
      entry = g_dashEntry;
      sl    = g_dashSL;
      tp    = g_dashTP;
      dir   = g_dashDir;
   }

   if(dir == 0) { Comment(""); return; }

   double risk   = (dir > 0) ? (entry - sl) : (sl - entry);
   double reward = (dir > 0) ? (tp - entry) : (entry - tp);
   double rr     = (risk > 0) ? (reward / risk) : 0;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string s = "═════ GAINZALGO — Position Plan ═════\n";
   s += (dir > 0 ? "LONG" : "SHORT") + "\n";
   s += "Entry: "    + DoubleToString(entry, digits) + "\n";
   s += "Stop Loss: "+ DoubleToString(sl, digits) + "\n";
   s += "Take Profit: "+ DoubleToString(tp, digits) + "\n";
   s += "Risk: "     + DoubleToString(risk, digits) + "\n";
   s += "Reward: "   + DoubleToString(reward, digits) + "\n";
   s += "R:R = 1:"   + DoubleToString(rr, 1) + (rr >= 2 ? " (OK)" : " (<1:2)") + "\n";
   s += "══════════════════════════════════════════";
   Comment(s);
}

//+------------------------------------------------------------------+
//| Log profit when a position is closed (Debug mode only)           |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(!InpDebugMode) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   if((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagic) return;

   double profit   = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double swap     = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double net      = profit + commission + swap;
   string symbol   = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   long   dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   string side     = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";  // closing deal: SELL = closed long (BUY), BUY = closed short (SELL)
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   Print("[GainzAlgo] Trade closed | ", side, " ", symbol,
         " | Profit: ", DoubleToString(profit, 2), " ", currency,
         " | Commission: ", DoubleToString(commission, 2),
         " | Swap: ", DoubleToString(swap, 2),
         " | Net: ", DoubleToString(net, 2), " ", currency,
         " | Balance: ", DoubleToString(balance, 2), " ", currency);
}

//+------------------------------------------------------------------+
//| Get position count by type for symbol                             |
//+------------------------------------------------------------------+
int GetPositionCount(string symbol, ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == symbol && posInfo.Magic() == InpMagic && posInfo.PositionType() == posType)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate lot size (fixed, compounding, or margin-based)          |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double entryPrice, double slPrice)
{
   double lots = InpLotSize;

   if(InpUseCompounding)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = balance * InpCompoundingPercent / 100.0;
      double slDistance = MathAbs(entryPrice - slPrice);
      
      if(slDistance > 0)
      {
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         
         if(tickSize > 0 && point > 0)
         {
            double lotValue = tickValue * (point / tickSize);
            double slPoints = slDistance / point;
            double moneyPerLot = slPoints * lotValue;
            
            if(moneyPerLot > 0)
               lots = riskMoney / moneyPerLot;
         }
      }
   }

   if(InpUseMarginBasedLot)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxLotByMargin = GetMaxLotByMargin(symbol, entryPrice, freeMargin * 0.9);
      if(maxLotByMargin > 0 && lots > maxLotByMargin)
         lots = maxLotByMargin;
      else if(maxLotByMargin == 0)
         lots = InpLotSize;  // use fixed lot when margin calc gives 0 (set Tester leverage 1:100+)
   }

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   
   int lotDigits = (lotStep <= 0.001) ? 3 : 2;
   return NormalizeDouble(lots, lotDigits);
}

//+------------------------------------------------------------------+
//| Check if we have enough margin for the given lot                   |
//+------------------------------------------------------------------+
bool HasEnoughMargin(string symbol, double lots, double price, ENUM_ORDER_TYPE orderType)
{
   double marginRequired = 0;
   if(!OrderCalcMargin(orderType, symbol, lots, price, marginRequired))
      return false;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   return (marginRequired <= freeMargin * 0.95);
}

//+------------------------------------------------------------------+
//| Get max lot size that fits within given margin                    |
//+------------------------------------------------------------------+
double GetMaxLotByMargin(string symbol, double price, double marginAvailable)
{
   if(marginAvailable <= 0) return 0;

   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   double lot = minLot;
   double marginForLot = 0;
   
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, minLot, price, marginForLot))
      return minLot;
   
   if(marginForLot > marginAvailable)
      return 0;

   double testLot = maxLot;
   int lotDigits = (lotStep <= 0.001) ? 3 : 2;
   while(testLot - lot > lotStep * 0.5)
   {
      double midLot = NormalizeDouble((lot + testLot) / 2, lotDigits);
      midLot = MathFloor(midLot / lotStep) * lotStep;
      if(midLot < minLot) midLot = minLot;
      
      if(OrderCalcMargin(ORDER_TYPE_BUY, symbol, midLot, price, marginForLot) && marginForLot <= marginAvailable)
         lot = midLot;
      else
         testLot = midLot;
   }
   
   return NormalizeDouble(lot, lotDigits);
}

//+------------------------------------------------------------------+
//| Close all positions for this EA (symbol or all)                   |
//+------------------------------------------------------------------+
void CloseAllPositions(string symbol)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == symbol && posInfo.Magic() == InpMagic)
            trade.PositionClose(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
//| Cleanup old chart objects to prevent IO errors (code 49/233)      |
//+------------------------------------------------------------------+
void CleanupOldObjects()
{
   long chartId = ChartID();
   if(chartId == 0) return;
   
   int total = ObjectsTotal(chartId, 0, -1);
   if(total < 30) return;
   
   datetime cutoff = iTime(_Symbol, periodToUse, 80);  // Chart symbol for objects
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chartId, i, 0, -1);
      if(StringFind(name, "GainzAlgo_") == 0)
      {
         datetime objTime = (datetime)ObjectGetInteger(chartId, name, OBJPROP_TIME);
         if(objTime > 0 && objTime < cutoff)
         {
            ObjectDelete(chartId, name);
            total--;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw BUY/SELL arrow on chart                                      |
//+------------------------------------------------------------------+
void DrawArrow(string symbol, int direction, string text, double tp, double sl)
{
   long chartId = ChartID();
   if(chartId == 0) return;
   datetime time = iTime(symbol, periodToUse, 1);
   double price = (direction > 0) ? iLow(symbol, periodToUse, 1) : iHigh(symbol, periodToUse, 1);
   
   string labelName = "GainzAlgo_" + symbol + "_" + IntegerToString(time) + "_" + text;
   
   if(ObjectFind(chartId, labelName) >= 0)
      ObjectDelete(chartId, labelName);

   if(ObjectCreate(chartId, labelName, OBJ_ARROW, 0, time, price))
   {
      ObjectSetInteger(chartId, labelName, OBJPROP_ARROWCODE, direction > 0 ? 241 : 242);  // Wingdings arrows (avoid 233 - conflicts with error code)
      ObjectSetInteger(chartId, labelName, OBJPROP_COLOR, direction > 0 ? clrLime : clrRed);
      ObjectSetInteger(chartId, labelName, OBJPROP_WIDTH, 3);
      ObjectSetInteger(chartId, labelName, OBJPROP_ANCHOR, direction > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(chartId, labelName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
      
      // Create or remove TP/SL label (optional - pane labels)
      string tpSlName = "GainzAlgo_TS_" + symbol + "_" + IntegerToString(time) + "_" + text;
      if(ObjectFind(chartId, tpSlName) >= 0) ObjectDelete(chartId, tpSlName);
      if(InpShowTPSLLabels)
      {
         double labelPrice = (direction > 0) ? price - (iHigh(symbol, periodToUse, 1) - iLow(symbol, periodToUse, 1)) * 0.3 
                                          : price + (iHigh(symbol, periodToUse, 1) - iLow(symbol, periodToUse, 1)) * 0.3;
         if(ObjectCreate(chartId, tpSlName, OBJ_TEXT, 0, time, labelPrice))
         {
            ObjectSetString(chartId, tpSlName, OBJPROP_TEXT, "TP: " + DoubleToString(tp, 2) + "  SL: " + DoubleToString(sl, 2));
            ObjectSetInteger(chartId, tpSlName, OBJPROP_COLOR, clrSilver);
            ObjectSetInteger(chartId, tpSlName, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(chartId, tpSlName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         }
      }
   }
   if(chartId != 0)
      ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
