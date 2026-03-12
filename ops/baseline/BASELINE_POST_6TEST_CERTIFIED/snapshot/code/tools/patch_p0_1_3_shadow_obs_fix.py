#!/usr/bin/env python3
"""
P0-1.3: Fix missing enrich_announce_line + robust gate brief for your gate_state schema.
- Backup: logs/ops/patches/P0_1_3_*/tbot/runtime/_shadow_observability.py
- Replaces def _gate_brief()
- Ensures def enrich_announce_line() exists and supports multiline HEARTBEAT
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_1_3_SHADOW_OBS_HEARTBEAT_AND_GATE"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-1.3] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-1.3] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    for x in [p] + list(p.parents):
        if (x / "tbot").is_dir() and (x / "tools").is_dir():
            return x
    die("Run from repo root (must contain ./tbot and ./tools).")

def replace_def_block(txt: str, func_name: str, new_block: str) -> tuple[str, bool]:
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
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_3_{ts}"
    backup_path = backup_dir / "tbot" / "runtime" / "_shadow_observability.py"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, backup_path)
    info(f"Backup: {backup_path.relative_to(root)}")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    # 1) Replace _gate_brief() based on your real gate_state schema
    new_gate_brief = (
        f"# {MARK}\n"
        "def _gate_brief() -> Optional[str]:\n"
        "    \"\"\"Robust brief for gate_state_*.json (supports your persistent-cap-v1 schema).\"\"\"\n"
        "    st = _read_latest_gate_state()\n"
        "    if not st or not isinstance(st, dict):\n"
        "        return None\n"
        "\n"
        "    def _to_int(v):\n"
        "        try:\n"
        "            if isinstance(v, bool):\n"
        "                return None\n"
        "            if isinstance(v, (int, float)):\n"
        "                return int(v)\n"
        "            if isinstance(v, str):\n"
        "                s = v.strip()\n"
        "                if s.isdigit() or (s.startswith('-') and s[1:].isdigit()):\n"
        "                    return int(s)\n"
        "        except Exception:\n"
        "            return None\n"
        "        return None\n"
        "\n"
        "    # Prefer true counters in your schema\n"
        "    valid = _to_int(st.get('valid_accepts'))\n"
        "    acc = _to_int(st.get('shadow_accept'))\n"
        "    plans = _to_int(st.get('shadow_plan'))\n"
        "    rej = _to_int(st.get('shadow_reject'))\n"
        "    boot = _to_int(st.get('boot'))\n"
        "\n"
        "    # risk in USD (float ok)\n"
        "    risk = st.get('accepted_risk_usd')\n"
        "    try:\n"
        "        if isinstance(risk, str):\n"
        "            risk = float(risk.strip())\n"
        "        elif isinstance(risk, (int, float)):\n"
        "            risk = float(risk)\n"
        "        else:\n"
        "            risk = None\n"
        "    except Exception:\n"
        "        risk = None\n"
        "\n"
        "    parts = []\n"
        "    if plans is not None:\n"
        "        parts.append(f'plans={plans}')\n"
        "    if valid is not None:\n"
        "        parts.append(f'valid={valid}')\n"
        "    elif acc is not None:\n"
        "        parts.append(f'accepts={acc}')\n"
        "    if rej is not None:\n"
        "        parts.append(f'rej={rej}')\n"
        "    if risk is not None:\n"
        "        parts.append('risk_usd=' + str(int(round(risk))))\n"
        "    if boot is not None:\n"
        "        parts.append(f'boot={boot}')\n"
        "\n"
        "    # If cap/cooldown ever get added later, include them too\n"
        "    cd = _to_int(st.get('cooldown_sec') or st.get('gate_cooldown_sec'))\n"
        "    if cd is not None:\n"
        "        parts.append(f'cd={cd}s')\n"
        "    cap = _to_int(st.get('max_plans_per_day') or st.get('daily_cap') or st.get('cap') or st.get('effective_cap'))\n"
        "    if cap is not None:\n"
        "        parts.append(f'cap={cap}')\n"
        "\n"
        "    return ' '.join(parts) if parts else 'gate_state=present'\n"
        "\n"
    )

    txt2, ok = replace_def_block(txt, "_gate_brief", new_gate_brief)
    if not ok:
        die("Could not find def _gate_brief() to replace.")

    # 2) Ensure enrich_announce_line exists + supports multiline HEARTBEAT
    if re.search(r"^def\s+enrich_announce_line\s*\(", txt2, flags=re.M) is None:
        info("enrich_announce_line() missing -> appending a correct implementation.")
        txt2 += (
            "\n"
            f"# {MARK}\n"
            "def enrich_announce_line(text: str) -> str:\n"
            "    \"\"\"Append shadow_gate=<brief> to HEARTBEAT first line (supports multiline).\"\"\"\n"
            "    try:\n"
            "        if ' | HEARTBEAT' not in text:\n"
            "            return text\n"
            "        if 'shadow_gate=' in text:\n"
            "            return text\n"
            "        brief = _gate_brief()\n"
            "        if not brief:\n"
            "            return text\n"
            "        # Preserve multiline format: add to the first line only\n"
            "        if '\\n' in text:\n"
            "            first, rest = text.split('\\n', 1)\n"
            "            return first.rstrip('\\r') + f' shadow_gate={brief}' + '\\n' + rest\n"
            "        return text.rstrip('\\n').rstrip('\\r') + f' shadow_gate={brief}\\n'\n"
            "    except Exception:\n"
            "        return text\n"
            "\n"
        )
    else:
        # Replace existing enrich_announce_line with safe multiline version
        new_enrich = (
            f"# {MARK}\n"
            "def enrich_announce_line(text: str) -> str:\n"
            "    \"\"\"Append shadow_gate=<brief> to HEARTBEAT first line (supports multiline).\"\"\"\n"
            "    try:\n"
            "        if ' | HEARTBEAT' not in text:\n"
            "            return text\n"
            "        if 'shadow_gate=' in text:\n"
            "            return text\n"
            "        brief = _gate_brief()\n"
            "        if not brief:\n"
            "            return text\n"
            "        if '\\n' in text:\n"
            "            first, rest = text.split('\\n', 1)\n"
            "            return first.rstrip('\\r') + f' shadow_gate={brief}' + '\\n' + rest\n"
            "        return text.rstrip('\\n').rstrip('\\r') + f' shadow_gate={brief}\\n'\n"
            "    except Exception:\n"
            "        return text\n"
            "\n"
        )
        txt2, ok_en = replace_def_block(txt2, "enrich_announce_line", new_enrich)
        if not ok_en:
            # Shouldn't happen, but don't break if parser couldn't replace
            info("WARN: could not replace enrich_announce_line block; leaving existing implementation.")

    f.write_text(txt2, encoding="utf-8")
    info("Applied P0-1.3 successfully.")

    info("Quick tests:")
    info('  python -c "from tbot.runtime import _shadow_observability as o; print(o._read_latest_gate_state()); print(o._gate_brief())"')
    info('  python -c "from tbot.runtime._shadow_observability import enrich_announce_line; s=\'INFO  | 2026-02-19T00:00:00 | SELFTEST | HEARTBEAT\\nin_session=True\\n\'; print(enrich_announce_line(s))"')

if __name__ == "__main__":
    main()
