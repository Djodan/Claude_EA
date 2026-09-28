"""Convert downloaded Dukascopy tick files into MT5 custom-symbol import files (NY-close server time).

Usage:  python duka_convert.py [INSTRUMENT] [SYMBOL] [PRICE_DIV] [TICKS_FROM yyyy-mm]
        default: USATECHIDXUSD NAS100_CONT 1000 2026-01
Reads:  C:/Users/dmavi/ClaudeData/<INSTRUMENT>/raw/YYYY/MM/DD/HHh.bi5 (duka_download.py)
Writes: <Common>/Files/ClaudeEA/data/<SYMBOL>_M1.csv          time,open,high,low,close,tickvol,spread (bid bars, all months)
        <Common>/Files/ClaudeEA/data/<SYMBOL>_ticks_YYYYMM.bin  int64 time_msc, double bid, double ask (from TICKS_FROM)
Time:   UTC -> GMT+2, GMT+3 while US DST is on (the "NY close" server clock the EA's session inputs use).
Import: run the MT5 script Claude_ImportCustom (Research/data/Claude_ImportCustom.mq5) with the same SYMBOL.
"""
import datetime as dt
import lzma
import struct
import sys
from array import array
from pathlib import Path

INST = sys.argv[1] if len(sys.argv) > 1 else "USATECHIDXUSD"
SYM = sys.argv[2] if len(sys.argv) > 2 else "NAS100_CONT"
DIV = float(sys.argv[3]) if len(sys.argv) > 3 else 1000.0
TICKS_FROM = sys.argv[4] if len(sys.argv) > 4 else "2026-01"
RAW = Path("C:/Users/dmavi/ClaudeData") / INST / "raw"
OUT = Path("C:/Users/dmavi/AppData/Roaming/MetaQuotes/Terminal/Common/Files/ClaudeEA/data")
POINT = 0.01


def us_dst(utc):
    """US DST: 2nd Sunday of March 07:00 UTC .. 1st Sunday of November 06:00 UTC."""
    y = utc.year
    mar = dt.datetime(y, 3, 8) + dt.timedelta(days=(6 - dt.datetime(y, 3, 8).weekday()) % 7, hours=7)
    nov = dt.datetime(y, 11, 1) + dt.timedelta(days=(6 - dt.datetime(y, 11, 1).weekday()) % 7, hours=6)
    return mar <= utc < nov


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted(RAW.rglob("*h.bi5"))
    print(f"{len(files)} hour files")
    bars = open(OUT / f"{SYM}_M1.csv", "w", newline="")
    bars.write("time,open,high,low,close,tickvol,spread\n")
    tick_f, tick_month = None, None
    cur = None                                     # [minute_sec, o, h, l, c, n, spread]
    nticks = nbars = 0
    for p in files:
        rel = p.relative_to(RAW).parts             # YYYY, MM, DD, HHh.bi5
        hour = dt.datetime(int(rel[0]), int(rel[1]), int(rel[2]), int(rel[3][:2]))
        raw = p.read_bytes()
        if not raw:
            continue
        d = lzma.decompress(raw)
        shift = 3 if us_dst(hour) else 2
        base_ms = int((hour + dt.timedelta(hours=shift)).replace(tzinfo=dt.timezone.utc).timestamp()) * 1000
        month = f"{hour + dt.timedelta(hours=shift):%Y%m}"
        want_ticks = f"{month[:4]}-{month[4:]}" >= TICKS_FROM
        if want_ticks and month != tick_month:
            if tick_f:
                tick_f.close()
            tick_f, tick_month = open(OUT / f"{SYM}_ticks_{month}.bin", "wb"), month
        buf = array("d") if want_ticks else None
        for off in range(0, len(d) - 19, 20):
            ms, ask_i, bid_i, _, _ = struct.unpack_from(">3I2f", d, off)
            bid, ask = bid_i / DIV, ask_i / DIV
            t_ms = base_ms + ms
            if want_ticks:
                tick_f.write(struct.pack("<qdd", t_ms, bid, ask))
                nticks += 1
            m = t_ms // 60000 * 60
            if cur is None or m != cur[0]:
                if cur:
                    bars.write(f"{cur[0]},{cur[1]:.2f},{cur[2]:.2f},{cur[3]:.2f},{cur[4]:.2f},{cur[5]},{cur[6]}\n")
                    nbars += 1
                cur = [m, bid, bid, bid, bid, 0, 0]
            cur[2] = max(cur[2], bid)
            cur[3] = min(cur[3], bid)
            cur[4] = bid
            cur[5] += 1
            cur[6] = int(round((ask - bid) / POINT))
        if nbars and nbars % 100000 < 60:
            print(f"{hour:%Y-%m-%d %H}h  bars {nbars}  ticks {nticks}", flush=True)
    if cur:
        bars.write(f"{cur[0]},{cur[1]:.2f},{cur[2]:.2f},{cur[3]:.2f},{cur[4]:.2f},{cur[5]},{cur[6]}\n")
        nbars += 1
    bars.close()
    if tick_f:
        tick_f.close()
    print(f"done: {nbars} M1 bars, {nticks} ticks -> {OUT}")


if __name__ == "__main__":
    main()
