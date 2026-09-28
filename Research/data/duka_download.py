"""Download Dukascopy hourly tick files (bi5) for one instrument - resumable, rate-limit friendly.

Usage:  python duka_download.py [INSTRUMENT] [FROM yyyy-mm-dd] [TO yyyy-mm-dd] [WORKERS]
        default: USATECHIDXUSD 2025-01-01 <today> 3
Files:  C:/Users/dmavi/ClaudeData/<INSTRUMENT>/raw/YYYY/MM/DD/HHh.bi5   (empty file = no ticks that hour)
Already downloaded hours are skipped, so the script can be stopped and restarted any time.
Source: https://datafeed.dukascopy.com/datafeed/<INSTRUMENT>/<YYYY>/<MM-1>/<DD>/<HH>h_ticks.bi5 (UTC hours)
"""
import datetime as dt
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

INST = sys.argv[1] if len(sys.argv) > 1 else "USATECHIDXUSD"
FROM = dt.datetime.strptime(sys.argv[2], "%Y-%m-%d") if len(sys.argv) > 2 else dt.datetime(2025, 1, 1)
TO = dt.datetime.strptime(sys.argv[3], "%Y-%m-%d") if len(sys.argv) > 3 else dt.datetime.utcnow()
WORKERS = int(sys.argv[4]) if len(sys.argv) > 4 else 3
ROOT = Path("C:/Users/dmavi/ClaudeData") / INST / "raw"
LOG = ROOT.parent / "download.log"
HDR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126.0"}
lock = threading.Lock()
stats = {"ok": 0, "empty": 0, "fail": 0, "skip": 0}


def hours():
    t = FROM
    while t < TO:
        wd = t.weekday()                       # index CFD: closed Sat, Sun before 22 UTC, Fri after 21 UTC
        if not (wd == 5 or (wd == 6 and t.hour < 22) or (wd == 4 and t.hour >= 21)):
            yield t
        t += dt.timedelta(hours=1)


def path(t):
    return ROOT / f"{t:%Y}" / f"{t:%m}" / f"{t:%d}" / f"{t:%H}h.bi5"


def fetch(t):
    p = path(t)
    if p.exists():
        with lock:
            stats["skip"] += 1
        return
    url = f"https://datafeed.dukascopy.com/datafeed/{INST}/{t.year}/{t.month - 1:02d}/{t.day:02d}/{t.hour:02d}h_ticks.bi5"
    data, wait = None, 2.0
    for _ in range(12):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers=HDR), timeout=40).read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                data = b""
                break
        except Exception:
            pass
        time.sleep(wait)
        wait = min(wait * 1.6, 60)
    with lock:
        if data is None:
            stats["fail"] += 1
            return
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        stats["ok" if data else "empty"] += 1


def main():
    todo = list(hours())
    t0 = time.time()
    print(f"{INST}: {len(todo)} hours {FROM:%Y-%m-%d}..{TO:%Y-%m-%d}, {WORKERS} workers -> {ROOT}", flush=True)
    with ThreadPoolExecutor(WORKERS) as ex:
        for i, _ in enumerate(ex.map(fetch, todo), 1):
            if i % 50 == 0 or i == len(todo):
                el = time.time() - t0
                line = (f"{i}/{len(todo)} ok {stats['ok']} empty {stats['empty']} skip {stats['skip']} "
                        f"fail {stats['fail']} | {el / 60:.1f} min")
                print(line, flush=True)
                with open(LOG, "a") as f:
                    f.write(time.strftime("%H:%M:%S ") + line + "\n")
    print("done", stats, flush=True)


if __name__ == "__main__":
    main()
