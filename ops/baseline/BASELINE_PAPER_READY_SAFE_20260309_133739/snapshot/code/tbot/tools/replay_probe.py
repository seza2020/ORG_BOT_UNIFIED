from __future__ import annotations
import os
from tbot.market.market_provider import build_market_snapshot

def main():
    syms = tuple((os.getenv("TBOT_SYMBOLS","SPY,QQQ").split(",")))
    for i in range(3):
        m = build_market_snapshot(symbols=syms)
        print("ITER", i, {k: (v.bar_index, v.ts, v.last, v.ema_fast, v.ema_slow, v.vwap) for k,v in m.items()})
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
