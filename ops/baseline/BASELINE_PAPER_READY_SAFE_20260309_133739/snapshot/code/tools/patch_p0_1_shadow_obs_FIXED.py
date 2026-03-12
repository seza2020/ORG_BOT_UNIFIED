#!/usr/bin/env python3
"""
P0-1 FIXED (robust):
- Upgrades: tbot/runtime/_shadow_observability.py (absolute/rooted paths)
- Ensures:  tbot/main.py calls patch_logging_emit() early (idempotent)
- Writes marker: logs/ops/p0_1_emit_patch.txt when patch installs and when it first intercepts announce.log

Outcome:
- HEARTBEAT line gets: shadow_gate=...
- shadow_accept/shadow_reject mirrored to: <repo_root>/logs/shadow_candidates.jsonl
"""

from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path


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


def write_helper(root: Path, backup_dir: Path) -> None:
    helper_path = root / HELPER_REL
    helper_path.parent.mkdir(parents=True, exist_ok=True)

    existing = ""
    if helper_path.exists():
        existing = helper_path.read_text(encoding="utf-8", errors="ignore")

    # If already has required functions, keep it.
    required = ["def enrich_announce_text", "def mirror_shadow_text", "def patch_logging_emit"]
    if existing and (MARK in existing) and all(k in existing for k in required) and "p0_1_emit_patch.txt" in existing:
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

# Repo root resolution:
# 1) Prefer deriving from announce.log handler baseFilename (most reliable).
# 2) Fallback: derive from this file location: <root>/tbot/runtime/_shadow_observability.py
_ROOT: Optional[Path] = None

def _fallback_root() -> Path:
    try:
        return Path(__file__).resolve().parents[2]
    except Exception:
        return Path.cwd().resolve()

def _root() -> Path:
    return _ROOT or _fallback_root()

def _set_root_from_announce_path(base_filename: str) -> None:
    global _ROOT
    try:
        p = Path(base_filename).resolve()
        # .../<root>/logs/announce.log  -> root = parent of logs
        if p.name.lower() == "announce.log" and p.parent.name.lower() == "logs":
            _ROOT = p.parent.parent
    except Exception:
        return

def _logs_dir() -> Path:
    return _root() / "logs"

def _ops_dir() -> Path:
    return _logs_dir() / "ops"

def _marker_path() -> Path:
    return _ops_dir() / "p0_1_emit_patch.txt"

def _write_marker(msg: str) -> None:
    try:
        p = _marker_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        ts = dt.datetime.now(dt.timezone.utc).isoformat()
        with p.open("a", encoding="utf-8") as f:
            f.write(f"{ts} | {msg}\n")
    except Exception:
        return

def _candidates_path() -> Path:
    # Optional override:
    #   $env:TBOT_SHADOW_CANDIDATES_PATH="C:\path\to\shadow_candidates.jsonl"
    raw = os.getenv("TBOT_SHADOW_CANDIDATES_PATH")
    if raw:
        p = Path(raw)
        return p if p.is_absolute() else (_root() / p)
    return _logs_dir() / "shadow_candidates.jsonl"

def _read_latest_gate_state() -> Optional[Dict[str, Any]]:
    ops = _ops_dir()
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

def _append_jsonl(path: Path, obj: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")

def enrich_announce_text(text: str) -> str:
    """
    Enrich formatted text. Handles multi-line messages.
    Appends shadow_gate=... to the line that contains ' | HEARTBEAT'.
    """
    try:
        if " | HEARTBEAT" not in text or "shadow_gate=" in text:
            return text
        brief = _gate_brief()
        if not brief:
            return text
        lines = text.splitlines(True)
        for i, ln in enumerate(lines):
            if " | HEARTBEAT" in ln and "shadow_gate=" not in ln:
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
        _append_jsonl(_candidates_path(), obj)
    except Exception:
        return

def mirror_shadow_text(text: str) -> None:
    try:
        for ln in text.splitlines():
            mirror_shadow_line(ln + "\n")
    except Exception:
        return

def patch_logging_emit() -> None:
    """
    Monkeypatch StreamHandler.emit globally, but only intercept handlers
    whose baseFilename points to .../logs/announce.log
    """
    try:
        if getattr(logging, "_P0_1_PATCHED", False):
            return

        old_emit = logging.StreamHandler.emit

        def _emit(self, record):
            # Use handler lock for safety (like standard emit)
            try:
                self.acquire()
            except Exception:
                pass

            try:
                base = getattr(self, "baseFilename", None)
                if isinstance(base, str):
                    # Root from handler path (most reliable)
                    _set_root_from_announce_path(base)

                if isinstance(base, str):
                    try:
                        p = Path(base)
                        is_announce = (p.name.lower() == "announce.log") and (p.parent.name.lower() == "logs")
                    except Exception:
                        is_announce = False

                    if is_announce:
                        msg = self.format(record)
                        if not msg.endswith("\n"):
                            msg += "\n"

                        msg2 = enrich_announce_text(msg)
                        mirror_shadow_text(msg2)

                        stream = getattr(self, "stream", None)
                        if stream is None:
                            try:
                                stream = self._open()  # FileHandler
                                self.stream = stream
                            except Exception:
                                stream = None

                        if stream is not None:
                            stream.write(msg2)
                            try:
                                self.flush()
                            except Exception:
                                pass

                            # Marker on first successful intercept
                            if not getattr(logging, "_P0_1_INTERCEPTED", False):
                                logging._P0_1_INTERCEPTED = True
                                _write_marker(f"INTERCEPT_OK root={_root()} candidates={_candidates_path()}")
                            return

            except Exception:
                pass
            finally:
                try:
                    self.release()
                except Exception:
                    pass

            return old_emit(self, record)

        logging.StreamHandler.emit = _emit
        logging._P0_1_PATCHED = True
        _write_marker("PATCH_INSTALLED")
    except Exception:
        return
'''

    if helper_path.exists():
        backup_file(root, helper_path, backup_dir)

    helper_path.write_text(helper_code, encoding="utf-8")
    info(f"Wrote/Upgraded helper: {HELPER_REL}")


def patch_main(root: Path, backup_dir: Path) -> None:
    p = root / MAIN_REL
    if not p.exists():
        die(f"Missing: {MAIN_REL}")

    txt = p.read_text(encoding="utf-8", errors="ignore")

    imp = "from tbot.runtime._shadow_observability import patch_logging_emit  # P0-1\n"
    call = "patch_logging_emit()  # P0-1\n"

    if "patch_logging_emit()  # P0-1" in txt:
        info(f"main.py already calls patch_logging_emit: {MAIN_REL}")
        return

    lines = txt.splitlines(True)

    insert_at = 0
    for i, line in enumerate(lines[:300]):
        if re.match(r"^\s*(from|import)\s+", line):
            insert_at = i + 1

    if imp not in txt:
        lines.insert(insert_at, imp)
        insert_at += 1

    lines.insert(insert_at, call)

    backup_file(root, p, backup_dir)
    p.write_text("".join(lines), encoding="utf-8")
    info(f"Patched: {MAIN_REL}")


def main() -> None:
    root = repo_root_from_cwd()
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_FIXED_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    write_helper(root, backup_dir)
    patch_main(root, backup_dir)

    info(f"Done. Backups in: {backup_dir.relative_to(root)}")
    info("Next steps:")
    info("  1) Restart bot processes (very important).")
    info("  2) Check marker:  Get-Content .\\logs\\ops\\p0_1_emit_patch.txt -Tail 20")
    info("  3) Check candidates: Test-Path .\\logs\\shadow_candidates.jsonl")
    info("  4) Check heartbeat: rg -n \"shadow_gate=\" .\\logs\\announce.log | Select-Object -First 20")

if __name__ == "__main__":
    main()
