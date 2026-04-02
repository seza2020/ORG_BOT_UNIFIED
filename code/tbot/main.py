from __future__ import annotations

import argparse
import atexit
import os
import sys
import traceback
from datetime import datetime
import json

BANNER = "ORG_BOT_UNIFIED"

def _bootstrap_trace_path() -> str:
    try:
        rr = os.getenv("TBOT_RUNROOT") or os.path.join(os.getcwd(), "runtime", "paper")
        return os.path.join(rr, "logs", "main_bootstrap_trace.log")
    except Exception:
        return r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\main_bootstrap_trace.log"

def _safe_parent_cmdline_bootstrap() -> str:
    try:
        import psutil
        p = psutil.Process(os.getpid())
        parent = p.parent()
        if parent is None:
            return ""
        return " ".join(parent.cmdline() or [])
    except Exception as e:
        return f"ERR:{type(e).__name__}"

def _safe_mp_bootstrap() -> dict:
    out = {}
    try:
        import multiprocessing as _mp
        cp = _mp.current_process()
        out["mp_name"] = getattr(cp, "name", None)
        out["mp_pid"] = getattr(cp, "pid", None)
        try:
            out["mp_parent_process"] = str(_mp.parent_process())
        except Exception as e2:
            out["mp_parent_process"] = f"ERR:{type(e2).__name__}"
    except Exception as e:
        out["mp_error"] = type(e).__name__
    return out

def _emit_bootstrap_trace(tag: str) -> None:
    try:
        p = {
            "ts": datetime.now().isoformat(timespec="seconds"),
            "tag": tag,
            "pid": os.getpid(),
            "ppid": os.getppid(),
            "__name__": __name__,
            "__file__": __file__,
            "__spec__": (None if __spec__ is None else str(__spec__)),
            "argv": sys.argv,
            "cwd": os.getcwd(),
            "runtime_manager": os.environ.get("TBOT_RUNTIME_MANAGER"),
            "parent_cmd": _safe_parent_cmdline_bootstrap(),
        }
        p.update(_safe_mp_bootstrap())
        tp = _bootstrap_trace_path()
        os.makedirs(os.path.dirname(tp), exist_ok=True)
        with open(tp, "a", encoding="utf-8") as f:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")
    except Exception:
        pass

_emit_bootstrap_trace("TOPLEVEL_IMPORT")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="tbot.main", description=BANNER)
    p.add_argument("--smoke", action="store_true", help="print identity/session info and exit 0")
    p.add_argument("--run", action="store_true", help="run orchestrator loop")
    p.add_argument("--iters", type=int, default=999999, help="max iterations")
    p.add_argument("--sleep", type=float, default=0.5, help="sleep seconds")
    return p


def _runroot() -> str:
    return os.getenv("TBOT_RUNROOT") or os.path.join(os.getcwd(), "runtime", "paper")


def _lock_path() -> str:
    return os.path.join(_runroot(), "locks", "tbot_main.lock")


def _pid_is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        if os.name == "nt":
            import ctypes
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            handle = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, int(pid))
            if handle:
                ctypes.windll.kernel32.CloseHandle(handle)
                return True
            return False
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def _parent_is_tbot_run() -> bool:
    """
    Evidence-based child re-entry guard.
    If this process was spawned by another python process already running
    tbot.main --run, block the child before lock acquisition.
    """
    try:
        import psutil  # already used elsewhere in project runtime
        p = psutil.Process(os.getpid())
        parent = p.parent()
        if parent is None:
            return False
        cmd = " ".join(parent.cmdline() or [])
        cmd_l = str(cmd).lower()
        return ("python" in cmd_l) and ("tbot.main" in cmd_l) and ("--run" in cmd_l)
    except Exception:
        return False


def _trace_path() -> str:
    return os.path.join(_runroot(), "logs", "main_start_trace.log")


def _append_start_trace(tag: str, extra: str = "") -> None:
    try:
        tp = _trace_path()
        os.makedirs(os.path.dirname(tp), exist_ok=True)
        with open(tp, "a", encoding="utf-8") as f:
            f.write(
                f"{datetime.now().isoformat(timespec='seconds')} "
                f"tag={tag} pid={os.getpid()} ppid={os.getppid()} "
                f"argv={sys.argv!r} "
                f"runtime_manager={os.environ.get('TBOT_RUNTIME_MANAGER')} "
                f"{extra}\n"
            )
    except Exception:
        pass


def _parent_cmdline() -> str:
    try:
        import psutil
        p = psutil.Process(os.getpid())
        parent = p.parent()
        if parent is None:
            return ""
        return " ".join(parent.cmdline() or [])
    except Exception:
        return ""


def _parent_is_tbot_run() -> bool:
    try:
        cmd = _parent_cmdline()
        cmd_l = str(cmd).lower()
        return ("python" in cmd_l) and ("tbot.main" in cmd_l) and ("--run" in cmd_l)
    except Exception:
        return False


def acquire_single_instance_or_exit() -> str:
    lp = _lock_path()
    os.makedirs(os.path.dirname(lp), exist_ok=True)

    existing_pid = None
    if os.path.exists(lp):
        try:
            txt = open(lp, "r", encoding="utf-8").read().strip()
            existing_pid = int(txt) if txt else None
        except Exception:
            existing_pid = None

        if existing_pid and _pid_is_alive(existing_pid):
            print("TBOT_SINGLE_INSTANCE_BLOCK", existing_pid, flush=True)
            raise SystemExit(0)

        try:
            os.remove(lp)
        except Exception:
            pass

    with open(lp, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))

    def _cleanup() -> None:
        try:
            if os.path.exists(lp):
                txt = open(lp, "r", encoding="utf-8").read().strip()
                if txt == str(os.getpid()):
                    os.remove(lp)
        except Exception:
            pass

    atexit.register(_cleanup)
    return lp


def smoke() -> int:
    print("TBOT_SMOKE_OK")
    print("CWD=", os.getcwd())
    print("PYTHONPATH=", os.environ.get("PYTHONPATH"))
    print("TBOT_RUNROOT=", os.environ.get("TBOT_RUNROOT"))
    print("TBOT_RUNTIME_MANAGER=", os.environ.get("TBOT_RUNTIME_MANAGER"))
    print("SYS_EXEC=", sys.executable)
    print("LOCK_PATH=", _lock_path())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.smoke:
        return smoke()

    if not args.run:
        parser.print_help()
        return 0

    _append_start_trace("MAIN_ENTER", f"parent_cmd={_parent_cmdline()!r}")

    if _parent_is_tbot_run():
        _append_start_trace("CHILD_BLOCK", f"parent_cmd={_parent_cmdline()!r}")
        print("TBOT_CHILD_REENTRY_BLOCK", os.getpid(), flush=True)
        return 0

    acquire_single_instance_or_exit()
    _append_start_trace("LOCK_ACQUIRED", f"lock_path={_lock_path()!r}")

    os.environ["TBOT_RUNTIME_MANAGER"] = "1"
    _append_start_trace("RUNTIME_MANAGER_SET", "")

    from tbot.runtime.orchestrator import run_loop

    print("TBOT_MAIN_SINGLE_RUN_MODE", flush=True)

    rc = run_loop(args)
    if rc in (None, 0):
        return 0
    return int(rc)


if __name__ == "__main__":
    try:
        rc = main()
        raise SystemExit(rc)
    except SystemExit:
        raise
    except Exception:
        print("TBOT_FATAL_EXCEPTION", flush=True)
        traceback.print_exc()
        raise SystemExit(1)




