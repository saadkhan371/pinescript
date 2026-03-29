# GainzAlgo EA for MetaTrader 5

MetaTrader 5 Expert Advisor converted from the Pine Script strategy. Optimized for 1-minute XAUUSD (Gold). Supports a **75%+ win-rate style** via M5 trend filter, new-signal-only entries, and max 1 position per direction.

## Strategy logic (same as Pine)

- **Trend**: 3 EMAs (Fast, Slow, Trend); long when bullish stack + price above trend, short when bearish stack + price below trend.
- **Entry**: Crossover, pullback + RSI, or bounce; RSI filter (not overbought on long, not oversold on short).
- **TP ≥ SL**: Take-profit distance ≥ stop-loss. **New-signal only**: open only when condition *just* became true. **Max 1 position per direction** (no stacking).
- **M5 trend filter**: Long only when M5 close > M5 MA(34) for N bars; short only when M5 close < M5 MA(34) for N bars.
- **Candle confirmation**: Long only if bar close > open; short only if bar close < open.

## Installation

1. Copy `GainzAlgo_EA.mq5` to your MetaTrader 5 `Experts` folder:
   - **Windows**: `C:\Users\[YourName]\AppData\Roaming\MetaQuotes\Terminal\[ID]\MQL5\Experts\`
   - **Mac**: `~/Library/Application Support/MetaQuotes/Terminal/[ID]/MQL5/Experts/`

2. Open MetaTrader 5 → **File** → **Open Data Folder** → `MQL5` → `Experts`

3. Compile the EA in MetaEditor (F7) or let MT5 auto-compile on first attach

4. Attach the EA to an XAUUSD (or any symbol) chart

## Inputs

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Preset** | Micro | Micro / Essential / Proficient / Alpha |
| **Fast EMA** | 5 | Fast EMA length |
| **Slow EMA** | 13 | Slow EMA length |
| **Trend EMA** | 34 | Trend EMA length |
| **RSI Length** | 7 | RSI period |
| **RSI OB/OS** | 72/28 | Overbought/Oversold levels |
| **ATR Length** | 14 | ATR period for SL/TP |
| **Timeframe** | M1 only | M1 or current chart |
| **Use M5 trend** | true | Only trade with M5 trend (75% strategy) |
| **M5 trend bars** | 2 | Require N M5 bars in trend |
| **Candle confirm** | true | Bar close in trade direction |
| **Min SL (points)** | 0 | Min SL distance (e.g. 50 for XAUUSD) |
| **Max positions** | 1 | Max per direction (1 = no stacking) |
| **Lot Size** | 0.01 | Trade lot size |
| **Magic** | 123456 | EA identifier |

## Presets

| Preset | SL (ATR) | TP (ATR) |
|--------|----------|----------|
| Micro | 0.8x | 1.0x |
| Essential | 1.8x | 2.2x |
| Proficient | 1.2x | 1.8x |
| Alpha | 1.0x | 1.4x |

## Features

- **New bar only** – Trades on confirmed bar close (no repainting)
- **New-signal only** – Opens when condition just became true (no entry every bar)
- **Max 1 position per direction** – No stacking (75% strategy)
- **M5 trend filter** – Long only when M5 bullish, short when M5 bearish
- **Candle confirmation** – Reduces false breakouts
- **TP ≥ SL** – Better risk:reward
- **BUY/SELL signals** – Arrows on chart with TP/SL labels
- **Alerts** – Popup alert on each trade
- **Auto SL/TP** – Stop Loss and Take Profit set at entry

## Recommended

- **Symbol**: XAUUSD, XAUUSDm
- **Timeframe**: M1 (1 minute)
- **Preset**: Micro or Essential for higher win-rate style; Alpha for more signals
- **Max positions**: 1; **Use M5 trend**: ON; **Candle confirm**: ON

## Disclaimer

Backtest before live trading. Past performance does not guarantee future results.
