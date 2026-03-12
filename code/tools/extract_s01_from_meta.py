# File: tools/extract_s01_from_meta.py
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--meta", required=True)
    ap.add_argument("--sid", default="S01")
    args = ap.parse_args()

    meta = Path(args.meta)
    sid = str(args.sid).upper()

    fires_real = 0
    accepts = 0
    rr_sum = 0.0
    rr_n = 0
    risk_sum = 0.0

    if not meta.exists():
        print(json.dumps({"error": "meta_not_found", "meta": str(meta)}))
        return 2

    with meta.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue

            kind = str(ev.get("kind", "")).lower()
            payload = ev.get("payload", {}) or {}

            # signal_fire (real vs forced)
            if kind == "signal_fire":
                if str(payload.get("sid", "")).upper() == sid:
                    src = str(payload.get("source", "real")).lower()
                    if src != "forced":
                        fires_real += 1

            # shadow_accept includes rr/risk
            if kind == "shadow_accept":
                if str(payload.get("sid", "")).upper() == sid:
                    accepts += 1
                    try:
                        risk_sum += float(payload.get("risk_usd", 0.0) or 0.0)
                    except Exception:
                        pass
                    try:
                        rr = float(payload.get("rr", None))
                        rr_sum += rr
                        rr_n += 1
                    except Exception:
                        pass

    avg_rr = (rr_sum / rr_n) if rr_n > 0 else 0.0

    out = {
        "sid": sid,
        "fires_real": fires_real,
        "accepts": accepts,
        "avg_rr": round(avg_rr, 4),
        "risk_sum": round(risk_sum, 2),
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
