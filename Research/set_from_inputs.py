"""Build a .set from a pass logged in Common/Files/ClaudeEA/inputs.csv (v4.55+: every pass's exact inputs).

Usage:  python set_from_inputs.py <Name> [--criterion X] [--profit X] [--trades N] [--from yyyy.mm.dd] [--list] [--first]
        Filters are ANDed (criterion / profit match to 0.01). --list shows matching rows without writing.
        e.g. python Research/set_from_inputs.py NAS_A --criterion 3227.51 --from 2026.06.29
Writes <Name>.set to MQL5/Profiles/Tester and Research/sets via make_set.py (all inputs fixed, no ranges).
"""

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FILE = Path("C:/Users/dmavi/AppData/Roaming/MetaQuotes/Terminal/Common/Files/ClaudeEA/inputs.csv")


def opt(args, key, conv=str):
    if key in args:
        i = args.index(key)
        v = conv(args[i + 1])
        del args[i:i + 2]
        return v
    return None


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    lst = "--list" in args
    first = "--first" in args               # several matches: take the one with the fewest engines on
    args = [a for a in args if a not in ("--list", "--first")]
    crit, prof, trades, frm = opt(args, "--criterion", float), opt(args, "--profit", float), opt(args, "--trades", int), opt(args, "--from")
    name = args[0] if args else None
    rows = []                                    # plain tab split: the inputs column contains '"' (csv would merge lines)
    with open(FILE, encoding="utf-8", errors="ignore") as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) >= len(hdr):
                rows.append(dict(zip(hdr, p[:len(hdr) - 1] + ["\t".join(p[len(hdr) - 1:])])))
    hit = [r for r in rows
           if (crit is None or abs(float(r["criterion"]) - crit) < 0.01)
           and (prof is None or abs(float(r["net_profit"]) - prof) < 0.01)
           and (trades is None or int(r["trades"]) == trades)
           and (frm is None or r["from"] == frm)]
    for r in hit[:20]:
        print(r["run_time"], r["symbol"], r["from"], r["to"], "crit", r["criterion"], "net", r["net_profit"], "trades", r["trades"])
    if lst or not hit:
        sys.exit(0 if hit else "no matching row")
    if len({r["inputs"] for r in hit}) > 1:
        if not first:
            sys.exit(f"{len(hit)} rows with different inputs match - narrow the filter or add --first")
        # identical results, different inputs = parameters of engines that never traded: take the fewest engines on
        eng = lambda r: sum(f"Inp{e}_Enable=true" in r["inputs"] for e in "TBNPMKVX")
        hit.sort(key=eng)
    out = []
    for item in hit[0]["inputs"].split(";"):
        if "=" not in item:
            continue
        k, v = item.split("=", 1)
        if k.startswith("InpBuyColor") or k.startswith("InpSellColor"):
            continue
        out.append(f'{k}="{v.strip(chr(34)).replace("|", ";")}"' if v.startswith('"') else f"{k}={v}")
    r = subprocess.run([sys.executable, str(HERE / "make_set.py"), name, "--exact-name", *out], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr)


if __name__ == "__main__":
    main()
