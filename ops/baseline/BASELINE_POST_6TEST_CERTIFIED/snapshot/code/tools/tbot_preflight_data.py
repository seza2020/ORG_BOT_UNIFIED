import os, sys, time
from pathlib import Path

# allow running from anywhere (Temp, Task Scheduler, etc.)
ROOT = r"C:\alpaca-bot\org_bot"
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from tbot.market.market_provider import build_market_snapshot

need = ("last","vwap","ema_fast","ema_slow","bar_index")

def one(sym: str):
    snap = build_market_snapshot((sym,))
    s = getattr(snap, sym, None)
    if s is None:
        return None, ["SNAP_ATTR_MISSING"]
    vals = {k: getattr(s, k, None) for k in need}
    missing = [k for k,v in vals.items() if v is None]
    return vals, missing

def main():
    sym = os.environ.get("TBOT_SYMBOLS","SPY").split(",")[0].strip() or "SPY"
    good = 0
    bad = 0
    last_bad = None

    # 10 samples ~10s
    for i in range(10):
        vals, missing = one(sym)
        if vals and not missing:
            good += 1
        else:
            bad += 1
            last_bad = (vals, missing)
        time.sleep(1)

    # Minimal output
    if good >= 7:
        vals, _ = one(sym)
        print(f"PREFLIGHT_OK sym={sym} good={good} bad={bad} last={vals['last']} vwap={vals['vwap']} ef={vals['ema_fast']} es={vals['ema_slow']} bi={vals['bar_index']}")
        raise SystemExit(0)

    print(f"PREFLIGHT_DATA_BAD sym={sym} good={good} bad={bad} last_bad={last_bad}")
    raise SystemExit(2)

if __name__ == "__main__":
    main()
