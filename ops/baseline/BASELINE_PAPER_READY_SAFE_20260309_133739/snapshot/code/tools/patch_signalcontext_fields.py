from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
TARGET = ROOT / "tbot" / "strategies" / "base.py"

def main() -> int:
    src = TARGET.read_text(encoding="utf-8")

    # Idempotent: if already has these fields, skip
    if "core_context" in src and "alpha_mode" in src and "alpha_cap_ratio" in src:
        print("PATCH_SKIP: SignalContext already has core_context/alpha_mode/alpha_cap_ratio")
        return 0

    # Find class SignalContext: dataclass with fields
    m = re.search(r"(?s)(class\s+SignalContext\s*:\s*\n)(?P<body>.*?)(\nclass|\n@dataclass|\Z)", src)
    if not m:
        print("PATCH_FAIL: could not find class SignalContext")
        return 2

    body = m.group("body")

    # Insert fields near the end of SignalContext fields list (best-effort)
    # We assume fields are declared as "name: type" lines.
    inject = "\n    # --- policy/runtime attachments (set by orchestrator) ---\n" \
             "    core_context: object | None = None\n" \
             "    alpha_mode: str | None = None\n" \
             "    alpha_cap_ratio: float | None = None\n"

    # Heuristic: append right before the first blank line that likely ends field declarations
    # If not found, just append at end of class block.
    if "\n\n" in body:
        parts = body.split("\n\n", 1)
        new_body = parts[0] + inject + "\n\n" + parts[1]
    else:
        new_body = body + inject

    out = src[:m.start("body")] + new_body + src[m.end("body"):]

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = TARGET.with_suffix(f".py.bak_ctx_fields_{ts}")
    shutil.copy2(TARGET, bak)
    TARGET.write_text(out, encoding="utf-8")
    print(f"PATCH_OK: added ctx fields | backup={bak}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
