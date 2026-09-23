# DJ Trend EA – Research Log

Working log for improving the EA through backtesting. Every change to defaults or presets
must be traceable to a result recorded here.

## Goal
Maximise **risk-adjusted** profitability, not just net profit:
- Primary: profit factor, recovery factor (net / max DD), max equity DD %
- Secondary: net profit, trade count (>= 30 per year so results mean something), expectancy
- A change is only "good" if it improves the primary metrics on the test symbol **and**
  doesn't collapse on a second symbol / period (avoid curve-fitting).

## Test protocol
- Period: **2026.01.01 – 2026.09.21** (user decision). Month-by-month runs for consistency checks.
- Model: "1 minute OHLC" or "Every tick based on real ticks" – record which.
- Fixed lots in all presets so runs compare like-for-like (risk sizing tested separately).
- **Always load the round's generated settings file** (Inputs tab → right-click → Load →
  `Claude_<Round>.set`, made by `Research/make_set.py`). The tester otherwise restores the
  last-used input values and silently ignores new code defaults. Verify the build stamp in the
  Journal line `DJ Trend EA v… build …` (also the `build` column of results.csv).
- Run type: **Optimisation over `Preset`** (range 1–9, step 1) → one table covering every preset.
  Then a **single run** of the best preset to get the trade list.
- Output files (read automatically): `%APPDATA%\MetaQuotes\Terminal\Common\Files\ClaudeEA\`
  - `results.csv` – one row per pass (appended)
  - `trades_<sym>_<tf>_P<n>.csv` – every closing deal of a single run

## Module inventory
| Area | Module | Status |
|---|---|---|
| Trigger | DJ Trend (EMA/SMA/HMA/ALMA basis on hlc3, ATR buffer) | in use |
| Filter | HTF DJ Trend (auto = next TF up) | ❌ R1 as flip filter |
| Filter | ADX (min, DI agree, rising) | ❌ R1 (min 20) |
| Filter | Volatility regime (ATR / avg ATR) | ✅ R1 – tuning R2 |
| Filter | MA slope (ATR units) | ❌ R1 (too strict) |
| Guard | Session / weekdays | untested |
| Guard | Max spread | untested |
| Guard | Daily loss / target / max trades | untested |
| Manage | Partial close | untested |
| Manage | Breakeven | ❌ R1 (1 ATR) · ≈ neutral R7 (1R on breakout) |
| Manage | ATR trailing | ❌ R1 (2/2.5 ATR) – retry wider |
| Manage | Time exit | untested |
| Exit | SL/TP: ATR, points, R:R | ✅ SL 2 ATR R1 – tuning R2 |
| Sizing | Fixed / risk % | fixed only so far |

---

## Round 1 – module screening (v1.20)
**Question:** which modules help the raw stop-and-reverse signal?
Each preset adds one thing to the baseline, so each effect can be isolated.

| Preset | Setup | Hypothesis |
|---|---|---|
| 1 | Baseline: pure indicator, stop & reverse, no SL/TP | Reference. Trend flips on a 0.5 ATR buffer usually chop in ranges → many small losses, a few big winners. |
| 2 | + SL 2.0 ATR | Caps the damage of failed flips; may cut some winners that pull back. |
| 3 | + SL + HTF trend | Removes counter-trend flips; expect fewer trades, higher PF. |
| 4 | + SL + ADX ≥ 20 | Removes flips in ranges; expect higher win %. |
| 5 | + SL + volatility 0.8–2.0 | Removes dead/spike regimes; unsure. |
| 6 | + SL + slope ≥ 0.15 ATR / 3 bars | Similar to ADX but faster; unsure. |
| 7 | + SL + BE (1.0 ATR) + trail (start 2.0, dist 2.5) | Protects open profit; may exit trends early. |
| 8 | + SL + HTF + ADX | Combination of the two filters expected to be strongest. |
| 9 | Candidate (default): SL + HTF + ADX + BE + trail | My starting guess for the best overall setup. |
| 10 | Candidate without BE (added after first run) | Confirms whether BE is what kills the winners. |

Signal settings for all: EMA 34, ATR 14, buffer 0.5, fixed 0.10 lots.

Test setup: **XAUUSD H1**, 2026.01.01–2026.09.21, 1-min OHLC, $100k, 1:500, Alpari demo. Build 1.20 2026.09.22 18:13.

**Results (optimisation, all presets):**

| Preset | Trades | Net | PF | Win % | Max DD % | Recovery |
|---|---|---|---|---|---|---|
| 1 Baseline | 171 | +7,163 | 1.16 | 32.2 | 10.75 | 0.59 |
| 2 +SL 2ATR | 171 | +11,148 | 1.28 | 32.2 | 9.24 | 1.05 |
| 3 +SL+HTF | 29 | -6,297 | 0.40 | 13.8 | 16.07 | -0.35 |
| 4 +SL+ADX20 | 93 | +3,085 | 1.10 | 26.9 | 13.18 | 0.20 |
| 5 +SL+VOL 0.8-2.0 | 144 | +9,641 | 1.31 | 31.9 | 7.51 | 1.15 |
| 6 +SL+SLOPE | 1 | -513 | 0 | 0 | 0.66 | – |
| 7 +SL+BE+TRAIL | 172 | +1,149 | 1.05 | 65.1 | 6.40 | 0.17 |
| 8 +SL+HTF+ADX | 21 | -1,462 | 0.81 | 19.0 | 14.24 | -0.09 |
| 9 Candidate | 40 | -2,691 | 0.59 | 72.5 | 5.59 | -0.47 |
| 10 Candidate no BE | 40 | -1,522 | 0.87 | 37.5 | 6.88 | -0.21 |

**Conclusions:**
- ✅ Raw signal has an edge on XAUUSD H1 (PF 1.16). Low win rate (32%), profit from few large trends.
- ✅ SL 2 ATR: +56% net, lower DD – cuts failed flips without touching entries.
- ✅ Volatility filter: best risk-adjusted (PF 1.31, DD 7.5%, recovery 1.15).
- ❌ HTF / ADX / slope: lagging – at a fresh flip they still reflect the old trend, so they reject
  exactly the best entries. HTF is worst. Slope 0.15 ATR/3 bars almost never true at a flip.
- ❌ BE 1 ATR + trail 2/2.5 ATR: raises win % but scratches the big winners the system lives on.
- Side effect: when filters block the opposite signal, the open position is not closed/reversed
  and blocks new entries (trade count drops) – filtered signals should maybe still close positions.

---

## Round 2 – tune SL and volatility filter (v1.20)
Base = preset 5 (SL + VOL), everything else off. Preset 0 (custom), grid:
SL 1.5–3.5 ATR (0.5), vol min 0–1.0 (0.2), vol max 1.5–3.5 (0.5) = 150 passes.
Hypothesis: optimum SL 2–3 ATR; vol min matters more than max (dead markets = chop).
Watch for a broad plateau, not a single spike (overfitting).

**Results (150 passes, build 1.20 18:5x):** best = SL 2.0, min 0.8, max off → 147 trades, +13,357,
PF 1.40, DD 7.27%, recovery 1.59 (vs R1 best PF 1.31 / rec 1.15).

Median recovery by value (other params varied):
- SL: 1.5 → 1.26 · 2.0 → 1.05 · 2.5 → 0.87 · 3.0 → 0.74 · 3.5 → 0.63 (monotonic: tighter better)
- Vol min: 0–0.6 identical (never binds) · 0.8 → 1.27 · 1.0 → 0.38 (too strict, 66 trades)
- Vol max: ≥2.5 never binds · 2.0 → 0.56 (hurts) · 1.5 → 0.77

**Conclusions:**
- ✅ Vol min ~0.8 helps at every SL, but the step 0.6→0.8→1.0 is coarse – possible spike. Refine.
- ✅ Tighter SL keeps improving → test 1.0–1.5.
- ❌ Vol max: little value, set to off (0).

---

## Round 3 – refine SL + vol min, exit on filtered flips (v1.20 + XF)
New option `InpExitOnFlip` (XF): a flip the filters block still closes the opposite position
(no new entry). Grid: SL 1.0–2.5 (0.25) × vol min 0.60–1.00 (0.05) × XF off/on = 126 passes.
Hypotheses: plateau around min 0.75–0.85; best SL 1.25–2.0; XF improves PF (stops riding
positions after the trend has flipped).

**Results:** _skipped – superseded by the v2.00 pivot (round 4)._

---

## Pivot (2026-09-22): goal = best backtest numbers on XAUUSD, any approach
User decisions: test period **2026 only** · **no martingale/grid** · any timeframe · **avoid
high-impact news**.

XAUUSD research notes:
- 2026 regime: parabolic rally to $5,595 (29 Jan), crash to ~$3,960, then $4,000–4,850 range.
  Volatility in the top 5% since 1971 (WGC). Drivers: central-bank buying, geopolitics (Iran),
  Fed leadership change, USD/yields. CME margin hikes accelerated sell-offs.
- Liquidity/volatility peaks at London open and the London–NY overlap; US data (NFP, CPI, FOMC)
  cause the largest spikes → session breakouts and news avoidance are the standard edges.
- User's older WeeklynDaily notes: gold longs 50% win vs shorts 17% (2025) → check long bias.

v2.00 architecture: portfolio of independent strategies (own magic = base + id, own TF, exits),
shared guards, 1% risk per trade (risk sizing so different stop sizes compare fairly).
- S1 Trend  – DJ Trend H1, SL 2 ATR, vol min 0.8 (round 2 best)
- S2 Breakout – M15 range 01:00–09:00 server, entries until 17:00, buffer 0.1 ATR, range 1.5–12 ATR,
  stop = opposite side of range, TP 2R, flat at 23:00
- S3 Pullback – H1 EMA 50/200 trend, RSI(14) crosses back through 40/60, SL 2 ATR, TP 3 ATR
- News guard – USD high-impact ±30 min, from calendar.csv exported on a live chart
- New outputs: `strategies.csv` (per-strategy stats per pass), `strategy` column in trade exports

---

## Change (v2.10): focus on M1 / M2, month-by-month testing
User request. All strategies follow the chart TF. Scalping adjustments: spread guard 60 pts,
session guard 09–22 server (skip Asian chop + rollover spreads), SL 3 ATR (M1 ATR ≈ $1.5,
spread ≈ $0.3), breakout range-width filter off, pullback TP 4.5 ATR.
Model must be **Every tick based on real ticks** (1-min OHLC is meaningless on M1).
Round 4 grid: preset 1–7 (strategy combos) × session guard on/off = 14 passes per month.
News guard active: calendar.csv exported 2026-09-22 (391 USD high-impact events in 2026; "Crude Oil"
excluded). NFP at 15:30 server confirms **Alpari server = GMT+3 (summer) / GMT+2 (winter)** →
London open 10:00 server, NY open 16:30 server, breakout range 01–09 ends 1 h before London.

## Round 4 – screen portfolio strategies (v2.00 → run on v2.10 M1/M2)
Presets 1–8: each strategy alone, all together, and each with/without the news guard.
Note: results now use 1% risk sizing – not comparable in $ with rounds 1–2 (compare PF / DD / recovery).
Hypotheses: breakout has the best PF on gold; news guard reduces big losses on all strategies;
pullback works better long-only.

**Results (v2.10, M1, real ticks, 1% risk, news on, session guard off in all passes):**

Full period 2026.01.01–09.21:

| Preset | Trades | Net | PF | Win % | Max DD % | Recovery |
|---|---|---|---|---|---|---|
| 1 Trend | 8,904 | -95,282 | 0.91 | 27.3 | 97.7 | -0.74 |
| **2 Breakout** | **143** | **+38,085** | **2.04** | **58.7** | **3.20** | **11.5** |
| 3 Pullback | 2,263 | -82,599 | 0.89 | 37.8 | 87.1 | -0.81 |
| 4–7 combos | 9–11k | -76k to -99k | 0.91–0.92 | – | 82–99 | – |

Breakout by month: Jun +5,466 PF 5.96 · Jul +686 PF 1.12 · Aug +4,752 PF 2.36 (profitable each month).

**Conclusions:**
- ✅ Session breakout is the edge on XAUUSD M1: PF 2.0, DD 3%, profitable every tested month.
- ❌ Trend and Pullback on M1: thousands of trades, PF < 1 – spread/noise dominate. Disabled on M1.
  (Trend was PF 1.40 on H1 in round 2 – timeframe matters.)
- Combos are worse than breakout alone: losing strategies drain equity (risk % sizing compounds).
- Test period fixed at 2026.01.01–09.21 from here on (user).

---

## Round 5 – tune the breakout (v2.11, M1)
Breakout only, news on, spread 60, session guard off. Grid (96 passes): range end 08/09/10 ·
TP 1.5/2/2.5/3 R · stop range/mid · one-per-day on/off · long-only vs both.
Hypotheses: range end 09–10 (just before London open) best; mid stop raises R but lowers win %;
long-only helps given gold's bias.

**Results (144 passes – direction ran long/short/both; model "Every tick", $100k):**
- Best = defaults: end 09, TP 2R, range stop, 1/day, both → 142 trades, +37,773, PF 2.03,
  DD 2.32%, recovery 11.6.
- TP 1.5–3R: PF 1.93–2.03 at end 09 → flat plateau (robust, not a spike).
- Direction (median): long-only PF 1.43 · short-only PF 2.03 · both PF 1.74 but best net/recovery.
- Mid stop: more net (up to +55k) but DD up to 5.2% and lower PF → range stop better risk-adjusted.
- Range end: 09 best (rec 5.9) > 08 (4.8, more trades) ≈ 10 (4.7, fewer trades).
- One-per-day: slightly better (rec 5.2 vs 4.8).

**Conclusions:** keep defaults. 2026 shorts outperform (crash regime) – don't force a long bias.

---

## Prop-firm constraints (user, 2026-09-22)
Account $100k prop firm. Rules: **no hedging**, **no single trade loss > 1% of the account**.
v2.14: risk 0.8% per trade (20% cushion for slippage/gaps), sized from min(balance, equity);
no-hedge check (never open against any open position on the symbol); results.csv adds
`max_loss_pct` (largest single loss / initial deposit) – must stay < 1.0 in every accepted setup.
Note: $ results from here are at 0.8% risk (×0.8 vs earlier rounds); compare PF / DD / recovery.

## Round 6 – breakout timing (v2.14, M1)
v2.13: trade export adds 1R risk, MFE/MAE (price and R) and result in R per trade.
Grid (54): last entry 14/17/20 · EOD close 20/23 · buffer 0/0.2/0.5 ATR · range start 01/03/05.
Hypotheses: earlier range start (01) best – full Asian range; last entry 17 (before late NY chop).

**Results (54 passes, v2.14, 0.8% risk, real ticks?, $100k):**
- Best: start 01, last entry 17, buffer 0.25, EOD 23 → 140 trades, +31,036, PF 2.15, DD 2.48%, rec 12.4.
- Range start (median rec): 01 → 9.4 · 03 → 5.5 · 05 → 2.7 — the full Asian range matters most.
- Last entry: 17 best rec (6.7); 14 highest PF but fewer trades; 20 adds weaker late trades.
- Buffer 0–0.25 plateau; 0.5 slightly worse. EOD 23 > 20.
- ⚠️ **max_loss_pct 1.00–1.04%** in almost every pass → breaks the prop 1% rule. Cause: risk % of
  the *current* balance (grown to ~$127k) → $1,016 loss = 1.02% of the $100k start. Losses were
  all ≈ -1.0R (no slippage problem).

Trade analysis (single run, 142 trades, v2.13 1% risk): exits 107 EOD / 23 SL / 12 TP.
EOD exits median +0.21R (71/107 winners). MFE ≥1R: 49 trades, ≥1.5R: 22, ≥2R: 9 → the 2R target
is rarely reached; most profit comes from the EOD close.

**Conclusions:** defaults confirmed (start 01, end 09, entries until 17, EOD 23); buffer → 0.25.

---

## v2.15 changes
- `Account size` input (100,000): risk = 0.8% of min(balance, equity, account size) → max loss per
  trade ≈ $800 regardless of profits (prop-safe; no compounding).
- Exit modules can work in **R** (initial stop distance) instead of ATR; breakout uses R.
  New breakout inputs: BE trigger/lock in R, partial close at R / %.

## Round 7 – breakout exits in R (v2.15, M1)
Grid (20): TP 1.0–3.0R (0.5) × breakeven at 1R on/off × partial 50% at 1R on/off.
Hypotheses: since only 9/142 trades reach 2R, TP 1–1.5R or partial at 1R converts more of the
MFE into profit; BE at 1R cuts the few reversals after +1R. Must keep max_loss_pct < 1.0.

**Results (10 passes – partial toggle was not ticked; v2.15, 0.8% risk capped at $100k):**

| TP | BE 1R | Trades | Net | PF | DD % | Recovery | Max loss % |
|---|---|---|---|---|---|---|---|
| **2.0R** | off | 140 | **+27,062** | 2.15 | 2.44 | **10.8** | 0.90 |
| 2.0R | on | 140 | +27,459 | **2.22** | 3.09 | 8.9 | 0.81 |
| 1.0R | off/on | 140 | +24,246 | 2.08 | 2.35 | 10.3 | 0.81 |
| 1.5 / 2.5 / 3.0R | off | 140 | +24,954–25,665 | 2.06–2.09 | 2.44 | 10.0–10.3 | 0.90 |

- Exits barely matter (PF 2.06–2.22) → keep TP 2R, no BE. ✅ Max loss now 0.81–0.90% (< 1% prop rule).

Trade breakdown (single run, 140 trades, total +33.8R):
- **Every month profitable** (Jan PF 1.16 … Jun 6.10) – consistent edge.
- By range width (= 1R): narrowest quartile (< $41.6) avg +0.46R PF 3.11; wider quartiles +0.10–0.24R.
- By entry hour (server): 09 → +18.2R (56 trades, PF 2.58) · 10–12 good · 14–15 weak (PF 0.9–1.3).
- SELL PF 2.72 vs BUY PF 1.70. Weekdays all positive (Mon weakest).

**Conclusions:** exit tuning exhausted; next gains must come from more / better entries.

---

## v2.20 changes
- **S4 BreakoutNY**: same breakout module, range = first N minutes after NY open (16:30 server),
  entries until 20:00, stop = other side, TP 2R, flat 23:00. Own magic (+4) and stats row.
- Breakout range filter vs **daily ATR(14)** (min/max × D1 ATR) – more stable than M1 ATR.

## Round 8 – NY ORB + daily-ATR range filter (v2.20, M1)
Grid (60): S2 max range 0 / 0.25 / 0.5 / 0.75 / 1.0 × D1 ATR · S4 range 15 / 30 / 45 / 60 min ·
S4 TP 1.5 / 2 / 2.5R. S2 and S4 always on (per-strategy results in strategies.csv).
Hypotheses: S2 max ≈ 0.5–0.75 × D1 ATR removes weak wide-range days; S4 adds ~15–20 trades/month
at PF > 1.5 without hurting S2.

**Results:** _pending_

Note: user's tester showed deposit $3,000 and "Every tick" – asked to keep $100k + real ticks
for comparability ($3k with 1% risk hits the 0.01-lot floor → real risk > 1%).

---

## Backlog / ideas (not yet tested)
- Optimise basis length / buffer once the module set is chosen (only after filters – avoid fitting noise).
- Re-entry after a stop-out while the trend is unchanged (currently waits for the next flip).
- Entry on pullback to the basis instead of on the flip bar.
- Chandelier / basis-line trailing instead of a fixed ATR trail.
- Long-only vs short-only asymmetry (check the long/short columns).
- Session / weekday effects (check hour / weekday columns in the trade export).
- Risk-% sizing once a stop-loss setup is chosen.
- Redesign HTF as "alignment entry": enter when H1 and H4 trend agree, not only on the H1 flip bar.
- Slope filter: evaluate a few bars after the flip, or lower threshold – low priority.
- Long-only variants for each strategy (gold long bias).
- Out-of-sample check on the previous year and a second symbol.
