# File: tools/patch_orch_attach_ctx_fields.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def _inject_after_emit(txt: str, kind: str, inject_lines: list[str]) -> str:
    # find event kind
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

    indent = re.match(r"^\s*", txt[ls:le]).group(0)
    block = "".join(indent + ln + "\n" for ln in inject_lines)
    return txt[:le+1] + block + txt[le+1:]


def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # idempotent: remove any previous attach blocks (best effort)
    txt = re.sub(r"(?ms)^\s*# Attach core_context to ctx.*?^\s*pass\s*$", "", txt)
    txt = re.sub(r"(?ms)^\s*# Attach alpha_mode to ctx.*?^\s*pass\s*$", "", txt)

    # attach core_context after core_context emit
    if 'setattr(ctx, "core_context"' not in txt:
        txt = _inject_after_emit(
            txt,
            "core_context",
            [
                '# Attach core_context to ctx for strategy access (safe)',
                'try:',
                '    setattr(ctx, "core_context", cc)',
                'except Exception:',
                '    pass',
            ],
        )

    # attach alpha_mode after alpha_mode emit
    if 'setattr(ctx, "alpha_mode"' not in txt:
        txt = _inject_after_emit(
            txt,
            "alpha_mode",
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
