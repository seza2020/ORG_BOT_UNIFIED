#!/usr/bin/env python3
"""
P0-2.3 Patch: Enforce daily risk budget inside ShadowGate.evaluate()

Goal:
- Make daily budget enforcement work even without orchestrator commit path.
- After an allow decision, increment in-memory risk_today immediately.
- Reset risk_today per-day in _roll_day().

Backups: logs/ops/patches/P0_2_3_*/tbot/runtime/shadow_gate.py
"""

from __future__ import annotations

import re
import sys
import shutil
import datetime as dt
from pathlib import Path


MARK = "P0_2_3_DAILY_BUDGET_ENFORCE_IN_GATE"


def die(msg: str) -> None:
    print(f"[P0-2.3] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg: str) -> None:
    print(f"[P0-2.3] {msg}")


def repo_root() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir():
        return p
    for parent in p.parents:
        if (parent / "tbot").is_dir():
            return parent
    die("Run from repo root (folder containing ./tbot).")


def backup(root: Path, f: Path) -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out


def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = f.read_text(encoding="utf-8", errors="ignore")
    if MARK in txt:
        info("Already patched.")
        return

    b = backup(root, f)
    info(f"Backup: {b.relative_to(root)}")

    # 1) Ensure _risk_today exists in __init__
    # Look for: def __init__(...): and add self._risk_today = 0.0 near other counters.
    init_re = re.compile(r"(def __init__\s*\(.*?\)\s*:\s*\n)(?P<body>(?:^[ \t]+.*\n)+)", re.M)
    m = init_re.search(txt)
    if not m:
        die("Could not find ShadowGate.__init__ block.")

    body = m.group("body")
    if "self._risk_today" not in body:
        # insert after first line of body (after possible super or attribute init)
        lines = body.splitlines(True)
        insert_at = 1 if len(lines) > 1 else 0
        indent = re.match(r"^(\s+)", lines[0]).group(1)  # type: ignore
        lines.insert(insert_at, f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n")
        new_body = "".join(lines)
        txt = txt[:m.start("body")] + new_body + txt[m.end("body"):]
        info("Added self._risk_today = 0.0 to __init__")
    else:
        info("self._risk_today already present in __init__ (skipping)")

    # 2) Reset risk_today in _roll_day(now) (or similar)
    roll_re = re.compile(r"(def _roll_day\s*\(\s*self\s*,\s*now\s*\)\s*:\s*\n)(?P<body>(?:^[ \t]+.*\n)+)", re.M)
    rm = roll_re.search(txt)
    if not rm:
        info("WARN: Could not find _roll_day(self, now). Will not add reset there.")
    else:
        rbody = rm.group("body")
        if "self._risk_today" not in rbody:
            # put reset near other resets: after day key assignment or where counters reset
            rlines = rbody.splitlines(True)
            # find a good place: after a line containing "self._day" or "self._key" or "self._date"
            idx = 0
            for i, ln in enumerate(rlines[:60]):
                if any(k in ln for k in ("self._day", "self._date", "self._key", "self._day_key", "key =")):
                    idx = i + 1
                    break
            indent = re.match(r"^(\s+)", rlines[0]).group(1)  # type: ignore
            rlines.insert(idx, f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n")
            new_rbody = "".join(rlines)
            txt = txt[:rm.start("body")] + new_rbody + txt[rm.end("body"):]
            info("Added self._risk_today reset to _roll_day(now)")
        else:
            info("self._risk_today already referenced in _roll_day (skipping)")

    # 3) Patch evaluate(): enforce daily budget + increment on allow
    # We'll inject two blocks:
    #  - BEFORE allow decision return: daily budget check
    #  - AFTER allow True: increment self._risk_today
    #
    # We'll locate evaluate signature line and its body, then insert based on first risk extraction line.

    eval_hdr = re.compile(r"(def evaluate\s*\(\s*self\s*,\s*now\s*,\s*plan\s*,.*?\)\s*:\s*\n)", re.M)
    em = eval_hdr.search(txt)
    if not em:
        die("Could not find def evaluate(self, now, plan, ...) in shadow_gate.py")

    # find evaluate block body (naive: until next def at same indentation)
    start = em.end(1)
    # indentation level for body
    m_indent = re.match(r"^([ \t]*)", txt[start:]).group(1)  # type: ignore
    # find next top-level def with same indent (i.e. begins at column of 'def' in class, usually 4 spaces)
    # safer: search for "\n    def " after start
    next_def = re.search(r"\n[ \t]*def\s+\w+\s*\(", txt[start:])
    if not next_def:
        die("Could not find end of evaluate() block.")
    end = start + next_def.start()

    eval_body = txt[start:end]

    if MARK in eval_body:
        info("evaluate() already patched (marker found).")
    else:
        # Determine indent inside evaluate (first non-empty line)
        lines = eval_body.splitlines(True)
        first_code = next((ln for ln in lines if ln.strip()), None)
        if not first_code:
            die("evaluate() body seems empty.")
        indent = re.match(r"^(\s+)", first_code).group(1)  # type: ignore

        # Insert daily budget check after risk extraction if we can find it, otherwise near top.
        # We look for a line where risk is computed (contains 'risk' and 'plan' and 'getattr')
        insert_pos = 0
        for i, ln in enumerate(lines[:200]):
            if ("risk" in ln.lower()) and ("plan" in ln.lower()) and ("getattr" in ln.lower() or "safe_float" in ln.lower()):
                insert_pos = i + 1
                break

        budget_check = (
            f"{indent}# {MARK}\n"
            f"{indent}# Enforce DAILY cumulative risk budget inside gate (not just per-trade).\n"
            f"{indent}_day_cap = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
            f"{indent}_risk = None\n"
            f"{indent}try:\n"
            f"{indent}    _risk = float(getattr(plan, 'risk_usd', None))\n"
            f"{indent}except Exception:\n"
            f"{indent}    _risk = None\n"
            f"{indent}if _day_cap is not None and _risk is not None:\n"
            f"{indent}    try:\n"
            f"{indent}        if float(getattr(self, '_risk_today', 0.0)) + float(_risk) > float(_day_cap):\n"
            f"{indent}            reasons.append('daily_risk_budget_reached')\n"
            f"{indent}    except Exception:\n"
            f"{indent}        pass\n"
        )

        lines.insert(insert_pos, budget_check)

        # Now ensure we increment on allow True just before returning allow/reasons.
        # Look for a return statement; if not found, append at end.
        # We inject right before the first "return" in evaluate.
        ret_idx = None
        for i, ln in enumerate(lines):
            if ln.lstrip().startswith("return "):
                ret_idx = i
                break

        inc_block = (
            f"{indent}# {MARK}\n"
            f"{indent}# If allowed, immediately consume daily budget in-memory (so next calls reject correctly).\n"
            f"{indent}try:\n"
            f"{indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
            f"{indent}    if _day_cap2 is not None and _risk is not None and (len(reasons) == 0):\n"
            f"{indent}        self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(_risk)\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
        )

        if ret_idx is None:
            lines.append("\n" + inc_block)
        else:
            lines.insert(ret_idx, inc_block)

        new_eval_body = "".join(lines)
        txt = txt[:start] + new_eval_body + txt[end:]
        info("Patched evaluate(): daily budget check + consume-on-allow")

    f.write_text(txt, encoding="utf-8")
    info("Applied P0-2.3 successfully.")
    info("Run: python .\\tools\\p0_2_2_gate_selftest.py")


if __name__ == "__main__":
    main()
