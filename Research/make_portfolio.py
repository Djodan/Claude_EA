"""Build ONE multi-pair .set (v4.52 Pair inputs) from a base set and each pair's own winning set.

Usage:  python make_portfolio.py <Name> --base <set> PAIR [PAIR ...] [InpX=value ...]
  PAIR = SYMBOL                  the pair runs the base set's settings
         SYMBOL=<set>            the pair runs <set> (only the inputs that differ from the base are written)
         SYMBOL=<set>;srisk=5    ...plus extra key=value items (short keys spread/slip/risk/srisk/irisk or any input)
         append @off             pair is in the set but switched off (e.g. GBPUSD=GBP_best@off)
  InpX=value                     overrides a base (chart) input
  --chunk N                      max characters per settings input (default 250; 4 inputs per pair)
<set> = a path, or a name in Research/sets or MQL5/Profiles/Tester (with or without .set / Claude_ prefix).
Writes <Name>.set to MQL5/Profiles/Tester and Research/sets via make_set.py.
e.g. python make_portfolio.py New_1k_Portfolio --base New_1k_1 XAUUSD GBPUSD=GBP_1k_best;srisk=5
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EA_FILE = HERE.parent / "Claude.mq5"
TESTER = HERE.parent.parent.parent / "Profiles" / "Tester"
MAX_PAIRS, PARTS = 5, 4
# inputs that are the same for every pair (chart / account level) - never written into pair settings
GLOBAL = re.compile(r"^Inp(Pair\d|Symbols$|SymbolSlot$|UseProfiles$|ServerTZ$|Magic$|Alert|Draw|BuyColor$|SellColor$|"
                    r"FontSize$|ShowDashboard$|Criterion$|MinTrades$|ReportResults$|ExportTrades$|NewsExport$|NewsFrom$)")


def find_set(name):
    for p in (Path(name), HERE / "sets" / name, TESTER / name):
        for q in (p, p.with_name(p.name + ".set"), p.with_name("Claude_" + p.name + ".set")):
            if q.is_file():
                return q
    sys.exit(f"set not found: {name}")


def read_set(path):
    raw = path.read_bytes()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", "ignore")
    vals = {}
    for line in text.splitlines():
        if not line or line.startswith(";") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v.split("||")[0].strip()
    return vals


def same(a, b):
    try:
        return abs(float(a) - float(b)) < 1e-9
    except ValueError:
        return a.lower() == b.lower()


def short(v):
    """compact value: true/false -> 1/0, 0.50 -> 0.5 (the EA reads both forms)"""
    if v.lower() in ("true", "false"):
        return "1" if v.lower() == "true" else "0"
    if re.fullmatch(r"-?\d+\.\d*", v):
        v = v.rstrip("0").rstrip(".")
    return v


def chunks(items, size):
    out, cur = [], ""
    for it in items:
        if len(it) > size:
            sys.exit(f"item longer than --chunk: {it}")
        if cur and len(cur) + 1 + len(it) > size:
            out.append(cur)
            cur = ""
        cur = f"{cur};{it}" if cur else it
    if cur:
        out.append(cur)
    return out


def main():
    args = sys.argv[1:]
    if len(args) < 3 or "--base" not in args:
        sys.exit(__doc__)
    size = 250
    if "--chunk" in args:
        i = args.index("--chunk")
        size = int(args[i + 1])
        del args[i:i + 2]
    i = args.index("--base")
    base_name = args[i + 1]
    del args[i:i + 2]
    name, rest = args[0], args[1:]
    fixed = [a for a in rest if a.startswith("Inp")]
    pairs = [a for a in rest if not a.startswith("Inp")]
    if not 1 <= len(pairs) <= MAX_PAIRS:
        sys.exit(f"1..{MAX_PAIRS} pairs needed, got {len(pairs)}")

    types = dict((m.group(2), m.group(1)) for m in
                 re.finditer(r"^\s*input\s+(\w+)\s+(\w+)\s*=", EA_FILE.read_text(encoding="utf-8"), re.M))
    base = read_set(find_set(base_name))

    out = []                                        # base (chart) inputs
    for k, v in base.items():
        t = types.get(k)
        if t is None or t == "color" or k.startswith("InpPair"):
            continue
        out.append(f'{k}="{v}"' if t == "string" else f"{k}={v}")

    report = []
    for n, spec in enumerate(pairs, 1):
        on = not spec.endswith("@off")
        spec = spec[:-4] if not on else spec
        sym, _, src = spec.partition("=")
        setname, *extra = src.split(";") if src else ("",)
        items = []
        if setname:
            pv = read_set(find_set(setname))
            for k, v in pv.items():
                if k in types and not GLOBAL.match(k) and types[k] != "color" and k in base and not same(v, base[k]):
                    if ";" in v:
                        sys.exit(f"{sym}: value of {k} contains ';'")
                    items.append(f"{k[3:]}={short(v)}")
        items += [e.strip() for e in extra if e.strip()]
        parts = chunks(items, size)
        if len(parts) > PARTS:
            sys.exit(f"{sym}: {len(items)} settings need {len(parts)} inputs of {size} chars (max {PARTS}) - "
                     f"raise --chunk or trim the pair set")
        parts += [""] * (PARTS - len(parts))
        out += [f"InpPair{n}_On={'true' if on else 'false'}", f'InpPair{n}="{sym}"']
        out += [f'InpPair{n}_S{j}="{p}"' for j, p in enumerate(parts, 1)]
        report.append(f"pair {n} {sym:8} {'on ' if on else 'OFF'} {len(items):3} settings "
                      f"({sum(map(len, parts))} chars){' from ' + setname if setname else ' = base'}")

    r = subprocess.run([sys.executable, str(HERE / "make_set.py"), name, "--exact-name", *out, *fixed],
                       capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode:
        sys.exit(r.stderr)
    print("\n".join(report))


if __name__ == "__main__":
    main()
