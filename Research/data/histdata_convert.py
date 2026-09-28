"""HistData.com M1 zips -> one MT5 custom-symbol bar file (NY-close server time).

Usage:  python histdata_convert.py [PAIR] [SYMBOL] [SPREAD_POINTS]
        default: NSXUSD NAS100_CONT 50        (50 points of 0.01 = 0.50 index points, conservative vs MNQ 0.25)
Reads:  C:/Users/dmavi/Downloads/HISTDATA_COM_ASCII_<PAIR>_M1*.zip   (browser downloads from histdata.com)
Writes: <Common>/Files/ClaudeEA/data/<SYMBOL>_M1.csv   time,open,high,low,close,tickvol,spread
HistData time = EST without DST (UTC-5 all year) -> UTC -> GMT+2 / GMT+3 while US DST is on (EA reference clock).
Import with the MT5 script Claude_ImportCustom (Ticks = false if there are no tick files).
"""
import collections
import datetime as dt
import io
import sys
import zipfile
from pathlib import Path

PAIR = sys.argv[1] if len(sys.argv) > 1 else "NSXUSD"
SYM = sys.argv[2] if len(sys.argv) > 2 else "NAS100_CONT"
SPREAD = int(sys.argv[3]) if len(sys.argv) > 3 else 50
SRC = Path("C:/Users/dmavi/Downloads")
OUT = Path("C:/Users/dmavi/AppData/Roaming/MetaQuotes/Terminal/Common/Files/ClaudeEA/data")


def us_dst(utc):
    y = utc.year
    mar = dt.datetime(y, 3, 8) + dt.timedelta(days=(6 - dt.datetime(y, 3, 8).weekday()) % 7, hours=7)
    nov = dt.datetime(y, 11, 1) + dt.timedelta(days=(6 - dt.datetime(y, 11, 1).weekday()) % 7, hours=6)
    return mar <= utc < nov


def main():
    bars = {}
    zips = sorted(SRC.glob(f"HISTDATA_COM_ASCII_{PAIR}_M1*.zip"))
    for z in zips:
        with zipfile.ZipFile(z) as zf:
            for name in zf.namelist():
                if not name.lower().endswith(".csv"):
                    continue
                for line in io.TextIOWrapper(zf.open(name), encoding="ascii", errors="ignore"):
                    p = line.strip().split(";")
                    if len(p) < 5:
                        continue
                    est = dt.datetime.strptime(p[0], "%Y%m%d %H%M%S")
                    utc = est + dt.timedelta(hours=5)
                    srv = utc + dt.timedelta(hours=3 if us_dst(utc) else 2)
                    t = int(srv.replace(tzinfo=dt.timezone.utc).timestamp())
                    bars[t] = tuple(float(x) for x in p[1:5])
    OUT.mkdir(parents=True, exist_ok=True)
    months = collections.Counter()
    with open(OUT / f"{SYM}_M1.csv", "w", newline="") as f:
        f.write("time,open,high,low,close,tickvol,spread\n")
        for t in sorted(bars):
            o, h, l, c = bars[t]
            f.write(f"{t},{o:.2f},{h:.2f},{l:.2f},{c:.2f},4,{SPREAD}\n")
            months[dt.datetime.utcfromtimestamp(t).strftime("%Y-%m")] += 1
    first, last = min(bars), max(bars)
    print(f"{len(zips)} zips -> {len(bars)} M1 bars  {dt.datetime.utcfromtimestamp(first)} .. "
          f"{dt.datetime.utcfromtimestamp(last)} (server time)  -> {OUT / (SYM + '_M1.csv')}")
    print("bars per month:", " ".join(f"{m}:{n}" for m, n in sorted(months.items())))


if __name__ == "__main__":
    main()
