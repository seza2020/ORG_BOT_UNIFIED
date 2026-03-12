#!/usr/bin/env python3
"""
P0-1.1 FIX (v2):
- Patch tbot/runtime/_shadow_observability.py
- Replace enrich_announce_line + mirror_shadow_line safely
- Avoid nested f-strings (the root cause of brief NameError)
- Backup under logs/ops/patches/
"""
from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_1_1_HEARTBEAT_MULTILINE_FIX_V2"

def die(msg: str, code: int = 1) -> None:
    print(f"[P0-1.1] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

def info(msg: str) -> None:
    print(f"[P0-1.1] {msg}")

def repo_root() -> Path:
    p = Path.cwd().resolve()
    for x in [p] + list(p.parents):
        if (x / "tbot").is_dir() and (x / "tools").is_dir():
            return x
    die("Run from repo root (must contain ./tbot and ./tools).")

def replace_function_block(txt: str, func_name: str, new_block: str) -> tuple[str, bool]:
    """
    Replace a top-level function 'def func_name(...): ...' up to next top-level 'def ...'
    """
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
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_1_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    backup_path = backup_dir / "tbot" / "runtime" / "_shadow_observability.py"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(f, backup_path)
    info(f"Backup: {backup_path.relative_to(root)}")

    txt = f.read_text(encoding="utf-8", errors="ignore")

    new_enrich = (
        "# " + MARK + "\n"
        "def enrich_announce_line(line: str) -> str:\n"
        "    \"\"\"\n"
        "    Append gate brief to HEARTBEAT lines.\n"
        "    Supports multiline messages like:\n"
        "      INFO | ts | run | HEARTBEAT\\n...\n"
        "    We append shadow_gate=... to the FIRST line (the one containing HEARTBEAT).\n"
        "    \"\"\"\n"
        "    try:\n"
        "        if \"HEARTBEAT\" not in line or \"shadow_gate=\" in line:\n"
        "            return line\n"
        "        brief = _gate_brief()\n"
        "        if not brief:\n"
        "            return line\n"
        "\n"
        "        # Multiline case: modify only first line\n"
        "        if \"\\n\" in line:\n"
        "            first, rest = line.split(\"\\n\", 1)\n"
        "            if \"HEARTBEAT\" in first:\n"
        "                return first.rstrip(\"\\r\") + \" shadow_gate=\" + str(brief) + \"\\n\" + rest\n"
        "            return line\n"
        "\n"
        "        # Single-line case\n"
        "        if line.endswith(\"\\n\"):\n"
        "            return line[:-1] + \" shadow_gate=\" + str(brief) + \"\\n\"\n"
        "        return line + \" shadow_gate=\" + str(brief)\n"
        "    except Exception:\n"
        "        return line\n"
        "\n"
    )

    new_mirror = (
        "# " + MARK + "\n"
        "def mirror_shadow_line(line: str) -> None:\n"
        "    \"\"\"Mirror shadow_accept/shadow_reject announce lines into JSONL candidates log.\"\"\"\n"
        "    try:\n"
        "        raw = line.rstrip(\"\\n\")\n"
        "        # tolerate slight formatting variations\n"
        "        if \" | shadow_accept\" not in raw and \" | shadow_reject\" not in raw:\n"
        "            return\n"
        "\n"
        "        parts = [p.strip() for p in raw.split(\"|\", 3)]\n"
        "        if len(parts) < 4:\n"
        "            return\n"
        "        level, ts, run_id, rest = parts[0], parts[1], parts[2], parts[3]\n"
        "        if \" \" not in rest:\n"
        "            return\n"
        "        msg, payload_str = rest.split(\" \", 1)\n"
        "        payload_str = payload_str.strip()\n"
        "        if not (payload_str.startswith(\"{\") and payload_str.endswith(\"}\")):\n"
        "            return\n"
        "\n"
        "        payload = ast.literal_eval(payload_str)\n"
        "        if not isinstance(payload, dict):\n"
        "            return\n"
        "\n"
        "        status = \"ACCEPT\" if msg == \"shadow_accept\" else \"REJECT\"\n"
        "        obj = {\n"
        "            \"ts\": ts,\n"
        "            \"run_id\": run_id,\n"
        "            \"level\": level,\n"
        "            \"event\": msg,\n"
        "            \"status\": status,\n"
        "            **payload,\n"
        "        }\n"
        "        _append_jsonl(_CANDIDATES_PATH, obj)\n"
        "\n"
        "        if msg == \"shadow_reject\":\n"
        "            reasons = payload.get(\"reasons\") or []\n"
        "            if isinstance(reasons, (list, tuple)) and \"daily_plan_cap_reached\" in reasons:\n"
        "                global _LAST_CAP_SUMMARY_UTC\n"
        "                now = _now_utc()\n"
        "                if _LAST_CAP_SUMMARY_UTC is None or (now - _LAST_CAP_SUMMARY_UTC).total_seconds() >= 60:\n"
        "                    _LAST_CAP_SUMMARY_UTC = now\n"
        "                    brief = _gate_brief()\n"
        "                    if brief:\n"
        "                        _append_jsonl(_CANDIDATES_PATH, {\n"
        "                            \"ts\": ts,\n"
        "                            \"run_id\": run_id,\n"
        "                            \"level\": \"WARN\",\n"
        "                            \"event\": \"shadow_gate_cap\",\n"
        "                            \"note\": \"daily_plan_cap_reached\",\n"
        "                            \"shadow_gate\": brief,\n"
        "                        })\n"
        "    except Exception:\n"
        "        return\n"
        "\n"
    )

    txt2, ok1 = replace_function_block(txt, "enrich_announce_line", new_enrich)
    txt3, ok2 = replace_function_block(txt2, "mirror_shadow_line", new_mirror)

    if not ok1:
        die("Could not find enrich_announce_line() to patch.")
    if not ok2:
        die("Could not find mirror_shadow_line() to patch.")

    f.write_text(txt3, encoding="utf-8")
    info("Applied P0-1.1 successfully.")

if __name__ == "__main__":
    main()
