#!/usr/bin/env python3
"""
P0-2.3 v2.4 - Restore last backup then apply AST-safe injection (multi-line def safe)

Fixes:
- Injects into *function body* using fn.body[0].lineno (never inside multi-line signature)
- Restores from latest P0_2_3_V2_3_* backup automatically (the one created before SyntaxError)

After run:
- rg -n "P0_2_3_V2_4_DAILY_BUDGET_ENFORCE" tbot/runtime/shadow_gate.py
- python .\\tools\\p0_2_2_gate_selftest.py
"""

from __future__ import annotations

import ast
import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_2_3_V2_4_DAILY_BUDGET_ENFORCE"

def die(msg: str) -> None:
    print(f"[P0-2.3v2.4] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2.4] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir():
        return p
    for parent in p.parents:
        if (parent / "tbot").is_dir():
            return parent
    die("Run from repo root (contains ./tbot).")

def find_latest_v2_3_backup(root: Path) -> Path | None:
    base = root / "logs" / "ops" / "patches"
    if not base.exists():
        return None
    cands = []
    for d in base.glob("P0_2_3_V2_3_*"):
        f = d / "tbot" / "runtime" / "shadow_gate.py"
        if f.exists():
            cands.append((d.stat().st_mtime, f))
    if not cands:
        return None
    cands.sort(key=lambda x: x[0], reverse=True)
    return cands[0][1]

def backup_current(root: Path, f: Path) -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_4_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def ensure_dt_import(src: str) -> str:
    # Our injected code references dt.datetime; ensure "import datetime as dt" exists.
    if re.search(r"^\s*import\s+datetime\s+as\s+dt\s*$", src, flags=re.M):
        return src
    lines = src.splitlines(True)
    insert_at = 0
    for i, ln in enumerate(lines[:200]):
        if ln.startswith("import ") or ln.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, "import datetime as dt  # " + MARK + "\n")
    return "".join(lines)

def parse_shadowgate(src: str):
    tree = ast.parse(src)
    sg = None
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "ShadowGate":
            sg = node
            break
    if sg is None:
        return None, {}
    methods = {}
    for n in sg.body:
        if isinstance(n, ast.FunctionDef):
            methods[n.name] = n
    return sg, methods

def indent_of(lines: list[str], i: int) -> str:
    m = re.match(r"^([ \t]*)", lines[i])
    return m.group(1) if m else ""

def inject_lines(lines: list[str], at_line_1based: int, block: str) -> list[str]:
    i = max(0, at_line_1based - 1)
    return lines[:i] + [block] + lines[i:]

def patch_init(lines: list[str], fn: ast.FunctionDef) -> tuple[list[str], bool]:
    # inject at first statement inside __init__
    if not fn.body:
        return lines, False
    start_body = fn.body[0].lineno  # 1-based
    seg = "".join(lines[fn.lineno-1:fn.end_lineno])
    if "self._risk_today" in seg:
        info("__init__: _risk_today already present")
        return lines, False

    body_indent = indent_of(lines, start_body-1)
    block = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}self._risk_today = 0.0\n"
        f"{body_indent}self._risk_day_key = None\n"
    )
    lines2 = inject_lines(lines, start_body, block)
    info("__init__: injected _risk_today/_risk_day_key at body start")
    return lines2, True

def patch_evaluate(lines: list[str], fn: ast.FunctionDef) -> tuple[list[str], bool]:
    if not fn.body:
        die("evaluate has empty body; cannot patch")

    # Prevent double patch
    seg = "".join(lines[fn.lineno-1:fn.end_lineno])
    if MARK in seg:
        info("evaluate: already patched")
        return lines, False

    body_start = fn.body[0].lineno
    body_indent = indent_of(lines, body_start-1)

    top = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}# Day roll + daily budget enforce (inside gate, multiline-signature safe)\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _now = None\n"
        f"{body_indent}    if 'now' in locals() and hasattr(locals().get('now'), 'strftime'):\n"
        f"{body_indent}        _now = locals().get('now')\n"
        f"{body_indent}    else:\n"
        f"{body_indent}        _now = dt.datetime.now(dt.timezone.utc)\n"
        f"{body_indent}    _k = _now.strftime('%Y%m%d')\n"
        f"{body_indent}    if getattr(self, '_risk_day_key', None) != _k:\n"
        f"{body_indent}        self._risk_day_key = _k\n"
        f"{body_indent}        self._risk_today = 0.0\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _day_cap = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{body_indent}    _risk_plan = float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{body_indent}    if _day_cap is not None:\n"
        f"{body_indent}        if float(getattr(self, '_risk_today', 0.0)) + _risk_plan > float(_day_cap):\n"
        f"{body_indent}            reasons.append('daily_risk_budget_reached')\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
    )

    lines2 = inject_lines(lines, body_start, top)

    # Now also try to consume budget before "return True" and/or before returning allow True.
    # We'll do a simple text pass over the function range after reparse for correct end_lineno.
    src2 = "".join(lines2)
    _, methods2 = parse_shadowgate(src2)
    fn2 = methods2.get(fn.name)
    if fn2 is None:
        die("Internal: evaluate missing after injection?")

    # recompute lines after injection
    lines3 = src2.splitlines(True)

    consume = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{body_indent}    if _day_cap2 is not None:\n"
        f"{body_indent}        if ('allow' in locals()) and bool(locals().get('allow')) and (len(reasons) == 0):\n"
        f"{body_indent}            self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
    )

    # insert consume block just before any "return" lines inside evaluate
    out = []
    changed = False
    for i, ln in enumerate(lines3):
        if (fn2.lineno-1) <= i < (fn2.end_lineno) and ln.lstrip().startswith("return"):
            out.append(consume)
            changed = True
        out.append(ln)

    info(f"evaluate: injected top-block at body_start line={body_start}, return-guards added={changed}")
    return out, True

def main() -> None:
    root = repo_root()
    target = root / "tbot" / "runtime" / "shadow_gate.py"
    if not target.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    # Restore from latest v2.3 backup (created right before SyntaxError)
    bk = find_latest_v2_3_backup(root)
    if not bk:
        die("Could not find latest P0_2_3_V2_3_* backup to restore from.")
    pre = backup_current(root, target)
    shutil.copy2(bk, target)
    info(f"Restored shadow_gate.py from: {bk.relative_to(root)}")
    info(f"Backup of current (pre-restore) saved to: {pre.relative_to(root)}")

    src = target.read_text(encoding="utf-8", errors="ignore")
    src = ensure_dt_import(src)
    sg, methods = parse_shadowgate(src)
    if sg is None:
        die("ShadowGate class not found after restore.")

    if "evaluate" not in methods:
        die("ShadowGate.evaluate not found. Paste the top of ShadowGate class; we'll target the correct method.")
    lines = src.splitlines(True)

    # patch __init__
    if "__init__" in methods:
        lines, _ = patch_init(lines, methods["__init__"])
        src = "".join(lines)
        sg, methods = parse_shadowgate(src)
        lines = src.splitlines(True)

    # patch evaluate
    lines, _ = patch_evaluate(lines, methods["evaluate"])

    target.write_text("".join(lines), encoding="utf-8")
    info("Applied P0-2.3 v2.4 successfully.")
    info("Next:")
    info('  rg -n "P0_2_3_V2_4_DAILY_BUDGET_ENFORCE" tbot/runtime/shadow_gate.py')
    info("  python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
