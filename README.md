# GainzAlgo EA - Pine Script Expert Advisor

A TradingView Pine Script v5 strategy inspired by the GainzAlgo V2 concept. Works across stocks, crypto, and forex on all timeframes.

## Strategy Logic

- **Trend-following**: 3 EMAs (Fast, Slow, Trend) define direction; price must be on the correct side of the trend EMA.
- **Entry triggers** (any one): EMA crossover, pullback with RSI in zone, or price bounce off Fast EMA.
- **Filters**: RSI not overbought on longs, not oversold on shorts.
- **TP ≥ SL**: Take-profit distance is always at least as large as stop-loss (better R:R for higher win-rate targets).
- **No repainting**: Signals use confirmed bar closes only (no look-ahead).

**Long:** Bullish EMA stack + price above trend + (crossover OR pullback OR bounce) + RSI &lt; overbought.  
**Short:** Bearish EMA stack + price below trend + (crossunder OR pullback OR bounce) + RSI &gt; oversold.

## Features

- **4 Presets** (Micro, Essential, Proficient, Alpha) – TP/SL and RSI thresholds
- **Stop Loss & Take Profit** – ATR-based; TP ≥ SL in all presets
- **No repainting** – signals on confirmed bar closes only
- **Entry/exit signals** – trend-based with EMA + RSI
- **Alerts** – for TradingView alerts and notifications

## Setup

1. Open [TradingView](https://www.tradingview.com) (free account works)
2. Open the Pine Editor (bottom of chart)
3. Copy the contents of `GainzAlgo_EA.pine` into the editor
4. Click **Add to Chart**

## Presets

| Preset     | Best For              | SL (ATR) | TP (ATR) | Notes        |
|------------|------------------------|----------|----------|--------------|
| **Micro**  | $100 scalping, small   | 0.8x     | 1.0x     | Tight, more signals |
| **Essential** | Higher TFs, conservative | 1.8x  | 2.2x     | Wider SL, fewer stop-outs |
| **Proficient** | Balanced            | 1.2x  | 1.8x     | Moderate     |
| **Alpha**  | M1 scalping, aggressive | 1.0x  | 1.4x     | More signals |

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
