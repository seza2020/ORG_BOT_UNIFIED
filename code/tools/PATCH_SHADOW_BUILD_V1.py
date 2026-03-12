from __future__ import annotations
from pathlib import Path
import re, sys

ROOT = Path(r"C:\alpaca-bot\org_bot")
SH = ROOT / "tbot" / "runtime" / "shadow.py"
OR = ROOT / "tbot" / "runtime" / "orchestrator.py"

def write_shadow_py() -> None:
    # Canonical minimal-but-compatible shadow module
    SH.write_text(r'''from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional, Literal
import json
import os

ShadowSide = Literal["LONG","SHORT"]

def _now_iso() -> str:
    # keep it simple; orchestrator already has its own ts
    return datetime.now().isoformat(timespec="seconds")

@dataclass
class ShadowPlan:
    ts: str
    env: str
    sid: str
    symbol: str
    side: ShadowSide
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
        return json.dumps(self.__dict__, ensure_ascii=False)

class ShadowPlanWriter:
    def __init__(self, path: str):
        self.path = path

    def append(self, plan: ShadowPlan) -> None:
        # IMPORTANT: pricing must be applied here (writer path)
        from tbot.runtime.shadow_pricing import price_shadow_plan
        plan = price_shadow_plan(plan)

        line = plan.to_json()
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")

# Backward compatible alias
ShadowWriter = ShadowPlanWriter

def build_shadow_plan(*args: Any, **kwargs: Any) -> ShadowPlan:
    """
    Compatibility builder.
    Supports being called with kwargs like:
      sid=, symbol=, side=, confidence=, reason=, entry=, stop=, tp=, qty=, risk_usd=, notes=, env=, ts=
    Also supports a dict payload as first arg (legacy).
    """
    if args and isinstance(args[0], dict):
        d = dict(args[0])
        d.update(kwargs)
    else:
        d = dict(kwargs)

    ts = str(d.get("ts") or _now_iso())
    env = str(d.get("env") or os.getenv("TBOT_ENV","PAPER"))

    sid = str(d.get("sid") or d.get("strategy") or "S01")
    symbol = str(d.get("symbol") or "SPY")
    side = str(d.get("side") or "LONG").upper()
    if side not in ("LONG","SHORT"):
        side = "LONG"

    confidence = float(d.get("confidence") or 0.0)
    reason = str(d.get("reason") or "shadow_plan")

    entry = float(d.get("entry") or 100.0)
    stop  = float(d.get("stop")  or 99.0)
    tp    = float(d.get("tp")    or 102.0)

    risk_usd = float(d.get("risk_usd") or d.get("shadow_risk_usd") or 250.0)
    max_qty  = int(float(d.get("shadow_max_qty") or d.get("max_qty") or 5000))

    per_share_risk = abs(entry - stop) if abs(entry-stop) > 1e-9 else 1.0
    qty = int(d.get("qty") or int(max(1, min(max_qty, risk_usd / per_share_risk))))
    rr = float(d.get("rr") or (abs(tp-entry) / per_share_risk if per_share_risk else 0.0))

    notes = str(d.get("notes") or "")
    return ShadowPlan(
        ts=ts, env=env, sid=sid, symbol=symbol, side=side, confidence=confidence, reason=reason,
        entry=entry, stop=stop, tp=tp, qty=qty, risk_usd=risk_usd, per_share_risk=float(per_share_risk), rr=rr,
        notes=notes
    )
''', encoding="utf-8")

def patch_orchestrator_py() -> None:
    txt = OR.read_text(encoding="utf-8", errors="replace")

    # 1) If plan is None, skip limiter/gate (prevents NoneType crash)
    # Replace the single line limiter.can_accept(plan.sid, now) with a guarded block.
    needle = r"ok_acc, rsn_acc = limiter\.can_accept\(plan\.sid, now\)"
    if re.search(needle, txt):
        repl = (
            "if plan is None:\n"
            "                logger.error('shadow_plan_none_skip', extra={'reason':'build_shadow_plan_failed'})\n"
            "                continue\n"
            "            ok_acc, rsn_acc = limiter.can_accept(plan.sid, now)"
        )
        txt = re.sub(needle, repl, txt, count=1)
    else:
        # If anchor not found, fail loud so we don't silently do nothing
        raise SystemExit("no_anchor: limiter.can_accept(plan.sid, now) not found")

    OR.write_text(txt, encoding="utf-8")

def main() -> None:
    write_shadow_py()
    patch_orchestrator_py()
    print(f"[PATCH] wrote {SH}")
    print(f"[PATCH] patched {OR}")

if __name__ == "__main__":
    main()
