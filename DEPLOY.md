# Deploying Claude EA on another computer / broker

## What to copy
- **Minimum:** `Claude.ex5` → `<new terminal>\MQL5\Experts\Claude\`. The .ex5 contains every module;
  it only needs MT5's standard library, which every MT5 has.
- **To edit/recompile:** the whole `Experts\Claude` folder (or `git clone https://github.com/Djodan/Claude_EA`).
- **Settings:** `Research\sets\*.set` → `<new terminal>\MQL5\Profiles\Tester\` (tester) or load them in the EA's
  Inputs tab on a chart (right-click → Load).

## First start (live chart)
1. Open an **XAUUSD M1** chart (any gold symbol name works, e.g. `XAUUSD.a`, `GOLD`).
2. Attach the EA and set **Broker server timezone** = the broker's SERVER clock, not where the company is based
   (many UK-regulated brokers run GMT+2/+3 servers → `TZ_NY_CLOSE`). The Health panel checks it against
   the live clock and against gold's daily trading break in the price history (works in the tester too).
3. Check the dashboard **Health** section – everything should be green:
   - Timezone mismatch → the message says which setting to use.
   - News file → exported automatically on attach and every 6 h
     (`%APPDATA%\MetaQuotes\Terminal\Common\Files\ClaudeEA\calendar_utc.csv`).
   - Algo Trading / account permissions / connection.
4. The **Next news** line shows the next high-impact USD event (blue = upcoming, orange = entries blocked now).

## Backtesting on the new computer
- The tester can't read the economic calendar. Attach the EA to a live chart **once** so it writes
  `calendar_utc.csv`; the Common folder is shared by all MT5 terminals on that PC.
- After updating the EA, re-select it in the tester's Expert list before loading a .set file
  (the tester caches the old input list).

## Broker-independent settings
- Session times are in reference time GMT+2/+3 (US DST) and converted from the broker's timezone.
- Spread limit and slippage are prices ($0.60 / $0.50 on gold) – same meaning on 2- and 3-digit brokers.
- Risk uses the broker's own tick value (`OrderCalcProfit`), so contract size differences are handled.
- A trade whose correct size is below the broker's minimum lot is skipped (never rounded up).
