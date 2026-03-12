# File: tools/patch_add_strategy_result_event.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # idempotent
    if 'kind="strategy_result"' in txt or "kind='strategy_result'" in txt:
        return 0

    # find the first occurrence of "sig = strat.evaluate(ctx)" inside the strategy loop
    m = re.search(r"(?m)^(?P<indent>\s*)sig\s*=\s*strat\.evaluate\(ctx\)\s*$", txt)
    if not m:
        return 2

    indent = m.group("indent")

    inject = (
        f"{indent}# Strategy diagnostic (enterprise QA)\n"
        f"{indent}try:\n"
        f"{indent}    import os\n"
        f"{indent}    _mvp = str(os.getenv('TBOT_ENABLE_S11_MVP','0')).strip()\n"
        f"{indent}    _has_cc = (getattr(ctx, 'core_context', None) is not None)\n"
        f"{indent}    _has_am = (getattr(ctx, 'alpha_mode', None) is not None)\n"
        f"{indent}    _sig = sig\n"
        f"{indent}    ev = make_event(level='INFO', kind='strategy_result', payload={{\n"
        f"{indent}        'sid': str(strat.sid),\n"
        f"{indent}        'mvp_env': _mvp,\n"
        f"{indent}        'has_core_context': bool(_has_cc),\n"
        f"{indent}        'has_alpha_mode': bool(_has_am),\n"
        f"{indent}        'returned': ('NONE' if _sig is None else 'SIGNAL'),\n"
        f"{indent}        'symbol': (None if _sig is None else str(_sig.symbol)),\n"
        f"{indent}        'side': (None if _sig is None else str(_sig.side)),\n"
        f"{indent}        'confidence': (None if _sig is None else float(_sig.confidence)),\n"
        f"{indent}        'reason': (None if _sig is None else str(_sig.reason)),\n"
        f"{indent}    }})\n"
        f"{indent}    meta.emit(ev); announce.emit(ev)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    # insert inject block right after the sig evaluate line
    line_end = txt.find("\n", m.end())
    if line_end < 0:
        line_end = len(txt)
    txt = txt[:line_end+1] + inject + txt[line_end+1:]

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
