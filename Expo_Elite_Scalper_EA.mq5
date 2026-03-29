//+------------------------------------------------------------------+
//|                                        Expo_Elite_Scalper_EA.mq5 |
//|                        EXPO ELITE SCALPER EA (multi-symbol)     |
//+------------------------------------------------------------------+
#property copyright "Expo Elite Scalper"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

input group "=== Risk & reward ==="
input double InpRiskPercent          = 1.0;    // Risk % of balance per trade
input double InpRR                   = 1.5;    // Take-profit R multiple (vs SL distance)

input group "=== Signal ==="
input int    InpRangeBars            = 20;     // M5 range lookback (closed bars)
input int    InpProbabilityThreshold = 65;     // Min score (0–100 scale; see README)
input int    InpEmaPeriod            = 50;     // M15 EMA period
input ENUM_TIMEFRAMES InpEmaTf       = PERIOD_M15;
input int    InpBodyMinPoints        = 20;     // M1 body size filter (points)

input group "=== Filters ==="
input int    InpMaxSpreadPoints      = 20;     // Max spread (points); 0 = off
input int    InpSessionStartHour     = 8;      // Server hour inclusive
input int    InpSessionEndHour       = 20;     // Server hour inclusive

input group "=== Symbols ==="
input string InpSymbolList           = "EURUSD,GBPUSD,XAUUSD,USDJPY";

input group "=== Execution ==="
input int    InpMagic                = 777;
input int    InpSlippagePoints       = 20;
input int    InpMaxPositionsPerSym   = 1;     // Max open positions per symbol (this magic)
input bool   InpUseNewM5Bar          = true;  // One evaluation per symbol per new M5 bar

input group "=== Logging ==="
input bool   InpLogCsv               = true;
input string InpLogFileName          = "ExpoElite_trade_log.csv";

input group "=== Display ==="
input bool   InpShowDashboard        = true;

string   g_syms[];
int      g_symCount = 0;
int      g_hEma[];
datetime g_lastM5Bar[];
double   g_buyScore = 0.0;
double   g_sellScore = 0.0;
string   g_dashSym = "";
int      g_fileHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
void ParseSymbols()
{
   ArrayResize(g_syms, 0);
   g_symCount = 0;
   string parts[];
   int n = StringSplit(InpSymbolList, ',', parts);
   for(int i = 0; i < n; i++)
   {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      if(StringLen(parts[i]) == 0) continue;
      ArrayResize(g_syms, g_symCount + 1);
      g_syms[g_symCount++] = parts[i];
   }
   if(g_symCount == 0)
   {
      ArrayResize(g_syms, 1);
      g_syms[0] = _Symbol;
      g_symCount = 1;
   }
}

//+------------------------------------------------------------------+
bool SessionActive()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour);
}

//+------------------------------------------------------------------+
double SpreadPoints(const string sym)
{
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0) return 0;
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   return (ask - bid) / pt;
}

//+------------------------------------------------------------------+
int CountPositions(const string sym)
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      c++;
   }
   return c;
}

//+------------------------------------------------------------------+
double NormalizeVolume(const string sym, double vol)
{
   double mn = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   vol = MathMax(mn, MathMin(mx, MathFloor(vol / st) * st));
   int dg = (st <= 0.001) ? 3 : 2;
   return NormalizeDouble(vol, dg);
}

//+------------------------------------------------------------------+
double LotForRisk(const string sym, const double entry, const double sl)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = bal * (InpRiskPercent / 100.0);
   if(riskMoney <= 0) return 0;

   double slDist = MathAbs(entry - sl);
   if(slDist <= 0) return 0;

   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickVal <= 0) return 0;

   double perLot = (slDist / tickSize) * tickVal;
   if(perLot <= 0) return 0;

   return NormalizeVolume(sym, riskMoney / perLot);
}

//+------------------------------------------------------------------+
bool RangeHighLow(const string sym, double &outHigh, double &outLow)
{
   double h[], l[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   int n = InpRangeBars;
   if(n < 1) return false;
   if(CopyHigh(sym, PERIOD_M5, 1, n, h) != n) return false;
   if(CopyLow(sym, PERIOD_M5, 1, n, l) != n) return false;
   int ih = ArrayMaximum(h, 0, n);
   int il = ArrayMinimum(l, 0, n);
   if(ih < 0 || il < 0) return false;
   outHigh = h[ih];
   outLow  = l[il];
   return (outHigh > 0 && outLow > 0);
}

//+------------------------------------------------------------------+
double GetProbability(const string sym, const int idx, const bool isBuy)
{
   if(idx < 0 || idx >= g_symCount || g_hEma[idx] == INVALID_HANDLE) return 0;

   double emaBuf[];
   ArraySetAsSeries(emaBuf, true);
   if(CopyBuffer(g_hEma[idx], 0, 1, 1, emaBuf) != 1) return 0;
   double ema = emaBuf[0];

   double closeM1 = iClose(sym, PERIOD_M1, 1);
   if(closeM1 <= 0) return 0;

   double closeM5 = iClose(sym, PERIOD_M5, 1);
   if(closeM5 <= 0) return 0;

   double rh, rl;
   if(!RangeHighLow(sym, rh, rl)) return 0;

   double score = 0;

   if(isBuy && closeM1 > ema) score += 30.0;
   if(!isBuy && closeM1 < ema) score += 30.0;

   if(isBuy && closeM5 > rh) score += 30.0;
   if(!isBuy && closeM5 < rl) score += 30.0;

   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0) pt = _Point;
   double openM1 = iOpen(sym, PERIOD_M1, 1);
   double body = MathAbs(closeM1 - openM1);
   if(body >= pt * InpBodyMinPoints) score += 20.0;

   return score;
}

//+------------------------------------------------------------------+
void LogTrade(const string sym, const long type, const double price, const double sl, const double tp)
{
   if(!InpLogCsv || g_fileHandle == INVALID_HANDLE) return;
   string tstr = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   FileWrite(g_fileHandle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), sym, tstr,
             DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
             DoubleToString(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
             DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)));
   FileFlush(g_fileHandle);
}

//+------------------------------------------------------------------+
bool ExecuteTrade(const string sym, const ENUM_ORDER_TYPE type, const double slLevel)
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
   if(price <= 0) return false;

   double sl = slLevel;
   double riskDist = (type == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
   if(riskDist <= 0)
   {
      Print("Expo Elite: invalid SL distance ", sym);
      return false;
   }

   double tp = (type == ORDER_TYPE_BUY) ? (price + riskDist * InpRR) : (price - riskDist * InpRR);

   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, dg);
   tp = NormalizeDouble(tp, dg);

   int stops = (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(stops > 0 && pt > 0)
   {
      double minD = stops * pt;
      if(type == ORDER_TYPE_BUY)
      {
         if(price - sl < minD) sl = NormalizeDouble(price - minD, dg);
         if(tp - price < minD) tp = NormalizeDouble(price + minD, dg);
      }
      else
      {
         if(sl - price < minD) sl = NormalizeDouble(price + minD, dg);
         if(price - tp < minD) tp = NormalizeDouble(price - minD, dg);
      }
      riskDist = (type == ORDER_TYPE_BUY) ? (price - sl) : (sl - price);
      tp = (type == ORDER_TYPE_BUY) ? NormalizeDouble(price + riskDist * InpRR, dg)
                                    : NormalizeDouble(price - riskDist * InpRR, dg);
   }

   double lot = LotForRisk(sym, price, sl);
   if(lot <= 0)
   {
      Print("Expo Elite: lot 0 ", sym);
      return false;
   }

   long fm = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   bool ok = false;
   if(type == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, sym, 0, sl, tp, "ExpoElite BUY");
   else
      ok = trade.Sell(lot, sym, 0, sl, tp, "ExpoElite SELL");

   if(ok)
      LogTrade(sym, (long)type, price, sl, tp);
   else
      Print("Expo Elite: order failed ", sym, " ", trade.ResultRetcodeDescription());

   return ok;
}

//+------------------------------------------------------------------+
void ProcessSymbol(const int idx)
{
   string sym = g_syms[idx];
   if(!SymbolSelect(sym, true)) return;

   if(InpMaxSpreadPoints > 0 && SpreadPoints(sym) > InpMaxSpreadPoints) return;

   if(CountPositions(sym) >= InpMaxPositionsPerSym) return;

   if(InpUseNewM5Bar)
   {
      datetime t5 = iTime(sym, PERIOD_M5, 0);
      if(t5 == 0 || t5 == g_lastM5Bar[idx]) return;
      g_lastM5Bar[idx] = t5;
   }

   double buyScore = GetProbability(sym, idx, true);
   double sellScore = GetProbability(sym, idx, false);

   g_buyScore = buyScore;
   g_sellScore = sellScore;
   g_dashSym = sym;

   double rh, rl;
   if(!RangeHighLow(sym, rh, rl)) return;

   double th = (double)InpProbabilityThreshold;

   if(buyScore >= th && buyScore > sellScore)
   {
      if(ExecuteTrade(sym, ORDER_TYPE_BUY, rl))
         return;
   }

   if(sellScore >= th && sellScore > buyScore)
      ExecuteTrade(sym, ORDER_TYPE_SELL, rh);
}

//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(!InpShowDashboard) { Comment(""); return; }
   string s = "EXPO ELITE SCALPER\n";
   if(StringLen(g_dashSym) > 0)
      s += g_dashSym + "\n";
   s += "BUY score: "  + DoubleToString(g_buyScore, 1) + "\n";
   s += "SELL score: " + DoubleToString(g_sellScore, 1);
   Comment(s);
}

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   ArrayResize(g_hEma, g_symCount);
   ArrayResize(g_lastM5Bar, g_symCount);
   for(int i = 0; i < g_symCount; i++)
   {
      g_lastM5Bar[i] = 0;
      string sym = g_syms[i];
      SymbolSelect(sym, true);
      g_hEma[i] = iMA(sym, InpEmaTf, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hEma[i] == INVALID_HANDLE)
      {
         Print("Expo Elite: iMA failed ", sym);
         return INIT_FAILED;
      }
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   if(InpLogCsv)
   {
      g_fileHandle = FileOpen(InpLogFileName, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
      if(g_fileHandle == INVALID_HANDLE)
         Print("Expo Elite: could not open log file (check MQL5\\Files): ", InpLogFileName);
      else
      {
         FileSeek(g_fileHandle, 0, SEEK_END);
         if(FileTell(g_fileHandle) == 0)
            FileWrite(g_fileHandle, "Time", "Symbol", "Type", "Price", "SL", "TP");
      }
   }

   Print("Expo Elite Scalper | symbols=", g_symCount, " | threshold=", InpProbabilityThreshold,
         " | session ", InpSessionStartHour, "-", InpSessionEndHour);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   for(int i = 0; i < g_symCount; i++)
      if(g_hEma[i] != INVALID_HANDLE) IndicatorRelease(g_hEma[i]);
   if(g_fileHandle != INVALID_HANDLE)
   {
      FileClose(g_fileHandle);
      g_fileHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!SessionActive()) return;

   for(int i = 0; i < g_symCount; i++)
      ProcessSymbol(i);

   DrawDashboard();
}

//+------------------------------------------------------------------+
