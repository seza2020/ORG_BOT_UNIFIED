#!/usr/bin/env python3
"""
P0-2.3 v2.2 Patch (organizational + robust):
- Enforce daily risk budget inside ShadowGate.evaluate()
- Avoid brittle line-bound parsing; derive indent from def-regex directly.
- Works with async def, CRLF, BOM/weird chars.

What it does:
1) Ensure self._risk_today exists in __init__ (best-effort)
2) Reset _risk_today in _roll_day if present (best-effort)
3) In evaluate():
   - Add daily budget check after reasons=[] (or at top)
   - Add consume-on-allow guarded via locals()/best-effort before returns
"""

from __future__ import annotations

import re, sys, shutil, datetime as dt
from pathlib import Path

MARK = "P0_2_3_V2_2_DAILY_BUDGET_ENFORCE"

def die(msg: str) -> None:
    print(f"[P0-2.3v2.2] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2.2] {msg}")

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
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_2_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def extract_def_block(txt: str, name: str) -> tuple[str, str, int, int]:
    """
    Returns (def_indent, body_indent, body_start, block_end)
    Using regex match of def line; block_end is next def with same indent or EOF.
    """
    m = re.search(rf"(?m)^(?P<indent>[ \t]*)(?:async\s+)?def\s+{re.escape(name)}\s*\(.*\)\s*:\s*$", txt)
    if not m:
        raise ValueError(f"def {name} not found")

    def_indent = m.group("indent")
    body_start = m.end() + 1

    # next def at same indent
    nxt = re.search(rf"(?m)^{re.escape(def_indent)}(?:async\s+)?def\s+\w+\s*\(", txt[body_start:])
    block_end = body_start + (nxt.start() if nxt else len(txt) - body_start)

    body = txt[body_start:block_end]
    body_indent = def_indent + (" " * 4)
    for ln in body.splitlines():
        if ln.strip():
            mm = re.match(r"^([ \t]+)", ln)
            if mm:
                body_indent = mm.group(1)
            break

    return def_indent, body_indent, body_start, block_end

def patch_init(txt: str) -> str:
    try:
        def_indent, body_indent, bs, be = extract_def_block(txt, "__init__")
    except Exception:
        info("WARN: __init__ not found -> skip _risk_today init")
        return txt

    body = txt[bs:be]
    if "self._risk_today" in body:
        info("__init__: self._risk_today already exists")
        return txt

    ins = f"{body_indent}# {MARK}\n{body_indent}self._risk_today = 0.0\n"
    txt2 = txt[:bs] + ins + body + txt[be:]
    info("__init__: added self._risk_today = 0.0")
    return txt2

def patch_roll_day(txt: str) -> tuple[str, bool]:
    try:
        def_indent, body_indent, bs, be = extract_def_block(txt, "_roll_day")
    except Exception:
        info("WARN: _roll_day not found -> will use fallback day-key in evaluate")
        return txt, False

    body = txt[bs:be]
    if MARK in body:
        info("_roll_day already patched")
        return txt, True

    ins = f"{body_indent}# {MARK}\n{body_indent}self._risk_today = 0.0\n"
    txt2 = txt[:bs] + ins + body + txt[be:]
    info("_roll_day: added self._risk_today reset")
    return txt2, True

def patch_evaluate(txt: str, has_roll_day: bool) -> str:
    def_indent, body_indent, bs, be = extract_def_block(txt, "evaluate")
    body = txt[bs:be]
    if MARK in body:
        info("evaluate already patched")
        return txt

    lines = body.splitlines(True)

    # insert after reasons=[] if exists, else near top
    ins_at = 0
    for i, ln in enumerate(lines[:500]):
        if re.search(r"\breasons\s*=\s*\[\s*\]\s*$", ln.strip()):
            ins_at = i + 1
            break

    fallback_dayroll = ""
    if not has_roll_day:
        fallback_dayroll = (
            f"{body_indent}# {MARK}\n"
            f"{body_indent}# Fallback day roll (when _roll_day not present)\n"
            f"{body_indent}try:\n"
            f"{body_indent}    _k = None\n"
            f"{body_indent}    if 'now' in locals() and hasattr(locals().get('now'), 'strftime'):\n"
            f"{body_indent}        _k = locals().get('now').strftime('%Y%m%d')\n"
            f"{body_indent}    if _k is not None and getattr(self, '_risk_day_key', None) != _k:\n"
            f"{body_indent}        self._risk_day_key = _k\n"
            f"{body_indent}        self._risk_today = 0.0\n"
            f"{body_indent}except Exception:\n"
            f"{body_indent}    pass\n"
        )

    budget_check = (
        f"{body_indent}# {MARK}\n"
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

    lines.insert(ins_at, fallback_dayroll + budget_check)

    # consume-on-allow: before returns (best-effort)
    consume = (
        f"{body_indent}# {MARK}\n"
        f"{body_indent}# Consume budget when allow=True (best-effort)\n"
        f"{body_indent}try:\n"
        f"{body_indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{body_indent}    if _day_cap2 is not None:\n"
        f"{body_indent}        _allow = None\n"
        f"{body_indent}        if 'allow' in locals():\n"
        f"{body_indent}            _allow = bool(locals().get('allow'))\n"
        f"{body_indent}        # If code returns literal True, _allow may be None; we handle that in return-patching below.\n"
        f"{body_indent}        if _allow is True and len(reasons) == 0:\n"
        f"{body_indent}            self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    pass\n"
    )

    new_lines = []
    for ln in lines:
        # If return True..., consume right before it (for literal-True path)
        if re.match(r"^[ \t]*return\s+True\b", ln.strip()):
            new_lines.append(
                f"{body_indent}# {MARK}\n"
                f"{body_indent}try:\n"
                f"{body_indent}    _day_cap3 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
                f"{body_indent}    if _day_cap3 is not None and len(reasons) == 0:\n"
                f"{body_indent}        self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
                f"{body_indent}except Exception:\n"
                f"{body_indent}    pass\n"
            )
            new_lines.append(ln)
            continue

        # Generic: before any return, inject consume block (won’t double-count unless allow=True path triggers)
        if ln.lstrip().startswith("return "):
            new_lines.append(consume)
            new_lines.append(ln)
            continue

        new_lines.append(ln)

    new_body = "".join(new_lines)
    txt2 = txt[:bs] + new_body + txt[be:]
    info("evaluate: injected daily budget check + consume-on-allow guards")
    return txt2

def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "shadow_gate.py"
    if not f.exists():
        die("Missing tbot/runtime/shadow_gate.py")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    b = backup(root, f)
    info(f"Backup: {b.relative_to(root)}")

    txt = patch_init(txt)
    txt, has_roll = patch_roll_day(txt)
    txt = patch_evaluate(txt, has_roll_day=has_roll)

    f.write_text(txt, encoding="utf-8")
    info("Applied P0-2.3 v2.2 successfully.")
    info("Now run: python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
