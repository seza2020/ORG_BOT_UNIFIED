# File: tools/scorecard_daily.py
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            try:
                out.append(json.loads(s))
            except Exception:
                continue
    return out


def _safe_float(x: Any) -> float | None:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None


def _is_forced(payload: dict[str, Any]) -> bool:
    # v2 heuristic (no orchestrator change required):
    # treat forced signals by the standard reason used in orchestrator tests
    r = str(payload.get("reason", "")).strip().lower()
    return ("forced_signal_test" in r) or ("forced" == str(payload.get("source", "")).strip().lower())


@dataclass
class SidStats:
    fires_forced: int = 0
    fires_real: int = 0

    accepts_forced: int = 0
    accepts_real: int = 0

    rejects: int = 0
    skips: int = 0

    conf_sum_forced: float = 0.0
    conf_n_forced: int = 0
    conf_sum_real: float = 0.0
    conf_n_real: int = 0

    rr_sum: float = 0.0
    rr_n: int = 0
    risk_sum: float = 0.0


def main() -> int:
    ap = argparse.ArgumentParser(description="Daily scorecard from meta.jsonl (v2)")
    ap.add_argument("--meta", default=r".\logs\meta.jsonl", help="meta jsonl path")
    ap.add_argument("--json", action="store_true", help="also print JSON summary")
    args = ap.parse_args()

    meta_path = Path(args.meta)
    events = _read_jsonl(meta_path)

    if not events:
        print(f"NO_DATA meta={meta_path}")
        return 2

    kind_counts = Counter()
    skip_reasons = Counter()
    reject_reasons = Counter()
    regime_counts = Counter()

    # per regime breakdown
    fires_by_regime = Counter()
    accepts_by_regime = Counter()
    skips_by_regime = Counter()
    rejects_by_regime = Counter()

    current_regime = "UNKNOWN"

    sid_stats: dict[str, SidStats] = defaultdict(SidStats)

    for ev in events:
        kind = str(ev.get("kind", "")).strip()
        kind_counts[kind] += 1

        payload = ev.get("payload") or {}
        if not isinstance(payload, dict):
            payload = {}

        if kind == "regime":
            r = str(payload.get("regime", "")).strip() or "UNKNOWN"
            current_regime = r
            regime_counts[r] += 1
            continue

        if kind == "signal_fire":
            sid = str(payload.get("sid", "")).strip()
            if sid:
                st = sid_stats[sid]
                forced = _is_forced(payload)
                c = _safe_float(payload.get("confidence"))

                if forced:
                    st.fires_forced += 1
                    if c is not None:
                        st.conf_sum_forced += c
                        st.conf_n_forced += 1
                else:
                    st.fires_real += 1
                    if c is not None:
                        st.conf_sum_real += c
                        st.conf_n_real += 1

                fires_by_regime[current_regime] += 1

        if kind == "signal_skip":
            sid = str(payload.get("sid", "")).strip()
            rsn = str(payload.get("reason", "")).strip()
            if rsn:
                skip_reasons[rsn] += 1
            if sid:
                sid_stats[sid].skips += 1
            skips_by_regime[current_regime] += 1

        if kind == "shadow_accept":
            sid = str(payload.get("sid", "")).strip()
            forced = _is_forced(payload)
            if sid:
                st = sid_stats[sid]
                if forced:
                    st.accepts_forced += 1
                else:
                    st.accepts_real += 1

                c = _safe_float(payload.get("confidence"))
                if forced:
                    if c is not None:
                        st.conf_sum_forced += c
                        st.conf_n_forced += 1
                else:
                    if c is not None:
                        st.conf_sum_real += c
                        st.conf_n_real += 1

                rr = _safe_float(payload.get("rr"))
                if rr is not None:
                    st.rr_sum += rr
                    st.rr_n += 1
                risk = _safe_float(payload.get("risk_usd"))
                if risk is not None:
                    st.risk_sum += risk

            accepts_by_regime[current_regime] += 1

        if kind == "shadow_reject":
            sid = str(payload.get("sid", "")).strip()
            reasons = payload.get("reasons")
            if isinstance(reasons, list):
                for r in reasons:
                    rs = str(r).strip()
                    if rs:
                        reject_reasons[rs] += 1
            if sid:
                sid_stats[sid].rejects += 1
            rejects_by_regime[current_regime] += 1

    # Print summary
    print(f"META={meta_path} events={len(events)}")
    print("KIND_COUNTS:", dict(kind_counts))

    if regime_counts:
        print("REGIME_COUNTS:", dict(regime_counts))

    if fires_by_regime:
        print("FIRES_BY_REGIME:", dict(fires_by_regime))
    if accepts_by_regime:
        print("ACCEPTS_BY_REGIME:", dict(accepts_by_regime))
    if skips_by_regime:
        print("SKIPS_BY_REGIME:", dict(skips_by_regime))
    if rejects_by_regime:
        print("REJECTS_BY_REGIME:", dict(rejects_by_regime))

    if skip_reasons:
        print("TOP_SKIP_REASONS:", skip_reasons.most_common(10))
    if reject_reasons:
        print("TOP_REJECT_REASONS:", reject_reasons.most_common(10))

    # SID table
    print("\nSID_STATS (v2):")
    print("sid | fireF | fireR | accF | accR | rejects | skips | avgConfF | avgConfR | avgRR | riskSum")
    for sid in sorted(sid_stats.keys()):
        st = sid_stats[sid]
        avg_cf = (st.conf_sum_forced / st.conf_n_forced) if st.conf_n_forced else None
        avg_cr = (st.conf_sum_real / st.conf_n_real) if st.conf_n_real else None
        avg_rr = (st.rr_sum / st.rr_n) if st.rr_n else None

        acf = f"{avg_cf:.3f}" if avg_cf is not None else "-"
        acr = f"{avg_cr:.3f}" if avg_cr is not None else "-"
        arr = f"{avg_rr:.3f}" if avg_rr is not None else "-"

        print(
            f"{sid:>3} | {st.fires_forced:>5} | {st.fires_real:>5} | {st.accepts_forced:>4} | {st.accepts_real:>4} | "
            f"{st.rejects:>7} | {st.skips:>5} | {acf:>8} | {acr:>8} | {arr:>5} | {st.risk_sum:>7.2f}"
        )

    if args.json:
        out = {
            "meta": str(meta_path),
            "events": len(events),
            "kind_counts": dict(kind_counts),
            "regime_counts": dict(regime_counts),
            "fires_by_regime": dict(fires_by_regime),
            "accepts_by_regime": dict(accepts_by_regime),
            "skips_by_regime": dict(skips_by_regime),
            "rejects_by_regime": dict(rejects_by_regime),
            "top_skip_reasons": skip_reasons.most_common(20),
            "top_reject_reasons": reject_reasons.most_common(20),
            "sid_stats": {
                sid: {
                    "fires_forced": st.fires_forced,
                    "fires_real": st.fires_real,
                    "accepts_forced": st.accepts_forced,
                    "accepts_real": st.accepts_real,
                    "rejects": st.rejects,
                    "skips": st.skips,
                    "avg_conf_forced": (st.conf_sum_forced / st.conf_n_forced) if st.conf_n_forced else None,
                    "avg_conf_real": (st.conf_sum_real / st.conf_n_real) if st.conf_n_real else None,
                    "avg_rr": (st.rr_sum / st.rr_n) if st.rr_n else None,
                    "risk_sum": st.risk_sum,
                }
                for sid, st in sid_stats.items()
            },
        }
        print("\nJSON_SUMMARY:")
        print(json.dumps(out, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
