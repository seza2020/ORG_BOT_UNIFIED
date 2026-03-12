# File: tools/make_replay_sample.py
from __future__ import annotations

import csv
from pathlib import Path


def main() -> int:
    out = Path(r".\replay\replay.csv")
    out.parent.mkdir(parents=True, exist_ok=True)

    # Minimal deterministic sample: alternating SPY/QQQ, with increasing last
    rows = []
    last_spy = 100.0
    last_qqq = 200.0
    for i in range(200):
        if i % 2 == 0:
            last_spy += 0.1
            rows.append({
                "symbol": "SPY",
                "last": f"{last_spy:.2f}",
                "vwap": f"{(last_spy-0.05):.2f}",
                "ema_fast": f"{(last_spy-0.02):.2f}",
                "ema_slow": f"{(last_spy-0.08):.2f}",
            })
        else:
            last_qqq += 0.2
            rows.append({
                "symbol": "QQQ",
                "last": f"{last_qqq:.2f}",
                "vwap": f"{(last_qqq-0.10):.2f}",
                "ema_fast": f"{(last_qqq-0.04):.2f}",
                "ema_slow": f"{(last_qqq-0.16):.2f}",
            })

    with out.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["symbol","last","vwap","ema_fast","ema_slow"])
        w.writeheader()
        w.writerows(rows)

    print(f"WROTE {out} rows={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
