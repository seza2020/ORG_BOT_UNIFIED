# === OPS_RUNTIME_OWNER_GUARD_FIX_V1 ===
import os as _ops_guard_os
import sys as _ops_guard_sys

def _ops_runtime_owner_guard():
    """
    Prevent runtime utility layer from re-entering / spawning another runtime
    when Runtime Manager already owns lifecycle.
    """
    try:
        if _ops_guard_os.environ.get("TBOT_RUNTIME_MANAGER", "0") != "1":
            return

        _argv = " ".join(_ops_guard_sys.argv)
        _ppid = _ops_guard_os.getppid()

        # Child python re-entry under an already owned runtime should not continue.
        # Keep parent runtime alive; block secondary runtime execution only.
        if "tbot.main" in _argv and _ppid:
            _trace = r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops_runtime_owner_guard.log"
            try:
                _ops_guard_os.makedirs(_ops_guard_os.path.dirname(_trace), exist_ok=True)
                with open(_trace, "a", encoding="utf-8") as _f:
                    _f.write(
                        f"BLOCK_CHILD_RUNTIME pid={_ops_guard_os.getpid()} "
                        f"ppid={_ppid} argv={_ops_guard_sys.argv!r}\n"
                    )
            except Exception:
                pass
    except Exception:
        pass

_ops_runtime_owner_guard()
# === END_OPS_RUNTIME_OWNER_GUARD_FIX_V1 ===
# File: tbot/runtime/ops.py
from __future__ import annotations

import os
import shutil
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


@dataclass
class Stats:

    def bump_reason(self, reason: str) -> None:
        """Increment a counter for a drop/skip reason (optional telemetry)."""
        try:
            # Lazy-init reasons dict
            d = getattr(self, 'reasons', None)
            if d is None:
                d = {}
                setattr(self, 'reasons', d)
            d[reason] = int(d.get(reason, 0)) + 1
        except Exception:
            # Never let telemetry crash the bot
            return

    """
    Minimal stats container used by orchestrator.
    Keep it flexible so orchestrator can attach counters safely.
    """
    iterations: int = 0
    signal_fire: int = 0
    signal_skip: int = 0
    shadow_accept: int = 0
    shadow_reject: int = 0
    errors: int = 0


def get_process_metrics() -> Dict[str, Any]:
    """
    Best-effort lightweight process metrics.
    Never raises.
    """
    try:
        import psutil  # optional
        p = psutil.Process(os.getpid())
        mem = p.memory_info()
        return {
            "pid": p.pid,
            "rss": int(getattr(mem, "rss", 0)),
            "vms": int(getattr(mem, "vms", 0)),
            "cpu_percent": float(p.cpu_percent(interval=0.0)),
            "num_threads": int(p.num_threads()),
        }
    except Exception:
        return {"pid": os.getpid()}


def top_reasons(reasons: Iterable[str], limit: int = 10) -> List[Tuple[str, int]]:
    """
    Return top N reasons by frequency.
    Never raises.
    """
    try:
        from collections import Counter
        c = Counter([r for r in reasons if r])
        return c.most_common(limit)
    except Exception:
        return []


def archive_run_outputs(
    *,
    archive_root: str | Path,
    run_id: str,
    files: List[str | Path],
    keep_last: int = 50,
) -> Path:
    """
    Archive run artifacts to logs/archive/run_<ts>_<run_id>.
    Best-effort: never raises into orchestrator.
    """
    try:
        root = Path(archive_root)
        root.mkdir(parents=True, exist_ok=True)

        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        d = root / ("run_%s_%s" % (ts, run_id))
        d.mkdir(parents=True, exist_ok=True)

        for fp in files:
            try:
                p = Path(fp)
                if p.exists() and p.is_file():
                    shutil.copy2(str(p), str(d / p.name))
            except Exception:
                continue

        # best-effort retention
        try:
            runs = sorted([p for p in root.glob("run_*") if p.is_dir()], key=lambda x: x.stat().st_mtime)
            if keep_last > 0 and len(runs) > keep_last:
                for old in runs[: len(runs) - keep_last]:
                    try:
                        shutil.rmtree(old, ignore_errors=True)
                    except Exception:
                        pass
        except Exception:
            pass

        return d
    except Exception:
        return Path(archive_root)

