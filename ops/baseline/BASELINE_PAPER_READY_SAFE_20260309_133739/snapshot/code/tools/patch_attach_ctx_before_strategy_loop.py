# File: tools/patch_attach_ctx_before_strategy_loop.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

MARK = "PATCH_CTX_ATTACH_BEFORE_STRATEGY_LOOP=1"

def main() -> int:
    txt = P.read_text(encoding="utf-8")
    if MARK in txt:
        return 0

    # Find the strategy loop line inside the session-allowed branch:
    # "for strat in strategies:"
    m = re.search(r"(?m)^(?P<indent>\s*)for\s+strat\s+in\s+strategies\s*:\s*$", txt)
    if not m:
        return 2

    ind = m.group("indent")

    block = (
        f"{ind}# {MARK}\n"
        f"{ind}# Ensure ctx has core_context + alpha_mode for strategy access (safe)\n"
        f"{ind}try:\n"
        f"{ind}    cc = detect_core_context(symbol=str(symbols[0] if symbols else 'NA'), snap=(market.get(symbols[0]) if symbols else object()))\n"
        f"{ind}    try:\n"
        f"{ind}        setattr(ctx, 'core_context', cc)\n"
        f"{ind}    except Exception:\n"
        f"{ind}        pass\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
        f"{ind}try:\n"
        f"{ind}    dec = decide_alpha_mode(regime=str(getattr(rr, 'regime', 'TREND')))\n"
        f"{ind}    try:\n"
        f"{ind}        setattr(ctx, 'alpha_mode', dec.mode)\n"
        f"{ind}    except Exception:\n"
        f"{ind}        pass\n"
        f"{ind}    ev = make_event(level='INFO', kind='alpha_mode', payload={{'mode': dec.mode, 'cap_ratio': float(getattr(dec,'cap_ratio',0.0)), 'reason': str(getattr(dec,'reason',''))}})\n"
        f"{ind}    meta.emit(ev); announce.emit(ev)\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n\n"
    )

    txt2 = txt[:m.start()] + block + txt[m.start():]
    P.write_text(txt2, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
