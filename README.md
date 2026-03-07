# GainzAlgo EA - Pine Script Expert Advisor

A TradingView Pine Script v5 strategy inspired by the GainzAlgo V2 concept. Works across stocks, crypto, and forex on all timeframes.

## Features

- **3 Presets** (Essential, Proficient, Alpha) – similar to GainzAlgo V2
- **Stop Loss & Take Profit** – ATR-based levels set at entry
- **No repainting** – signals use confirmed bar closes only
- **Entry/exit signals** – trend-based with EMA + RSI
- **Alerts** – for TradingView alerts and notifications

## Setup

1. Open [TradingView](https://www.tradingview.com) (free account works)
2. Open the Pine Editor (bottom of chart)
3. Copy the contents of `GainzAlgo_EA.pine` into the editor
4. Click **Add to Chart**

## Presets

| Preset | Best For | SL (ATR) | TP (ATR) | Signals |
|--------|----------|----------|----------|---------|
| **Essential** | Higher TFs, conservative | 1.5x | 2.5x | Fewer |
| **Proficient** | Balanced | 1.0x | 2.0x | Moderate |
| **Alpha** | Lower TFs, aggressive | 0.8x | 1.5x | More |

## Alerts

1. Right-click the chart → **Add alert**
2. Condition: **GainzAlgo EA**
3. Choose **Long Entry** or **Short Entry**
4. Set notifications (email, webhook, etc.)

## Customization

- **Indicators**: EMA lengths, RSI, overbought/oversold
- **Risk Management**: ATR multipliers, risk %
- **Display**: Toggle EMAs, signals, SL/TP lines

## Disclaimer

This is an original implementation for educational use. Backtest before live trading. Past performance does not guarantee future results.
