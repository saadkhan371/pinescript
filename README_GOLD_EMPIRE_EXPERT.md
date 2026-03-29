# Gold Empire Expert (MT5) — XAUUSD

This document describes `Gold_Empire_Expert.mq5`: a deliberately **simple and strict** XAUUSD EA using **closed-bar signals**, **EMA200 trend**, **ADX strength**, **ATR-based SL/TP**, optional **session shield**, and **frequency limits**.

---

## File

- EA: `Gold_Empire_Expert.mq5`

---

## Design goals

- **Quality over quantity** in the default preset: fewer trades, clearer conditions.
- **No repainting**: decisions use the **last fully closed** candle on the entry timeframe (`shift = 1`).
- **Multi-timeframe (MTF)** where it matters: trend EMA and ADX can run on **different** timeframes than the chart.
- **Gold-aware caveat**: spreads, session, and broker point value matter; always validate on **your** symbol (e.g. `XAUUSD`, `XAUUSDm`) and server time.

---

## Core logic

### 1) When the EA evaluates a signal

- On each tick, the EA detects a **new bar** on the **entry timeframe** (`InpEntryTF`, or **current chart** if set to `PERIOD_CURRENT`).
- When a new bar appears, the **previous** bar is complete. All conditions below use that **closed** bar (`shift = 1`) on each indicator’s own timeframe.

### 2) Trend filter — EMA200 (`InpTrendEmaTF`)

- **Buy bias** allowed only if **close > EMA200** on the **trend timeframe** (closed bar).
- **Sell bias** allowed only if **close < EMA200** on the **trend timeframe** (closed bar).

### 3) Momentum filter — ADX (`InpAdxTF`)

- ADX **main line** (built-in ADX) on the **ADX timeframe** must be **≥ `InpAdxThreshold`** on the closed bar.
- This is a **strength** filter, not a direction filter (no DI+/DI− cross logic in v1).

### 4) Pullback / “near EMA200” zone — entry timeframe

On the **entry** timeframe (same TF as `hEmaEntryTf` / chart when `EntryTF = CURRENT`):

- Let `d = |close − EMA200|` (closed bar).
- **Buy**: `d ≤ InpPullbackMaxPoints × SYMBOL_POINT` **and** `close > EMA200`.
- **Sell**: same distance rule **and** `close < EMA200`.

So the EA trades **with** the local EMA200 side while still requiring **higher-timeframe** trend alignment.

### 5) Stop loss and take profit — ATR

- ATR is read on the **entry** timeframe (`InpAtrPeriod`).
- **SL distance** = `InpSlAtrMult × ATR`.
- **TP distance** = `InpTpAtrMult × ATR`.
- Stops are adjusted outward if they violate the symbol’s **minimum stop distance** (`SYMBOL_TRADE_STOPS_LEVEL`).

### 6) Limits and cooldown

- **`InpMaxOpenPositions`**: cap simultaneous positions for this **symbol + magic**.
- **`InpBarsCooldown`**: after a successful entry, wait this many **new closed bars** on the entry TF before another entry (`0` = no cooldown).
- **`InpMaxTradesPerDay`**: cap **new deal entries** per **server calendar day** for this symbol + magic (`0` = unlimited).

### 7) Session shield (optional)

- **`InpAvoidRollover`**: blocks a configurable server-time window (default **22:00 inclusive → 02:00 exclusive**, wrapping midnight).
- **`InpAvoidFridayLate`**: blocks from **`InpFridayLateFromHour`** onward on **Friday** (server time).

---

## Inputs (quick reference)

| Group | Parameter | Role |
|--------|-----------|------|
| Symbol & session | `InpSymbol` | Empty = chart symbol |
| Timeframes | `InpEntryTF` | Signal timeframe (`CURRENT` = chart) |
| | `InpTrendEmaTF` | EMA200 trend filter TF |
| | `InpAdxTF` | ADX TF |
| Strategy | `InpEmaPeriod` | EMA length (default 200) |
| | `InpAdxPeriod` | ADX length (default 14) |
| | `InpAdxThreshold` | Minimum ADX |
| | `InpPullbackMaxPoints` | Max distance from EMA200 in **points** |
| | `InpAtrPeriod`, `InpSlAtrMult`, `InpTpAtrMult` | ATR SL/TP |
| Limits | `InpBarsCooldown`, `InpMaxOpenPositions`, `InpMaxTradesPerDay` | Frequency caps |
| Risk | `InpFixedLot` / `InpUseRiskPercent` | Sizing |
| Session | Rollover + Friday | Optional blocks |

---

## Default preset philosophy

Defaults target **selectivity**:

- **H4** trend EMA vs **H1** ADX is a common combination when trading **H1** entries: higher TF regime, shorter TF strength.
- **ADX 20** and a **moderate pullback band** reduce clutter.
- **Cooldown** + **max trades per day** reduce over-trading in chop.

---

## Want MORE trades on H1 (e.g. 2–3 per day)?

These changes **increase activity** (and usually **noise**). Forward-test / backtest on **your** broker’s XAUUSD.

1. **MTF filters**
   - **EMA200 trend TF**: `4 Hours` → **`1 Hour`** or **`Current`** (same as chart).  
     *This is usually the largest “trade killer” when the chart is H1: a stricter higher TF blocks many setups.*
   - **ADX TF**: `1 Hour` → **`Current`** to align ADX with the entry chart.

2. **Strategy**
   - **ADX threshold**: `20` → **`16–18`** (lower → more signals).
   - **Pullback zone** (`InpPullbackMaxPoints`): `20` → **`40–60`** (wider → more near-EMA entries).

3. **Limits / cooldown**
   - **Bars cooldown**: `3` → **`1`** (`0` = off).
   - **Max trades per day**: default **`5`** → **`0`** (unlimited) or **`8–10`** if you only want a softer cap.
   - **`InpMaxOpenPositions`**: raise only if you intentionally want overlapping trades.

4. **Session shield**
   - **`InpAvoidRollover`**: `true` → **`false`** (or narrow the hour window).
   - **`InpAvoidFridayLate`**: `true` → **`false`** if you want late Friday entries.

---

## Which filter is the “real bottleneck”? (practical note)

On **H1**-style trading, **the higher-timeframe EMA200 trend filter** (`InpTrendEmaTF`) typically removes the **most** candidates, because it enforces a single regime across many bars. **Pullback width** is usually second (geometry of how close price must be to EMA200). **ADX threshold** is often third: it thins weak-trend periods but rarely dominates as much as a **4H** vs **1H** trend mismatch.

Your mileage varies with symbol, session, and whether Gold is trending or mean-reverting — **test**, don’t assume.

---

## Installation & testing (MT5)

1. Copy `Gold_Empire_Expert.mq5` into `MQL5/Experts/` (or your project folder synced with MT5).
2. Compile in **MetaEditor**.
3. Attach to a chart (e.g. **H1** XAUUSD). Set **`InpSymbol`** if the chart symbol differs from your tradable name.
4. In Strategy Tester, prefer modes that respect bar logic (**Every tick based on real ticks** or **1 OHLC**), not **Math calculations**, so indicators and prices behave realistically.
5. Align **server time** with how you interpret rollover and Friday rules.

---

## Risk disclaimer

Automated trading involves risk. This EA is a technical template; **past results do not guarantee future performance**. Use demo/testing first and only risk capital you can afford to lose.
