from __future__ import annotations
from pathlib import Path
import re
import sys

ROOT = Path(r"C:\alpaca-bot\org_bot")
SHADOW = ROOT / r"tbot\runtime\shadow.py"

CANDIDATE_CLASS_NAMES = [
    "ShadowPlanWriter",     # expected
    "ShadowWriter",         # common alt
    "ShadowPlanWriterV2",
    "ShadowPlansWriter",
    "ShadowPlanLogWriter",
    "ShadowPlanAppender",
]

def backup(p: Path) -> Path:
    bak = p.with_suffix(p.suffix + ".bak_autofix_alias")
    bak.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    print("[PATCH] backup:", str(bak))
    return bak

def find_defined_classes(txt: str) -> list[str]:
    # match: class Name(
    return re.findall(r"(?m)^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(|:)", txt)

def main() -> int:
    if not SHADOW.exists():
        print("[PATCH] missing:", SHADOW)
        return 2

    txt = SHADOW.read_text(encoding="utf-8")

    if re.search(r"(?m)^\s*class\s+ShadowPlanWriter\s*(?:\(|:)", txt) or re.search(r"(?m)^\s*ShadowPlanWriter\s*=", txt):
        print("[PATCH] ShadowPlanWriter already present")
        return 0

    defined = set(find_defined_classes(txt))
    print("[PATCH] defined_classes:", ", ".join(sorted(defined)) if defined else "(none)")

    # pick best available candidate
    target = None
    for name in CANDIDATE_CLASS_NAMES:
        if name in defined and name != "ShadowPlanWriter":
            target = name
            break

    if target is None:
        # last resort: pick any class that looks like a writer
        for name in sorted(defined):
            if "Writer" in name or "Shadow" in name:
                target = name
                break

    if target is None:
        print("[PATCH] no suitable class found to alias -> NOT PATCHING")
        return 3

    backup(SHADOW)

    # append alias at end (safe)
    if not txt.endswith("\n"):
        txt += "\n"
    txt += "\n# --- compatibility alias (autofix) ---\n"
    txt += f"ShadowPlanWriter = {target}\n"
    SHADOW.write_text(txt, encoding="utf-8")
    print(f"[PATCH] added alias: ShadowPlanWriter = {target}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
