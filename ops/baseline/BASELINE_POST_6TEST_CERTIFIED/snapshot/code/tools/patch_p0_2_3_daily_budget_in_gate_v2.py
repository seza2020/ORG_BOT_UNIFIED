#!/usr/bin/env python3
"""
P0-2.3 v2 Patch: enforce daily risk budget inside ShadowGate.evaluate() (signature-agnostic)

- Finds def evaluate(...) in tbot/runtime/shadow_gate.py regardless of signature.
- Adds:
  - daily budget reject: daily_risk_budget_reached
  - consume on allow: self._risk_today += risk_plan
  - day reset: in _roll_day(...) if present, otherwise fallback day-key in evaluate
Idempotent via marker.
"""

from __future__ import annotations
import re, sys, shutil, datetime as dt
from pathlib import Path

MARK = "P0_2_3_V2_DAILY_BUDGET_ENFORCE"

def die(msg: str) -> None:
    print(f"[P0-2.3v2] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def info(msg: str) -> None:
    print(f"[P0-2.3v2] {msg}")

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
    out = root / "logs" / "ops" / "patches" / f"P0_2_3_V2_{ts}" / f.relative_to(root)
    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, out)
    return out

def _extract_block(txt: str, def_line_start: int) -> tuple[int,int,str]:
    """
    Given index at start of a 'def ...' line, extract its block until next def at same indent.
    """
    # indent of def line
    line_start = def_line_start
    line_end = txt.find("\n", line_start)
    if line_end == -1:
        line_end = len(txt)
    def_line = txt[line_start:line_end]
    m = re.match(r"^(\s*)def\s+", def_line)
    if not m:
        die("Internal: def line indent parse failed.")
    def_indent = m.group(1)

    body_start = line_end + 1
    # Find next line that starts with same indent + "def "
    pat = re.compile(rf"\n{re.escape(def_indent)}def\s+\w+\s*\(", re.M)
    nm = pat.search(txt, body_start)
    block_end = nm.start() if nm else len(txt)
    return body_start, block_end, txt[body_start:block_end]

def _patch_roll_day(txt: str) -> tuple[str, bool]:
    m = re.search(r"^\s*def\s+_roll_day\s*\(.*\)\s*:\s*$", txt, flags=re.M)
    if not m:
        info("WARN: _roll_day(...) not found. Will use fallback day-reset inside evaluate().")
        return txt, False

    body_start, block_end, body = _extract_block(txt, m.start())

    if MARK in body:
        info("_roll_day already patched.")
        return txt, True

    lines = body.splitlines(True)
    first_code = next((ln for ln in lines if ln.strip()), "")
    indent = re.match(r"^(\s+)", first_code).group(1) if first_code else "        "

    # Insert reset near top
    insert_at = 0
    reset = f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n"
    lines.insert(insert_at, reset)

    new_body = "".join(lines)
    new_txt = txt[:body_start] + new_body + txt[block_end:]
    info("Patched _roll_day(): added self._risk_today reset.")
    return new_txt, True

def _patch_init_risk_today(txt: str) -> tuple[str, bool]:
    # Add self._risk_today in __init__ if missing
    im = re.search(r"^\s*def\s+__init__\s*\(.*\)\s*:\s*$", txt, flags=re.M)
    if not im:
        info("WARN: __init__ not found (skipping _risk_today init).")
        return txt, False

    body_start, block_end, body = _extract_block(txt, im.start())
    if "self._risk_today" in body:
        info("__init__: self._risk_today already present.")
        return txt, True

    lines = body.splitlines(True)
    first_code = next((ln for ln in lines if ln.strip()), "")
    indent = re.match(r"^(\s+)", first_code).group(1) if first_code else "        "
    ins = f"{indent}# {MARK}\n{indent}self._risk_today = 0.0\n"
    lines.insert(0, ins)

    new_body = "".join(lines)
    new_txt = txt[:body_start] + new_body + txt[block_end:]
    info("Patched __init__(): added self._risk_today = 0.0")
    return new_txt, True

def _patch_evaluate(txt: str, has_roll_day: bool) -> tuple[str, bool]:
    em = re.search(r"^\s*def\s+evaluate\s*\(.*\)\s*:\s*$", txt, flags=re.M)
    if not em:
        die("Could not find def evaluate(...) in tbot/runtime/shadow_gate.py")

    body_start, block_end, body = _extract_block(txt, em.start())
    if MARK in body:
        info("evaluate already patched.")
        return txt, True

    lines = body.splitlines(True)
    first_code = next((ln for ln in lines if ln.strip()), "")
    indent = re.match(r"^(\s+)", first_code).group(1) if first_code else "        "

    # Find where reasons list exists; we want to insert after "reasons = []" if possible
    reasons_idx = None
    for i, ln in enumerate(lines[:300]):
        if re.search(r"\breasons\s*=\s*\[\s*\]\s*$", ln.strip()):
            reasons_idx = i + 1
            break
    if reasons_idx is None:
        # fallback: insert near top
        reasons_idx = 0

    # Fallback day reset if no _roll_day:
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

    # Insert day reset (if needed) then budget check
    insert_payload = (day_reset + budget_block)
    lines.insert(reasons_idx, insert_payload)

    # Insert consume-on-allow: before first 'return'
    ret_idx = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("return "):
            ret_idx = i
            break

    consume = (
        f"{indent}# {MARK}\n"
        f"{indent}# Consume day budget immediately when allowed (so subsequent calls reject correctly).\n"
        f"{indent}try:\n"
        f"{indent}    _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)\n"
        f"{indent}    if _day_cap2 is not None and len(reasons) == 0:\n"
        f"{indent}        self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    if ret_idx is None:
        lines.append("\n" + consume)
    else:
        lines.insert(ret_idx, consume)

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
    info("Applied P0-2.3 v2 successfully.")
    info("Now run: python .\\tools\\p0_2_2_gate_selftest.py")

if __name__ == "__main__":
    main()
