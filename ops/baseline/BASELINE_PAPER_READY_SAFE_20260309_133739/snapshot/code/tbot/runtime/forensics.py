# tbot/runtime/forensics.py
from __future__ import annotations

import os, time, sys

def _runroot() -> str:
    return (os.getenv("TBOT_RUNROOT") or os.getenv("TBOT_RUNTIME") or "").strip()

def _ops_dir(rr: str) -> str:
    return os.path.join(rr, "logs", "ops")

def audit_entrypoint_rc(rc) -> None:
    # Enabled by env flag only
    if os.getenv("TBOT_FORENSICS", "0") != "1":
        return
    rr = _runroot()
    if not rr:
        return
    try:
        ops = _ops_dir(rr)
        os.makedirs(ops, exist_ok=True)
        p = os.path.join(ops, "ENTRYPOINT_RC_AUDIT.log")
        with open(p, "a", encoding="utf-8") as f:
            f.write(f"ts={time.time():.0f} rc={rc!r} argv={sys.argv!r} runroot={rr!r}\n")
    except Exception:
        return
