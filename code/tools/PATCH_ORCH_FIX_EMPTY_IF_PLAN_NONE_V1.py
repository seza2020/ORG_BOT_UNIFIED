from __future__ import annotations
from pathlib import Path
import re

OR = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")

def indent(s: str) -> str:
    return re.match(r"^[ \t]*", s).group(0)

def next_nonblank(lines: list[str], i: int) -> int | None:
    j = i + 1
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    return j if j < len(lines) else None

def main() -> None:
    lines = OR.read_text(encoding="utf-8", errors="replace").splitlines(True)
    changed = 0
    for i, line in enumerate(lines):
        if re.match(r"^[ \t]*if\s+plan\s+is\s+None\s*:\s*$", line):
            ind = indent(line)
            j = next_nonblank(lines, i)
            if j is None:
                # file ends after if -> insert body
                body = [
                    ind + "    logger.error('shadow_plan_none_skip', extra={'reason':'build_shadow_plan_failed'})\n",
                    ind + "    continue\n",
                ]
                lines[i+1:i+1] = body
                changed += len(body)
                continue

            # If next nonblank line is NOT more indented, then the 'if' has no body -> insert safe body
            if len(indent(lines[j])) <= len(ind):
                body = [
                    ind + "    logger.error('shadow_plan_none_skip', extra={'reason':'build_shadow_plan_failed'})\n",
                    ind + "    continue\n",
                ]
                lines[i+1:i+1] = body
                changed += len(body)

    if changed == 0:
        print("[PATCH] no empty if-plan-none blocks found; no changes made")
    else:
        OR.write_text("".join(lines), encoding="utf-8")
        print(f"[PATCH] inserted missing if bodies for plan is None (lines_added={changed})")

if __name__ == "__main__":
    main()
