#!/usr/bin/env python3
"""
P0-1.1 HOTFIX:
- Fix enrich_announce_line to work with multiline HEARTBEAT messages.
- Make shadow_accept/reject matching more tolerant.
Creates backup under logs/ops/patches/.
"""
from __future__ import annotations
import datetime as dt
import re
import shutil
import sys
from pathlib import Path

MARK = "P0_1_1_HEARTBEAT_MULTILINE_FIX"

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
    lines = txt.splitlines(True)
    start = None
    pat = re.compile(rf"^\s*def\s+{re.escape(func_name)}\s*\(")
    for i, line in enumerate(lines):
        if pat.match(line):
            start = i
            break
    if start is None:
        return txt, False

    # end = next top-level def (col 0) after start
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

    new_enrich = f'''# {MARK}
def enrich_announce_line(line: str) -> str:
    """
    Append gate brief to HEARTBEAT lines.
    Supports multiline messages like:
      INFO | ts | run | HEARTBEAT\\n...
    We append shadow_gate=... to the FIRST line (the one containing HEARTBEAT).
    """
    try:
        if "HEARTBEAT" not in line or "shadow_gate=" in line:
            return line
        brief = _gate_brief()
        if not brief:
            return line

        # Split once so we can modify only the first line
        if "\\n" in line:
            first, rest = line.split("\\n", 1)
            if "HEARTBEAT" in first:
                return first.rstrip("\\r") + f" shadow_gate={brief}\\n" + rest
            return line

        # Single-line case
        if line.endswith("\\n"):
            return line[:-1] + f" shadow_gate={brief}\\n"
        return line + f" shadow_gate={brief}"
    except Exception:
        return line
'''

    new_mirror = f'''# {MARK}
def mirror_shadow_line(line: str) -> None:
    """Mirror shadow_accept/shadow_reject announce lines into JSONL candidates log."""
    try:
        raw = line.rstrip("\\n")
        # tolerate missing trailing space after event name
        if " | shadow_accept" not in raw and " | shadow_reject" not in raw:
            return

        parts = [p.strip() for p in raw.split("|", 3)]
        if len(parts) < 4:
            return
        level, ts, run_id, rest = parts[0], parts[1], parts[2], parts[3]
        if " " not in rest:
            return
        msg, payload_str = rest.split(" ", 1)
        payload_str = payload_str.strip()
        if not (payload_str.startswith("{") and payload_str.endswith("}")):
            return

        payload = ast.literal_eval(payload_str)
        if not isinstance(payload, dict):
            return

        status = "ACCEPT" if msg == "shadow_accept" else "REJECT"
        obj = {{
            "ts": ts,
            "run_id": run_id,
            "level": level,
            "event": msg,
            "status": status,
            **payload,
        }}
        _append_jsonl(_CANDIDATES_PATH, obj)

        if msg == "shadow_reject":
            reasons = payload.get("reasons") or []
            if isinstance(reasons, (list, tuple)) and "daily_plan_cap_reached" in reasons:
                global _LAST_CAP_SUMMARY_UTC
                now = _now_utc()
                if _LAST_CAP_SUMMARY_UTC is None or (now - _LAST_CAP_SUMMARY_UTC).total_seconds() >= 60:
                    _LAST_CAP_SUMMARY_UTC = now
                    brief = _gate_brief()
                    if brief:
                        _append_jsonl(_CANDIDATES_PATH, {{
                            "ts": ts,
                            "run_id": run_id,
                            "level": "WARN",
                            "event": "shadow_gate_cap",
                            "note": "daily_plan_cap_reached",
                            "shadow_gate": brief,
                        }})
    except Exception:
        return
'''

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
