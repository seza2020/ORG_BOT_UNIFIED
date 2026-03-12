#!/usr/bin/env python3
"""
P0-2.3 v2.3 (AST-based) - Enforce daily risk budget inside ShadowGate decision method.

Why:
- Your shadow_gate.py has multiline function headers; regex can't find "def evaluate(...):".
- AST can find the method reliably.

What it does:
1) Ensures self._risk_today exists in ShadowGate.__init__ (best-effort injection)
2) Patches ShadowGate.evaluate if present; otherwise patches the first method in ShadowGate that:
   - contains "risk_above_max_trade" or "daily_plan_cap_reached" in its source (heuristic)
3) Injects:
   - day-roll fallback keyed by YYYYMMDD (uses `now` if available, else datetime.now(timezone.utc))
   - daily budget check -> reasons.append("daily_risk_budget_reached")
   - consume budget on allow (best-effort, before returns)

Backups in: logs/ops/patches/P0_2_3_V2_3_<ts>/
"""

from __future__ import annotations

import ast
import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_2_3_V2_3_DAILY_BUDGET_ENFORCE"

def die(msg: str) -> None:
    print(f"[P0-2.3v2.3] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2.3] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir():
        return p
    for parent in p.parents:
        if (parent / "tbot").is_dir():
            return parent
    die("Run from repo root (contains ./tbot).")

def backup(root: Path, f: Path) -> Path:
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_3_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def _indent_of_line(lines: list[str], i: int) -> str:
    m = re.match(r"^([ \t]*)", lines[i])
    return m.group(1) if m else ""

def _first_body_indent(lines: list[str], start: int, end: int, default: str) -> str:
    for i in range(start, min(end, len(lines))):
        if lines[i].strip():
            m = re.match(r"^([ \t]+)", lines[i])
            if m:
                return m.group(1)
            return default
    return default

def _ast_find_shadowgate_and_methods(src: str):
    tree = ast.parse(src)
    shadow_cls = None
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "ShadowGate":
            shadow_cls = node
            break
    if shadow_cls is None:
        return None, {}

    methods = {}
    for n in shadow_cls.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            # Need end_lineno in py3.8+ (you have 3.13)
            methods[n.name] = n
    return shadow_cls, methods

def _pick_target_method(src_lines: list[str], methods: dict) -> str | None:
    # Prefer evaluate if exists
    if "evaluate" in methods:
        return "evaluate"

    # Heuristic: find a method that contains gate reasons keywords
    for name, fn in methods.items():
        if not getattr(fn, "lineno", None) or not getattr(fn, "end_lineno", None):
            continue
        seg = "".join(src_lines[fn.lineno-1:fn.end_lineno])
        if ("risk_above_max_trade" in seg) or ("daily_plan_cap_reached" in seg) or ("reasons.append" in seg):
            return name

    # fallback: first public method
    for name in methods.keys():
        if not name.startswith("_"):
            return name
    return None

def _inject_into_method(lines: list[str], fn_node, inject_block: str) -> tuple[list[str], bool]:
    start = fn_node.lineno - 1
    end = fn_node.end_lineno  # slicing end is exclusive already if used as [:end]
    # Find insertion line: after "reasons = []" within method block
    insert_at = None
    for i in range(start, min(end, len(lines))):
        if re.search(r"\breasons\s*=\s*\[\s*\]\s*$", lines[i].strip()):
            insert_at = i + 1
            break
    if insert_at is None:
        # after docstring if present (first triple-quote block), else right after def header block
        # Find first non-empty line after header, skip docstring if it's the first statement.
        insert_at = start + 1
        # Move to first body line with indent > def indent
        def_indent = _indent_of_line(lines, start)
        for i in range(start+1, min(end, len(lines))):
            if lines[i].strip() and _indent_of_line(lines, i).startswith(def_indent) and _indent_of_line(lines, i) != def_indent:
                insert_at = i
                break

    # Prevent double patch
    seg = "".join(lines[start:end])
    if MARK in seg:
        return lines, False

    lines2 = lines[:insert_at] + [inject_block] + lines[insert_at:]
    return lines2, True

def _inject_before_returns(lines: list[str], fn_node, inject_block: str) -> tuple[list[str], bool]:
    start = fn_node.lineno - 1
    end = fn_node.end_lineno
    seg = "".join(lines[start:end])
    if MARK in seg:
        # already patched via earlier inject; still may need return injection, but avoid duplication
        pass

    out = []
    changed = False
    for i, ln in enumerate(lines):
        if start <= i < end and ln.lstrip().startswith("return "):
            out.append(inject_block)
            changed = True
        out.append(ln)
    return out, changed

def _patch_init(lines: list[str], methods: dict) -> tuple[list[str], bool]:
    if "__init__" not in methods:
        info("WARN: ShadowGate.__init__ not found; skip _risk_today init")
        return lines, False

    fn = methods["__init__"]
    start = fn.lineno - 1
    end = fn.end_lineno
    seg = "".join(lines[start:end])
    if "self._risk_today" in seg:
        info("__init__: self._risk_today already exists")
        return lines, False

    def_indent = _indent_of_line(lines, start)
    body_indent = _first_body_indent(lines, start+1, end, def_indent + "    ")
    inject = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}self._risk_today = 0.0\n"
    )

    # insert near top of __init__ body (after any docstring)
    insert_at = start + 1
    # find first real body line
    for i in range(start+1, min(end, len(lines))):
        if lines[i].strip():
            insert_at = i
            break

    lines2 = lines[:insert_at] + [inject] + lines[insert_at:]
    info("__init__: added self._risk_today = 0.0")
    return lines2, True

def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    src = f.read_text(encoding="utf-8", errors="ignore")
    cls, methods = _ast_find_shadowgate_and_methods(src)
    if cls is None:
        die("Could not find class ShadowGate in shadow_gate.py")

    lines = src.splitlines(True)

    b = backup(root, f)
    info(f"Backup: {b.relative_to(root)}")

    # 1) init
    lines, _ = _patch_init(lines, methods)

    # Rebuild src for accurate lineno? We changed line offsets.
    # Easiest: re-parse after init patch.
    src2 = "".join(lines)
    cls2, methods2 = _ast_find_shadowgate_and_methods(src2)
    if cls2 is None:
        die("Internal: ShadowGate missing after init patch?")

    target = _pick_target_method(src2.splitlines(True), methods2)
    if not target:
        die("Could not pick a target decision method inside ShadowGate.")

    fn = methods2[target]
    info(f"Target method: ShadowGate.{target}  (lines {fn.lineno}-{fn.end_lineno})")

    # compute indent for injection inside target
    def_line_idx = fn.lineno - 1
    def_indent = _indent_of_line(src2.splitlines(True), def_line_idx)
    body_indent = _first_body_indent(src2.splitlines(True), fn.lineno, fn.end_lineno, def_indent + "    ")

    # daily budget blocks
    inject_top = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}# Day roll fallback (works even if _roll_day/_rollover isn't present)\n"
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
        f"\n"
        f"{body_indent}# Daily budget check (inside gate)\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _day_cap = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{body_indent}    _risk_plan = float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{body_indent}    if _day_cap is not None:\n"
        f"{body_indent}        if float(getattr(self, '_risk_today', 0.0)) + _risk_plan > float(_day_cap):\n"
        f"{body_indent}            reasons.append('daily_risk_budget_reached')\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
    )

    inject_before_return = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}# Consume budget on allow=True (best-effort)\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{body_indent}    if _day_cap2 is not None:\n"
        f"{body_indent}        _a = None\n"
        f"{body_indent}        if 'allow' in locals():\n"
        f"{body_indent}            _a = bool(locals().get('allow'))\n"
        f"{body_indent}        # If return True is used without 'allow', we still guard by empty reasons.\n"
        f"{body_indent}        if (_a is True) and (len(reasons) == 0):\n"
        f"{body_indent}            self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
    )

    # apply injections
    lines3 = src2.splitlines(True)
    lines3, ok_top = _inject_into_method(lines3, fn, inject_top)

    # reparse after top injection to keep lineno aligned for return injection
    src3 = "".join(lines3)
    _, methods3 = _ast_find_shadowgate_and_methods(src3)
    fn3 = methods3[target]

    lines4 = src3.splitlines(True)
    lines4, ok_ret = _inject_before_returns(lines4, fn3, inject_before_return)

    out_src = "".join(lines4)
    f.write_text(out_src, encoding="utf-8")

    info(f"Applied {MARK}. top_injected={ok_top} return_injected={ok_ret}")
    info("Now run: python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
