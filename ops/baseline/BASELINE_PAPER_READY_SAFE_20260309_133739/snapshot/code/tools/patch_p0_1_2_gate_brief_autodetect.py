#!/usr/bin/env python3
"""
P0-1.2: Make _gate_brief() robust (auto-detect keys in gate_state_*.json)
- Replaces ONLY def _gate_brief() block in tbot/runtime/_shadow_observability.py
- Adds safe fallbacks so HEARTBEAT always gets shadow_gate=... when gate_state exists
- Backup under logs/ops/patches/
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_1_2_GATE_BRIEF_AUTODETECT"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-1.2] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-1.2] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    for x in [p] + list(p.parents):
        if (x / "tbot").is_dir() and (x / "tools").is_dir():
            return x
    die("Run from repo root (must contain ./tbot and ./tools).")

def replace_func(txt: str, func_name: str, new_block: str) -> tuple[str, bool]:
    lines = txt.splitlines(True)
    start = None
    pat = re.compile(rf"^def\s+{re.escape(func_name)}\s*\(")
    for i, line in enumerate(lines):
        if pat.match(line):
            start = i
            break
    if start is None:
        return txt, False

    end = None
    for j in range(start + 1, len(lines)):
        if re.match(r"^def\s+\w+\s*\(", lines[j]):
            end = j
            break
    if end is None:
        end = len(lines)

    out = "".join(lines[:start]) + new_block + "".join(lines[end:])
    return out, True

def main() -> None:
    root = repo_root()
    f = root / "tbot" / "runtime" / "_shadow_observability.py"
    if not f.exists():
        die(f"Missing: {f}")

    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_2_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = backup_dir / "tbot" / "runtime" / "_shadow_observability.py"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, backup_path)
    info(f"Backup: {backup_path.relative_to(root)}")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    new_gate_brief = (
        "# " + MARK + "\n"
        "def _gate_brief() -> Optional[str]:\n"
        "    \"\"\"Return a short, stable summary of current shadow gate state.\n"
        "    This is intentionally robust to schema drift in gate_state_*.json.\n"
        "    \"\"\"\n"
        "    st = _read_latest_gate_state()\n"
        "    if not st or not isinstance(st, dict):\n"
        "        return None\n"
        "\n"
        "    # Some writers nest state under common keys\n"
        "    for k in (\"state\", \"gate\", \"shadow_gate\", \"shadow\", \"data\"):\n"
        "        v = st.get(k)\n"
        "        if isinstance(v, dict):\n"
        "            st = {**st, **v}\n"
        "\n"
        "    def _to_int(x: Any) -> Optional[int]:\n"
        "        try:\n"
        "            if isinstance(x, bool):\n"
        "                return None\n"
        "            if isinstance(x, (int, float)):\n"
        "                return int(x)\n"
        "            if isinstance(x, str):\n"
        "                s = x.strip()\n"
        "                if s.isdigit() or (s.startswith(\"-\") and s[1:].isdigit()):\n"
        "                    return int(s)\n"
        "        except Exception:\n"
        "            return None\n"
        "        return None\n"
        "\n"
        "    def _pick_int(keys_exact: list[str], contains_any: tuple[str, ...]) -> Optional[int]:\n"
        "        # 1) exact\n"
        "        for k in keys_exact:\n"
        "            if k in st:\n"
        "                v = _to_int(st.get(k))\n"
        "                if v is not None:\n"
        "                    return v\n"
        "        # 2) substring search\n"
        "        for k, v0 in st.items():\n"
        "            try:\n"
        "                kk = str(k).lower()\n"
        "            except Exception:\n"
        "                continue\n"
        "            if any(sub in kk for sub in contains_any):\n"
        "                v = _to_int(v0)\n"
        "                if v is not None:\n"
        "                    return v\n"
        "        return None\n"
        "\n"
        "    def _pick_str(keys_exact: list[str], contains_any: tuple[str, ...]) -> Optional[str]:\n"
        "        for k in keys_exact:\n"
        "            if k in st and st.get(k):\n"
        "                return str(st.get(k))\n"
        "        for k, v0 in st.items():\n"
        "            try:\n"
        "                kk = str(k).lower()\n"
        "            except Exception:\n"
        "                continue\n"
        "            if any(sub in kk for sub in contains_any) and v0:\n"
        "                return str(v0)\n"
        "        return None\n"
        "\n"
        "    accepts = _pick_int(\n"
        "        [\"accepts_today\", \"n_accepts_today\", \"accepted_today\", \"accepts\", \"accepted\"],\n"
        "        (\"accept\", \"accepted\")\n"
        "    )\n"
        "    cap = _pick_int(\n"
        "        [\"max_plans_per_day\", \"daily_cap\", \"cap\", \"cap_plans\", \"effective_cap\", \"max_daily\"],\n"
        "        (\"cap\", \"max_plans\", \"max_plans_per\", \"daily_cap\", \"max_daily\")\n"
        "    )\n"
        "    cd = _pick_int(\n"
        "        [\"cooldown_sec\", \"gate_cooldown_sec\", \"cooldown\"],\n"
        "        (\"cooldown\",)\n"
        "    )\n"
        "    reset = _pick_str(\n"
        "        [\"next_reset_utc\", \"reset_utc\", \"reset_at_utc\", \"reset_at\", \"next_reset\"],\n"
        "        (\"reset\",)\n"
        "    )\n"
        "\n"
        "    parts: list[str] = []\n"
        "    try:\n"
        "        if accepts is not None and cap is not None:\n"
        "            rem = max(int(cap) - int(accepts), 0)\n"
        "            parts.append(str(int(accepts)) + \"/\" + str(int(cap)))\n"
        "            parts.append(\"rem=\" + str(rem))\n"
        "        elif accepts is not None:\n"
        "            parts.append(\"accepts=\" + str(int(accepts)))\n"
        "        elif cap is not None:\n"
        "            parts.append(\"cap=\" + str(int(cap)))\n"
        "        if cd is not None:\n"
        "            parts.append(\"cd=\" + str(int(cd)) + \"s\")\n"
        "        if reset:\n"
        "            parts.append(\"reset=\" + reset)\n"
        "\n"
        "        # last resort: if we have a dict but couldn't extract numbers\n"
        "        if not parts:\n"
        "            parts.append(\"gate_state=present\")\n"
        "\n"
        "        return \" \".join(parts)\n"
        "    except Exception:\n"
        "        return \"gate_state=present\"\n"
        "\n"
    )

    txt2, ok = replace_func(txt, "_gate_brief", new_gate_brief)
    if not ok:
        die("Could not find def _gate_brief() to replace (pattern mismatch).")

    f.write_text(txt2, encoding="utf-8")
    info("Applied P0-1.2 successfully.")
    info('Verify (offline): python -c "from tbot.runtime import _shadow_observability as o; print(o._read_latest_gate_state()); print(o._gate_brief())"')

if __name__ == "__main__":
    main()
