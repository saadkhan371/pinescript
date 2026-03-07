# GainzAlgo EA for MetaTrader 5

MetaTrader 5 Expert Advisor converted from the Pine Script strategy. Optimized for 1-minute XAUUSD (Gold).

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
| **Preset** | Alpha | Essential / Proficient / Alpha |
| **Fast EMA** | 5 | Fast EMA length |
| **Slow EMA** | 13 | Slow EMA length |
| **Trend EMA** | 34 | Trend EMA length |
| **RSI Length** | 7 | RSI period |
| **RSI OB/OS** | 72/28 | Overbought/Oversold levels |
| **ATR Length** | 14 | ATR period for SL/TP |
| **Lot Size** | 0.01 | Trade lot size |
| **Magic** | 123456 | EA identifier |

## Presets

| Preset | SL (ATR) | TP (ATR) |
|--------|----------|----------|
| Essential | 1.8x | 2.2x |
| Proficient | 1.2x | 1.8x |
| Alpha | 1.0x | 1.4x |

## Features

- **New bar only** – Trades on confirmed bar close (no repainting)
- **BUY/SELL signals** – Arrows on chart with TP/SL labels
- **Alerts** – Popup alert on each trade
- **Auto SL/TP** – Stop Loss and Take Profit set at entry

## Recommended

- **Symbol**: XAUUSD, XAUUSDm
- **Timeframe**: M1 (1 minute)
- **Preset**: Alpha for scalping

## Disclaimer

Backtest before live trading. Past performance does not guarantee future results.
