# Gold Liquidity Grab Scalper (MT5)

Expert Advisor: **`Gold_LiquidityGrab_Scalper_EA.mq5`**

A **1-minute–oriented** XAUUSD-style scalper implementing **trend → pullback → liquidity grab → confirmation candle**, with optional **session windows**, **daily trade cap**, and **pause after two consecutive losses**.

For the **EMA stack + M5 filter** scalper (GainzAlgo-style), see **`README_GAINZALGO_SCALPER.md`** and **`GainzAlgo_Scalper_EA.mq5`**.

---

## Strategy summary

1. **Trend (EMA 20 / 50 / 200)**  
   - **Long**: `EMA20 > EMA50 > EMA200` and **close > EMA200**.  
   - **Short**: reversed stack and **close < EMA200**.  
   - If the stack is not aligned, there is **no** trend bias.

2. **Pullback to EMA zone**  
   On the **signal bar** (last closed bar), the **low** (longs) or **high** (shorts) or **close** must be within **`InpPullbackTouchPts`** of **EMA20 or EMA50** (in **points** × `SYMBOL_POINT`).

3. **Liquidity grab (optional)**  
   - **Long**: `low[1] < low[2]` (sweep under the previous bar’s low).  
   - **Short**: `high[1] > high[2]`.  
   Disable with **`InpRequireLiquidityGrab = false`** for more (noisier) signals.

4. **RSI (`InpRsiPeriod`, default 14)**  
   - **Long**: RSI in **[`InpRsiBuyMin`, `InpRsiBuyMax`]** (default 40–45), and if **`InpRequireRsiTurn`**: **RSI rising** vs prior bar.  
   - **Short**: mirror with **55–60** and RSI **falling**.

5. **Trigger**  
   - **Strong candle**: close in trade direction.  
   - **Engulfing**: body engulfs the **previous** bar’s body (bullish / bearish).  
   Controlled by **`InpAllowStrongCandle`** and **`InpAllowEngulfing`**.

6. **Entries**  
   Evaluated **once per new bar** on **`InpTf`** (default **M1**), using **shift 1** (fully closed bar). **Edge-only**: a new order fires when the full setup turns **true** after being **false** on the prior evaluation (no repeat entries while the setup stays on).

---

## Stops and take profit

- **SL (long)**: below the sweep — **`min(low[1], low[2]) − InpSlExtraPts`** (in points), then enforced to at least **`InpMinSlPts`**.  
- **SL (short)**: symmetric above the sweep high.  
- **`InpMaxSlPts`**: maximum SL distance in points; if **`InpSkipIfSlOutOfBand`**, trades are **skipped** when structure would require a wider stop.  
- **TP**: **`InpRewardRisk ×`** risk distance (default **1:2**).  
- Broker **minimum stop level** is applied when possible.

**Important:** “Pips” on Gold differ by broker (`SYMBOL_POINT`, digits). Tune **`InpMinSlPts` / `InpMaxSlPts`** to your symbol, not a generic Forex pip.

---

## Risk and limits

- **`InpUseRiskPercent`**: position size from **risk %** and SL distance; else **`InpFixedLot`**.  
- **`InpMaxOpenPositions`**: cap simultaneous positions (this symbol + magic).  
- **`InpMaxTradesPerDay`**: cap **entries** per **server calendar day** (`0` = unlimited).  
- **`InpStopAfterTwoLosses`**: after **two closed losses in a row** (net P/L including commission/swap), **no new entries** until **`InpResetConsecDaily`** rolls the count at **server midnight**.

---

## Session filter (server time)

If **`InpUseSessionFilter = true`**:

- **`InpUseWinOverlap`**: only **`[InpOverlapStart, InpOverlapEnd)`** hours.  
- Else **London** and/or **NY** windows are **OR**’d: trade if the hour falls in **any** enabled window.

Adjust hours to your **broker server** (London/NY are not UTC-universal).

---

## Installation

1. Copy **`Gold_LiquidityGrab_Scalper_EA.mq5`** into `MQL5/Experts/`.  
2. Compile in MetaEditor.  
3. Attach to **M1** (recommended) on your Gold symbol; set **`InpSymbol`** if it differs from the chart.  
4. Use a tester mode with real bar progression (**Every tick** or **OHLC**), not **Math calculations**.

---

## Risk disclaimer

Futures/CFD/FX trading is risky. This EA is educational; **backtest and forward-test** on your broker before live use.
