#!/usr/bin/env python3
"""
P0-1 patch (FIXED): Shadow observability + candidates log + gate summary in HEARTBEAT.

- Adds: tbot/runtime/_shadow_observability.py
  - enrich_announce_line(line): appends shadow_gate brief to HEARTBEAT lines
  - mirror_shadow_line(line): mirrors shadow_accept/shadow_reject into logs/shadow_candidates.jsonl (JSONL)

- Patches the python file(s) that write logs/announce.log so that:
  - line = enrich_announce_line(line) before writing/printing
  - mirror_shadow_line(line) after writing/printing
"""

from __future__ import annotations

import datetime as dt
import re
import shutil
import sys
from pathlib import Path
from typing import List, Tuple


MARK = "P0_1_SHADOW_OBSERVABILITY"
HELPER_REL = Path("tbot") / "runtime" / "_shadow_observability.py"


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
    die("Run this from repo root (must contain ./tbot and ./tools).")


def backup_file(root: Path, path: Path, out_dir: Path) -> None:
    rel = path.relative_to(root)
    dest = out_dir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)


def write_helper(root: Path) -> None:
    helper_path = root / HELPER_REL
    if helper_path.exists():
        txt = helper_path.read_text(encoding="utf-8", errors="ignore")
        if MARK in txt:
            info(f"Helper already patched: {HELPER_REL}")
            return

    helper_path.parent.mkdir(parents=True, exist_ok=True)

    # IMPORTANT: do NOT use f-string here. The helper itself contains f-strings.
    helper_code = r'''# P0_1_SHADOW_OBSERVABILITY
from __future__ import annotations

import ast
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any, Dict, Optional

# Optional override:
#   $env:TBOT_SHADOW_CANDIDATES_PATH="C:\path\to\logs\shadow_candidates.jsonl"
_CANDIDATES_PATH = os.getenv("TBOT_SHADOW_CANDIDATES_PATH") or str(Path("logs") / "shadow_candidates.jsonl")

# Cap-summary spam guard (process-local)
_LAST_CAP_SUMMARY_UTC: Optional[dt.datetime] = None

def _now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)

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

    try:
        parts = []
        if accepts is not None and cap is not None:
            rem = max(int(cap) - int(accepts), 0)
            parts += [f"{int(accepts)}/{int(cap)}", f"rem={rem}"]
        if cd is not None:
            parts.append(f"cd={int(cd)}s")
        reset = st.get("next_reset_utc") or st.get("reset_utc") or st.get("reset_at_utc")
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

def enrich_announce_line(line: str) -> str:
    """Append gate brief to HEARTBEAT lines (no format changes otherwise)."""
    try:
        if " | HEARTBEAT " in line and "shadow_gate=" not in line:
            brief = _gate_brief()
            if brief:
                return line.rstrip("\n") + f" shadow_gate={brief}\n"
    except Exception:
        pass
    return line

def mirror_shadow_line(line: str) -> None:
    """Mirror shadow_accept/shadow_reject announce lines into JSONL candidates log."""
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

        if msg == "shadow_reject":
            reasons = payload.get("reasons") or []
            if isinstance(reasons, (list, tuple)) and "daily_plan_cap_reached" in reasons:
                global _LAST_CAP_SUMMARY_UTC
                now = _now_utc()
                if _LAST_CAP_SUMMARY_UTC is None or (now - _LAST_CAP_SUMMARY_UTC).total_seconds() >= 60:
                    _LAST_CAP_SUMMARY_UTC = now
                    brief = _gate_brief()
                    if brief:
                        _append_jsonl(_CANDIDATES_PATH, {
                            "ts": ts,
                            "run_id": run_id,
                            "level": "WARN",
                            "event": "shadow_gate_cap",
                            "note": "daily_plan_cap_reached",
                            "shadow_gate": brief,
                        })
    except Exception:
        return
'''
    helper_path.write_text(helper_code, encoding="utf-8")
    info(f"Wrote helper module: {HELPER_REL}")


def find_logger_candidates(root: Path) -> List[Path]:
    py_files: List[Path] = []
    for p in root.rglob("*.py"):
        s = str(p)
        if any(seg in s for seg in [str(root / ".venv"), str(root / ".git"), str(root / "logs"), str(root / ".backups")]):
            continue
        try:
            txt = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if "announce.log" in txt and (".write(" in txt or "print(" in txt):
            py_files.append(p)
    return py_files


def ensure_import(txt: str) -> Tuple[str, bool]:
    imp = "from tbot.runtime._shadow_observability import enrich_announce_line, mirror_shadow_line  # P0-1"
    if imp in txt:
        return txt, False

    lines = txt.splitlines(True)
    insert_at = 0
    for i, line in enumerate(lines[:300]):
        if line.startswith("import ") or line.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, imp + "\n")
    return "".join(lines), True


def patch_io_calls(txt: str) -> Tuple[str, int]:
    """
    Patches safe patterns only:
      - fh.write(line) or fh.write(line + "\\n")
      - print(line, file=fh) (common)
    """
    lines = txt.splitlines(True)
    patched = 0
    out: List[str] = []

    write_re = re.compile(r'^(?P<indent>\s*)(?P<h>\w+)\.write\((?P<arg>[^)]*)\)\s*(#.*)?$')
    print_re = re.compile(r'^(?P<indent>\s*)print\(\s*line\s*,\s*file\s*=\s*(?P<h>\w+)\s*(?:,\s*end\s*=\s*["\']\\n["\'])?\s*\)\s*(#.*)?$')

    for line in lines:
        m = write_re.match(line)
        if m:
            indent = m.group("indent")
            arg = m.group("arg").strip()
            arg_nospace = arg.replace(" ", "")
            acceptable = (arg == "line") or (arg_nospace in ("line+'\\n'", 'line+"\\n"'))
            if acceptable and not any(MARK in l for l in out[-4:]):
                out.append(f"{indent}# {MARK}\n")
                out.append(f"{indent}line = enrich_announce_line(line)\n")
                out.append(line)
                out.append(f"{indent}mirror_shadow_line(line)\n")
                patched += 1
                continue

        m2 = print_re.match(line)
        if m2:
            indent = m2.group("indent")
            if not any(MARK in l for l in out[-4:]):
                out.append(f"{indent}# {MARK}\n")
                out.append(f"{indent}line = enrich_announce_line(line)\n")
                out.append(line)
                out.append(f"{indent}mirror_shadow_line(line)\n")
                patched += 1
                continue

        out.append(line)

    return "".join(out), patched


def main() -> None:
    root = repo_root_from_cwd()
    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    write_helper(root)

    candidates = find_logger_candidates(root)
    if not candidates:
        die("Could not find a python file that references 'announce.log'. Run: rg -n \"announce\\.log\" -S tbot")

    total_patched = 0
    for f in candidates:
        txt = f.read_text(encoding="utf-8", errors="ignore")
        if MARK in txt:
            info(f"Already patched: {f.relative_to(root)}")
            continue

        new_txt, _ = ensure_import(txt)
        new_txt, patched_calls = patch_io_calls(new_txt)

        if patched_calls == 0:
            info(f"Skip (no safe write(line)/print(line,file=..) patterns): {f.relative_to(root)}")
            continue

        backup_file(root, f, backup_dir)
        f.write_text(new_txt, encoding="utf-8")
        info(f"Patched: {f.relative_to(root)}  (io-calls patched: {patched_calls})")
        total_patched += patched_calls

    if total_patched == 0:
        die("No files were patched. Paste the file that writes logs/announce.log and I'll tailor the patch exactly.")
    info(f"Done. Backups saved under: {backup_dir.relative_to(root)}")
    info('Quick verify: rg -n "P0_1_SHADOW_OBSERVABILITY|shadow_candidates\\.jsonl" -S tbot')
    info("Runtime verify: check logs/announce.log HEARTBEAT includes 'shadow_gate=' and logs/shadow_candidates.jsonl is created.")


if __name__ == "__main__":
    main()
