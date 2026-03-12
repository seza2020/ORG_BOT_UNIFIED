# File: tools/patch_orch_strategy_result_event.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # Insert import os if missing (env check)
    if re.search(r"(?m)^\s*import os\s*$", txt) is None:
        # place near top imports
        txt = txt.replace("import time", "import time\nimport os", 1)

    # Avoid double patch
    if "kind=\"strategy_result\"" in txt or "kind='strategy_result'" in txt:
        return 0

    # Find the spot right after: sig = strat.evaluate(ctx)
    needle = "sig = strat.evaluate(ctx)"
    idx = txt.find(needle)
    if idx < 0:
        return 2

    # Determine indentation from that line
    ls = txt.rfind("\n", 0, idx) + 1
    le = txt.find("\n", idx)
    if le < 0:
        le = len(txt)
    indent = re.match(r"^\s*", txt[ls:le]).group(0)

    block = f"""
{indent}# Diagnostic: record strategy output (safe, no trading impact)
{indent}try:
{indent}    _mvp = str(os.getenv("TBOT_ENABLE_S11_MVP","0")).strip()
{indent}    _has_cc = getattr(ctx, "core_context", None) is not None
{indent}    _sig = sig
{indent}    ev = make_event(level="INFO", kind="strategy_result", payload={{
{indent}        "sid": str(strat.sid),
{indent}        "mvp_env": _mvp,
{indent}        "has_core_context": bool(_has_cc),
{indent}        "returned": ("NONE" if _sig is None else "SIGNAL"),
{indent}        "symbol": (None if _sig is None else str(_sig.symbol)),
{indent}        "side": (None if _sig is None else str(_sig.side)),
{indent}        "confidence": (None if _sig is None else float(_sig.confidence)),
{indent}        "reason": (None if _sig is None else str(_sig.reason)),
{indent}    }})
{indent}    meta.emit(ev); announce.emit(ev)
{indent}except Exception:
{indent}    pass
"""

    # Insert block right after the evaluate line (line end)
    txt = txt[:le+1] + block + txt[le+1:]
    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
