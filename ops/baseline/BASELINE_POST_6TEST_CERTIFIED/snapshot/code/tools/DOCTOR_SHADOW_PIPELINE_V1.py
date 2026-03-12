from __future__ import annotations
from pathlib import Path
import subprocess, sys, re, json, inspect

ROOT = Path(r"C:\alpaca-bot\org_bot")
PY = ROOT / ".venv" / "Scripts" / "python.exe"

OR = ROOT / "tbot" / "runtime" / "orchestrator.py"
SH = ROOT / "tbot" / "runtime" / "shadow.py"
SP = ROOT / "tbot" / "runtime" / "shadow_pricing.py"

def run_py_compile(path: Path) -> tuple[bool, str]:
    p = subprocess.run([str(PY), "-m", "py_compile", str(path)], capture_output=True, text=True)
    ok = (p.returncode == 0)
    out = (p.stdout or "") + (p.stderr or "")
    return ok, out.strip()

def latest_good_backup(target: Path) -> Path | None:
    # Look for: orchestrator.py.bak_* (and any .bak* variants)
    cand = []
    for pat in [target.name + ".bak_*", target.name + ".bak*", target.name + ".*bak*"]:
        cand.extend(target.parent.glob(pat))
    # Dedup
    seen = set()
    uniq = []
    for c in cand:
        if c.exists():
            k = str(c).lower()
            if k not in seen:
                seen.add(k)
                uniq.append(c)
    # Sort newest first
    uniq.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    for b in uniq:
        ok, _ = run_py_compile(b)
        if ok:
            return b
    return None

def restore_if_broken(path: Path) -> bool:
    ok, msg = run_py_compile(path)
    if ok:
        print(f"[OK] compile: {path}")
        return True
    print(f"[BROKEN] compile failed: {path}")
    print(msg.splitlines()[-15:])
    b = latest_good_backup(path)
    if not b:
        print(f"[FAIL] no compiling backup found for: {path}")
        return False
    bak_keep = path.with_name(path.name + f".doctor_keep_{now_tag()}.bak")
    bak_keep.write_text(path.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    path.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[RESTORE] restored from backup: {b.name}")
    print(f"[RESTORE] kept broken copy at: {bak_keep.name}")
    ok2, msg2 = run_py_compile(path)
    if not ok2:
        print(f"[FAIL] restored file still does not compile: {path}")
        print(msg2)
        return False
    print(f"[OK] compile after restore: {path}")
    return True

def now_tag() -> str:
    import datetime
    return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

def ensure_shadow_module():
    # Rebuild shadow.py to a minimal, consistent, attribute-safe implementation.
    # This avoids mismatch between orchestrator imports and the writer path.
    src = r'''from __future__ import annotations

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
    env: str = "PAPER",
    entry: float = 100.0,
    stop: float = 99.0,
    tp: float = 102.0,
    qty: int = 0,
    risk_usd: float = 0.0,
    per_share_risk: float = 0.0,
    rr: float = 0.0,
    notes: str = "",
    ts: Optional[str] = None,
    **_ignored: Any,
) -> ShadowPlan:
    if ts is None:
        ts = datetime.utcnow().replace(microsecond=0).isoformat()
    return ShadowPlan(
        ts=ts, env=env, sid=sid, symbol=symbol, side=side,
        confidence=float(confidence), reason=str(reason),
        entry=float(entry), stop=float(stop), tp=float(tp),
        qty=int(qty), risk_usd=float(risk_usd),
        per_share_risk=float(per_share_risk), rr=float(rr),
        notes=str(notes) if notes is not None else ""
    )

class ShadowPlanWriter:
    def __init__(self, path: str):
        self.path = path

    def append(self, plan: ShadowPlan) -> None:
        from tbot.runtime.shadow_pricing import price_shadow_plan
        plan = price_shadow_plan(plan)
        plan = ShadowPlan.from_any(plan)
        line = plan.to_json()
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")

# backward compat alias
ShadowWriter = ShadowPlanWriter
'''
    # Keep backup
    if SH.exists():
        SH_bak = SH.with_name(SH.name + f".doctor_bak_{now_tag()}")
        SH_bak.write_text(SH.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print(f"[BACKUP] {SH.name} -> {SH_bak.name}")
    SH.write_text(src, encoding="utf-8")
    ok, msg = run_py_compile(SH)
    if not ok:
        raise RuntimeError(f"shadow.py rebuild failed:\n{msg}")
    print("[OK] rebuilt shadow.py (ShadowPlan + ShadowPlanWriter + build_shadow_plan)")

def ensure_shadow_pricing_wrapper():
    # Ensure price_shadow_plan exists and can call existing pricing functions safely.
    txt = SP.read_text(encoding="utf-8", errors="replace") if SP.exists() else ""
    if "def price_shadow_plan(" in txt:
        print("[OK] shadow_pricing.py already has price_shadow_plan")
        return

    wrapper = r'''
# ---- AUTO: price_shadow_plan wrapper (doctor) ----
def price_shadow_plan(plan):
    """
    Unifies pricing into writer path.
    Tries to call whatever pricing function exists in this module and apply
    entry/stop/tp back onto the plan object/dict.

    Returns: plan (same type as input if possible)
    """
    import os, inspect

    # normalize access
    def get(obj, k, default=None):
        if isinstance(obj, dict):
            return obj.get(k, default)
        return getattr(obj, k, default)

    def setv(obj, k, v):
        if isinstance(obj, dict):
            obj[k] = v
            return obj
        try:
            setattr(obj, k, v)
        except Exception:
            pass
        return obj

    symbol = get(plan, "symbol", None)
    side = get(plan, "side", None)

    # env knobs
    price_mode = os.getenv("TBOT_SHADOW_PRICE_MODE", "last")
    rr = float(os.getenv("TBOT_SHADOW_RR", str(get(plan,"rr", 2.0) or 2.0)))
    stop_pct = float(os.getenv("TBOT_SHADOW_STOP_PCT", "0.003"))

    # candidates (most likely first)
    candidates = [
        "price_shadow_prices",
        "get_shadow_prices",
        "compute_shadow_prices",
        "calc_shadow_prices",
        "price_prices",
        "price",
    ]

    prices = None
    for name in candidates:
        fn = globals().get(name)
        if not callable(fn):
            continue
        try:
            sig = inspect.signature(fn)
            kwargs = {}
            for p in sig.parameters.values():
                if p.name in ("symbol", "sym"):
                    kwargs[p.name] = symbol
                elif p.name in ("side",):
                    kwargs[p.name] = side
                elif p.name in ("rr", "target_rr"):
                    kwargs[p.name] = rr
                elif p.name in ("stop_pct", "stop_percent"):
                    kwargs[p.name] = stop_pct
                elif p.name in ("price_mode", "mode"):
                    kwargs[p.name] = price_mode
            prices = fn(**kwargs) if kwargs else fn()
            if prices is not None:
                break
        except Exception:
            continue

    # Apply result
    # Accept: object with .entry/.stop/.tp or dict with keys or tuple/list (entry, stop, tp)
    if prices is None:
        return plan

    try:
        if isinstance(prices, dict):
            e, s, t = prices.get("entry"), prices.get("stop"), prices.get("tp")
        elif isinstance(prices, (tuple, list)) and len(prices) >= 3:
            e, s, t = prices[0], prices[1], prices[2]
        else:
            e = getattr(prices, "entry", None)
            s = getattr(prices, "stop", None)
            t = getattr(prices, "tp", None)

        if e is not None: plan = setv(plan, "entry", float(e))
        if s is not None: plan = setv(plan, "stop", float(s))
        if t is not None: plan = setv(plan, "tp", float(t))
    except Exception:
        return plan

    return plan
# ---- END AUTO ----
'''
    bak = SP.with_name(SP.name + f".doctor_bak_{now_tag()}") if SP.exists() else None
    if bak:
        bak.write_text(txt, encoding="utf-8")
        print(f"[BACKUP] {SP.name} -> {bak.name}")
    SP.write_text(txt + "\n" + wrapper, encoding="utf-8")
    ok, msg = run_py_compile(SP)
    if not ok:
        raise RuntimeError(f"shadow_pricing.py wrapper failed:\n{msg}")
    print("[OK] ensured price_shadow_plan exists in shadow_pricing.py")

def patch_orchestrator_plan_guard():
    # We patch orchestrator safely with minimal assumptions:
    # - after build_shadow_plan(...), ensure plan is not None
    # - if dict -> wrap into ShadowPlan.from_any
    txt = OR.read_text(encoding="utf-8", errors="replace")

    # Keep backup
    bak = OR.with_name(OR.name + f".doctor_bak_{now_tag()}")
    bak.write_text(txt, encoding="utf-8")
    print(f"[BACKUP] {OR.name} -> {bak.name}")

    # We need to find the location where shadow plan is built and appended.
    # Common marker: "shadow_writer.append(plan)"
    if "shadow_writer.append(plan)" not in txt:
        print("[WARN] anchor shadow_writer.append(plan) not found; skipping orchestrator guard patch")
        return

    # Insert guard just before append and limiter usage if applicable
    # We'll add a small block that normalizes plan.
    guard = r'''
        # ---- AUTO: doctor guard (plan normalization) ----
        try:
            from tbot.runtime.shadow import ShadowPlan
        except Exception:
            ShadowPlan = None

        if plan is None:
            logger.error("shadow_plan_none_skip", extra={"reason": "build_shadow_plan_failed"})
            continue

        if isinstance(plan, dict) and ShadowPlan is not None:
            try:
                plan = ShadowPlan.from_any(plan)
            except Exception:
                pass
        # ---- END AUTO ----
'''
    # Heuristic: place right before the first "shadow_writer.append(plan)"
    txt2 = re.sub(r"(^[ \t]*shadow_writer\.append$begin:math:text$plan$end:math:text$\s*$)",
                  guard + r"\1", txt, count=1, flags=re.MULTILINE)

    OR.write_text(txt2, encoding="utf-8")

    ok, msg = run_py_compile(OR)
    if not ok:
        # If our patch made it worse, revert to backup immediately.
        OR.write_text(bak.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        raise RuntimeError("orchestrator guard patch failed; reverted.\n" + msg)

    print("[OK] patched orchestrator.py with plan None/dict guard")

def main():
    print(f"[DOCTOR] ROOT={ROOT}")
    # 1) Restore orchestrator if currently broken (IndentationError etc.)
    if not restore_if_broken(OR):
        raise SystemExit(2)

    # 2) Ensure shadow + pricing wrappers (consistent modules)
    ensure_shadow_pricing_wrapper()
    ensure_shadow_module()

    # 3) Patch orchestrator to guard plan
    patch_orchestrator_plan_guard()

    # 4) Final compile verification
    for p in [OR, SH, SP]:
        ok, msg = run_py_compile(p)
        if not ok:
            print(f"[FAIL] final compile failed: {p}\n{msg}")
            raise SystemExit(3)

    print("[OK] DOCTOR complete: orchestrator+shadow+shadow_pricing all compile")

if __name__ == "__main__":
    main()
