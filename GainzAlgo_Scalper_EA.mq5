//+------------------------------------------------------------------+
//|                                         GainzAlgo_Scalper_EA.mq5 |
//|   GainzAlgo scalper — single-symbol M1 stack + M5 filter + ATR   |
//|   Logic aligned with GainzAlgo_EA.mq5 / GainzAlgo_EA.pine        |
//+------------------------------------------------------------------+
#property copyright "GainzAlgo Scalper"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

input group "=== Preset ==="
enum ENUM_GS_PRESET
{
   GS_PRESET_MICRO,       // Micro (tight TP/SL)
   GS_PRESET_ESSENTIAL,   // Essential
   GS_PRESET_PROFICIENT,  // Proficient
   GS_PRESET_ALPHA        // Alpha
};
input ENUM_GS_PRESET InpPreset = GS_PRESET_MICRO;

input group "=== Symbol ==="
input string InpSymbol = "";              // Empty = chart symbol
input int    InpMagic  = 123457;          // Magic (distinct from full GainzAlgo EA)
input int    InpSlippagePoints = 30;

input group "=== Indicators ==="
input int InpEmaFastLen  = 5;
input int InpEmaSlowLen  = 13;
input int InpEmaTrendLen = 34;
input int InpRsiLen      = 7;
input int InpRsiOB       = 72;
input int InpRsiOS       = 28;
input int InpAtrLen      = 14;
input int InpM5TrendMaPeriod = 34;       // M5 trend EMA (matches Pine request.security)

input group "=== Timeframe ==="
enum ENUM_GS_TF
{
   GS_TF_CURRENT,
   GS_TF_M1
};
input ENUM_GS_TF InpTimeframe = GS_TF_M1;
input bool InpUseM5Trend     = true;
input int  InpM5TrendBars    = 2;
input bool InpCandleConfirm  = true;
input double InpMinSLPoints  = 0;       // Min SL distance (points, 0=off)

input group "=== Risk ==="
input bool   InpUseAtrMult   = true;
input double InpTpMult       = 2.0;       // Used when InpUseAtrMult = false
input double InpSlMult       = 1.0;
input bool   InpUseCompounding = false;
input bool   InpUseMarginBasedLot = true;
input double InpLotSize      = 0.01;
input double InpCompoundingPercent = 0.5;
input int    InpMaxPositions = 1;

input group "=== Behaviour ==="
input bool InpExitOnTrendCross = true;   // Close when fast/slow cross against position
input bool InpVerbose          = false;

string   g_sym;
ENUM_TIMEFRAMES g_period;
int hFast, hSlow, hTrend, hRsi, hAtr, hM5Ma;
datetime g_lastBar = 0;
bool     g_lastLong = false, g_lastShort = false;
double   g_presetTP, g_presetSL, g_presetRSIThresh;

//+------------------------------------------------------------------+
void ApplyPreset()
{
   switch(InpPreset)
   {
      case GS_PRESET_MICRO:
         g_presetTP = 1.0; g_presetSL = 0.8; g_presetRSIThresh = 6.0; break;
      case GS_PRESET_ESSENTIAL:
         g_presetTP = 2.2; g_presetSL = 1.8; g_presetRSIThresh = 3.0; break;
      case GS_PRESET_PROFICIENT:
         g_presetTP = 1.8; g_presetSL = 1.2; g_presetRSIThresh = 5.0; break;
      case GS_PRESET_ALPHA:
      default:
         g_presetTP = 1.4; g_presetSL = 1.0; g_presetRSIThresh = 8.0; break;
   }
}

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   if(st <= 0) st = 0.01;
   lots = MathFloor(lots / st) * st;
   lots = MathMax(mn, MathMin(mx, lots));
   int dg = (st <= 0.001) ? 3 : 2;
   return NormalizeDouble(lots, dg);
}

//+------------------------------------------------------------------+
bool HasEnoughMargin(double lots, double price, ENUM_ORDER_TYPE ot)
{
   double m = 0;
   if(!OrderCalcMargin(ot, g_sym, lots, price, m)) return false;
   return m <= AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.95;
}

//+------------------------------------------------------------------+
double MaxLotByMargin(double price, double marginAvail)
{
   if(marginAvail <= 0) return 0;
   double mn = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double lo = mn, hi = mx;
   int dg = (st <= 0.001) ? 3 : 2;
   while(hi - lo > st * 0.5)
   {
      double mid = NormalizeDouble(MathFloor(((lo + hi) / 2) / st) * st, dg);
      if(mid < mn) mid = mn;
      double m = 0;
      if(OrderCalcMargin(ORDER_TYPE_BUY, g_sym, mid, price, m) && m <= marginAvail)
         lo = mid;
      else
         hi = mid;
   }
   return NormalizeDouble(lo, dg);
}

//+------------------------------------------------------------------+
double CalculateLotSize(double entryPrice, double slPrice)
{
   double lots = InpLotSize;
   if(InpUseCompounding)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney = bal * (InpCompoundingPercent / 100.0);
      double slDist = MathAbs(entryPrice - slPrice);
      if(slDist > 0)
      {
         double tickValue = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);
         double point     = SymbolInfoDouble(g_sym, SYMBOL_POINT);
         if(tickSize > 0 && point > 0)
         {
            double moneyPerLot = (slDist / tickSize) * tickValue;
            if(moneyPerLot > 0) lots = riskMoney / moneyPerLot;
         }
      }
   }
   if(InpUseMarginBasedLot)
   {
      double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double cap = MaxLotByMargin(entryPrice, free * 0.9);
      if(cap > 0 && lots > cap) lots = cap;
      else if(cap == 0) lots = InpLotSize;
   }
   return NormalizeLots(lots);
}

//+------------------------------------------------------------------+
int PosCount(ENUM_POSITION_TYPE t)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != g_sym || posInfo.Magic() != InpMagic) continue;
      if(posInfo.PositionType() == t) n++;
   }
   return n;
}

//+------------------------------------------------------------------+
void CloseAll()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != g_sym || posInfo.Magic() != InpMagic) continue;
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_sym = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   if(!SymbolSelect(g_sym, true)) return INIT_FAILED;

   g_period = (InpTimeframe == GS_TF_M1) ? PERIOD_M1 : PERIOD_CURRENT;
   ApplyPreset();

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   long fm = SymbolInfoInteger(g_sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);

   hFast  = iMA(g_sym, g_period, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(g_sym, g_period, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(g_sym, g_period, InpEmaTrendLen, 0, MODE_EMA, PRICE_CLOSE);
   hRsi   = iRSI(g_sym, g_period, InpRsiLen, PRICE_CLOSE);
   hAtr   = iATR(g_sym, g_period, InpAtrLen);
   hM5Ma  = iMA(g_sym, PERIOD_M5, InpM5TrendMaPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE || hTrend == INVALID_HANDLE ||
      hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE || hM5Ma == INVALID_HANDLE)
      return INIT_FAILED;

   g_lastBar = 0;
   g_lastLong = g_lastShort = false;
   Print("GainzAlgo Scalper | ", g_sym, " | TF=", (g_period == PERIOD_M1 ? "M1" : "CURRENT"),
         " | Preset=", EnumToString(InpPreset));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   if(hFast != INVALID_HANDLE)  IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE)  IndicatorRelease(hSlow);
   if(hTrend != INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRsi != INVALID_HANDLE)   IndicatorRelease(hRsi);
   if(hAtr != INVALID_HANDLE)   IndicatorRelease(hAtr);
   if(hM5Ma != INVALID_HANDLE)  IndicatorRelease(hM5Ma);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime t = iTime(g_sym, g_period, 0);
   if(t == 0 || t == g_lastBar) return;
   g_lastBar = t;

   double emaF[], emaS[], emaT[], rsi[], atr[];
   ArraySetAsSeries(emaF, true);
   ArraySetAsSeries(emaS, true);
   ArraySetAsSeries(emaT, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hFast, 0, 1, 3, emaF) < 3) return;
   if(CopyBuffer(hSlow, 0, 1, 3, emaS) < 3) return;
   if(CopyBuffer(hTrend, 0, 1, 3, emaT) < 3) return;
   if(CopyBuffer(hRsi, 0, 1, 3, rsi) < 3) return;
   if(CopyBuffer(hAtr, 0, 1, 1, atr) < 1) return;

   double c0 = iClose(g_sym, g_period, 1);
   double c1 = iClose(g_sym, g_period, 2);
   double h1 = iHigh(g_sym, g_period, 1);
   double l1 = iLow(g_sym, g_period, 1);
   if(c0 <= 0 || h1 <= 0 || l1 <= 0) return;

   double emaF0 = emaF[0], emaF1 = emaF[1];
   double emaS0 = emaS[0], emaS1 = emaS[1];
   double emaT0 = emaT[0];
   double rsi0 = rsi[0];
   double atr0 = (atr[0] > 0) ? atr[0] : (h1 - l1);

   double effTP = InpUseAtrMult ? g_presetTP : InpTpMult;
   double effSL = InpUseAtrMult ? g_presetSL : InpSlMult;
   double point = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   double slDist = atr0 * effSL;
   if(InpMinSLPoints > 0 && point > 0 && slDist < InpMinSLPoints * point)
      slDist = InpMinSLPoints * point;

   bool bullishTrend = (emaF0 > emaS0 && emaS0 > emaT0);
   bool bearishTrend = (emaF0 < emaS0 && emaS0 < emaT0);
   bool priceAboveTrend = (c0 > emaT0);
   bool priceBelowTrend = (c0 < emaT0);

   bool longCrossover  = (emaF1 < emaS1 && emaF0 > emaS0);
   bool longPullback   = (c0 > emaF0 && emaF0 > emaS0 && rsi0 > InpRsiOS && rsi0 < (InpRsiOB - g_presetRSIThresh));
   bool longBounce     = (c1 < emaF[1] && c0 > emaF0 && emaF0 > emaS0);
   bool longCondition  = bullishTrend && priceAboveTrend && (longCrossover || longPullback || longBounce) && rsi0 < InpRsiOB;

   bool shortCrossover = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortPullback  = (c0 < emaF0 && emaF0 < emaS0 && rsi0 < InpRsiOB && rsi0 > (InpRsiOS + g_presetRSIThresh));
   bool shortBounce    = (c1 > emaF[1] && c0 < emaF0 && emaF0 < emaS0);
   bool shortCondition = bearishTrend && priceBelowTrend && (shortCrossover || shortPullback || shortBounce) && rsi0 > InpRsiOS;

   bool m5Bull = true, m5Bear = true;
   if(InpUseM5Trend)
   {
      int nb = (InpM5TrendBars < 1) ? 1 : MathMin(InpM5TrendBars, 10);
      double m5ma[];
      ArraySetAsSeries(m5ma, true);
      if(CopyBuffer(hM5Ma, 0, 1, nb, m5ma) >= nb)
      {
         int bull = 0, bear = 0;
         for(int b = 0; b < nb; b++)
         {
            double cl = iClose(g_sym, PERIOD_M5, 1 + b);
            if(cl > m5ma[b]) bull++;
            if(cl < m5ma[b]) bear++;
         }
         m5Bull = (bull >= nb);
         m5Bear = (bear >= nb);
      }
   }

   bool candleLong = true, candleShort = true;
   if(InpCandleConfirm)
   {
      double o0 = iOpen(g_sym, g_period, 1);
      candleLong  = (c0 > o0);
      candleShort = (c0 < o0);
   }

   bool newLong  = longCondition && !g_lastLong && m5Bull && candleLong;
   bool newShort = shortCondition && !g_lastShort && m5Bear && candleShort;

   bool longExitTrend  = (emaF1 > emaS1 && emaF0 < emaS0);
   bool shortExitTrend = (emaF1 < emaS1 && emaF0 > emaS0);

   int dg = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   double longTP  = NormalizeDouble(c0 + atr0 * effTP, dg);
   double longSL  = NormalizeDouble(c0 - slDist, dg);
   double shortTP = NormalizeDouble(c0 - atr0 * effTP, dg);
   double shortSL = NormalizeDouble(c0 + slDist, dg);

   int lc = PosCount(POSITION_TYPE_BUY);
   int sc = PosCount(POSITION_TYPE_SELL);

   double ask = SymbolInfoDouble(g_sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);

   if(newLong && newShort)
   {
      if(InpVerbose) Print("GainzScalper: long+short edge — skip");
   }
   else if(newLong && lc < InpMaxPositions)
   {
      if(sc > 0) CloseAll();
      else
      {
         double lots = CalculateLotSize(ask, longSL);
         if(lots > 0 && HasEnoughMargin(lots, ask, ORDER_TYPE_BUY))
         {
            if(trade.Buy(lots, g_sym, ask, longSL, longTP, "GainzScalper BUY") && InpVerbose)
               Print("GainzScalper BUY ", g_sym, " lots=", lots);
         }
      }
   }
   else if(newShort && sc < InpMaxPositions)
   {
      if(lc > 0) CloseAll();
      else
      {
         double lots = CalculateLotSize(bid, shortSL);
         if(lots > 0 && HasEnoughMargin(lots, bid, ORDER_TYPE_SELL))
         {
            if(trade.Sell(lots, g_sym, bid, shortSL, shortTP, "GainzScalper SELL") && InpVerbose)
               Print("GainzScalper SELL ", g_sym, " lots=", lots);
         }
      }
   }

   if(InpExitOnTrendCross)
   {
      if(lc > 0 && longExitTrend && !longCondition) CloseAll();
      if(sc > 0 && shortExitTrend && !shortCondition) CloseAll();
   }

   g_lastLong  = longCondition;
   g_lastShort = shortCondition;

   string cmt = "";
   for(int j = PositionsTotal() - 1; j >= 0; j--)
   {
      if(!posInfo.SelectByIndex(j)) continue;
      if(posInfo.Symbol() != g_sym || posInfo.Magic() != InpMagic) continue;
      double e = posInfo.PriceOpen();
      double sl = posInfo.StopLoss();
      double tp = posInfo.TakeProfit();
      int dir = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
      double risk = (dir > 0) ? (e - sl) : (sl - e);
      double rew  = (dir > 0) ? (tp - e) : (e - tp);
      double rr   = (risk > 0) ? rew / risk : 0;
      cmt = "GainzAlgo Scalper | " + (dir > 0 ? "LONG" : "SHORT") + "\nR:R = 1:" + DoubleToString(rr, 1);
      break;
   }
   Comment(cmt);
}

//+------------------------------------------------------------------+
