# GainzAlgo Scalper (MT5)

Expert Advisor: **`GainzAlgo_Scalper_EA.mq5`**

A **single-chart, single-symbol** MT5 implementation of the **GainzAlgo** rules from **`GainzAlgo_EA.pine`** / **`GainzAlgo_EA.mq5`**: **fast/medium/trend EMA stack**, **RSI filter**, **pullback / crossover / bounce** entries, **M5 EMA trend confirmation**, **optional candle-direction confirm**, **ATR-based SL/TP** with presets, and **optional exit on fast/slow cross**.

For the **liquidity grab + EMA 20/50/200** playbook, see **`README_GOLD_LIQUIDITY_GRAB_SCALPER.md`** and **`Gold_LiquidityGrab_Scalper_EA.mq5`**.

---

## Relationship to other files

| Artifact | Role |
|----------|------|
| **`GainzAlgo_EA.mq5`** | Full EA: multi-symbol option, chart arrows, dashboard, tester logging. |
| **`GainzAlgo_Scalper_EA.mq5`** | **Scalper build**: same **core signal math** and risk helpers, **one symbol**, lighter UI (chart **Comment** with R:R when in a trade). |
| **`GainzAlgo_EA.pine`** | TradingView reference; scalper EA mirrors the MQ5 `ProcessSymbol` logic. |

Magic number default **`123457`** is **different** from **`GainzAlgo_EA.mq5`** (`123456`) so you can run both on different charts without ticket confusion.

---

## Core logic (closed bar)

On each **new bar** of the working timeframe (**M1** by default, or **current chart**):

- **Buffers** use **shift 1** as the last **closed** bar (`c0`, `o0`, etc.), matching the main GainzAlgo EA.

### Trend

- **Bullish**: `EMA_fast > EMA_slow > EMA_trend` and **`close > EMA_trend`**.  
- **Bearish**: reversed.

### Entry patterns (OR)

**Long**

- **Crossover**: fast crosses above slow.  
- **Pullback**: price above fast EMA, stack bullish, RSI between oversold and `OB - presetRSIThresh`.  
- **Bounce**: prior close below fast EMA, current close above fast EMA, stack bullish.  

**Short**: symmetric.

**RSI gates**

- Long requires **`RSI < overbought`**.  
- Short requires **`RSI > oversold`**.

### Filters

- **M5 trend** (`InpUseM5Trend`): last **`InpM5TrendBars`** closed M5 bars must be on the correct side of **EMA(`InpM5TrendMaPeriod`)** (default **34**).  
- **Candle confirm** (`InpCandleConfirm`): signal bar must **close bullish** (long) or **bearish** (short).  
- **New signal only**: enters when **`longCondition` / `shortCondition`** becomes true vs the **previous stored** state (no churn while the condition stays true).

### Exits

- If **`InpExitOnTrendCross`**: closes positions when **fast/slow cross** against the trade **and** the corresponding **long/short condition** is no longer true (same idea as the full EA).

---

## Presets (`InpPreset`)

Same economic meaning as **`GainzAlgo_EA.mq5`**:

| Preset | Role |
|--------|------|
| **Micro** | Tighter ATR multipliers; larger RSI cushion (`presetRSIThresh`). |
| **Essential / Proficient / Alpha** | Wider or more aggressive ATR bands; different RSI cushion. |

When **`InpUseAtrMult = true`**, **SL/TP distances** use **`presetSL` / `presetTP` × ATR**. When **false**, **`InpSlMult` / `InpTpMult`** apply.

---

## Risk and sizing

- **`InpLotSize`**: base lot.  
- **`InpUseCompounding`**: risk **`InpCompoundingPercent`** of balance vs SL distance (same structure as the full EA).  
- **`InpUseMarginBasedLot`**: caps lot by **free margin** (binary search), falling back to **`InpLotSize`** if needed.  
- **`InpMinSLPoints`**: floor SL distance in **points** (useful on XAUUSD).

---

## Inputs cheat sheet

- **Symbol**: empty = chart symbol.  
- **Timeframe**: **`GS_TF_M1`** (default) or **chart timeframe**.  
- **Max positions**: default **1** (scalper-style).  
- **`InpVerbose`**: log entries to Experts journal.

---

## Installation

1. Copy **`GainzAlgo_Scalper_EA.mq5`** to `MQL5/Experts/`.  
2. Compile.  
3. Attach to **M1** Gold (or your symbol); enable Algo Trading.  
4. Prefer Strategy Tester modes with proper bar execution (not **Math calculations** only).

---

## Risk disclaimer

Automated trading can lose money. Test thoroughly on **your** symbol, spread, and session before going live.
