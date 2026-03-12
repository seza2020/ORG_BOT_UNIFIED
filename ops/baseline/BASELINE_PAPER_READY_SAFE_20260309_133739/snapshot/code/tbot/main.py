from __future__ import annotations

import argparse
import atexit
import os
import sys
import traceback

BANNER = "ORG_BOT_UNIFIED"

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

    acquire_single_instance_or_exit()

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
