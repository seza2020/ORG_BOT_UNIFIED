from __future__ import annotations

import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
TARGET = ROOT / "tbot" / "runtime" / "orchestrator.py"

MARK = 'setattr(ctx, "core_context"'

def main() -> int:
    if not TARGET.exists():
        print(f"PATCH_FAIL: missing target: {TARGET}")
        return 2

    src = TARGET.read_text(encoding="utf-8")

    if MARK in src:
        print("PATCH_SKIP: ctx attach already present")
        return 0

    # Find ctx construction end: ctx = SignalContext(... ) block
    m = re.search(r"(?s)(?P<block>ctx\s*=\s*SignalContext\(\s*.*?\n\s*\)\s*)", src)
    if not m:
        print("PATCH_FAIL: could not find ctx = SignalContext(...) block")
        return 3

    block = m.group("block")

    # Determine indent from the ctx line
    m2 = re.search(r"(?m)^(?P<indent>[ \t]*)ctx\s*=\s*SignalContext\(", block)
    indent = m2.group("indent") if m2 else ""

    inject = f"""
{indent}# Attach core_context + alpha_mode to ctx BEFORE strategy evaluation (critical)
{indent}try:
{indent}    cc = detect_core_context(symbol=str(symbols[0] if symbols else "NA"), snap=(market.get(symbols[0]) if symbols else object()))
{indent}    setattr(ctx, "core_context", cc)
{indent}except Exception:
{indent}    cc = None
{indent}
{indent}try:
{indent}    _reg = rr.regime
{indent}    _conf = rr.confidence
{indent}    _strength = (getattr(cc, "trend_strength", 0.0) if cc is not None else 0.0)
{indent}    dec = decide_alpha_mode(regime=str(_reg), regime_conf=float(_conf), core_strength=float(_strength))
{indent}    setattr(ctx, "alpha_mode", str(dec.mode))
{indent}    setattr(ctx, "alpha_cap_ratio", float(getattr(dec, "cap_ratio", 1.0)))
{indent}except Exception:
{indent}    pass
"""

    out = src[:m.end()] + inject + src[m.end():]

    # Backup
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = TARGET.with_suffix(f".py.bak_ctx_attach_before_eval_{ts}")
    shutil.copy2(TARGET, bak)

    TARGET.write_text(out, encoding="utf-8")
    print(f"PATCH_OK: attached ctx.core_context + ctx.alpha_mode | backup={bak}")

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
