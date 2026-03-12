from __future__ import annotations
import os, re, shutil
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
SH   = ROOT / r"tbot\runtime\shadow.py"

NEW_FUNC = r'''
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
'''

def fail(msg:str):
    print("[PATCH][FAIL]", msg)
    raise SystemExit(1)

def main():
    if not SH.exists():
        fail(f"missing {SH}")

    src = SH.read_text(encoding="utf-8")

    # Ensure datetime import exists (needed by NEW_FUNC)
    if not re.search(r"(?m)^\s*from\s+datetime\s+import\s+datetime\s*$", src):
        # Try to insert after existing imports block
        m = re.search(r"(?ms)^(?:from\s+__future__.*?\n)?((?:import|from)\s+.*\n)+", src)
        if m:
            insert_at = m.end(0)
            src = src[:insert_at] + "from datetime import datetime\n" + src[insert_at:]
        else:
            src = "from datetime import datetime\n" + src

    # Backup
    ts = os.environ.get("TS", "")
    bak = SH.with_suffix(SH.suffix + f".bak_rewrite_{ts}")
    shutil.copyfile(SH, bak)
    print(f"[PATCH] backup -> {bak}")

    # Replace the entire build_shadow_plan definition (from def line to before next top-level def/class)
    pat = r"(?ms)^def\s+build_shadow_plan\s*\(.*?\)\s*->.*?:\s*.*?(?=^\s*(?:def|class)\s+|\Z)"
    if not re.search(pat, src):
        # if annotation differs, try looser pattern
        pat = r"(?ms)^def\s+build_shadow_plan\s*\(.*?\):\s*.*?(?=^\s*(?:def|class)\s+|\Z)"
        if not re.search(pat, src):
            fail("build_shadow_plan definition not found")

    src2, n = re.subn(pat, NEW_FUNC.strip() + "\n\n", src, count=1)
    if n != 1:
        fail(f"unexpected replace count={n}")

    SH.write_text(src2, encoding="utf-8")
    print(f"[PATCH] rewrote build_shadow_plan in {SH}")

if __name__ == "__main__":
    main()
