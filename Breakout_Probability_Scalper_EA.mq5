//+------------------------------------------------------------------+
//|                                      Breakout_Probability_Scalper_EA.mq5 |
//|                       Breakout Probability Scalper (Panel + Orders)      |
//+------------------------------------------------------------------+
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//==== INPUTS ====
input group "=== Core ==="
input int      InpRangePeriod      = 20;      // Range period for support/resistance
input int      InpLookbackBars     = 50;      // Lookback bars for probability engine
input double   InpThreshold        = 0.65;    // Breakout probability threshold (0..1)
input double   InpRR               = 2.0;     // Risk:Reward multiplier
input double   InpLotSize          = 0.10;    // Fixed lot size
input int      InpMagic            = 778899;  // Magic number
input double   InpInitialAmount    = 100.0;   // Initial amount reference ($)

input group "=== Money Management ==="
input bool     InpUseCompounding   = false;   // Compounding lot sizing
input double   InpRiskPercent      = 1.0;     // Risk % per trade when compounding is ON

input group "=== Execution ==="
input bool     InpUsePendingStops  = true;    // True=BuyStop/SellStop, False=market entries
input int      InpSlippagePoints   = 20;      // Slippage for market execution
input bool     InpOnePositionOnly  = true;    // Allow max one position at a time
input bool     InpOneOrderOnly     = true;    // Allow max one pending order at a time
input int      InpMaxOpenTrades    = 4;       // Maximum simultaneous open positions

input group "=== Visuals ==="
input bool     InpShowPanel        = true;    // Show stats/probability panel
input bool     InpShowLevels       = true;    // Draw support/resistance lines

//==== GLOBAL STATS ====
int       g_wins = 0;
int       g_losses = 0;
datetime  g_lastBarTime = 0;
double    g_startBalance = 0.0;

string PANEL_NAME = "BPS_StatsPanel";
string RES_NAME   = "BPS_RES";
string SUP_NAME   = "BPS_SUP";

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
double GetHighest(const int bars, const int shift_start = 1)
{
   double high = iHigh(_Symbol, _Period, shift_start);
   for(int i = shift_start + 1; i < shift_start + bars; i++)
   {
      double h = iHigh(_Symbol, _Period, i);
      if(h > high) high = h;
   }
   return high;
}

double GetLowest(const int bars, const int shift_start = 1)
{
   double low = iLow(_Symbol, _Period, shift_start);
   for(int i = shift_start + 1; i < shift_start + bars; i++)
   {
      double l = iLow(_Symbol, _Period, i);
      if(l < low) low = l;
   }
   return low;
}

int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

int CountOwnPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP) count++;
   }
   return count;
}

void CancelOwnPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((int)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_SELL_STOP)
         trade.OrderDelete(ticket);
   }
}

double NormalizeLot(const double rawLot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   double lot = rawLot;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   lot = MathFloor(lot / step) * step;
   int lotDigits = 2;
   if(step == 0.1) lotDigits = 1;
   else if(step == 0.01) lotDigits = 2;
   else if(step == 0.001) lotDigits = 3;
   else if(step == 0.0001) lotDigits = 4;
   return NormalizeDouble(lot, lotDigits);
}

double CalculateLotSize(const double entryPrice, const double slPrice)
{
   if(!InpUseCompounding)
      return NormalizeLot(InpLotSize);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);
   if(riskMoney <= 0.0) return NormalizeLot(InpLotSize);

   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0.0) return NormalizeLot(InpLotSize);

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0) return NormalizeLot(InpLotSize);

   double moneyPerLotAtSL = (slDistance / tickSize) * tickValue;
   if(moneyPerLotAtSL <= 0.0) return NormalizeLot(InpLotSize);

   double lots = riskMoney / moneyPerLotAtSL;
   return NormalizeLot(lots);
}

//+------------------------------------------------------------------+
//| Probability Engine                                               |
//+------------------------------------------------------------------+
void CalculateProbability(double &upProb, double &downProb)
{
   double up = 0.0, down = 0.0, total = 0.0;
   double alpha = 2.0 / (InpLookbackBars + 1.0);

   for(int i = 1; i < InpLookbackBars; i++)
   {
      double weight = MathPow((1.0 - alpha), i);

      double high = iHigh(_Symbol, _Period, i);
      double low = iLow(_Symbol, _Period, i);
      double prevHigh = iHigh(_Symbol, _Period, i + 1);
      double prevLow = iLow(_Symbol, _Period, i + 1);

      if(high > prevHigh) up += weight;
      if(low < prevLow) down += weight;

      total += weight;
   }

   if(total <= 0.0)
   {
      upProb = 0.5;
      downProb = 0.5;
      return;
   }

   upProb = up / total;
   downProb = down / total;
}

//+------------------------------------------------------------------+
//| Visuals                                                          |
//+------------------------------------------------------------------+
void DrawPanel(const double upProb, const double downProb)
{
   if(!InpShowPanel) return;

   double total = (double)(g_wins + g_losses);
   double winrate = (total > 0.0) ? ((double)g_wins / total) * 100.0 : 0.0;

   string signal = "NEUTRAL";
   if(upProb > InpThreshold && upProb > downProb) signal = "BUY BIAS";
   if(downProb > InpThreshold && downProb > upProb) signal = "SELL BIAS";

   string text =
      "Breakout Probability Scalper\n" +
      "Initial: $" + DoubleToString(InpInitialAmount, 2) + " | Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n" +
      "WIN: " + IntegerToString(g_wins) + "   LOSS: " + IntegerToString(g_losses) + "\n" +
      "WinRate: " + DoubleToString(winrate, 2) + "%\n\n" +
      "UP: " + DoubleToString(upProb * 100.0, 2) + "%\n" +
      "DOWN: " + DoubleToString(downProb * 100.0, 2) + "%\n" +
      "Threshold: " + DoubleToString(InpThreshold * 100.0, 1) + "%\n" +
      "MM: " + (InpUseCompounding ? "Compounding " + DoubleToString(InpRiskPercent, 2) + "%" : "Fixed Lot " + DoubleToString(InpLotSize, 2)) + "\n" +
      "Signal: " + signal;

   if(ObjectFind(0, PANEL_NAME) < 0)
   {
      ObjectCreate(0, PANEL_NAME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PANEL_NAME, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, PANEL_NAME, OBJPROP_XDISTANCE, 16);
      ObjectSetInteger(0, PANEL_NAME, OBJPROP_YDISTANCE, 20);
   }

   ObjectSetString(0, PANEL_NAME, OBJPROP_TEXT, text);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_FONTSIZE, 10);
}

void DrawLevels(const double resistance, const double support)
{
   if(!InpShowLevels) return;

   if(ObjectFind(0, RES_NAME) < 0)
      ObjectCreate(0, RES_NAME, OBJ_HLINE, 0, 0, resistance);
   if(ObjectFind(0, SUP_NAME) < 0)
      ObjectCreate(0, SUP_NAME, OBJ_HLINE, 0, 0, support);

   ObjectSetDouble(0, RES_NAME, OBJPROP_PRICE, resistance);
   ObjectSetDouble(0, SUP_NAME, OBJPROP_PRICE, support);
   ObjectSetInteger(0, RES_NAME, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, SUP_NAME, OBJPROP_COLOR, clrTomato);
}

//+------------------------------------------------------------------+
//| Trading                                                          |
//+------------------------------------------------------------------+
void TradeLogic(const double resistance, const double support, const double upProb, const double downProb)
{
   int openPositions = CountOwnPositions();
   if(InpOnePositionOnly && openPositions > 0)
      return;
   if(openPositions >= InpMaxOpenTrades)
      return;
   if(InpOneOrderOnly && CountOwnPendingOrders() > 0)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // If both pass, pick stronger side only.
   bool buySignal = (upProb > InpThreshold && upProb > downProb);
   bool sellSignal = (downProb > InpThreshold && downProb > upProb);
   if(!buySignal && !sellSignal) return;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   if(buySignal)
   {
      double price = InpUsePendingStops ? resistance : ask;
      double sl = support;
      double tp = price + (price - sl) * InpRR;
      double lots = CalculateLotSize(price, sl);

      price = NormalizeDouble(price, digits);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      // Guard: ensure valid directional prices.
      if(!(sl < price && tp > price)) return;

      bool ok = InpUsePendingStops
                ? trade.BuyStop(lots, price, _Symbol, sl, tp)
                : trade.Buy(lots, _Symbol, ask, sl, tp, "BPS Buy");
      if(ok) Print("BUY signal placed | UpProb=", DoubleToString(upProb * 100.0, 2), "% | lots=", DoubleToString(lots, 2));
   }
   else if(sellSignal)
   {
      double price = InpUsePendingStops ? support : bid;
      double sl = resistance;
      double tp = price - (sl - price) * InpRR;
      double lots = CalculateLotSize(price, sl);

      price = NormalizeDouble(price, digits);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      if(!(sl > price && tp < price)) return;

      bool ok = InpUsePendingStops
                ? trade.SellStop(lots, price, _Symbol, sl, tp)
                : trade.Sell(lots, _Symbol, bid, sl, tp, "BPS Sell");
      if(ok) Print("SELL signal placed | DownProb=", DoubleToString(downProb * 100.0, 2), "% | lots=", DoubleToString(lots, 2));
   }
}

//+------------------------------------------------------------------+
//| Event handlers                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRangePeriod < 2 || InpLookbackBars < 5 || InpThreshold <= 0.0 || InpThreshold >= 1.0)
   {
      Print("Invalid inputs: check RangePeriod, LookbackBars, Threshold.");
      return INIT_PARAMETERS_INCORRECT;
   }
   g_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(g_startBalance <= 0.0) g_startBalance = InpInitialAmount;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectDelete(0, PANEL_NAME);
   ObjectDelete(0, RES_NAME);
   ObjectDelete(0, SUP_NAME);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.symbol != _Symbol) return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT) return; // Count only closed deals.

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   if(profit > 0.0) g_wins++;
   else if(profit < 0.0) g_losses++;
}

void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   // Use closed bars only for stable levels/probability.
   double resistance = GetHighest(InpRangePeriod, 1);
   double support = GetLowest(InpRangePeriod, 1);

   if(resistance <= support) return;

   double upProb, downProb;
   CalculateProbability(upProb, downProb);

   DrawPanel(upProb, downProb);
   DrawLevels(resistance, support);

   if(InpOneOrderOnly) CancelOwnPendingOrders(); // Keep only latest setup
   TradeLogic(resistance, support, upProb, downProb);
}

