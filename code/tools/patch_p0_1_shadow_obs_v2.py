#!/usr/bin/env python3
"""
P0-1 patch (v2): Shadow observability + candidates log + gate summary in HEARTBEAT.

What it does:
1) Writes/updates: tbot/runtime/_shadow_observability.py
   - enrich_announce_line(line): appends "shadow_gate=..." to HEARTBEAT lines
   - mirror_shadow_line(line): mirrors shadow_accept/shadow_reject into logs/shadow_candidates.jsonl
   - obs_write(fh, s): safe writer wrapper (enrich + write + mirror)
   - install_logging_observer(handler): wraps logging handler.format() to enrich+mirror

2) Patches the python file(s) that write logs/announce.log using one of:
   A) with open(...announce.log...) as FH:  -> replaces FH.write(...) / print(...,file=FH) with obs_write(FH,...)
   B) logging.FileHandler(...announce.log...) -> injects install_logging_observer(handler)

Backups are stored under: logs/ops/patches/P0_1_<timestamp>/
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

EXCLUDE_DIR_SEGMENTS = {
    ".git", ".venv", "venv", "logs",
    "backups", ".backups",
    "_quarantine", "_restore_stage", "_restore", "_archive",
}

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

def should_skip(root: Path, p: Path) -> bool:
    try:
        rel = p.relative_to(root)
    except Exception:
        return True
    parts = [x for x in rel.parts]
    for seg in parts:
        if seg in EXCLUDE_DIR_SEGMENTS:
            return True
        # skip mega restore dirs that start with "_" (but allow files like _shadow_observability.py)
        if seg.startswith("_") and seg not in {HELPER_REL.name}:
            return True
    return False

def write_helper(root: Path) -> None:
    helper_path = root / HELPER_REL
    if helper_path.exists():
        txt = helper_path.read_text(encoding="utf-8", errors="ignore")
        if MARK in txt:
            info(f"Helper already present: {HELPER_REL}")
            return

    helper_path.parent.mkdir(parents=True, exist_ok=True)

    helper_code = f'''# {MARK}
from __future__ import annotations

import ast
import datetime as dt
import json
import os
from pathlib import Path
from typing import Any, Dict, Optional

# Optional override:
#   $env:TBOT_SHADOW_CANDIDATES_PATH="C:\\path\\to\\logs\\shadow_candidates.jsonl"
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
            parts += [f"{{int(accepts)}}/{{int(cap)}}", f"rem={{rem}}"]
        if cd is not None:
            parts.append(f"cd={{int(cd)}}s")
        reset = st.get("next_reset_utc") or st.get("reset_utc") or st.get("reset_at_utc")
        if reset:
            parts.append(f"reset={{reset}}")
        return " ".join(parts) if parts else None
    except Exception:
        return None


def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\\n")


def enrich_announce_line(line: str) -> str:
    """Append gate brief to HEARTBEAT lines (no format changes otherwise)."""
    try:
        if " | HEARTBEAT " in line and "shadow_gate=" not in line:
            brief = _gate_brief()
            if brief:
                return line.rstrip("\\n") + f" shadow_gate={{brief}}\\n"
    except Exception:
        pass
    return line


def mirror_shadow_line(line: str) -> None:
    """Mirror shadow_accept/shadow_reject announce lines into JSONL candidates log."""
    try:
        raw = line.rstrip("\\n")
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
        obj = {{
            "ts": ts,
            "run_id": run_id,
            "level": level,
            "event": msg,
            "status": status,
            **payload,
        }}
        _append_jsonl(_CANDIDATES_PATH, obj)

        # Optional: summarize cap reached (max once per 60s)
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


def obs_write(fh, s) -> None:
    """Drop-in replacement for fh.write(...) / print(...,file=fh)."""
    try:
        text = str(s)
    except Exception:
        text = repr(s)

    if not text.endswith("\\n"):
        text += "\\n"

    text = enrich_announce_line(text)

    try:
        fh.write(text)
        try:
            fh.flush()
        except Exception:
            pass
    except Exception:
        # If write fails, we still try to mirror for debugging.
        pass

    mirror_shadow_line(text)


def install_logging_observer(handler) -> None:
    """
    Wrap handler.format(record) so that every formatted announce line is:
      enrich_announce_line -> mirror_shadow_line
    """
    try:
        old_format = handler.format

        def _format(record):
            s = old_format(record)
            if not s.endswith("\\n"):
                s_nl = s + "\\n"
            else:
                s_nl = s
            s_nl = enrich_announce_line(s_nl)
            mirror_shadow_line(s_nl)
            return s_nl.rstrip("\\n")

        handler.format = _format
    except Exception:
        return
'''
    helper_path.write_text(helper_code, encoding="utf-8")
    info(f"Wrote helper module: {HELPER_REL}")


def iter_py_files(root: Path) -> List[Path]:
    out: List[Path] = []
    for p in root.rglob("*.py"):
        if should_skip(root, p):
            continue
        out.append(p)
    return out


def find_candidates(root: Path) -> List[Path]:
    files = iter_py_files(root)
    scored = []
    for p in files:
        try:
            txt = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        if "announce.log" not in txt and "announce_log" not in txt:
            # still allow if it clearly formats announce lines
            if (" | HEARTBEAT " not in txt) and ("shadow_reject" not in txt) and ("shadow_accept" not in txt):
                continue

        score = 0
        score += txt.count("announce.log") * 10
        score += txt.count("FileHandler") * 3
        score += txt.count("with open") * 2
        score += txt.count("shadow_reject") * 2
        score += txt.count(" | HEARTBEAT ") * 2
        scored.append((score, p))

    scored.sort(key=lambda x: x[0], reverse=True)
    return [p for _, p in scored[:30]]  # top N


def ensure_import(txt: str) -> Tuple[str, bool]:
    imp = "from tbot.runtime._shadow_observability import obs_write, install_logging_observer  # P0-1"
    if imp in txt:
        return txt, False

    lines = txt.splitlines(True)
    insert_at = 0
    for i, line in enumerate(lines[:300]):
        if line.startswith("import ") or line.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, imp + "\n")
    return "".join(lines), True


def patch_open_blocks(txt: str) -> Tuple[str, int]:
    """
    Patch:
      with open(...announce.log...) as FH:
          FH.write(EXPR)  -> obs_write(FH, EXPR)
          print(EXPR, file=FH, ...) -> obs_write(FH, EXPR)
    """
    lines = txt.splitlines(True)
    out: List[str] = []
    patched = 0

    with_re = re.compile(r'^(?P<indent>\s*)with\s+open\((?P<args>.*)\)\s+as\s+(?P<fh>\w+)\s*:\s*$')
    write_re_tpl = r'^(?P<indent>\s*){fh}\.write\((?P<arg>.*)\)\s*(?P<comment>#.*)?$'
    print_re_tpl = r'^(?P<indent>\s*)print\((?P<arg>[^,]+)\s*,\s*file\s*=\s*{fh}\b.*\)\s*(?P<comment>#.*)?$'

    i = 0
    while i < len(lines):
        line = lines[i]
        m = with_re.match(line)
        if not m:
            out.append(line)
            i += 1
            continue

        args = m.group("args")
        fh = m.group("fh")
        if "announce.log" not in args.replace("\\\\", "\\"):
            out.append(line)
            i += 1
            continue

        out.append(line)
        base_indent = m.group("indent")
        block_indent_len = None

        i += 1
        # Determine block indent (first non-empty, non-comment line)
        j = i
        while j < len(lines):
            if lines[j].strip() == "" or lines[j].lstrip().startswith("#"):
                j += 1
                continue
            block_indent_len = len(lines[j]) - len(lines[j].lstrip())
            break

        if block_indent_len is None:
            continue

        write_re = re.compile(write_re_tpl.format(fh=re.escape(fh)))
        print_re = re.compile(print_re_tpl.format(fh=re.escape(fh)))

        while i < len(lines):
            cur = lines[i]
            if cur.strip() == "":
                out.append(cur); i += 1; continue

            cur_indent_len = len(cur) - len(cur.lstrip())
            if cur_indent_len < block_indent_len and not cur.startswith(base_indent + " "):
                break  # block ended

            mw = write_re.match(cur)
            if mw:
                indent = mw.group("indent")
                arg = mw.group("arg").strip()
                comment = mw.group("comment") or ""
                out.append(f"{indent}# {MARK}\n")
                out.append(f"{indent}obs_write({fh}, {arg}) {comment}\n")
                patched += 1
                i += 1
                continue

            mp = print_re.match(cur)
            if mp:
                indent = mp.group("indent")
                arg = mp.group("arg").strip()
                comment = mp.group("comment") or ""
                out.append(f"{indent}# {MARK}\n")
                out.append(f"{indent}obs_write({fh}, {arg}) {comment}\n")
                patched += 1
                i += 1
                continue

            out.append(cur)
            i += 1

    return "".join(out), patched


def patch_logging_filehandler(txt: str) -> Tuple[str, int]:
    """
    Patch logging.FileHandler("...announce.log..."):
      handler = logging.FileHandler("...announce.log...")
      install_logging_observer(handler)

    Also supports:
      logger.addHandler(logging.FileHandler("...announce.log..."))
    """
    lines = txt.splitlines(True)
    out: List[str] = []
    patched = 0

    assign_re = re.compile(r'^(?P<indent>\s*)(?P<var>\w+)\s*=\s*(?P<rhs>.*FileHandler\s*\(.*announce\.log.*\).*)$')
    addhandler_inline_re = re.compile(r'^(?P<indent>\s*)(?P<logger>\w+)\.addHandler\((?P<rhs>.*FileHandler\s*\(.*announce\.log.*\).*)\)\s*$')

    for line in lines:
        m1 = assign_re.match(line)
        if m1:
            out.append(line)
            indent = m1.group("indent")
            var = m1.group("var")
            out.append(f"{indent}# {MARK}\n")
            out.append(f"{indent}install_logging_observer({var})\n")
            patched += 1
            continue

        m2 = addhandler_inline_re.match(line)
        if m2:
            indent = m2.group("indent")
            rhs = m2.group("rhs")
            tmp = "_announce_handler_p0_1"
            out.append(f"{indent}{tmp} = {rhs}\n")
            out.append(f"{indent}# {MARK}\n")
            out.append(f"{indent}install_logging_observer({tmp})\n")
            out.append(f"{indent}{m2.group('logger')}.addHandler({tmp})\n")
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

    cands = find_candidates(root)
    if not cands:
        die("No candidate python files found. Run: rg -n \"announce\\.log\" -S tbot")

    total = 0
    for f in cands:
        try:
            txt = f.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if MARK in txt:
            continue

        # We only patch if file likely touches announce.log
        if ("announce.log" not in txt) and ("FileHandler" not in txt) and ("shadow_reject" not in txt) and (" | HEARTBEAT " not in txt):
            continue

        new_txt, _ = ensure_import(txt)

        new_txt2, p_open = patch_open_blocks(new_txt)
        new_txt3, p_log = patch_logging_filehandler(new_txt2)

        p = p_open + p_log
        if p == 0:
            continue

        backup_file(root, f, backup_dir)
        f.write_text(new_txt3, encoding="utf-8")
        info(f"Patched: {f.relative_to(root)}  (edits={p})")
        total += p

    if total == 0:
        die(
            "No edits applied.\n"
            "Next: run these and paste output:\n"
            "  rg -n \"announce\\.log\" -S tbot\n"
            "  rg -n \"FileHandler\\(|with open\\(\" -S tbot\n"
        )

    info(f"DONE. Backups saved under: {backup_dir.relative_to(root)}")
    info("Quick verify (PowerShell):")
    info("  rg -n \"P0_1_SHADOW_OBSERVABILITY|obs_write\\(|install_logging_observer\\(\" -S tbot")
    info("Runtime verify:")
    info("  Get-Content .\\logs\\announce.log -Tail 80 | Select-String -Pattern \"HEARTBEAT|shadow_gate=\"")
    info("  Get-Content .\\logs\\shadow_candidates.jsonl -Tail 20")


if __name__ == "__main__":
    main()
