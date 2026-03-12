# File: tools/repair_orchestrator_ctx_attach.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

# These markers identify blocks we inserted previously (any indentation)
RE_CORE_ATTACH = re.compile(r"(?ms)^\s*# Attach core_context to ctx for strategy access \(safe\)\s*.*?^\s*pass\s*$")
RE_ALPHA_ATTACH = re.compile(r"(?ms)^\s*# Attach alpha_mode to ctx for strategy access \(safe\)\s*.*?^\s*pass\s*$")

def _indent_of(line: str) -> str:
    return re.match(r"^\s*", line).group(0)

def _insert_after_first(txt: str, anchor_re: re.Pattern, insert: str) -> str:
    m = anchor_re.search(txt)
    if not m:
        return txt
    pos = m.end(0)
    return txt[:pos] + insert + txt[pos:]

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # 0) Remove any previous attach blocks (regardless of indentation)
    txt2 = RE_CORE_ATTACH.sub("", txt)
    txt2 = RE_ALPHA_ATTACH.sub("", txt2)
    txt = txt2

    # 1) Insert core_context attach right after core_context event emit
    # Find the core_context event block and the FIRST "meta.emit(ev); announce.emit(ev)" after it.
    idx_cc = txt.find('kind="core_context"')
    if idx_cc < 0:
        return 2

    idx_emit_cc = txt.find("meta.emit(ev); announce.emit(ev)", idx_cc)
    if idx_emit_cc < 0:
        return 3

    # Determine indentation from that emit line
    line_start = txt.rfind("\n", 0, idx_emit_cc) + 1
    line_end = txt.find("\n", idx_emit_cc)
    if line_end < 0:
        line_end = len(txt)
    indent = _indent_of(txt[line_start:line_end])

    core_block = (
        f"{indent}# Attach core_context to ctx for strategy access (safe)\n"
        f"{indent}try:\n"
        f"{indent}    setattr(ctx, \"core_context\", cc)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    # Insert AFTER the emit line
    txt = txt[:line_end+1] + core_block + txt[line_end+1:]

    # 2) Insert alpha_mode attach just before alpha_mode event creation
    idx_am = txt.find('kind="alpha_mode"')
    if idx_am < 0:
        return 4

    idx_ev_make = txt.rfind("ev = make_event", 0, idx_am)
    if idx_ev_make < 0:
        return 5

    # Determine indentation from that ev line
    ls2 = txt.rfind("\n", 0, idx_ev_make) + 1
    le2 = txt.find("\n", idx_ev_make)
    if le2 < 0:
        le2 = len(txt)
    indent2 = _indent_of(txt[ls2:le2])

    alpha_block = (
        f"{indent2}# Attach alpha_mode to ctx for strategy access (safe)\n"
        f"{indent2}try:\n"
        f"{indent2}    setattr(ctx, \"alpha_mode\", dec.mode)\n"
        f"{indent2}except Exception:\n"
        f"{indent2}    pass\n\n"
    )

    txt = txt[:idx_ev_make] + alpha_block + txt[idx_ev_make:]

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
