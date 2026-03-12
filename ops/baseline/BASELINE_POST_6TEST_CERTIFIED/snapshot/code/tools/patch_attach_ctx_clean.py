# File: tools/patch_attach_ctx_clean.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

RE_CORE_ATTACH = re.compile(r"(?ms)^\s*# Attach core_context to ctx for strategy access \(safe\)\s*.*?^\s*pass\s*$")
RE_ALPHA_ATTACH = re.compile(r"(?ms)^\s*# Attach alpha_mode to ctx for strategy access \(safe\)\s*.*?^\s*pass\s*$")

def _indent_of(line: str) -> str:
    return re.match(r"^\s*", line).group(0)

def _insert_after_emit(txt: str, kind: str, block_lines: list[str]) -> str:
    idx = txt.find(f'kind="{kind}"')
    if idx < 0:
        idx = txt.find(f"kind='{kind}'")
    if idx < 0:
        return txt

    emit = "meta.emit(ev); announce.emit(ev)"
    idx_emit = txt.find(emit, idx)
    if idx_emit < 0:
        return txt

    ls = txt.rfind("\n", 0, idx_emit) + 1
    le = txt.find("\n", idx_emit)
    if le < 0:
        le = len(txt)

    indent = _indent_of(txt[ls:le])
    block = "".join(indent + ln + "\n" for ln in block_lines)

    return txt[:le+1] + block + txt[le+1:]


def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # Remove old blocks (idempotent)
    txt = RE_CORE_ATTACH.sub("", txt)
    txt = RE_ALPHA_ATTACH.sub("", txt)

    # Insert core_context attach
    if 'setattr(ctx, "core_context"' not in txt:
        txt = _insert_after_emit(
            txt, "core_context",
            [
                '# Attach core_context to ctx for strategy access (safe)',
                'try:',
                '    setattr(ctx, "core_context", cc)',
                'except Exception:',
                '    pass',
            ],
        )

    # Insert alpha_mode attach
    if 'setattr(ctx, "alpha_mode"' not in txt:
        txt = _insert_after_emit(
            txt, "alpha_mode",
            [
                '# Attach alpha_mode to ctx for strategy access (safe)',
                'try:',
                '    setattr(ctx, "alpha_mode", dec.mode)',
                'except Exception:',
                '    pass',
            ],
        )

    P.write_text(txt, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
