from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Any, Optional
import json

@dataclass
class ShadowPlan:
    ts: str
    env: str
    sid: str
    symbol: str
    side: str
    confidence: float
    reason: str
    entry: float
    stop: float
    tp: float
    qty: int
    risk_usd: float
    per_share_risk: float
    rr: float
    notes: str = ""

    def to_json(self) -> str:
        return json.dumps(asdict(self), ensure_ascii=False)

    @staticmethod
    def from_any(obj: Any) -> "ShadowPlan":
        if isinstance(obj, ShadowPlan):
            return obj
        if isinstance(obj, dict):
            return ShadowPlan(**obj)
        # attribute-like
        d = {k: getattr(obj, k) for k in (
            "ts","env","sid","symbol","side","confidence","reason",
            "entry","stop","tp","qty","risk_usd","per_share_risk","rr","notes"
        ) if hasattr(obj, k)}
        return ShadowPlan(**d)

def build_shadow_plan(
    *,
    sid: str,
    symbol: str,
    side: str,
    confidence: float,
    reason: str,
    entry: float,
    stop: float,
    tp: float,
    risk_usd: float = 0.0,
    max_qty: int = 0,
    qty: int = 0,
    per_share_risk: float = 0.0,
    rr: float = 0.0,
    notes: str = "",
    ts: str | None = None,
    env: str = "PAPER",
    **_ignored,
) -> "ShadowPlan":
    """
    Build a ShadowPlan from priced levels.
    Computes per_share_risk, rr, and qty if missing/invalid.
    Keeps it robust against extra kwargs.
    """
    if ts is None:
        ts = datetime.utcnow().isoformat(timespec="seconds")

    side_u = str(side).upper().strip() if side is not None else ""
    e = float(entry); s = float(stop); t = float(tp)

    # per-share risk and rr (must be positive)
    if side_u == "SHORT":
        psr = float(s - e)
        rr_calc = (e - t) / psr if psr > 0 else 0.0
    else:
        psr = float(e - s)
        rr_calc = (t - e) / psr if psr > 0 else 0.0

    if (per_share_risk is None) or (float(per_share_risk) <= 0.0):
        per_share_risk = psr

    if (rr is None) or (float(rr) <= 0.0):
        rr = rr_calc

    # qty from risk_usd / per_share_risk
    ru = float(risk_usd) if risk_usd is not None else 0.0
    if (qty is None) or (int(qty) <= 0):
        if (per_share_risk is not None) and (float(per_share_risk) > 0.0) and (ru > 0.0):
            q = int(ru / float(per_share_risk))
            if q < 1:
                q = 1
            mq = int(max_qty) if max_qty is not None else 0
            if mq > 0 and q > mq:
                q = mq
            qty = q
        else:
            qty = 0

    # normalize
    per_share_risk = float(per_share_risk) if per_share_risk is not None else 0.0
    rr = float(rr) if rr is not None else 0.0

    return ShadowPlan(
        ts=str(ts),
        env=str(env),
        sid=str(sid),
        symbol=str(symbol),
        side=str(side_u),
        confidence=float(confidence),
        reason=str(reason),
        entry=float(e),
        stop=float(s),
        tp=float(t),
        qty=int(qty),
        risk_usd=float(ru),
        per_share_risk=float(per_share_risk),
        rr=float(rr),
        notes=str(notes) if notes is not None else "",
    )


class ShadowPlanWriter:
    def __init__(self, path: str):
        self.path = path

    def append(self, plan: ShadowPlan) -> None:
        import os, json
        import datetime as _dt

        try:
            # best-effort stringify
            if hasattr(plan, "to_json"):
                line = plan.to_json()
            else:
                try:
                    line = json.dumps(getattr(plan, "__dict__", {}), ensure_ascii=False)
                except Exception:
                    line = json.dumps({"plan": str(plan)}, ensure_ascii=False)

            with open(self.path, "a", encoding="utf-8") as f:
                f.write(line + "\n")
                f.flush()
                try:
                    os.fsync(f.fileno())
                except Exception:
                    pass
        except Exception as e:
            # sidecar error log (never silent)
            try:
                errp = str(self.path) + ".write_errors.log"
                with open(errp, "a", encoding="utf-8") as ef:
                    ef.write(f"{_dt.datetime.now(_dt.timezone.utc).isoformat()} | append_failed | {type(e).__name__}: {e}\n")
            except Exception:
                pass
            raise
