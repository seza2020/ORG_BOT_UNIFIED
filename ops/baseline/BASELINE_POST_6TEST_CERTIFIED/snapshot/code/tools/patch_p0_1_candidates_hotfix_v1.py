from __future__ import annotations

import datetime as dt
import shutil
from pathlib import Path

MARK = "P0_1_CANDIDATES_HOTFIX_V1"

def die(msg: str):
    raise SystemExit("[P0-1-HOTFIX] " + msg)

def repo_root() -> Path:
    p = Path.cwd().resolve()
    if (p / "tbot").is_dir():
        return p
    for parent in [p] + list(p.parents):
        if (parent / "tbot").is_dir():
            return parent
    die("Run from repo root (must contain ./tbot).")

def main() -> None:
    root = repo_root()
    helper = root / "tbot" / "runtime" / "_shadow_observability.py"
    if not helper.exists():
        die(f"Missing helper: {helper}")

    txt = helper.read_text(encoding="utf-8", errors="ignore")
    if MARK in txt:
        print("[P0-1-HOTFIX] Already applied.")
        return

    ts = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = root / "logs" / "ops" / "patches" / f"P0_1_HOTFIX_{ts}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(helper, backup_dir / "_shadow_observability.py")
    print(f"[P0-1-HOTFIX] Backup: {backup_dir}")

    hotfix = f"""

# {MARK}
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
            f.write(f"{{_dt.datetime.now(_dt.timezone.utc).isoformat()}} | {{note}}\\n")
    except Exception:
        pass

def _sanitize_candidates_path(p: str) -> str:
    try:
        return str(p).strip().strip('\"').strip(\"'\")
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
            f.write(_json.dumps(obj, ensure_ascii=False) + "\\n")
        return True
    except Exception as e:
        _obs_err(f"WRITE_FAIL path={{path!r}} err={{e!r}}")
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
    obj = {{
        "ts": "SELFTEST",
        "run_id": "SELFTEST",
        "level": "INFO",
        "event": "selftest_shadow_candidates",
        "ok": True,
    }}
    ok = _append_jsonl_safe(_CANDIDATES_PATH, obj)
    return _CANDIDATES_PATH if ok else ""
"""

    helper.write_text(txt + hotfix, encoding="utf-8")
    print("[P0-1-HOTFIX] Applied. Now run selftest.")

if __name__ == "__main__":
    main()
