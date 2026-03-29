# Breakout Probability Scalper EA (MQ5)

This document explains how `Breakout_Probability_Scalper_EA.mq5` works, how it decides BUY/SELL, and how to configure it.

---

## File

- EA: `Breakout_Probability_Scalper_EA.mq5`

---

## Strategy Overview

The EA is a breakout scalper that combines:

- **Range levels** (recent support and resistance)
- **Breakout probability engine** (UP% vs DOWN%)
- **Threshold filter** (trade only when probability is strong enough)
- **Risk/Reward target** using configurable `RR`

It can place:

- **Pending breakout orders** (`BuyStop`/`SellStop`)  
  or
- **Direct market orders** (`Buy`/`Sell`)

depending on your input setting.

---

## Core Logic

### 1) Range Detection

On each new bar, the EA calculates:

- `resistance` = highest high of last `InpRangePeriod` closed bars
- `support` = lowest low of last `InpRangePeriod` closed bars

These are used as breakout trigger levels and SL anchors.

### 2) Probability Engine

The EA loops through `InpLookbackBars` and computes weighted directional pressure:

- If `high(i) > high(i+1)` => adds weighted score to **UP**
- If `low(i) < low(i+1)` => adds weighted score to **DOWN**

Weights use exponential decay:

- `alpha = 2 / (LookbackBars + 1)`
- `weight = (1 - alpha)^i`

Then:

- `upProb = up / totalWeight`
- `downProb = down / totalWeight`

### 3) Trade Decision by Probability %

- **BUY bias** when:
  - `upProb > InpThreshold`
  - `upProb > downProb`
- **SELL bias** when:
  - `downProb > InpThreshold`
  - `downProb > upProb`

If both fail, no trade is placed.

### 4) Entry, SL, TP

#### BUY setup

- Entry:
  - Pending mode: `price = resistance` (`BuyStop`)
  - Market mode: `price = Ask`
- Stop Loss: `support`
- Take Profit: `price + (price - SL) * InpRR`

#### SELL setup

- Entry:
  - Pending mode: `price = support` (`SellStop`)
  - Market mode: `price = Bid`
- Stop Loss: `resistance`
- Take Profit: `price - (SL - price) * InpRR`

---

## Trade Management Rules

- **New bar only**: main logic runs once per bar (reduces overtrading/noise).
- **One position control**:
  - `InpOnePositionOnly=true` => max one open EA position.
- **One order control**:
  - `InpOneOrderOnly=true` => max one pending breakout order.
  - Old pending stop orders are deleted before placing the latest setup.
- **Magic number isolation**:
  - Only positions/orders with EA magic are counted/managed.

---

## Win/Loss Statistics

In `OnTradeTransaction`, the EA tracks closed deal result:

- `profit > 0` => `wins++`
- `profit < 0` => `losses++`

Profit includes:

- deal profit
- swap
- commission

This gives realistic win/loss counting.

---

## Chart Panel and Lines

### Panel (top-right)

Shows:

- Initial amount and current balance
- WIN / LOSS count
- WinRate %
- UP probability %
- DOWN probability %
- Threshold %
- Money management mode (Fixed Lot / Compounding + risk %)
- Current signal bias (BUY BIAS / SELL BIAS / NEUTRAL)

### Levels

Horizontal lines:

- `RES` (green)
- `SUP` (red)

These update each new bar.

---

## Inputs

### Core

- `InpRangePeriod` (default 20): bars used for support/resistance
- `InpLookbackBars` (default 50): bars used in probability engine
- `InpThreshold` (default 0.65): probability trigger (0..1)
- `InpRR` (default 2.0): risk-reward multiplier
- `InpLotSize` (default 0.10): fixed lot size
- `InpMagic` (default 778899): EA magic number
- `InpInitialAmount` (default 100.0): initial amount reference shown in panel

### Money Management

- `InpUseCompounding` (default false):
  - false => uses fixed lot (`InpLotSize`)
  - true => dynamic lot based on account balance and risk %
- `InpRiskPercent` (default 1.0): risk % per trade when compounding is ON

Compounding lot formula (simplified):

- `riskMoney = AccountBalance * (InpRiskPercent / 100)`
- `moneyPerLotAtSL = (SLDistance / TickSize) * TickValue`
- `lots = riskMoney / moneyPerLotAtSL` (normalized to broker min/max/step)

### Execution

- `InpUsePendingStops` (default true):
  - true => breakout pending stops
  - false => immediate market orders
- `InpSlippagePoints` (default 20): slippage for market execution
- `InpOnePositionOnly` (default true): one open position max
- `InpOneOrderOnly` (default true): one pending order max
- `InpMaxOpenTrades` (default 4): maximum simultaneous open positions

### Visuals

- `InpShowPanel` (default true): show info panel
- `InpShowLevels` (default true): show support/resistance lines

---

## Recommended Starting Settings (Scalping)

- Timeframe: `M1` or `M5`
- `InpRangePeriod`: `20`
- `InpLookbackBars`: `50`
- `InpThreshold`: `0.60` to `0.70`
- `InpRR`: `1.5` to `2.0`
- `InpUsePendingStops`: `true`
- `InpOnePositionOnly`: `true`
- `InpOneOrderOnly`: `true`
- `InpInitialAmount`: `100`
- For compounding:
  - `InpUseCompounding`: `true`
  - `InpRiskPercent`: `0.5` to `1.0`

Tune threshold and RR per symbol volatility.

---

## How to Run in MT5

1. Place `Breakout_Probability_Scalper_EA.mq5` in `MQL5/Experts/`
2. Compile in MetaEditor (F7)
3. Attach EA to chart
4. Enable AutoTrading
5. Open Toolbox -> Experts/Journal for logs
6. For a `$100` test, set Strategy Tester deposit to `100`

---

## Notes

- This EA is breakout-probability driven; it may skip many bars if threshold is not met.
- Pending-stop mode is generally closer to breakout behavior than market mode.
- Backtest and forward test before live use.
- Adjust lot size to your account risk limits.
- If you trade a `$100` account, start with either a small fixed lot or compounding with low risk (0.5% to 1.0%).

