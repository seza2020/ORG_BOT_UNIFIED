# File: C:\alpaca-bot\org_bot\tools\patch_orchestrator_inject_market.py
from __future__ import annotations

from pathlib import Path


ORCH = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
IMPORT_LINE = "from tbot.runtime.market_provider import build_market_snapshot\n"


def _ensure_import(txt: str) -> str:
    if "from tbot.runtime.market_provider import build_market_snapshot" in txt:
        return txt

    lines = txt.splitlines(True)
    out = []
    inserted = False

    i = 0
    while i < len(lines):
        out.append(lines[i])

        # insert after __future__ import block (and one blank line if present)
        if (not inserted) and lines[i].startswith("from __future__ import"):
            i += 1
            while i < len(lines) and lines[i].startswith("from __future__ import"):
                out.append(lines[i])
                i += 1
            if i < len(lines) and lines[i].strip() == "":
                out.append(lines[i])
                i += 1
            out.append(IMPORT_LINE)
            inserted = True
            continue

        i += 1

    if not inserted:
        # fallback: insert near top
        out.insert(1, IMPORT_LINE)

    return "".join(out)


def main() -> None:
    txt = ORCH.read_text(encoding="utf-8")
    txt = _ensure_import(txt)

    lines = txt.splitlines(True)
    out = []
    inserted_market_line = False

    has_market_param = "market=" in txt

    for ln in lines:
        # insert market line right before ctx = SignalContext(
        if (not inserted_market_line) and ("ctx = SignalContext(" in ln):
            prefix = ln[: len(ln) - len(ln.lstrip(" \t"))]
            out.append(f"{prefix}market = build_market_snapshot(now=now, symbols=symbols)\n")
            inserted_market_line = True

        # inject market=market after symbols=symbols, if not already present
        if ("symbols=symbols" in ln) and (not has_market_param):
            out.append(ln)
            prefix = ln[: len(ln) - len(ln.lstrip(" \t"))]
            out.append(f"{prefix}market=market,\n")
            continue

        out.append(ln)

    ORCH.write_text("".join(out), encoding="utf-8")
    print("PATCHED:", str(ORCH))


if __name__ == "__main__":
    main()
