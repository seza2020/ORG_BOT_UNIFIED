# File: tools/core_strength_hist.py
from __future__ import annotations

import json
import sys
from collections import Counter

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: core_strength_hist.py <meta.jsonl>")
        return 2
    path = sys.argv[1]
    vals = []
    bias = Counter()
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("kind") != "core_context":
                continue
            p = e.get("payload") or {}
            try:
                vals.append(float(p.get("trend_strength", 0.0)))
            except Exception:
                pass
            bias[str(p.get("bias",""))] += 1

    if not vals:
        print("no core_context found")
        return 3

    vals.sort()
    def pct(x):
        i = int(round((len(vals)-1)*x))
        return vals[max(0, min(len(vals)-1, i))]

    print("COUNT", len(vals))
    print("BIAS", dict(bias))
    print("P50", round(pct(0.50), 4))
    print("P75", round(pct(0.75), 4))
    print("P90", round(pct(0.90), 4))
    print("MAX", round(vals[-1], 4))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
