# File: tools/patch_orch_ensure_ctx_before_eval.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    if "PATCH_ENSURE_CTX_BEFORE_EVAL=1" in txt:
        return 0

    # Insert right before: sig = strat.evaluate(ctx)
    m = re.search(r"(?m)^(?P<indent>\s*)sig\s*=\s*strat\.evaluate\(ctx\)\s*$", txt)
    if not m:
        return 2

    ind = m.group("indent")

    block = (
        f"{ind}# PATCH_ENSURE_CTX_BEFORE_EVAL=1\n"
        f"{ind}# Ensure ctx has core_context + alpha_mode before strategy runs (safe)\n"
        f"{ind}try:\n"
        f"{ind}    if getattr(ctx, 'core_context', None) is None:\n"
        f"{ind}        cc = detect_core_context(symbol=str(symbols[0] if symbols else 'NA'), snap=(market.get(symbols[0]) if symbols else object()))\n"
        f"{ind}        try:\n"
        f"{ind}            setattr(ctx, 'core_context', cc)\n"
        f"{ind}        except Exception:\n"
        f"{ind}            pass\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n"
        f"{ind}try:\n"
        f"{ind}    if getattr(ctx, 'alpha_mode', None) is None:\n"
        f"{ind}        _rr = locals().get('rr', None)\n"
        f"{ind}        dec = decide_alpha_mode(regime=(getattr(_rr, 'regime', 'TREND') if _rr is not None else 'TREND'))\n"
        f"{ind}        try:\n"
        f"{ind}            setattr(ctx, 'alpha_mode', dec.mode)\n"
        f"{ind}        except Exception:\n"
        f"{ind}            pass\n"
        f"{ind}except Exception:\n"
        f"{ind}    pass\n\n"
    )

    # add block right before the evaluate line
    txt = txt[:m.start()] + block + txt[m.start():]
    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
