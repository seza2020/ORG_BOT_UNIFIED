from __future__ import annotations
from pathlib import Path
import re, sys

OR = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
TARGET_LINE = 2182  # from error

def indent(s: str) -> str:
    return re.match(r"^[ \t]*", s).group(0)

def is_block_opener(s: str) -> bool:
    t = s.rstrip()
    if not t:
        return False
    # treat these as "block/continuation openers" where extra indent is valid
    if t.endswith(":"):
        return True
    if t.endswith(("(", "[", "{", "\\", ",")):
        return True
    return False

def prev_sig(lines: list[str], i: int) -> int | None:
    j = i - 1
    while j >= 0 and lines[j].strip() == "":
        j -= 1
    return j if j >= 0 else None

def main() -> None:
    lines = OR.read_text(encoding="utf-8", errors="replace").splitlines(True)
    i0 = max(0, TARGET_LINE - 1 - 40)
    i1 = min(len(lines) - 1, TARGET_LINE - 1 + 40)

    changed = 0

    # Fix the target line (and a small cluster after it) if it is over-indented without a block opener.
    i = TARGET_LINE - 1
    if i < 0 or i >= len(lines):
        raise SystemExit(f"target_out_of_range: {TARGET_LINE}")

    # Find baseline indent from previous significant line
    pj = prev_sig(lines, i)
    if pj is None:
        raise SystemExit("no_prev_line_found")

    base_ind = indent(lines[pj])
    prev_line = lines[pj]

    # If previous significant line does NOT open a block, current line must not be more indented than base_ind
    if not is_block_opener(prev_line):
        cur_ind = indent(lines[i])
        if len(cur_ind) > len(base_ind) and lines[i].strip() != "":
            # reduce exactly to base indent
            lines[i] = base_ind + lines[i].lstrip(" \t")
            changed += 1

        # also fix immediately-following lines that are similarly over-indented but still not under a block opener
        k = i + 1
        while k <= i1:
            if lines[k].strip() == "":
                k += 1
                continue
            # if we hit a new block opener at base indent, stop
            if indent(lines[k]) == base_ind and is_block_opener(lines[k]):
                break
            curk = indent(lines[k])
            if len(curk) > len(base_ind) and not is_block_opener(lines[k-1]) and lines[k].strip() != "":
                lines[k] = base_ind + lines[k].lstrip(" \t")
                changed += 1
                k += 1
                continue
            break

    if changed == 0:
        raise SystemExit("no_change: unexpected-indent not auto-corrected; need local context")

    OR.write_text("".join(lines), encoding="utf-8")
    print(f"[PATCH] fixed unexpected indent near line {TARGET_LINE} (changes={changed})")

if __name__ == "__main__":
    main()
