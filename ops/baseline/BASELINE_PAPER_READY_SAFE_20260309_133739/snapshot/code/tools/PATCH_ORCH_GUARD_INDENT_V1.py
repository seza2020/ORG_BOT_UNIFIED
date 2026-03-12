from __future__ import annotations
from pathlib import Path
import re, sys

OR = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")

def main() -> None:
    txt = OR.read_text(encoding="utf-8", errors="replace")

    # Case A: our inserted guard exists but indentation inside is wrong -> normalize block.
    # Replace:
    # <ind>if plan is None:
    # <anything up to limiter.can_accept(plan.sid, now)>
    # with a clean, correctly indented block.
    pat_guard = re.compile(
        r"(?m)^(?P<ind>[ \t]*)if plan is None:\s*\r?\n"
        r"(?:(?:[ \t]*\S.*\r?\n){0,6})"
        r"(?P<ind2>[ \t]*)ok_acc, rsn_acc = limiter\.can_accept$begin:math:text$plan\\\.sid\, now$end:math:text$\s*$"
    )

    m = pat_guard.search(txt)
    if m:
        ind = m.group("ind")
        ind_in = ind + ("    " if "\t" not in ind else "\t")
        repl = (
            f"{ind}if plan is None:\n"
            f"{ind_in}logger.error('shadow_plan_none_skip', extra={{'reason':'build_shadow_plan_failed'}})\n"
            f"{ind_in}continue\n"
            f"{ind}ok_acc, rsn_acc = limiter.can_accept(plan.sid, now)\n"
        )
        txt = txt[:m.start()] + repl + txt[m.end():]
        OR.write_text(txt, encoding="utf-8")
        print("[PATCH] normalized existing plan-none guard block")
        return

    # Case B: anchor exists but guard not inserted yet -> insert safely with indentation capture.
    pat_anchor = re.compile(r"(?m)^(?P<ind>[ \t]*)ok_acc, rsn_acc = limiter\.can_accept$begin:math:text$plan\\\.sid\, now$end:math:text$\s*$")
    m2 = pat_anchor.search(txt)
    if not m2:
        raise SystemExit("no_anchor: limiter.can_accept(plan.sid, now) not found")

    ind = m2.group("ind")
    ind_in = ind + ("    " if "\t" not in ind else "\t")
    repl = (
        f"{ind}if plan is None:\n"
        f"{ind_in}logger.error('shadow_plan_none_skip', extra={{'reason':'build_shadow_plan_failed'}})\n"
        f"{ind_in}continue\n"
        f"{ind}ok_acc, rsn_acc = limiter.can_accept(plan.sid, now)"
    )
    txt = txt[:m2.start()] + repl + txt[m2.end():]
    OR.write_text(txt, encoding="utf-8")
    print("[PATCH] inserted plan-none guard block")

if __name__ == "__main__":
    main()
