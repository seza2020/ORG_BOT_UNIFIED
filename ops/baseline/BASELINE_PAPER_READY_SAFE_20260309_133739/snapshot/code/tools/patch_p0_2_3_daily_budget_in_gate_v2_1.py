#!/usr/bin/env python3
"""
P0-2.3 v2.1 Patch: enforce daily risk budget inside ShadowGate.evaluate() (robust)

Fixes vs v2:
- Supports: async def
- Supports BOM / weird leading chars by using regex search, not strict re.match
- Better block extraction (find def indent via regex on the full line)
"""

from __future__ import annotations
import re, sys, shutil, datetime as dt
from pathlib import Path

MARK = "P0_2_3_V2_1_DAILY_BUDGET_ENFORCE"

def die(msg: str) -> None:
    print(f"[P0-2.3v2.1] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2.1] {msg}")

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
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_1_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def _line_bounds(txt: str, i: int) -> tuple[int,int]:
    ls = txt.rfind("\n", 0, i)
    ls = 0 if ls == -1 else ls + 1
    le = txt.find("\n", i)
    le = len(txt) if le == -1 else le
    return ls, le

def _extract_block(txt: str, def_match_start: int) -> tuple[str, str, str, int, int]:
    """
    Return (def_indent, body_indent, body_text, body_start, block_end)
    """
    ls, le = _line_bounds(txt, def_match_start)
    def_line = txt[ls:le]

    # Robust indent detection (supports async def)
    m = re.search(r"^(\s*)(?:async\s+)?def\s+\w+\s*\(", def_line)
    if not m:
        # Print the raw line for debugging
        dbg = def_line.replace("\t", "\\t").replace("\r", "\\r")
        die(f"Could not parse def-line indent. Line was: {dbg}")

    def_indent = m.group(1)

    body_start = le + 1
    # Next def at same indentation
    pat = re.compile(rf"\n{re.escape(def_indent)}(?:async\s+)?def\s+\w+\s*\(", re.M)
    nm = pat.search(txt, body_start)
    block_end = nm.start() if nm else len(txt)

    body = txt[body_start:block_end]
    # Determine body indent from first non-empty line
    body_indent = "        "
    for ln in body.splitlines():
        if ln.strip():
            mm = re.match(r"^(\s+)", ln)
            if mm:
                body_indent = mm.group(1)
            break

    return def_indent, body_indent, body, body_start, block_end

def _find_def(txt: str, name: str):
    return re.search(rf"^\s*(?:async\s+)?def\s+{re.escape(name)}\s*\(.*\)\s*:\s*$", txt, flags=re.M)

def _patch_init_risk_today(txt: str) -> tuple[str, bool]:
    m = _find_def(txt, "__init__")
    if not m:
        info("WARN: __init__ not found (skipping _risk_today init).")
        return txt, False

    _, indent, body, body_start, block_end = _extract_block(txt, m.start())
    if "self._risk_today" in body:
        info("__init__: self._risk_today already present.")
        return txt, True

    ins = f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n"
    new_body = ins + body
    new_txt = txt[:body_start] + new_body + txt[block_end:]
    info("Patched __init__(): added self._risk_today = 0.0")
    return new_txt, True

def _patch_roll_day(txt: str) -> tuple[str, bool]:
    m = _find_def(txt, "_roll_day")
    if not m:
        info("WARN: _roll_day(...) not found. Will use fallback day-reset inside evaluate().")
        return txt, False

    _, indent, body, body_start, block_end = _extract_block(txt, m.start())
    if MARK in body:
        info("_roll_day already patched.")
        return txt, True

    reset = f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n"
    new_body = reset + body
    new_txt = txt[:body_start] + new_body + txt[block_end:]
    info("Patched _roll_day(): added self._risk_today reset.")
    return new_txt, True

def _patch_evaluate(txt: str, has_roll_day: bool) -> tuple[str, bool]:
    m = _find_def(txt, "evaluate")
    if not m:
        die("Could not find def evaluate(...) in tbot/runtime/shadow_gate.py")

    _, indent, body, body_start, block_end = _extract_block(txt, m.start())
    if MARK in body:
        info("evaluate already patched.")
        return txt, True

    lines = body.splitlines(True)

    # Where to insert budget check: after 'reasons = []' if present
    ins_at = 0
    for i, ln in enumerate(lines[:400]):
        if re.search(r"\breasons\s*=\s*\[\s*\]\s*$", ln.strip()):
            ins_at = i + 1
            break

    day_reset = ""
    if not has_roll_day:
        day_reset = (
            f"{indent}# {MARK}\n"
            f"{indent}# Fallback day-rolling if _roll_day(...) not found.\n"
            f"{indent}try:\n"
            f"{indent}    _now_key = None\n"
            f"{indent}    if 'now' in locals() and hasattr(locals().get('now'), 'strftime'):\n"
            f"{indent}        _now_key = locals().get('now').strftime('%Y%m%d')\n"
            f"{indent}    if _now_key is not None:\n"
            f"{indent}        if getattr(self, '_risk_day_key', None) != _now_key:\n"
            f"{indent}            self._risk_day_key = _now_key\n"
            f"{indent}            self._risk_today = 0.0\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
        )

    budget_block = (
        f"{indent}# {MARK}\n"
        f"{indent}# Daily budget enforcement inside gate.\n"
        f"{indent}try:\n"
        f"{indent}    _day_cap = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{indent}    _risk_plan = float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{indent}    if _day_cap is not None:\n"
        f"{indent}        if float(getattr(self, '_risk_today', 0.0)) + float(_risk_plan) > float(_day_cap):\n"
        f"{indent}            reasons.append('daily_risk_budget_reached')\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    lines.insert(ins_at, day_reset + budget_block)

    # Consume-on-allow: insert before first return
    ret_i = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("return "):
            ret_i = i
            break

    consume = (
        f"{indent}# {MARK}\n"
        f"{indent}# Consume day budget immediately when allowed.\n"
        f"{indent}try:\n"
        f"{indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{indent}    if _day_cap2 is not None and len(reasons) == 0:\n"
        f"{indent}        self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    if ret_i is None:
        lines.append("\n" + consume)
    else:
        lines.insert(ret_i, consume)

    new_body = "".join(lines)
    new_txt = txt[:body_start] + new_body + txt[block_end:]
    info("Patched evaluate(): added daily budget check + consume-on-allow.")
    return new_txt, True

def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    b = backup(root, f)
    info(f"Backup: {b.relative_to(root)}")

    txt, _ = _patch_init_risk_today(txt)
    txt, has_roll = _patch_roll_day(txt)
    txt, _ = _patch_evaluate(txt, has_roll_day=has_roll)

    f.write_text(txt, encoding="utf-8")
    info("Applied P0-2.3 v2.1 successfully.")
    info("Now run: python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
