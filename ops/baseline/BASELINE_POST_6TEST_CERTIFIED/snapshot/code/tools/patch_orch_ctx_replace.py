from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
TARGET = ROOT / "tbot" / "runtime" / "orchestrator.py"

def main() -> int:
    src = TARGET.read_text(encoding="utf-8")

    # Ensure replace import exists
    if "from dataclasses import replace" not in src:
        src = re.sub(
            r"(?m)^from dataclasses import (.+)$",
            lambda m: (m.group(0) if "replace" in m.group(1) else f"from dataclasses import {m.group(1)}, replace"),
            src,
            count=1,
        )

    # Idempotent marker
    if "replace(ctx," in src and "core_context=cc" in src and "alpha_mode=" in src:
        print("PATCH_SKIP: orchestrator already uses replace(ctx, ...)")
        return 0

    # Replace the old setattr blocks (best-effort): we insert a robust block right after alpha_mode decision.
    # We'll anchor right after the alpha_mode event emit line: meta.emit(ev); announce.emit(ev)
    anchor = r'meta\.emit\(ev\);\s*announce\.emit\(ev\)'
    m = re.search(anchor, src)
    if not m:
        print("PATCH_FAIL: could not find anchor meta.emit(ev); announce.emit(ev)")
        return 2

    inject = r"""
        # Attach core_context + alpha_mode to ctx for strategy access (frozen-safe via dataclasses.replace)
        try:
            _cc = cc if "cc" in locals() else None
            _mode = str(dec.mode) if "dec" in locals() else None
            _cap = float(getattr(dec, "cap_ratio", 1.0)) if "dec" in locals() else None
            ctx = replace(ctx, core_context=_cc, alpha_mode=_mode, alpha_cap_ratio=_cap)
        except Exception:
            pass
"""

    # Insert inject AFTER the first occurrence of anchor AFTER alpha_mode event.
    # To minimize unintended placement, we insert after the first alpha_mode emit.
    m2 = re.search(r'(?s)kind="alpha_mode".*?' + anchor, src)
    if not m2:
        print("PATCH_FAIL: could not locate alpha_mode emit block")
        return 3

    insert_pos = m2.end()
    out = src[:insert_pos] + inject + src[insert_pos:]

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = TARGET.with_suffix(f".py.bak_ctx_replace_{ts}")
    shutil.copy2(TARGET, bak)
    TARGET.write_text(out, encoding="utf-8")
    print(f"PATCH_OK: ctx replace injected | backup={bak}")

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
