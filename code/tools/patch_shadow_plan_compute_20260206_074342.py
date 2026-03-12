from __future__ import annotations
import io, os, re, sys, shutil
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
SH   = ROOT / r"tbot\runtime\shadow.py"

def fail(msg:str, code:int=1):
    print("[PATCH][FAIL]", msg)
    raise SystemExit(code)

def main():
    if not SH.exists():
        fail(f"missing {SH}")

    src = SH.read_text(encoding="utf-8")

    bak = SH.with_suffix(SH.suffix + f".bak_compute_{os.environ.get('TS','')}".rstrip('_'))
    if not bak.name.endswith(".py"):
        # keep as .py-like
        pass
    shutil.copyfile(SH, bak)
    print(f"[PATCH] backup -> {bak}")

    # Find build_shadow_plan function block
    m = re.search(r"(?ms)^def\s+build_shadow_plan\s*\(\s*.*?\)\s*->\s*ShadowPlan\s*:\s*(.*?)^(?=def\s|\Z)", src)
    if not m:
        fail("build_shadow_plan() not found")

    body = m.group(1)

    # Ensure max_qty param is accepted (not ignored)
    # If signature doesn't already include max_qty, add it.
    if "max_qty" not in src.split("def build_shadow_plan",1)[1].split(")->",1)[0]:
        # insert into signature near entry/stop/tp
        src = re.sub(
            r"(?ms)^(def\s+build_shadow_plan\s*\(\s*\*\s*,\s*sid:\s*str,\s*)(.*?)\n\)\s*->\s*ShadowPlan\s*:",
            lambda mm: mm.group(1) + mm.group(2) + "\n    max_qty: int = 0,\n",
            src,
            count=1
        )

    # Replace function body with computed logic while keeping original return ShadowPlan(...)
    # We'll locate the final `return ShadowPlan(` and rebuild a safe body.
    m2 = re.search(r"(?ms)^def\s+build_shadow_plan\s*\(.*?\)\s*->\s*ShadowPlan\s*:\s*(.*?)^\s*return\s+ShadowPlan\s*\(",
                   src)
    if not m2:
        fail("could not locate return ShadowPlan( inside build_shadow_plan")

    prefix = src[:m2.end(1)]
    rest   = src[m2.end(1):]

    # Build new pre-return logic
    inject = r'''
    # AUTO: compute per_share_risk / rr / qty if missing or invalid
    side_u = str(side).upper().strip() if side is not None else ""
    e = float(entry)
    s = float(stop)
    t = float(tp)

    # risk per share (must be positive)
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
    try:
        ru = float(risk_usd)
    except Exception:
        ru = 0.0

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

    # Normalize floats (avoid -0.0)
    try:
        per_share_risk = float(per_share_risk)
    except Exception:
        per_share_risk = 0.0
    try:
        rr = float(rr)
    except Exception:
        rr = 0.0
'''
    # Insert inject before return ShadowPlan(
    src_new = prefix + inject + rest

    SH.write_text(src_new, encoding="utf-8")
    print(f"[PATCH] wrote {SH}")

if __name__ == "__main__":
    main()
