# GainzAlgo EA for MetaTrader 5

Expert Advisor for MetaTrader 5, optimized for 1-minute XAUUSD (Gold) scalping. Converted from Pine Script. Supports a **75%+ win-rate style** via strict filters and one position per direction.

---

## Strategy Overview

GainzAlgo EA is a **trend-following scalping strategy** that uses:
- **3 EMAs** (Fast, Slow, Trend) for trend direction
- **RSI** for momentum filter (avoid overbought/oversold entries)
- **ATR** for dynamic Stop Loss and Take Profit (TP ≥ SL)
- **M5 trend filter** – only long when M5 is bullish, only short when M5 is bearish
- **New-signal only** – open only when the condition *just* became true (no stacking on every bar)
- **Max 1 position per direction** – no stacking longs or shorts

### Core Logic

```
BUY when:  Bullish trend (EMA stack up) + Price above trend + (Crossover OR Pullback OR Bounce) + RSI not overbought
           + M5 bullish (close > M5 MA(34) for N bars) + Candle confirm (close > open) + NEW signal (was false last bar)
SELL when: Bearish trend (EMA stack down) + Price below trend + (Crossover OR Pullback OR Bounce) + RSI not oversold
           + M5 bearish (close < M5 MA(34) for N bars) + Candle confirm (close < open) + NEW signal (was false last bar)
```

Exits: SL/TP at entry, or trend-reversal exit (EMA crossover against position).

---

## Strategy Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GAINZALGO EA - STRATEGY FLOW                         │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌──────────────┐
                              │   OnTick()   │
                              └──────┬───────┘
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │  New Bar Detected?     │
                        │  (No Repainting)       │
                        └────────┬───────────────┘
                                 │ No
                                 ├──────────────────► Skip (wait)
                                 │ Yes
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     INDICATOR CALCULATION (Bar 1 = Closed)                 │
│  EMA Fast(5) │ EMA Slow(13) │ EMA Trend(34) │ RSI(7) │ ATR(14) │ M5 MA(34) │
└────────────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         TREND DETECTION                                    │
│  Bullish: EMA Fast > EMA Slow > EMA Trend                                  │
│  Bearish: EMA Fast < EMA Slow < EMA Trend                                 │
└────────────────────────────────────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
         ┌──────────────────┐      ┌──────────────────┐
         │  BULLISH TREND?   │      │  BEARISH TREND?   │
         │  Price > Trend   │      │  Price < Trend    │
         └────────┬─────────┘      └────────┬───────────┘
                  │                        │
                  ▼                        ▼
    ┌─────────────────────────┐  ┌─────────────────────────┐
    │ LONG ENTRY SIGNAL?       │  │ SHORT ENTRY SIGNAL?     │
    │ • EMA Crossover          │  │ • EMA Crossunder        │
    │ • OR Pullback + RSI      │  │ • OR Pullback + RSI     │
    │ • OR Price Bounce        │  │ • OR Price Bounce       │
    │ • RSI < Overbought       │  │ • RSI > Oversold        │
    └────────────┬────────────┘  └────────────┬────────────┘
                 │                           │
                 ▼                           ▼
    ┌─────────────────────────┐  ┌─────────────────────────┐
    │ 75% FILTERS (optional)   │  │ 75% FILTERS (optional)   │
    │ • M5 bullish (N bars)     │  │ • M5 bearish (N bars)    │
    │ • Candle: close > open    │  │ • Candle: close < open   │
    │ • NEW signal (not prev)   │  │ • NEW signal (not prev)  │
    └────────────┬────────────┘  └────────────┬────────────┘
                 │                           │
                 ▼                           ▼
    ┌─────────────────────────┐  ┌─────────────────────────┐
    │  Close Short (if any)    │  │  Close Long (if any)     │
    │  BUY (max 1 long)       │  │  SELL (max 1 short)      │
    │  SL = Entry - ATR×mult  │  │  SL = Entry + ATR×mult   │
    │  TP ≥ SL distance       │  │  TP ≥ SL distance        │
    │  Min SL points (if set)  │  │  Min SL points (if set)  │
    └─────────────────────────┘  └─────────────────────────┘
                 │                           │
                 └───────────────┬───────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │  Trend Reversal Exit?  │
                    │  (Optional - SL/TP    │
                    │   handles most exits)  │
                    └────────────────────────┘
```

---

## Entry Conditions Diagram

```
                    BUY (LONG) ENTRY
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │   EMA Fast ──────► EMA Slow ──────► EMA Trend   │  ← Bullish stack
    │        \                \                \      │
    │         \                \                \    │
    │   Price (Close) > EMA Trend                   │  ← Price above trend
    │                                                 │
    │   TRIGGER (any one):                            │
    │   • Crossover:  EMA Fast crosses above Slow     │
    │   • Pullback:   Price > Fast EMA, RSI 28-64     │
    │   • Bounce:     Close crosses above Fast EMA   │
    │                                                 │
    │   FILTER: RSI < 72 (not overbought)             │
    │                                                 │
    └─────────────────────────────────────────────────┘

                    SELL (SHORT) ENTRY
    ┌─────────────────────────────────────────────────┐
    │                                                 │
    │   EMA Trend ──────► EMA Slow ──────► EMA Fast   │  ← Bearish stack
    │        /                /                /     │
    │   Price (Close) < EMA Trend                   │  ← Price below trend
    │                                                 │
    │   TRIGGER (any one):                            │
    │   • Crossunder: EMA Fast crosses below Slow     │
    │   • Pullback:   Price < Fast EMA, RSI 36-72     │
    │   • Bounce:     Close crosses below Fast EMA   │
    │                                                 │
    │   FILTER: RSI > 28 (not oversold)               │
    │                                                 │
    └─────────────────────────────────────────────────┘
```

---

## Presets Comparison

```
┌────────────────┬─────────────┬─────────────┬─────────────────────────────┐
│    PRESET      │  SL (ATR)   │  TP (ATR)   │         BEST FOR             │
├────────────────┼─────────────┼─────────────┼─────────────────────────────┤
│ Micro          │    0.8x     │    1.0x     │ $100, small profit, scalping │
│ Essential      │    1.8x     │    2.2x     │ Higher TFs, conservative     │
│ Proficient     │    1.2x     │    1.8x     │ Balanced, all timeframes     │
│ Alpha          │    1.0x     │    1.4x     │ M1 scalping, more signals    │
└────────────────┴─────────────┴─────────────┴─────────────────────────────┘
```

---

## Margin-Based Lot Sizing

When **Auto lot to fit margin** is ON, the EA calculates the maximum lot size that fits within 90% of your free margin. This helps avoid "not enough money" errors on small accounts.

**Note:** If your broker's minimum lot (e.g. 0.01) requires more margin than you have, the EA won't place trades. For $100 accounts with XAUUSD, consider a broker that offers **micro lots (0.001)** or **cent accounts**.

## Troubleshooting: "symbol XAUUSDm does not exist" / "Error creating indicator handles"

If you see **"symbol XAUUSDm does not exist"** or **"cannot load indicator ... (XAUUSDm) [4801]"**:
- **Cause**: Strategy Tester is in **"Math calculations"** mode, which does not load history or symbol data.
- **Fix**: In Strategy Tester, set **Model** to **"Open prices only"** or **"Every tick"** (not "Math calculations"). Then run the test again.

## Troubleshooting: IO Error Code 49 (233)

If you see "IO operation failed with code 49 (233)":
- **Cause**: Often from too many chart objects or arrow code conflict
- **Fix**: EA now uses arrow codes 241/242 and auto-cleans old objects
- **Manual**: Remove EA from chart and re-attach to clear objects

## Troubleshooting: "Not enough money" (10019) with $100 and 0.01 lot

- **Cause:** Strategy Tester is using **leverage 1:1**. For 0.01 lot EURUSDm the required margin is ~\$1,170, so $100 is insufficient.
- **Fix:** Set the tester **Leverage** to **Unlimited** or **1:100** (or 1:500). Then 0.01 lot needs ~\$12–30 margin and orders will open. (In MT5 the leverage may be in the tester panel, agent config, or account settings.)
- The EA now skips sending orders when margin is insufficient and prints once: *"Set Strategy Tester LEVERAGE to Unlimited or 1:100"*.

## Troubleshooting: No trades / balance not changing

- **Debug mode (default ON)** – In EA inputs **Debug mode** = ON: full logs (signals, order open/fail) and **profit per closed trade** in the Journal (`[GainzAlgo] Trade closed | BUY/SELL symbol | Profit: X.XX | Balance: Y.YY`). Set **Debug mode** = OFF for live trading (errors only). Check the **Journal** tab for `[GainzAlgo] Signal BUY/SELL`, `>>> BUY/SELL opened`, and trade-closed lines. If you see no signals, try a **longer test period** or preset **Alpha** / **Micro** for more entries.
- **EURUSDm / XAUUSDm** – Use **EURUSDm** for $100 (low margin). **XAUUSDm** needs ~$500+ for 0.001 lot.

## Troubleshooting: No Arrows/Signals Showing

- **Use M1 chart** – For best visibility, open the symbol on **M1 timeframe** and attach the EA
- **Enable AutoTrading** – Press Ctrl+E or click the AutoTrading button (must be green)
- **Show signals** – Ensure "Show BUY/SELL Arrows" is ON in EA inputs
- **Check Experts tab** – View → Toolbox → Experts for init message and any errors
- **Strategy Tester** – Enable "Visual mode" to see the chart during backtest

## Installation

1. Copy `GainzAlgo_EA.mq5` to your MT5 Experts folder:
   - **Windows**: `C:\Users\[Name]\AppData\Roaming\MetaQuotes\Terminal\[ID]\MQL5\Experts\`
   - **Mac**: `~/Library/Application Support/MetaQuotes/Terminal/[ID]/MQL5/Experts/`

2. Open MetaTrader 5 → **File** → **Open Data Folder** → `MQL5` → `Experts`

3. Compile in MetaEditor (F7) or let MT5 auto-compile on first attach

4. Attach EA to chart → Enable **AutoTrading** (Ctrl+E)

---

## Input Parameters

### Preset
| Parameter | Default | Description |
|-----------|---------|-------------|
| Preset | Micro | Micro / Essential / Proficient / Alpha |

### Timeframe
| Parameter | Default | Description |
|-----------|---------|-------------|
| Timeframe mode | M1 only | **M1 only** – Always use 1-minute (recommended for scalping) |
| | | **Current chart** – Use the chart's timeframe |
| **Use M5 trend** | true | Only long when M5 bullish, short when M5 bearish (75% strategy) |
| **M5 trend bars** | 2 | Require N consecutive M5 bars in trend (2 = confirmation) |
| **Candle confirm** | true | Bar must close in trade direction (close > open long, close < open short) |
| **Min SL (points)** | 0 | Minimum SL distance in points (0 = off; e.g. 50 for XAUUSD to avoid noise) |

### Indicators
| Parameter | Default | Description |
|-----------|---------|-------------|
| Fast EMA Length | 5 | Fast EMA period |
| Slow EMA Length | 13 | Slow EMA period |
| Trend EMA Length | 34 | Trend EMA period |
| RSI Length | 7 | RSI period |
| RSI Overbought | 72 | RSI upper threshold |
| RSI Oversold | 28 | RSI lower threshold |
| ATR Length | 14 | ATR period for SL/TP |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| Use ATR for SL/TP | true | Use preset ATR multipliers |
| Take Profit (x ATR) | 2.0 | Manual TP when ATR off |
| Stop Loss (x ATR) | 1.0 | Manual SL when ATR off |
| **Auto lot to fit margin** | true | Reduces lot to fit margin (avoids "not enough money") |
| **Max positions** | 1 | Max open positions per direction (1 = 75% strategy, no stacking) |
| Enable Compounding | false | Lot size grows with balance |
| Fixed Lot Size | 0.001 | Max lot (or fixed when margin-based) |
| Risk % per trade | 0.5 | Balance % when compounding ON |
| Magic Number | 123456 | EA identifier |

### Display
| Parameter | Default | Description |
|-----------|---------|-------------|
| Show BUY/SELL Arrows | true | Chart arrows with TP/SL labels |

---

## Compounding

| Mode | Behavior |
|------|----------|
| **OFF** | Fixed lot size (e.g. 0.01) every trade |
| **ON** | Lot = (Balance × Risk%) / (SL distance value) — grows/shrinks with account |

**Example (Compounding ON, 1% risk, $100 balance):**
- Risk per trade = $1
- SL distance = 20 pips → Lot sized so 20-pip loss ≈ $1

---

## Recommended Settings

| Account | Compounding | Lot Size | Preset |
|---------|-------------|----------|--------|
| **$100** | OFF | **0.001** | Micro (small profit) |
| $500+ | OFF or ON | 0.01 / 0.5% | Alpha |
| $1000+ | ON | 1% | Alpha |

**Default setup for XAUUSDm $100 / M1 (MetaTrader 5):**
- Symbol: XAUUSDm
- Timeframe: M1 only
- Lot: 0.001 (margin-based ON)
- Initial Deposit: 100
- Max positions: **1** (75% strategy)
- Use M5 trend: ON, M5 trend bars: 2, Candle confirm: ON
- Min SL points: 0 (or 50–80 for XAUUSD if quick SL hits)
- Compounding: OFF

---

## Symbol

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Symbol** | XAUUSDm | Single symbol (XAUUSDm in MetaTrader 5 for Gold) |
| **Trade multiple symbols** | false | When ON, trade all symbols in list |
| **Symbol List** | XAUUSDm | Comma-separated (used when Multi ON) |

**XAUUSDm + $100 setup:** Symbol = **XAUUSDm** (MetaTrader 5 Gold). Initial Deposit = **100**. Use 0.001 lot; margin-based ON. *Note: Many brokers need ~$500+ margin for 0.001 lot – use a cent account or broker with micro lots if $100 is not enough.*

## Strategy Tester

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Initial Deposit** | 100 | Reference value – set Strategy Tester **Deposit** to match |

**XAUUSDm $100:** In Strategy Tester set **Symbol** to **XAUUSDm**, **Deposit** to **100**, **Timeframe** M1. Use mode **"Open prices only"** or **"Every tick"**. Preset **Micro**, 0.001 lot.

**EURUSDm $100 / 0.01 lot – "not enough money":** Your tester is using **leverage 1:1**, so 0.01 lot needs ~\$1,170 margin and \$100 is not enough. Set the Strategy Tester **Leverage** to **Unlimited** or **1:100** (in the tester settings or in the testing agent configuration). Then 0.01 lot will need ~\$12–30 margin and orders will open.

## Strategy Tester Logs

When running in Strategy Tester, the EA logs to the **Journal** tab:
- **Debug mode ON:** `[GainzAlgo] Signal BUY/SELL`, `>>> BUY/SELL opened/failed`, and **`[GainzAlgo] Trade closed | ... | Profit: X.XX | Balance: Y.YY`** for each closed position
- **OnDeinit:** Total Investment, Final Balance, Total Profit/Loss (currency and %)

## Features

- **New bar only** – Trades on confirmed bar close (no repainting)
- **New-signal only** – Opens only when condition *just* became true (no entry every bar)
- **Max 1 position per direction** – No stacking longs or shorts (75% strategy)
- **M5 trend filter** – Long only when M5 bullish, short only when M5 bearish (configurable N-bar confirmation)
- **Candle confirmation** – Signal bar must close in trade direction (reduces false breakouts)
- **TP ≥ SL** – Take-profit distance ≥ stop-loss (better R:R)
- **Min SL (points)** – Optional minimum SL distance to avoid noise stop-outs (e.g. XAUUSD)
- **BUY/SELL arrows** – Chart signals with TP/SL labels
- **Alerts** – Popup on each trade
- **Auto SL/TP** – Set at entry
- **Compounding** – Optional risk-based lot sizing
- **Trend reversal exit** – Closes on EMA crossover against position

---

## Disclaimer

Backtest before live trading. Past performance does not guarantee future results. Trading involves risk.
