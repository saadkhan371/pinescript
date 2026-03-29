//+------------------------------------------------------------------+
//|                              Gold_LiquidityGrab_Scalper_EA.mq5 |
//|     M1 XAUUSD: Trend + EMA20/50/200 + pullback + liquidity grab   |
//+------------------------------------------------------------------+
#property copyright "Gold Liquidity Grab Scalper"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

input group "=== Symbol & execution ==="
input string InpSymbol           = "";        // Empty = chart symbol
input int    InpMagic             = 771001;   // Magic number
input int    InpSlippagePoints    = 30;       // Slippage (points)
input ENUM_TIMEFRAMES InpTf       = PERIOD_M1; // Signal timeframe (M1 recommended)

input group "=== EMA trend stack ==="
input int    InpEmaFast           = 20;
input int    InpEmaMid            = 50;
input int    InpEmaSlow           = 200;

input group "=== Pullback & grab ==="
input double InpPullbackTouchPts  = 30.0;      // Max distance (points) low/high to EMA20 or EMA50
input bool   InpRequireLiquidityGrab = true;    // Require sweep of prior bar high/low

input group "=== RSI (14) ==="
input int    InpRsiPeriod         = 14;
input double InpRsiBuyMin         = 40.0;       // Buy: RSI zone low
input double InpRsiBuyMax         = 45.0;       // Buy: RSI zone high
input double InpRsiSellMin        = 55.0;
input double InpRsiSellMax        = 60.0;
input bool   InpRequireRsiTurn    = true;       // RSI turning (vs previous bar)

input group "=== Entry trigger ==="
input bool   InpAllowStrongCandle = true;       // Close in direction (bull/bear body)
input bool   InpAllowEngulfing    = true;       // Body engulfs previous body

input group "=== Stops & target ==="
input double InpSlExtraPts        = 5.0;        // SL beyond sweep extreme (points)
input double InpMinSlPts          = 50.0;       // Min SL distance (points; broker-dependent)
input double InpMaxSlPts          = 100.0;      // Max SL distance (points); 0 = no cap
input double InpRewardRisk        = 2.0;         // TP = RR × risk distance
input bool   InpSkipIfSlOutOfBand = true;       // No trade if SL outside min/max band

input group "=== Risk & limits ==="
input bool   InpUseRiskPercent    = true;       // Lot by risk % (else fixed lot)
input double InpRiskPercent       = 1.0;        // Risk % per trade
input double InpFixedLot          = 0.10;       // Fixed lot if risk % off
input int    InpMaxOpenPositions  = 1;
input int    InpMaxTradesPerDay   = 5;          // 0 = unlimited
input bool   InpStopAfterTwoLosses = true;      // Pause after 2 consecutive losses
input bool   InpResetConsecDaily  = true;       // Reset consecutive loss count at server midnight

input group "=== Session filter (server time) ==="
input bool   InpUseSessionFilter  = false;      // If true, trade only in windows below
input bool   InpUseWinLondon      = true;       // London window
input int    InpLondonStart       = 8;          // Inclusive
input int    InpLondonEnd         = 12;         // Exclusive
input bool   InpUseWinNY          = true;       // New York window
input int    InpNYStart           = 13;         // Inclusive
input int    InpNYEnd             = 17;         // Exclusive
input bool   InpUseWinOverlap     = false;      // Overlap only (stricter)
input int    InpOverlapStart      = 13;
input int    InpOverlapEnd        = 16;

input group "=== Expert ==="
input bool   InpVerbose           = true;

string   g_sym;
int      hEmaF = INVALID_HANDLE, hEmaM = INVALID_HANDLE, hEmaS = INVALID_HANDLE, hRsi = INVALID_HANDLE;
datetime g_lastBarTime = 0;
bool     g_lastBuySetup = false, g_lastSellSetup = false;
int      g_consecLosses = 0;
datetime g_resetDay     = 0;

//+------------------------------------------------------------------+
datetime DayStart(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
bool HourInRange(const int h, const int startInclusive, const int endExclusive)
{
   if(startInclusive == endExclusive) return false;
   if(startInclusive < endExclusive)
      return (h >= startInclusive && h < endExclusive);
   return (h >= startInclusive || h < endExclusive);
}

//+------------------------------------------------------------------+
bool SessionAllows()
{
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int h = dt.hour;

   if(InpUseWinOverlap)
      return HourInRange(h, InpOverlapStart, InpOverlapEnd);

   bool ok = false;
   if(InpUseWinLondon)
      ok = ok || HourInRange(h, InpLondonStart, InpLondonEnd);
   if(InpUseWinNY)
      ok = ok || HourInRange(h, InpNYStart, InpNYEnd);
   return ok;
}

//+------------------------------------------------------------------+
int CountOpenOwn()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
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
   datetime from = DayStart(TimeCurrent());
   if(!HistorySelect(from, TimeCurrent())) return 9999;
   int cnt = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != g_sym) continue;
      if((int)HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      long ty = HistoryDealGetInteger(d, DEAL_TYPE);
      if(ty != DEAL_TYPE_BUY && ty != DEAL_TYPE_SELL) continue;
      cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
double NormalizeVol(double v)
{
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   v = MathMax(mn, MathMin(mx, MathFloor(v / st) * st));
   int dg = (st >= 0.09) ? 1 : (st <= 0.001 ? 3 : 2);
   return NormalizeDouble(v, dg);
}

//+------------------------------------------------------------------+
double LotForRisk(const double entry, const double sl)
{
   if(!InpUseRiskPercent) return NormalizeVol(InpFixedLot);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = bal * (InpRiskPercent / 100.0);
   if(riskMoney <= 0) return NormalizeVol(InpFixedLot);
   double slDist = MathAbs(entry - sl);
   if(slDist <= 0) return NormalizeVol(InpFixedLot);
   double tickSize = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickVal <= 0) return NormalizeVol(InpFixedLot);
   double perLot = (slDist / tickSize) * tickVal;
   if(perLot <= 0) return NormalizeVol(InpFixedLot);
   return NormalizeVol(riskMoney / perLot);
}

//+------------------------------------------------------------------+
bool CopyBuf(int h, int shift, double &v)
{
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(h, 0, shift, 1, b) != 1) return false;
   v = b[0];
   return MathIsValidNumber(v);
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   if(!SymbolSelect(g_sym, true))
   {
      Print("LiquidityGrab: bad symbol ", g_sym);
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   long fm = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   hEmaF = iMA(g_sym, InpTf, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaM = iMA(g_sym, InpTf, InpEmaMid, 0, MODE_EMA, PRICE_CLOSE);
   hEmaS = iMA(g_sym, InpTf, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hRsi  = iRSI(g_sym, InpTf, InpRsiPeriod, PRICE_CLOSE);
   if(hEmaF == INVALID_HANDLE || hEmaM == INVALID_HANDLE || hEmaS == INVALID_HANDLE || hRsi == INVALID_HANDLE)
      return INIT_FAILED;

   g_lastBarTime = 0;
   g_lastBuySetup = g_lastSellSetup = false;
   Print("Gold Liquidity Grab Scalper | ", g_sym, " | TF=", EnumToString(InpTf));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hEmaF != INVALID_HANDLE) IndicatorRelease(hEmaF);
   if(hEmaM != INVALID_HANDLE) IndicatorRelease(hEmaM);
   if(hEmaS != INVALID_HANDLE) IndicatorRelease(hEmaS);
   if(hRsi != INVALID_HANDLE) IndicatorRelease(hRsi);
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal)) return;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != g_sym) return;
   if((int)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double net = HistoryDealGetDouble(deal, DEAL_PROFIT)
              + HistoryDealGetDouble(deal, DEAL_COMMISSION)
              + HistoryDealGetDouble(deal, DEAL_SWAP);
   if(net < 0.0) g_consecLosses++;
   else g_consecLosses = 0;
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime ds = DayStart(TimeCurrent());
   if(ds != g_resetDay)
   {
      g_resetDay = ds;
      if(InpResetConsecDaily)
         g_consecLosses = 0;
   }
   if(!SessionAllows()) return;
   if(CountOpenOwn() >= InpMaxOpenPositions) return;
   if(InpMaxTradesPerDay > 0 && CountEntriesToday() >= InpMaxTradesPerDay) return;
   if(InpStopAfterTwoLosses && g_consecLosses >= 2) return;

   datetime t0 = iTime(g_sym, InpTf, 0);
   if(t0 == 0 || t0 == g_lastBarTime) return;
   g_lastBarTime = t0;

   const int s1 = 1, s2 = 2;
   double emaF1, emaM1, emaS1, rsi1, rsi2;
   if(!CopyBuf(hEmaF, s1, emaF1) || !CopyBuf(hEmaM, s1, emaM1) || !CopyBuf(hEmaS, s1, emaS1)) return;
   if(!CopyBuf(hRsi, s1, rsi1) || !CopyBuf(hRsi, s2, rsi2)) return;

   double open1 = iOpen(g_sym, InpTf, s1);
   double high1 = iHigh(g_sym, InpTf, s1);
   double low1  = iLow(g_sym, InpTf, s1);
   double close1 = iClose(g_sym, InpTf, s1);
   double open2 = iOpen(g_sym, InpTf, s2);
   double high2 = iHigh(g_sym, InpTf, s2);
   double low2  = iLow(g_sym, InpTf, s2);
   double close2 = iClose(g_sym, InpTf, s2);
   if(open1 <= 0 || high1 <= 0 || low1 <= 0 || close1 <= 0) return;

   double pt = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   if(pt <= 0) pt = 0.01;
   double touchMax = InpPullbackTouchPts * pt;

   bool stackBuy  = (emaF1 > emaM1 && emaM1 > emaS1);
   bool stackSell = (emaF1 < emaM1 && emaM1 < emaS1);
   bool priceAbove200 = (close1 > emaS1);
   bool priceBelow200 = (close1 < emaS1);

   bool trendBuy  = stackBuy && priceAbove200;
   bool trendSell = stackSell && priceBelow200;

   bool touchBuy =
      (MathAbs(low1 - emaF1) <= touchMax || MathAbs(low1 - emaM1) <= touchMax ||
       MathAbs(close1 - emaF1) <= touchMax || MathAbs(close1 - emaM1) <= touchMax);
   bool touchSell =
      (MathAbs(high1 - emaF1) <= touchMax || MathAbs(high1 - emaM1) <= touchMax ||
       MathAbs(close1 - emaF1) <= touchMax || MathAbs(close1 - emaM1) <= touchMax);

   bool grabBuy  = !InpRequireLiquidityGrab || (low1 < low2);
   bool grabSell = !InpRequireLiquidityGrab || (high1 > high2);

   bool rsiBuyOk =
      (rsi1 >= InpRsiBuyMin && rsi1 <= InpRsiBuyMax && (!InpRequireRsiTurn || (rsi1 > rsi2)));
   bool rsiSellOk =
      (rsi1 >= InpRsiSellMin && rsi1 <= InpRsiSellMax && (!InpRequireRsiTurn || (rsi1 < rsi2)));

   bool bullBody = (close1 > open1);
   bool bearBody = (close1 < open1);
   bool bullEngulf = (close1 > open1 && open1 < close2 && close1 > close2 && close2 < open2);
   bool bearEngulf = (close1 < open1 && open1 > close2 && close1 < close2 && close2 > open2);

   bool trigBuy  = (InpAllowStrongCandle && bullBody) || (InpAllowEngulfing && bullEngulf);
   bool trigSell = (InpAllowStrongCandle && bearBody) || (InpAllowEngulfing && bearEngulf);

   bool buySetup  = trendBuy && touchBuy && grabBuy && rsiBuyOk && trigBuy;
   bool sellSetup = trendSell && touchSell && grabSell && rsiSellOk && trigSell;

   bool newBuy  = buySetup && !g_lastBuySetup;
   bool newSell = sellSetup && !g_lastSellSetup;
   g_lastBuySetup = buySetup;
   g_lastSellSetup = sellSetup;

   if(buySetup && sellSetup)
   {
      if(InpVerbose) Print("LiquidityGrab: conflicting setups — skip");
      return;
   }

   if(!newBuy && !newSell) return;

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   int dg = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);

   if(newBuy)
   {
      double sweepLow = MathMin(low1, low2);
      double sl = sweepLow - InpSlExtraPts * pt;
      double entry = ask;
      double riskDist = entry - sl;
      if(riskDist < InpMinSlPts * pt)
      {
         sl = entry - InpMinSlPts * pt;
         riskDist = entry - sl;
      }
      if(InpMaxSlPts > 0 && riskDist > InpMaxSlPts * pt && InpSkipIfSlOutOfBand)
      {
         if(InpVerbose) Print("LiquidityGrab: BUY skipped — SL too wide");
         return;
      }
      if(InpMaxSlPts > 0 && riskDist > InpMaxSlPts * pt)
      {
         sl = entry - InpMaxSlPts * pt;
         riskDist = entry - sl;
      }
      double tp = entry + riskDist * InpRewardRisk;
      int stops = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minStop = stops * pt;
      if(minStop > 0)
      {
         if(entry - sl < minStop) sl = NormalizeDouble(entry - minStop, dg);
         if(tp - entry < minStop) tp = NormalizeDouble(entry + minStop, dg);
         riskDist = entry - sl;
         tp = NormalizeDouble(entry + riskDist * InpRewardRisk, dg);
      }
      sl = NormalizeDouble(sl, dg);
      tp = NormalizeDouble(tp, dg);
      double lot = LotForRisk(entry, sl);
      trade.SetExpertMagicNumber(InpMagic);
      if(lot > 0 && trade.Buy(lot, g_sym, 0, sl, tp, "LiqGrab BUY"))
      {
         if(InpVerbose) Print("LiquidityGrab BUY | SL=", sl, " TP=", tp);
      }
      else if(InpVerbose) Print("LiquidityGrab BUY fail: ", trade.ResultRetcodeDescription());
   }
   else if(newSell)
   {
      double sweepHigh = MathMax(high1, high2);
      double sl = sweepHigh + InpSlExtraPts * pt;
      double entry = bid;
      double riskDist = sl - entry;
      if(riskDist < InpMinSlPts * pt)
      {
         sl = entry + InpMinSlPts * pt;
         riskDist = sl - entry;
      }
      if(InpMaxSlPts > 0 && riskDist > InpMaxSlPts * pt && InpSkipIfSlOutOfBand)
      {
         if(InpVerbose) Print("LiquidityGrab: SELL skipped — SL too wide");
         return;
      }
      if(InpMaxSlPts > 0 && riskDist > InpMaxSlPts * pt)
      {
         sl = entry + InpMaxSlPts * pt;
         riskDist = sl - entry;
      }
      double tp = entry - riskDist * InpRewardRisk;
      int stops = (int)SymbolInfoInteger(g_sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minStop = stops * pt;
      if(minStop > 0)
      {
         if(sl - entry < minStop) sl = NormalizeDouble(entry + minStop, dg);
         if(entry - tp < minStop) tp = NormalizeDouble(entry - minStop, dg);
         riskDist = sl - entry;
         tp = NormalizeDouble(entry - riskDist * InpRewardRisk, dg);
      }
      sl = NormalizeDouble(sl, dg);
      tp = NormalizeDouble(tp, dg);
      double lot = LotForRisk(entry, sl);
      trade.SetExpertMagicNumber(InpMagic);
      if(lot > 0 && trade.Sell(lot, g_sym, 0, sl, tp, "LiqGrab SELL"))
      {
         if(InpVerbose) Print("LiquidityGrab SELL | SL=", sl, " TP=", tp);
      }
      else if(InpVerbose) Print("LiquidityGrab SELL fail: ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
