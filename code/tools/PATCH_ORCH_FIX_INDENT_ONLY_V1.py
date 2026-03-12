from __future__ import annotations
from pathlib import Path
import sys, re

OR = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")

def main() -> None:
    txt = OR.read_text(encoding="utf-8", errors="replace").splitlines(True)

    changed = 0
    i = 0
    while i < len(txt):
        line = txt[i]
        m = re.match(r"^(?P<ind>[ \t]*)if\s+plan\s+is\s+None\s*:\s*(\r?\n)?$", line)
        if not m:
            i += 1
            continue

        ind = m.group("ind")
        ind_in = ind + ("    " if "\t" not in ind else "\t")

        # find next non-empty line (do not skip too far)
        j = i + 1
        while j < len(txt) and txt[j].strip() == "":
            j += 1

        # If block is missing or the next statement is not indented -> fix by inserting a proper block
        needs_insert = True
        if j < len(txt):
            nxt = txt[j]
            # already correctly indented?
            if nxt.startswith(ind_in):
                needs_insert = False
            # if it's a wrongly-indented logger/continue at same indent as "if", we can just indent them
            if nxt.startswith(ind) and not nxt.startswith(ind_in):
                if re.search(r"\blogger\.error\s*\(", nxt) or re.match(r"^[ \t]*continue\b", nxt):
                    # indent this line
                    txt[j] = ind_in + nxt[len(ind):]
                    changed += 1
                    # also indent immediate following "continue" if present and wrong
                    k = j + 1
                    while k < len(txt) and txt[k].strip() == "":
                        k += 1
                    if k < len(txt) and re.match(rf"^{re.escape(ind)}continue\b", txt[k]):
                        txt[k] = ind_in + txt[k][len(ind):]
                        changed += 1
                    needs_insert = False

        if needs_insert:
            block = (
                f"{ind_in}logger.error('shadow_plan_none_skip', extra={{'reason':'build_shadow_plan_failed'}})\n"
                f"{ind_in}continue\n"
            )
            txt.insert(i + 1, block)
            changed += 1
            i += 2
            continue

        i += 1

    if changed == 0:
        raise SystemExit("no_change: did not find a broken 'if plan is None' block to fix")

    OR.write_text("".join(txt), encoding="utf-8")
    print(f"[PATCH] fixed indentation for plan-none guard (changes={changed})")

if __name__ == "__main__":
    main()
