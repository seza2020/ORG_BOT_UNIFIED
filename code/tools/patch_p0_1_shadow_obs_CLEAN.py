#!/usr/bin/env python3
"""
P0-1 CLEAN patch (from scratch):
- Writes/Upgrades: tbot/runtime/_shadow_observability.py
- Patches: tbot/main.py to activate patch at startup (patch_logging_emit)

Result:
- HEARTBEAT lines gain: shadow_gate=<accept/cap rem cd reset>
- shadow_accept / shadow_reject mirrored to logs/shadow_candidates.jsonl
"""

from __future__ import annotations

import datetime as dt
import shutil
import sys
from pathlib import Path
import re


MARK = "P0_1_SHADOW_OBSERVABILITY"
HELPER_REL = Path("tbot") / "runtime" / "_shadow_observability.py"
MAIN_REL = Path("tbot") / "main.py"


def die(msg: str, code: int = 1) -> None:
    print(f"[P0-1] ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg: str) -> None:
    print(f"[P0-1] {msg}")


def repo_root_from_cwd() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir() and (p / "tools").is_dir():
        return p
    for parent in [p] + list(p.parents):
        if (parent / "tbot").is_dir() and (parent / "tools").is_dir():
            return parent
    die("Run from repo root (must contain ./tbot and ./tools).")


def backup_file(root: Path, src: Path, backup_dir: Path) -> None:
    rel = src.relative_to(root)
    dst = backup_dir / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def ensure_helper(root: Path, backup_dir: Path) -> None:
    helper_path = root / HELPER_REL
    helper_path.parent.mkdir(parents=True, exist_ok=True)

    existing = ""
    if helper_path.exists():
        existing = helper_path.read_text(encoding="utf-8", errors="ignore")

    # If already has our marker AND required functions, keep it.
    required = ["def enrich_announce_text", "def mirror_shadow_text", "def patch_logging_emit"]
    if existing and (MARK in existing) and all(k in existing for k in required):
        info(f"Helper already OK: {HELPER_REL}")
        return

    helper_code = "# " + MARK + "\n" + r'''from __future__ import annotations

import ast
import datetime as dt
import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, Optional

# Optional override:
#   $env:TBOT_SHADOW_CANDIDATES_PATH="C:\path\to\logs\shadow_candidates.jsonl"
_CANDIDATES_PATH = os.getenv("TBOT_SHADOW_CANDIDATES_PATH") or str(Path("logs") / "shadow_candidates.jsonl")

def _read_latest_gate_state() -> Optional[Dict[str, Any]]:
    ops = Path("logs") / "ops"
    try:
        files = sorted(ops.glob("gate_state_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    except Exception:
        return None
    if not files:
        return None
    try:
        return json.loads(files[0].read_text(encoding="utf-8"))
    except Exception:
        return None

def _gate_brief() -> Optional[str]:
    st = _read_latest_gate_state()
    if not st:
        return None

    accepts = st.get("accepts_today") or st.get("accepts") or st.get("accepted") or st.get("n_accepts_today")
    cap = st.get("max_plans_per_day") or st.get("cap_plans") or st.get("daily_cap") or st.get("effective_cap") or st.get("cap")
    cd = st.get("cooldown_sec") or st.get("gate_cooldown_sec")
    reset = st.get("next_reset_utc") or st.get("reset_utc") or st.get("reset_at_utc")

    try:
        parts = []
        if accepts is not None and cap is not None:
            rem = max(int(cap) - int(accepts), 0)
            parts += [f"{int(accepts)}/{int(cap)}", f"rem={rem}"]
        if cd is not None:
            parts.append(f"cd={int(cd)}s")
        if reset:
            parts.append(f"reset={reset}")
        return " ".join(parts) if parts else None
    except Exception:
        return None

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")

def enrich_announce_text(text: str) -> str:
    """
    Enrich *formatted* log text. Handles multi-line messages.
    Appends shadow_gate=... only to the line that contains ' | HEARTBEAT'.
    """
    try:
        if " | HEARTBEAT" not in text or "shadow_gate=" in text:
            return text
        brief = _gate_brief()
        if not brief:
            return text
        lines = text.splitlines(True)  # keep \n
        for i, ln in enumerate(lines):
            if (" | HEARTBEAT" in ln) and ("shadow_gate=" not in ln):
                if ln.endswith("\n"):
                    ln = ln[:-1] + f" shadow_gate={brief}\n"
                else:
                    ln = ln + f" shadow_gate={brief}"
                lines[i] = ln
                break
        return "".join(lines)
    except Exception:
        return text

def mirror_shadow_line(line: str) -> None:
    """
    Mirror one announce line if it is shadow_accept/shadow_reject with dict payload.
    """
    try:
        raw = line.rstrip("\n")
        if " | shadow_accept " not in raw and " | shadow_reject " not in raw:
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
        obj = {"ts": ts, "run_id": run_id, "level": level, "event": msg, "status": status, **payload}
        _append_jsonl(_CANDIDATES_PATH, obj)
    except Exception:
        return

def mirror_shadow_text(text: str) -> None:
    """
    Runs mirror_shadow_line over each line of a multi-line formatted message.
    """
    try:
        for ln in text.splitlines():
            mirror_shadow_line(ln + "\n")
    except Exception:
        return

def patch_logging_emit() -> None:
    """
    Monkeypatch logging.StreamHandler.emit globally, but only intercept
    handlers that have baseFilename containing 'announce.log'.
    """
    try:
        if getattr(logging, "_P0_1_PATCHED", False):
            return

        old_emit = logging.StreamHandler.emit

        def _emit(self, record):
            try:
                base = getattr(self, "baseFilename", None)
                if isinstance(base, str) and base.lower().endswith(os.sep + "announce.log"):
                    msg = self.format(record)
                    if not msg.endswith("\n"):
                        msg += "\n"
                    msg2 = enrich_announce_text(msg)
                    mirror_shadow_text(msg2)

                    # write enriched text ourselves (avoid double-write)
                    stream = getattr(self, "stream", None)
                    if stream is None:
                        try:
                            stream = self._open()  # FileHandler has _open()
                            self.stream = stream
                        except Exception:
                            stream = None
                    if stream is not None:
                        stream.write(msg2)
                        try:
                            self.flush()
                        except Exception:
                            pass
                        return
            except Exception:
                pass
            return old_emit(self, record)

        logging.StreamHandler.emit = _emit
        logging._P0_1_PATCHED = True
    except Exception:
        return
'''

    if helper_path.exists():
        backup_file(root, helper_path, backup_dir)

    helper_path.write_text(helper_code, encoding="utf-8")
    info(f"Wrote/Upgraded helper: {HELPER_REL}")


def patch_main_py(root: Path, backup_dir: Path) -> None:
    main_path = root / MAIN_REL
    if not main_path.exists():
        die(f"Missing: {MAIN_REL}")

    txt = main_path.read_text(encoding="utf-8", errors="ignore")

    if "patch_logging_emit" in txt and "P0-1" in txt:
        info(f"main.py already patched: {MAIN_REL}")
        return

    import_line = "from tbot.runtime._shadow_observability import patch_logging_emit  # P0-1\n"
    call_line = "patch_logging_emit()  # P0-1\n"

    lines = txt.splitlines(True)

    # Insert after import block (first ~300 lines)
    insert_at = 0
    for i, line in enumerate(lines[:300]):
        if re.match(r"^\s*(from|import)\s+", line):
            insert_at = i + 1

    # Avoid duplicate import
    if import_line not in txt:
        lines.insert(insert_at, import_line)
        insert_at += 1

    # Add call right after import (or right after insert position)
    if call_line not in txt:
        lines.insert(insert_at, call_line)

    new_txt = "".join(lines)

    backup_file(root, main_path, backup_dir)
    main_path.write_text(new_txt, encoding="utf-8")
    info(f"Patched: {MAIN_REL}")


def main() -> None:
    root = repo_root_from_cwd()
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_CLEAN_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    ensure_helper(root, backup_dir)
    patch_main_py(root, backup_dir)

    info(f"Done. Backups in: {backup_dir.relative_to(root)}")
    info("Verify after running bot:")
    info(r'  rg -n "shadow_gate=" .\logs\announce.log | Select-Object -First 10')
    info(r'  Test-Path .\logs\shadow_candidates.jsonl')
    info(r'  Get-Content .\logs\shadow_candidates.jsonl -Tail 20')

if __name__ == "__main__":
    main()
