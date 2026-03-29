//+------------------------------------------------------------------+
//|                                          Gold_Empire_Expert.mq5 |
//|                         Gold Empire Expert — XAUUSD (strict)    |
//+------------------------------------------------------------------+
#property copyright "Gold Empire Expert"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==== INPUTS ====
input group "=== Symbol & session ==="
input string InpSymbol              = "";           // Symbol (empty = chart symbol)
input int    InpMagic               = 902100;       // Magic number
input int    InpSlippagePoints      = 30;           // Slippage (points)

input group "=== Timeframes (MTF) ==="
input ENUM_TIMEFRAMES InpEntryTF              = PERIOD_CURRENT; // Entry / signal timeframe (CURRENT = chart)
input ENUM_TIMEFRAMES InpTrendEmaTF          = PERIOD_H4;       // EMA200 trend filter timeframe
input ENUM_TIMEFRAMES InpAdxTF                 = PERIOD_H1;       // ADX strength timeframe

input group "=== Strategy (EMA200 + ADX + ATR) ==="
input int    InpEmaPeriod           = 200;          // EMA period (trend & pullback)
input int    InpAdxPeriod           = 14;          // ADX period
input double InpAdxThreshold        = 20.0;         // Min ADX (main line)
input double InpPullbackMaxPoints   = 20.0;         // Max |close-EMA200| on entry TF (points)
input int    InpAtrPeriod           = 14;           // ATR period (SL/TP)
input double InpSlAtrMult           = 1.5;          // Stop loss × ATR
input double InpTpAtrMult           = 2.5;          // Take profit × ATR

input group "=== Limits / cooldown ==="
input int    InpBarsCooldown        = 3;            // Closed bars after trade before new entry (0 = off)
input int    InpMaxOpenPositions    = 1;            // Max simultaneous positions (this symbol + magic)
input int    InpMaxTradesPerDay     = 5;            // Max new entries per day (0 = unlimited)

input group "=== Risk ==="
input double InpFixedLot            = 0.10;         // Fixed lot (if risk % off)
input bool   InpUseRiskPercent      = false;        // Size lot by risk % of balance
input double InpRiskPercent         = 1.0;          // Risk % per trade (if ON)

input group "=== Session shield (optional) ==="
input bool   InpAvoidRollover       = true;         // Block rollover window
input int    InpRolloverStartHour    = 22;           // Rollover start (server hour, inclusive)
input int    InpRolloverEndHour     = 2;            // Rollover end (server hour, exclusive)
input bool   InpAvoidFridayLate     = true;         // Block late Friday
input int    InpFridayLateFromHour  = 20;           // Friday block from this hour (server, inclusive)

input group "=== Expert ==="
input bool   InpVerbose             = true;         // Print decisions to Experts log

//==== GLOBALS ====
string   g_sym;
ENUM_TIMEFRAMES g_entryTf;
int      hEmaTrendTf   = INVALID_HANDLE;
int      hEmaEntryTf   = INVALID_HANDLE;
int      hAdx          = INVALID_HANDLE;
int      hAtr          = INVALID_HANDLE;
datetime g_lastEntryBarTime = 0;
int      g_cooldownBarsLeft = 0;
datetime g_lastCooldownBarTime = 0;

//+------------------------------------------------------------------+
int EffectiveEntryTF()
{
   if(InpEntryTF == PERIOD_CURRENT)
      return (int)_Period;
   return (int)InpEntryTF;
}

//+------------------------------------------------------------------+
bool IsNewClosedBarEntryTf()
{
   datetime t = iTime(g_sym, (ENUM_TIMEFRAMES)EffectiveEntryTF(), 0);
   if(t == 0) return false;
   if(t == g_lastEntryBarTime) return false;
   g_lastEntryBarTime = t;
   return true;
}

//+------------------------------------------------------------------+
void UpdateCooldownOnNewBar()
{
   datetime t = iTime(g_sym, (ENUM_TIMEFRAMES)EffectiveEntryTF(), 0);
   if(t == 0 || t == g_lastCooldownBarTime) return;
   g_lastCooldownBarTime = t;
   if(g_cooldownBarsLeft > 0)
      g_cooldownBarsLeft--;
}

//+------------------------------------------------------------------+
void ArmCooldownAfterTrade()
{
   g_cooldownBarsLeft = MathMax(0, InpBarsCooldown);
}

//+------------------------------------------------------------------+
bool SessionAllowsTrade()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(InpAvoidFridayLate && dt.day_of_week == 5 && dt.hour >= InpFridayLateFromHour)
      return false;

   if(InpAvoidRollover)
   {
      int h = dt.hour;
      int a = InpRolloverStartHour;
      int b = InpRolloverEndHour;
      if(a == b)
         return true;
      if(a < b)
      {
         if(h >= a && h < b) return false;
      }
      else
      {
         // wraps midnight e.g. 22 -> 2
         if(h >= a || h < b) return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
int CountEntriesToday()
{
   if(InpMaxTradesPerDay <= 0) return 0;

   datetime from = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(from, TimeCurrent()))
      return 9999;

   int cnt = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != g_sym) continue;
      if((int)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
double NormalizeVolume(double vol)
{
   double minLot = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   vol = MathMax(minLot, MathMin(maxLot, vol));
   vol = MathFloor(vol / step) * step;
   int dg = 2;
   if(step >= 0.09) dg = 1;
   else if(step <= 0.001) dg = 3;
   return NormalizeDouble(vol, dg);
}

//+------------------------------------------------------------------+
double LotForTrade(double entryPrice, double slPrice)
{
   if(!InpUseRiskPercent)
      return NormalizeVolume(InpFixedLot);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   if(riskMoney <= 0.0) return NormalizeVolume(InpFixedLot);

   double slDist = MathAbs(entryPrice - slPrice);
   if(slDist <= 0.0) return NormalizeVolume(InpFixedLot);

   double tickSize = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return NormalizeVolume(InpFixedLot);

   double perLot = (slDist / tickSize) * tickValue;
   if(perLot <= 0.0) return NormalizeVolume(InpFixedLot);

   return NormalizeVolume(riskMoney / perLot);
}

//+------------------------------------------------------------------+
bool CopyOne(int handle, int buffer, int shift, double &out)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, buffer, shift, 1, buf) != 1)
      return false;
   out = buf[0];
   return MathIsValidNumber(out);
}

//+------------------------------------------------------------------+
bool ReadIndicators(int shift,
                    double &emaTrend, double &closeTrend,
                    double &emaEntry, double &closeEntry,
                    double &adx, double &atr,
                    double &point)
{
   point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(point <= 0.0) point = 0.01;

   closeTrend = iClose(g_sym, InpTrendEmaTF, shift);
   closeEntry = iClose(g_sym, (ENUM_TIMEFRAMES)EffectiveEntryTF(), shift);
   if(!MathIsValidNumber(closeTrend) || !MathIsValidNumber(closeEntry)) return false;

   if(!CopyOne(hEmaTrendTf, 0, shift, emaTrend)) return false;
   if(!CopyOne(hEmaEntryTf, 0, shift, emaEntry)) return false;
   if(!CopyOne(hAdx, 0, shift, adx)) return false;
   if(!CopyOne(hAtr, 0, shift, atr)) return false;
   return true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym = InpSymbol;
   if(StringLen(g_sym) == 0)
      g_sym = _Symbol;

   if(!SymbolSelect(g_sym, true))
   {
      Print("Gold Empire: symbol not found: ", g_sym);
      return INIT_FAILED;
   }

   g_entryTf = (ENUM_TIMEFRAMES)EffectiveEntryTF();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   long fillMode = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fillMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   hEmaTrendTf = iMA(g_sym, InpTrendEmaTF, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hEmaEntryTf = iMA(g_sym, g_entryTf, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAdx        = iADX(g_sym, InpAdxTF, InpAdxPeriod);
   hAtr        = iATR(g_sym, g_entryTf, InpAtrPeriod);

   if(hEmaTrendTf == INVALID_HANDLE || hEmaEntryTf == INVALID_HANDLE ||
      hAdx == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Gold Empire: failed to create indicator handles");
      return INIT_FAILED;
   }

   g_lastEntryBarTime = 0;
   g_lastCooldownBarTime = 0;
   g_cooldownBarsLeft = 0;

   Print("Gold Empire Expert initialized | ", g_sym,
         " | EntryTF=", EnumToString((ENUM_TIMEFRAMES)g_entryTf),
         " | TrendEMA=", EnumToString(InpTrendEmaTF),
         " | ADX=", EnumToString(InpAdxTF));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hEmaTrendTf != INVALID_HANDLE) IndicatorRelease(hEmaTrendTf);
   if(hEmaEntryTf != INVALID_HANDLE) IndicatorRelease(hEmaEntryTf);
   if(hAdx != INVALID_HANDLE) IndicatorRelease(hAdx);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!SessionAllowsTrade())
      return;

   if(CountOwnPositions() >= InpMaxOpenPositions)
      return;

   if(InpMaxTradesPerDay > 0 && CountEntriesToday() >= InpMaxTradesPerDay)
      return;

   UpdateCooldownOnNewBar();

   if(!IsNewClosedBarEntryTf())
      return;

   if(InpBarsCooldown > 0 && g_cooldownBarsLeft > 0)
   {
      if(InpVerbose)
         Print("Gold Empire: cooldown ", g_cooldownBarsLeft, " bar(s) left");
      return;
   }

   const int sh = 1; // signal on last fully closed candle

   double emaTrend, emaEntry, adx, atr, closeTrend, closeEntry, pt;
   if(!ReadIndicators(sh, emaTrend, closeTrend, emaEntry, closeEntry, adx, atr, pt))
   {
      if(InpVerbose) Print("Gold Empire: indicator read failed");
      return;
   }

   double maxDist = InpPullbackMaxPoints * pt;

   bool trendLong  = (closeTrend > emaTrend);
   bool trendShort = (closeTrend < emaTrend);

   bool adxOk = (adx >= InpAdxThreshold);

   double dEntry = MathAbs(closeEntry - emaEntry);
   bool zoneLong  = (dEntry <= maxDist) && (closeEntry > emaEntry);
   bool zoneShort = (dEntry <= maxDist) && (closeEntry < emaEntry);

   bool buy  = trendLong && adxOk && zoneLong;
   bool sell = trendShort && adxOk && zoneShort;

   if(buy && sell)
   {
      if(InpVerbose) Print("Gold Empire: both sides valid — skip");
      return;
   }

   if(!buy && !sell)
      return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   double entry = buy ? ask : bid;
   double sl = buy ? entry - InpSlAtrMult * atr : entry + InpSlAtrMult * atr;
   double tp = buy ? entry + InpTpAtrMult * atr : entry - InpTpAtrMult * atr;

   int stops = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stops * pt;
   if(minDist > 0)
   {
      if(buy)
      {
         if(entry - sl < minDist) sl = entry - minDist;
         if(tp - entry < minDist) tp = entry + minDist;
      }
      else
      {
         if(sl - entry < minDist) sl = entry + minDist;
         if(entry - tp < minDist) tp = entry - minDist;
      }
   }

   double lot = LotForTrade(entry, sl);
   if(lot <= 0.0)
   {
      if(InpVerbose) Print("Gold Empire: lot size 0");
      return;
   }

   trade.SetExpertMagicNumber(InpMagic);

   bool ok = false;
   if(buy)
      ok = trade.Buy(lot, g_sym, 0, sl, tp, "GoldEmpire BUY");
   else
      ok = trade.Sell(lot, g_sym, 0, sl, tp, "GoldEmpire SELL");

   if(ok)
   {
      ArmCooldownAfterTrade();
      if(InpVerbose)
         Print("Gold Empire: ", (buy ? "BUY" : "SELL"), " lot=", lot, " ADX=", DoubleToString(adx, 2),
               " distEMA=", DoubleToString(dEntry / pt, 1), " pt");
   }
   else if(InpVerbose)
      Print("Gold Empire: order failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
