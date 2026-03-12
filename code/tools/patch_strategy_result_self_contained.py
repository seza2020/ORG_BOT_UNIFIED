# File: tools/patch_strategy_result_self_contained.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # Must exist first
    if "kind='strategy_result'" not in txt and 'kind="strategy_result"' not in txt:
        return 2

    # If already patched, exit
    if "PATCH_STRATEGY_RESULT_SELF_CONTAINED=1" in txt:
        return 0

    # Find the strategy_result block (we inserted it previously)
    # Anchor: "Strategy diagnostic (enterprise QA)" then the try: block
    anchor = re.search(r"(?s)(?P<block>\s*# Strategy diagnostic \(enterprise QA\)\s*\n\s*try:\s*\n.*?meta\.emit\(ev\);\s*announce\.emit\(ev\)\s*\n\s*except Exception:\s*\n\s*pass\s*\n)", txt)
    if not anchor:
        return 3

    block = anchor.group("block")

    # Inject ensure-ctx inside this try: after import os (or at top if not found)
    inject = (
        "    # PATCH_STRATEGY_RESULT_SELF_CONTAINED=1\n"
        "    # Ensure ctx has core_context + alpha_mode before reporting flags\n"
        "    try:\n"
        "        if getattr(ctx, 'core_context', None) is None:\n"
        "            cc = detect_core_context(symbol=str(symbols[0] if symbols else 'NA'), snap=(market.get(symbols[0]) if symbols else object()))\n"
        "            try:\n"
        "                setattr(ctx, 'core_context', cc)\n"
        "            except Exception:\n"
        "                pass\n"
        "    except Exception:\n"
        "        pass\n"
        "    try:\n"
        "        if getattr(ctx, 'alpha_mode', None) is None:\n"
        "            _rr = locals().get('rr', None)\n"
        "            dec = decide_alpha_mode(regime=(getattr(_rr, 'regime', 'TREND') if _rr is not None else 'TREND'))\n"
        "            try:\n"
        "                setattr(ctx, 'alpha_mode', dec.mode)\n"
        "            except Exception:\n"
        "                pass\n"
        "    except Exception:\n"
        "        pass\n"
    )

    # Place injection right after "import os" line inside the try block if present.
    if "import os" in block:
        block2 = block.replace("    import os\n", "    import os\n" + inject, 1)
    else:
        # Put after try: line
        block2 = re.sub(r"(?m)^(\s*try:\s*)$", r"\1\n" + inject.rstrip("\n"), block, count=1)

    txt2 = txt.replace(block, block2, 1)
    P.write_text(txt2, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
