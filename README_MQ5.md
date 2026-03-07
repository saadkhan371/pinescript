# GainzAlgo EA for MetaTrader 5

Expert Advisor for MetaTrader 5, optimized for 1-minute XAUUSD (Gold) scalping. Converted from Pine Script.

---

## Strategy Overview

GainzAlgo EA is a **trend-following scalping strategy** that uses:
- **3 EMAs** (Fast, Slow, Trend) for trend direction
- **RSI** for momentum filter (avoid overbought/oversold entries)
- **ATR** for dynamic Stop Loss and Take Profit

### Core Logic

```
BUY when:  Bullish trend (EMA stack up) + Price above trend + (Crossover OR Pullback OR Bounce) + RSI not overbought
SELL when: Bearish trend (EMA stack down) + Price below trend + (Crossover OR Pullback OR Bounce) + RSI not oversold
```

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
│  EMA Fast(5) │ EMA Slow(13) │ EMA Trend(34) │ RSI(7) │ ATR(14)            │
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
    │ LONG ENTRY SIGNAL?     │  │ SHORT ENTRY SIGNAL?     │
    │ • EMA Crossover        │  │ • EMA Crossunder        │
    │ • OR Pullback + RSI    │  │ • OR Pullback + RSI     │
    │ • OR Price Bounce      │  │ • OR Price Bounce       │
    │ • RSI < Overbought     │  │ • RSI > Oversold        │
    └────────────┬────────────┘  └────────────┬────────────┘
                 │                           │
                 ▼                           ▼
    ┌─────────────────────────┐  ┌─────────────────────────┐
    │  Close Short (if any)   │  │  Close Long (if any)    │
    │  BUY with SL/TP        │  │  SELL with SL/TP        │
    │  SL = Entry - ATR×mult │  │  SL = Entry + ATR×mult  │
    │  TP = Entry + ATR×mult │  │  TP = Entry - ATR×mult  │
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
│ Essential      │    1.8x     │    2.2x     │ Higher TFs, conservative     │
│ Proficient     │    1.2x     │    1.8x     │ Balanced, all timeframes     │
│ Alpha          │    1.0x     │    1.4x     │ M1 scalping, more signals    │
└────────────────┴─────────────┴─────────────┴─────────────────────────────┘
```

---

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
| Preset | Alpha | Essential / Proficient / Alpha |

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
| **Enable Compounding** | false | Lot size grows with balance |
| Fixed Lot Size | 0.01 | Lot when compounding OFF |
| Risk % per trade | 1.0 | Balance % risked when compounding ON |
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
| $100 | OFF | 0.01 | Alpha or Proficient |
| $500+ | OFF or ON | 0.01 / 0.5% | Alpha |
| $1000+ | ON | 1% | Alpha |

**Symbol**: XAUUSD, XAUUSDm  
**Timeframe**: M1 (1 minute)

---

## Features

- **New bar only** – Trades on confirmed bar close (no repainting)
- **BUY/SELL arrows** – Chart signals with TP/SL labels
- **Alerts** – Popup on each trade
- **Auto SL/TP** – Set at entry
- **Compounding** – Optional risk-based lot sizing
- **Trend reversal exit** – Closes on EMA crossover against position

---

## Disclaimer

Backtest before live trading. Past performance does not guarantee future results. Trading involves risk.
