# Claude EA – handoff (state at save 40, EA v4.51, 2026-09-26)

Read this first in a new chat (CLAUDE.md, auto-loaded, holds the repo / commit / naming rules). Detailed history of every test round: `Research/PROGRESS.md`.
Portability / live deployment guide: `DEPLOY.md`.

## 1. Project & working rules
- MT5 Expert Advisor, started as a port of the Pine v6 indicator "DJ Trend – Claude"
  (`DJ Trend - Claude Indicator.txt`), now a modular multi-strategy, multi-symbol XAUUSD-first EA.
- Repo = only `...\MQL5\Experts\Claude` → https://github.com/Djodan/Claude_EA.git (branch main).
- **Commit messages: `N. short description`** (sequential; last = **40**, next = **41**). Commit + push after
  meaningful progress (user pre-approved pushes). Add the Co-Authored-By trailer.
- User wants **short, summarized replies**. Think broad in optimisation (no self-imposed limits; let the optimiser
  decide, including sizing; add caps later).
- Owner: DjoDan Maviaki. Broker/terminal: **Alpari MT5** (demo, 1:500), live/prop feed may differ (VPS "MetaQuotes"
  feed gave wider Asian ranges – PF 1.67 vs 2.06 on Alpari).

## 2. Paths
| What | Path |
|---|---|
| EA source | `C:\Users\dmavi\AppData\Roaming\MetaQuotes\Terminal\36A64B8C79A6163D85E6173B54096685\MQL5\Experts\Claude\` |
| Main file | `Claude.mq5` (inputs → config → engines/builders, health/dashboard, OnInit/OnTick/OnTester) |
| Modules | `Modules\{Core,Signals,Signals\Filters,Guards,Manage,Trade,Strategy,Math,Notify,Visual}` |
| Research log | `Research\PROGRESS.md` · set generator `Research\make_set.py` · set archive `Research\sets\` |
| Tester set folder | `MQL5\Profiles\Tester\` (make_set.py writes here too). Tester HTML reports land here as well. |
| EA result CSVs | `%APPDATA%\MetaQuotes\Terminal\Common\Files\ClaudeEA\` – results.csv, consistency.csv, strategies.csv, trades_<sym>_<tf>_P<preset>_<year>.csv, calendar_utc.csv |
| Per-pair profiles | `%APPDATA%\MetaQuotes\Terminal\Common\Files\ClaudeEA\profiles\<SYMBOL>.set` |
| User's drop folder | `C:\Users\dmavi\OneDrive\Desktop\delete\` (optimisation XMLs, reports) |
| Compiler | `"/c/Program Files/Alpari MT5/MetaEditor64.exe" /compile:"Claude.mq5" /log:"<scratchpad>/compile.log"` then `iconv -f utf-16 -t utf-8 compile.log \| grep Result` |
| Broker symbols with history | `%APPDATA%\...\36A64...\bases\Alpari-MT5-Demo\history\` (XAUUSD, XAGUSD, XAUEUR, majors, crosses, crypto) |

Shell notes: Git Bash; bash heredoc `python - <<'EOF'` works (never add `</dev/null` → REPL). For big edits write a
`.py` in the scratchpad with exact-match `replace` + asserts. Use `timeout 60 python ...`. Don't leave a bare
`cat > file` without heredoc (hangs). MetaEditor can overwrite Claude.mq5 from a stale open tab – the user keeps
it closed; always compile yourself. MT5 terminal is usually open → cannot run the tester from the CLI; the
user runs tests and reports "results are ready" → read the CSVs / HTML / XML yourself.

## 3. Architecture (v4.52)
```
inputs ──BuildConfig──► SEAConfig g_cfg ──ApplyPreset──► per symbol: CSymbolEngine
   (all reads via PD/PL/PB/PS accessors so a per-pair profile can replace any input)
CSymbolEngine = config copy (+ symbol overrides) + CGuardManager + CStrategy*[] + CExcursionTracker + CAlertManager
CStrategy     = signal modules (1 TRIGGER + FILTERs) + CTradeManager + CRiskManager + CPositionManager(exits)
```
- Builders in Claude.mq5 (`BuildTrend/BuildBreakout/BuildPullback/BuildVWAP/BuildPBO/BuildMeanRev/BuildMomentum`)
  use the global `g_eng` (engine being built) → `StartStrategy` → `g_eng.Add(st)`. `AddExits` adds position modules.
- Strategy ids / magic = InpMagic (20260900) + id: 1 Trend (DJ Trend flip), 2 Breakout (Asian range), 3 Pullback
  (EMA + RSI), 4 BreakoutNY, 5 VWAPTrend, 6 PullbackBO, 7 MeanRevScalp, 8 MomentumScalp.
- Presets (Presets.mqh) only toggle enables: 0 custom, 1 Trend, 2 Breakout, 3 Pullback, 4–7 combos, 8 VWAP,
  9 PBO, 10 VWAP+PBO, 11 +S2, 12 Scalp MR, 13 Scalp MO, 14 MR+MO, 15 Scalp+PBO.
- Signals: `SignalBase`/`SeriesModule` (CopyRates per symbol/TF), roles TRIGGER/FILTER, `AllowsAt`/`BiasAtIndex`.
  Filters: ADX (min/max), Volatility, Slope, TrendMA (any TF), TimeWindow (2 windows). "AsianBias" = a
  SessionBreakout used as a filter (scalps only in the direction price broke the Asian range).
- Guards (per engine, checked before entries): News (calendar CSV, `AUTO` currencies), Session, Spread (price,
  price-scaled from chart symbol, or % of D1 ATR), DailyLimits (**account-wide** across symbols: % loss, % target,
  $ target, $ loss, max trades; closes positions on limit), Activity (per-pair hourly tick-volume profile).
- Exits: Breakeven, Trailing, PartialClose (R or ATR units), TimeExit (bars), SessionClose (EOD + 5 min before broker
  session end), **WeekendClose** (Fri 22:00 ref, all strategies), NewsExit (N min before high-impact news).
- Sizing (RiskManager): lots = base × risk% / (stop × tick value); base = min(balance, equity, InpAccountSize cap;
  cap 0 = off → compounding). Skips a trade if the lot would be below min lot (never rounds risk up).
- Time: all session inputs are **reference time GMT+2/+3 with US DST (NY-close)**; `CTimeZone` converts from
  `InpServerTZ` (Alpari & most brokers = TZ_NY_CLOSE). Dashboard verifies (daily-break detection in M1 data).
- News: live chart exports the MT5 calendar to `Common\Files\ClaudeEA\calendar_utc.csv` (every 6 h, from
  InpNewsFrom). Tester only reads the file → a live chart must have exported it. Quirk handled: MT5 calendar uses
  the *current* server offset.
- Health/dashboard: problems (timezone, algo trading off, missing/old news file, symbol issues, strategy issues,
  profile state, risk) show red/orange on the dashboard and in the journal; next high-impact news shown.
- OnTester: custom criterion (`InpCriterion`: 0 net profit … **6 TC_PROFIT_DD_PCT** (default, "Custom max"), 7
  consistency), min trades; writes CSVs (config summary string identifies each run) and per-symbol trade lists.

### Multi-symbol & per-pair adaptation (v4.40–4.51)
- `InpSymbols` = "" (chart symbol) or `XAUUSD,XAGUSD:spread=0.05;srisk=5,EURUSD:spread=0.00025` – keys spread, slip
  (price), risk (S1–S4 %), srisk (scalper %), irisk (intraday %). Suffixes auto-resolve. Attach to ONE chart
  (XAUUSD M1). Live: 1 s timer processes all symbols.
- `InpSymbolSlot` 0 = all, N = only Nth → optimise 1..N to test pairs one by one (tester can't optimise strings).
- Without overrides, spread/slippage inputs (set for the chart symbol) scale by price; a spread override is absolute
  and beats `InpSpreadAtrPct`.
- `InpUseActivity/Min/Days`, `InpSpreadAtrPct`, `InpUseProfiles` (keep profiles OFF while optimising).
- **v4.52 Pair inputs** (one set = whole portfolio): `InpPair1..5_On`, `InpPairN` symbol, `InpPairN_S1..S4` settings
  text `key=value;...` (only what differs from the chart inputs; short keys too). Any pair on → replaces `InpSymbols`;
  text beats a profile file; unknown keys show red on the health. Build with
  `python Research/make_portfolio.py <Name> --base <set> XAUUSD GBPUSD=<gbp set>[;srisk=5][@off] [InpX=v ...]`.
  MT5 cuts string inputs at 255 chars incl. the name (243 value) → chunks of 240. Daily limits are account-wide: give every pair the same daily settings. Risks add up across pairs.
- Everything else is scale-free (ATR/R-based). Settings are tuned on XAUUSD only – other pairs untested.

## 4. Creating sets – `Research/make_set.py`
The tester caches inputs in `Profiles/Tester/Claude.set`; **always load a generated .set and re-select the EA after
a recompile** (otherwise new inputs are missing → e.g. the "Scaled" run silently had no daily target).
```
python Research/make_set.py <Name> [--exact-name] [--profile] NAME=value NAME=start:step:stop ...
```
- Starts from the code defaults in Claude.mq5; `NAME=value` fixes, `NAME=a:s:b` optimises (enum names, PERIOD_*,
  true/false `false:0:true`, D'..' dates, colours). Quoted strings (`'InpSymbols="A,B:spread=1"'`) are literal.
- Writes UTF-16 to `Profiles\Tester\` and `Research\sets\` (`Claude_<Name>.set` unless `--exact-name`);
  `--profile` also installs it as `Common\Files\ClaudeEA\profiles\<Name>.set`.
- Enum stepping walks the enum list: `InpS_TF=1:1:15` = M1..M15; `16385:1:16408` = H1..D1.
- Pattern used for derived sets: a scratchpad script loads an existing set (UTF-16, take the part before `||`),
  skips strings/dates, overrides keys, calls make_set.py. When deriving from pre-v4.40 sets, pin the new inputs
  (InpSymbols "", InpUseProfiles/Activity false, InpSpreadAtrPct 0, news "USD") – see New_1k_1.
- Tester standard: XAUUSD **M1**, 2026.01.01–2026.09.21, $100k (prop) or $1k (cash); explore with 1-min OHLC +
  Fast genetic + Custom max; verify winners with "Every tick based on real ticks", Optimisation disabled.
- Reading results: results.csv/consistency.csv (join on run_time+config; consistency has max_loss_pct vs initial
  deposit, best_day_share_pct, avg/best/worst day), strategies.csv (per strategy), trades CSV (MFE/MAE, R). Tester
  XML (optimisation) = SpreadsheetML rows; HTML reports are UTF-16 – parse `<tr>`/`<td>`. Analysis scripts from
  earlier rounds follow that pattern (regex rows → dicts → sort by Custom).

## 5. What we learned (key numbers, 2026 unless stated; details in PROGRESS.md)
- DJ Trend on M1 and generic M1 scalpers lose (costs ≈ 0.1–0.15R). H1 DJ Trend PF ≈ 1.4. S4 NY breakout, S6 PBO,
  S5 VWAP (alone), retry-after-block: no edge.
- **S2 Asian breakout** (range 01–08/09 ref, M5, TP 2–3.8R) is the backbone. best_2026 PF ≈ 2.1 but 2025 PF 1.04;
  **best_2025_2026** (D1 EMA 50 trend + news exit 5) is the only config proven in both years (2025 PF 1.47,
  2026 PF 2.59, max loss 0.795% @0.8%).
- **Scalper R19_A** (preset 14, M5, AlignAsian, MO TP 0.5R close 0.9 stop at extreme, M15 EMA 100, 07–21, EOD 22):
  real ticks +38.5k PF 1.80 DD 2.8% worst 1.05R. More trades = lower quality (600 tr PF 1.27, 800 PF 1.16).
- **Top_2** (S2 M5 + H2 EMA100 filter, BE 1.25R, TP 3.8R + S3 H2 70/300): real ticks PF 2.6–2.7, DD 1.9–2.6%,
  worst 1.02R. **Top_1** (S2 + S3 M15 20/100): +70k PF 1.93 but worst 1.64R (gaps) → size ≤0.45%.
- Weekend holds caused >1% losses → WeekendClose (v4.30). Max loss above risk comes from gaps/slippage; size by
  each engine's worst-trade R.
- $1k accounts: only the scalper fits (median stop $2.8 per 0.01 lot; S2 ≈ $55). Final_Cash_200PerDay (10% risk,
  +$200/−30% day): **$1k → $13,217**, PF 1.71, DD 29%, 86/130 days ≥ $200. 10% with no target: $44k, DD 36%.
- Consistency rule (best day ≤ 40% of profit) passes easily (best day 6–14%).

## 6. Current recommended sets (Research/sets)
| Set | Use | Status |
|---|---|---|
| New_Prop_Low_Risk | Prop keep/pass: Top_2 at 0.6%, day stop −2% | tested: +18.3k PF 2.68 DD 1.86% worst 0.60% |
| New_Prop_High_Risk | Prop challenge: scalper 0.7% + Top_1 swing 0.45%, day −3% | tested: +64.6k PF 1.64 DD 3.78% worst 0.746% |
| New_1k_1 | $1k high risk, $200/day (legacy-pinned) | tested: $13,216.98 ✅ (v4.51 regression OK) |
| New_1k_2 | same, daily target 20% of balance | tested: +36.3k PF 1.29 DD 36.5% |
| Final_Lowest_DD | Top_2 at 0.4% | +11.8k DD 1.36% (regression check for v4.40+: 127 trades, +11,767.93) |
| Cash_Multi_* / Final_Cash_200PerDay_Multi | $1k multi-pair variants | worse than gold-only (Round 27) |
| Round24_PairScan / Round25_PairAdapt / Round24_PairOptimize / Round22_Cash200_HighRisk | pair & $1k optimisations | not yet run properly |

## 7. Open to-dos
1. Verify New_Prop_* on 2026 real ticks, then **2025 out-of-sample**; fallback best_2025_2026 at 0.75%.
2. Regression-check v4.51 (Final_Lowest_DD / New_1k_1 must match old numbers).
3. Multi-pair: run PairScan/PairAdapt → optimise good pairs per slot → save profiles → portfolio test.
4. Daily caps / $ goals step by step; US-holiday early closes not handled (only broker session end).
5. Alerts show the engine's symbol; SSignal has no symbol field (fine for now).

## 8. Expanding the EA
- New signal: subclass `CSeriesModule` (see SignalMomentumScalp: Update() fills m_last, History() for chart),
  add a settings struct + config struct in Config.mqh, a `BuildX()` in Claude.mq5 calling `StartStrategy(st, id, s)`,
  a new STRAT_ id + name in `g_stratNames`, inputs (read through BuildConfig so profiles work), preset wiring,
  ConfigSummary text. New filter: subclass CSignalModule/CSeriesModule with AllowsAt(); add via `st.AddSignal(f, ROLE_FILTER)`.
- New guard: subclass `CGuard` (CanOpen/OnTick/m_status), register in `RegisterGuards` (per engine).
- New exit: subclass `CPositionModule` (Manage(SPosition&)), add in `AddExits`.
- Keep inputs in reference time, price-scale-free (ATR/R), and add health checks for anything that can silently fail.
- After changes: compile, bump EA_VERSION, generate sets, log in PROGRESS.md, commit "N. ...", push.
