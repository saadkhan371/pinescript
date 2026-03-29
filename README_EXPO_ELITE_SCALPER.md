# Expo Elite Scalper EA (MT5)

Expert Advisor: **`Expo_Elite_Scalper_EA.mq5`**

Multi-symbol scalper that scores **buy** and **sell** setups using an **M15 EMA filter**, **M5 range breakout context**, and **M1 candle body size**, then places market orders with **risk-based sizing** and a fixed **reward-to-risk multiple**.

This implementation replaces the sketch you had (MQL4-style APIs, per-tick leaks, and simplified lot math) with **MQL5-compliant** code: proper **handles**, **closed-bar logic** where noted, **tick-value lot sizing**, **spread and session filters**, and optional **CSV logging**.

---

## Files

| File | Purpose |
|------|---------|
| `Expo_Elite_Scalper_EA.mq5` | EA source |
| `README_EXPO_ELITE_SCALPER.md` | This document |

---

## Traded symbols

Default list: **`EURUSD,GBPUSD,XAUUSD,USDJPY`** (`InpSymbolList`).

- Use your broker’s **exact names** (e.g. `EURUSDm`, `XAUUSDm`).
- Symbols are added to **Market Watch** on init via `SymbolSelect`.

---

## Session and spread

- **`InpSessionStartHour` / `InpSessionEndHour`**: **Server time** (inclusive on both ends in the code). Adjust to your broker’s server, not necessarily UTC or “London time”.
- **`InpMaxSpreadPoints`**: If **> 0**, skips a symbol when `(Ask − Bid) / SYMBOL_POINT` exceeds this value. Set **0** to disable.

---

## Signal model (score, not a true “probability”)

The EA adds **points** (max about **80** per side). The input **`InpProbabilityThreshold`** is a **minimum score** (your original used **65**). The on-chart label says **“score”** for clarity; it is **not** a statistical probability.

### Buy score (+30 +30 +20 max)

1. **+30** — M1 **closed** bar (`shift 1`): `close > EMA` on **`InpEmaTf`** (default **M15**), period **`InpEmaPeriod`** (default **50**).
2. **+30** — M5 **closed** bar: `close > range high`, where **range high** is the **highest high** of the last **`InpRangeBars`** M5 bars, counting from **shift 1** (excludes the forming bar).
3. **+20** — M1 **closed** bar body `|close − open| ≥ InpBodyMinPoints × SYMBOL_POINT` for that symbol.

### Sell score

Same structure with **below EMA**, **close below range low**, and the same body rule.

### Entry rules

- **Buy** if `buyScore ≥ threshold` **and** `buyScore > sellScore`. **SL** at **range low** (same M5 window as above). **TP** at **`InpRR` ×** risk distance.
- **Sell** if `sellScore ≥ threshold` **and** `sellScore > buyScore`. **SL** at **range high**. **TP** symmetric.

If a **buy** order is **successfully** opened, the EA does **not** also open a **sell** on that symbol in the same pass.

---

## Timing (important)

- **`InpUseNewM5Bar = true` (default):** each symbol is only evaluated when a **new M5 bar** opens for that symbol. This greatly reduces repeated orders on the same setup (your original loop would fire every tick).
- Indicators and range use **closed** bars (**shift 1**) for EMA, M5 close, and M1 body, so the core signal does not depend on the **currently forming** M1 bar for those checks.

---

## Risk and lot size

- **`InpRiskPercent`**: percent of **account balance** risked if price hits **SL**.
- Lot size uses **`SYMBOL_TRADE_TICK_SIZE`** and **`SYMBOL_TRADE_TICK_VALUE`** and the **actual SL distance in price** (not a “pips × 10” shortcut).

---

## Stops and filling

- Stops are adjusted to satisfy **`SYMBOL_TRADE_STOPS_LEVEL`** when the broker requires a minimum distance.
- **Filling mode** is chosen from the symbol’s **`SYMBOL_FILLING_MODE`** (IOC / FOK / RETURN).

---

## Logging

- **`InpLogCsv`**: append trades to **`MQL5/Files/<InpLogFileName>`** (default `ExpoElite_trade_log.csv`).
- If the file is empty, a **header row** is written once.
- **`FileFlush`** is called after each write so data survives crashes more often.

If the file cannot be opened, the EA still runs; a message is printed in the **Experts** log.

---

## Dashboard

- **`InpShowDashboard`**: `Comment()` shows **BUY score** and **SELL score** for the **last processed symbol** in the loop (not all symbols at once).

---

## Inputs quick reference

| Input | Role |
|--------|------|
| `InpRiskPercent` | Risk % per trade |
| `InpRR` | TP multiple vs SL distance |
| `InpRangeBars` | M5 bars for range high/low |
| `InpProbabilityThreshold` | Minimum **score** to trade |
| `InpEmaPeriod` / `InpEmaTf` | Trend EMA |
| `InpBodyMinPoints` | M1 body filter (points) |
| `InpMaxSpreadPoints` | Max spread (points); 0 = off |
| `InpSessionStartHour` / `InpSessionEndHour` | Server-hour window |
| `InpSymbolList` | Comma-separated symbols |
| `InpMagic` | Order magic |
| `InpMaxPositionsPerSym` | Cap positions per symbol |
| `InpUseNewM5Bar` | Evaluate once per new M5 bar per symbol |

---

## Installation

1. Copy `Expo_Elite_Scalper_EA.mq5` into `MQL5/Experts/`.
2. Compile in MetaEditor.
3. Attach to **any** chart (logic does not use chart symbol unless it appears in `InpSymbolList`).
4. Enable **Algo Trading** and allow **WebRequest** only if you add features that need it (not required for this EA).

---

## Testing notes

- Use **Every tick** or **1 minute OHLC** in the Strategy Tester; results depend on multi-symbol data availability in the tester.
- **Gold** and **FX** have very different **point** sizes; tune **`InpBodyMinPoints`** and **`InpMaxSpreadPoints`** per symbol class.

---

## Risk disclaimer

Trading involves substantial risk. This EA is a technical template; past performance does not guarantee future results. Test on demo and with your broker’s specifications before live use.
