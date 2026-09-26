# Claude EA – project instructions

## Start here
Read `Research/HANDOFF.md` (full EA state, paths, set workflow, results, to-dos), then the tail of
`Research/PROGRESS.md` (test history). Live/portability guide: `DEPLOY.md`.

## Repository
- Scope: only this folder (`MQL5\Experts\Claude`). Remote: https://github.com/Djodan/Claude_EA.git, branch `main`.
- Commit and push after every meaningful step (pre-approved by the user) – code changes, new set files,
  results logged in PROGRESS.md.
- **Commit message format: `N. short description`** – N is sequential across the whole history
  (check `git log --oneline -1` and add 1). Examples: `41. HANDOFF.md - complete EA state for a new chat`,
  `40. New_Prop_High_Risk / New_Prop_Low_Risk - max loss per trade <= 0.8%`.
- Include compiled `Claude.ex5` with source changes; bump `EA_VERSION` in Claude.mq5 for behaviour changes.

## Naming
- Test rounds: `RoundN_<Topic>` set files (e.g. `Round25_PairAdapt`), logged as `## Round N – ...` in PROGRESS.md.
- Deliverable sets: `New_<Account>_<Variant>` (current: New_1k_1, New_1k_2, New_Prop_High_Risk, New_Prop_Low_Risk);
  older generations `Final_*`, `Halfway_Top_*`, `R19_*`, `best_2026`, `best_2025_2026`.
- Sets are generated with `Research/make_set.py` (writes `Research/sets/` and `MQL5/Profiles/Tester/`); never
  hand-edit UTF-16 .set files.

## Working style
- Replies short and summarized. Optimise broadly first (sizing included), add limits later.
- Compile yourself with MetaEditor64 (see HANDOFF.md); the user keeps MetaEditor closed and runs all backtests.
- After a recompile remind the user to re-select the EA before loading a set (tester caches inputs).
- Prop rules: $100k, no hedging, max loss per trade 0.8% (1% hard), best day ≤ 40% of total profit.
