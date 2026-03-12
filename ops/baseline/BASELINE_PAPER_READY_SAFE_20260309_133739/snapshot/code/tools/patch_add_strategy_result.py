from __future__ import annotations

import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
TARGET = ROOT / "tbot" / "runtime" / "orchestrator.py"

MARK = 'kind="strategy_result"'

INJECT = r"""
{indent}# Strategy result telemetry (self-contained, safe)
{indent}try:
{indent}    _mvp = str(__import__("os").getenv("TBOT_ENABLE_S11_MVP", "0")).strip()
{indent}    _has_cc = (getattr(ctx, "core_context", None) is not None)
{indent}    _has_am = (getattr(ctx, "alpha_mode", None) is not None)
{indent}    _sig = sig
{indent}    ev = make_event(level="INFO", kind="strategy_result", payload={{
{indent}        "sid": str(strat.sid),
{indent}        "mvp_env": _mvp,
{indent}        "has_core_context": bool(_has_cc),
{indent}        "has_alpha_mode": bool(_has_am),
{indent}        "returned": ("NONE" if _sig is None else "SIGNAL"),
{indent}        "symbol": (None if _sig is None else str(getattr(_sig, "symbol", None))),
{indent}        "side": (None if _sig is None else str(getattr(_sig, "side", None))),
{indent}        "confidence": (None if _sig is None else float(getattr(_sig, "confidence", 0.0))),
{indent}        "reason": (None if _sig is None else str(getattr(_sig, "reason", ""))),
{indent}    }})
{indent}    meta.emit(ev); announce.emit(ev)
{indent}except Exception:
{indent}    pass
"""

def main() -> int:
    if not TARGET.exists():
        print(f"PATCH_FAIL: missing target: {TARGET}")
        return 2

    src = TARGET.read_text(encoding="utf-8")

    if MARK in src:
        print("PATCH_SKIP: strategy_result already present")
        return 0

    # Find the exact line: sig = strat.evaluate(ctx)
    m = re.search(r"(?m)^(?P<indent>[ \t]*)sig\s*=\s*strat\.evaluate\(\s*ctx\s*\)\s*$", src)
    if not m:
        print("PATCH_FAIL: could not find 'sig = strat.evaluate(ctx)' line")
        return 3

    indent = m.group("indent")

    # Insert immediately after that line
    insert_block = INJECT.format(indent=indent)
    out = src[:m.end()] + "\n" + insert_block + src[m.end():]

    # Backup
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = TARGET.with_suffix(f".py.bak_strategy_result_{ts}")
    shutil.copy2(TARGET, bak)

    TARGET.write_text(out, encoding="utf-8")
    print(f"PATCH_OK: wrote strategy_result block | backup={bak}")

    # Compile check
    import py_compile
    try:
        py_compile.compile(str(TARGET), doraise=True)
    except Exception as e:
        print(f"COMPILE_FAIL: {e}")
        shutil.copy2(bak, TARGET)
        print(f"ROLLBACK_OK: restored from {bak}")
        return 4

    print("COMPILE_OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
