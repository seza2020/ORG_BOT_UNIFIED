from __future__ import annotations

import argparse
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

BINS = [0.0, 0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.12, 0.2, 0.35, 0.5, 1.01]
THRESHOLDS = [0.0, 0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.12]

def _bin(x: float) -> str:
    for i in range(len(BINS)-1):
        a, b = BINS[i], BINS[i+1]
        if a <= x < b:
            return f"[{a:.3f},{b:.3f})"
    return f"[{BINS[-2]:.3f},{BINS[-1]:.3f})"

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--meta", required=True, help="meta jsonl path")
    args = ap.parse_args()

    p = Path(args.meta)
    if not p.exists():
        print("NO_FILE", p)
        return 2

    fires = []   # (sid, conf, regime)
    accepts = [] # (sid, conf, regime)

    last_regime = None

    with p.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            kind = str(ev.get("kind",""))
            payload = ev.get("payload", {}) or {}

            if kind == "regime":
                last_regime = str(payload.get("regime","")) or None

            if kind == "signal_fire":
                sid = str(payload.get("sid",""))
                conf = float(payload.get("confidence", 0.0) or 0.0)
                fires.append((sid, conf, last_regime or "UNKNOWN"))

            if kind == "shadow_accept":
                sid = str(payload.get("sid",""))
                conf = float(payload.get("confidence", 0.0) or 0.0)
                accepts.append((sid, conf, last_regime or "UNKNOWN"))

    print(f"META={p} fires={len(fires)} accepts={len(accepts)}")

    # Histogram (fires)
    h = Counter()
    for _, conf, _ in fires:
        h[_bin(conf)] += 1
    print("CONF_HIST_FIRES:")
    for k in sorted(h.keys()):
        print(f"  {k}: {h[k]}")

    # Acceptance ratio by threshold (global, fires->accepts proxy)
    # Since accepts correspond to gate pass, for now we compute how many fires would survive thresholds.
    confs = [c for _, c, _ in fires]
    if confs:
        confs_sorted = sorted(confs)
        p50 = confs_sorted[int(0.50*(len(confs_sorted)-1))]
        p75 = confs_sorted[int(0.75*(len(confs_sorted)-1))]
        p90 = confs_sorted[int(0.90*(len(confs_sorted)-1))]
        print(f"CONF_PCTS: p50={p50:.4f} p75={p75:.4f} p90={p90:.4f}")

    print("THRESHOLD_SURVIVAL (fires):")
    for t in THRESHOLDS:
        kept = sum(1 for c in confs if c >= t)
        rate = kept / max(1, len(confs))
        print(f"  min_conf>={t:.3f}: kept={kept} ({rate*100:.1f}%)")

    # Breakdown by regime
    by_reg = defaultdict(list)
    for _, conf, reg in fires:
        by_reg[reg].append(conf)
    print("BY_REGIME_PCTS (fires):")
    for reg, lst in sorted(by_reg.items()):
        lst = sorted(lst)
        p50 = lst[int(0.50*(len(lst)-1))]
        p75 = lst[int(0.75*(len(lst)-1))]
        p90 = lst[int(0.90*(len(lst)-1))]
        print(f"  {reg}: n={len(lst)} p50={p50:.4f} p75={p75:.4f} p90={p90:.4f}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
