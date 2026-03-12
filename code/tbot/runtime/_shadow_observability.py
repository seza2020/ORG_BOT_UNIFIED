# P0_1_SHADOW_OBSERVABILITY
from __future__ import annotations

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

# P0_1_2_GATE_BRIEF_AUTODETECT
# P0_1_3_SHADOW_OBS_HEARTBEAT_AND_GATE
def _gate_brief() -> Optional[str]:
    """Robust brief for gate_state_*.json (supports your persistent-cap-v1 schema)."""
    st = _read_latest_gate_state()
    if not st or not isinstance(st, dict):
        return None

    def _to_int(v):
        try:
            if isinstance(v, bool):
                return None
            if isinstance(v, (int, float)):
                return int(v)
            if isinstance(v, str):
                s = v.strip()
                if s.isdigit() or (s.startswith('-') and s[1:].isdigit()):
                    return int(s)
        except Exception:
            return None
        return None

    # Prefer true counters in your schema
    valid = _to_int(st.get('valid_accepts'))
    acc = _to_int(st.get('shadow_accept'))
    plans = _to_int(st.get('shadow_plan'))
    rej = _to_int(st.get('shadow_reject'))
    boot = _to_int(st.get('boot'))

    # risk in USD (float ok)
    risk = st.get('accepted_risk_usd')
    try:
        if isinstance(risk, str):
            risk = float(risk.strip())
        elif isinstance(risk, (int, float)):
            risk = float(risk)
        else:
            risk = None
    except Exception:
        risk = None

    parts = []
    if plans is not None:
        parts.append(f'plans={plans}')
    if valid is not None:
        parts.append(f'valid={valid}')
    elif acc is not None:
        parts.append(f'accepts={acc}')
    if rej is not None:
        parts.append(f'rej={rej}')
    if risk is not None:
        parts.append('risk_usd=' + str(int(round(risk))))
    if boot is not None:
        parts.append(f'boot={boot}')

    # If cap/cooldown ever get added later, include them too
    cd = _to_int(st.get('cooldown_sec') or st.get('gate_cooldown_sec'))
    if cd is not None:
        parts.append(f'cd={cd}s')
    cap = _to_int(st.get('max_plans_per_day') or st.get('daily_cap') or st.get('cap') or st.get('effective_cap'))
    if cap is not None:
        parts.append(f'cap={cap}')

    return ' '.join(parts) if parts else 'gate_state=present'

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


# P0_1_CANDIDATES_HOTFIX_V1
# Makes shadow_candidates.jsonl write failures observable (no more silent swallow)

import os as _os
import json as _json
import traceback as _traceback
from pathlib import Path as _Path
import datetime as _dt

_ERR_PATH = _Path("logs") / "ops" / "shadow_observability_errors.log"

def _obs_err(note: str) -> None:
    try:
        _ERR_PATH.parent.mkdir(parents=True, exist_ok=True)
        with _ERR_PATH.open("a", encoding="utf-8") as f:
            f.write(f"{_dt.datetime.now(_dt.timezone.utc).isoformat()} | {note}\n")
    except Exception:
        pass

def _sanitize_candidates_path(p: str) -> str:
    try:
        return str(p).strip().strip('"').strip("'")
    except Exception:
        return str(_Path("logs") / "shadow_candidates.jsonl")

try:
    _CANDIDATES_PATH = _sanitize_candidates_path(_CANDIDATES_PATH)  # type: ignore
except Exception:
    _CANDIDATES_PATH = _sanitize_candidates_path(
        _os.getenv("TBOT_SHADOW_CANDIDATES_PATH") or str(_Path("logs") / "shadow_candidates.jsonl")
    )

def get_candidates_path() -> str:
    return _CANDIDATES_PATH

def _append_jsonl_safe(path: str, obj: dict) -> bool:
    try:
        p = _Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("a", encoding="utf-8") as f:
            f.write(_json.dumps(obj, ensure_ascii=False) + "\n")
        return True
    except Exception as e:
        _obs_err(f"WRITE_FAIL path={path!r} err={e!r}")
        _obs_err(_traceback.format_exc().rstrip())
        if _os.getenv("TBOT_SHADOW_OBS_DEBUG") == "1":
            raise
        return False

# If module already had _append_jsonl(), override it so existing mirror calls become safe+observable
try:
    _append_jsonl  # type: ignore
    _append_jsonl = _append_jsonl_safe  # type: ignore
except Exception:
    pass

def selftest_shadow_candidates() -> str:
    obj = {
        "ts": "SELFTEST",
        "run_id": "SELFTEST",
        "level": "INFO",
        "event": "selftest_shadow_candidates",
        "ok": True,
    }
    ok = _append_jsonl_safe(_CANDIDATES_PATH, obj)
    return _CANDIDATES_PATH if ok else ""

# P0_1_3_SHADOW_OBS_HEARTBEAT_AND_GATE
def enrich_announce_line(text: str) -> str:
    """Append shadow_gate=<brief> to HEARTBEAT first line (supports multiline)."""
    try:
        if ' | HEARTBEAT' not in text:
            return text
        if 'shadow_gate=' in text:
            return text
        brief = _gate_brief()
        if not brief:
            return text
        # Preserve multiline format: add to the first line only
        if '\n' in text:
            first, rest = text.split('\n', 1)
            return first.rstrip('\r') + f' shadow_gate={brief}' + '\n' + rest
        return text.rstrip('\n').rstrip('\r') + f' shadow_gate={brief}\n'
    except Exception:
        return text

