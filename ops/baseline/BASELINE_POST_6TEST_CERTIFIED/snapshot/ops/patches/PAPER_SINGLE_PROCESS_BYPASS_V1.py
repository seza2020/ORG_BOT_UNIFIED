import json
import multiprocessing
import os
import subprocess
import sys
import time
import traceback
from datetime import datetime

RUNROOT = os.environ.get("TBOT_RUNROOT", r"C:\alpaca-bot\ORG_BOT_UNIFIED")
LOG_PATH = os.path.join(RUNROOT, "runtime", "paper", "logs", "paper_single_process_bypass_v1.jsonl")

def _log(kind, payload=None):
    row = {
        "ts": datetime.utcnow().isoformat() + "Z",
        "kind": kind,
        "pid": os.getpid(),
        "ppid": os.getppid(),
        "argv": sys.argv,
        "payload": payload or {},
    }
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False, default=str) + "\n")
    except Exception:
        pass

def _looks_like_tbot_run_invocation(obj) -> bool:
    try:
        s = " ".join(obj) if isinstance(obj, (list, tuple)) else str(obj)
    except Exception:
        s = str(obj)
    s = s.lower()
    return ("tbot.main" in s) and ("--run" in s)

def _install_spawn_blockers():
    try:
        _orig_popen = subprocess.Popen

        class _BlockedPopen(_orig_popen):
            def __init__(self, *args, **kwargs):
                probe = ""
                if args:
                    probe = str(args[0])
                if _looks_like_tbot_run_invocation(probe):
                    _log("blocked_subprocess_popen", {"args": args, "kwargs": kwargs})
                    raise RuntimeError("BLOCKED_REENTRY_SUBPROCESS_POPEN")
                _log("subprocess_popen_passthrough", {"args": args, "kwargs": kwargs})
                super().__init__(*args, **kwargs)

        subprocess.Popen = _BlockedPopen
    except Exception as e:
        _log("spawn_blocker_patch_error", {"target": "subprocess.Popen", "error": repr(e)})

    try:
        _orig_run = subprocess.run
        def _blocked_run(*args, **kwargs):
            probe = ""
            if args:
                probe = str(args[0])
            if _looks_like_tbot_run_invocation(probe):
                _log("blocked_subprocess_run", {"args": args, "kwargs": kwargs})
                raise RuntimeError("BLOCKED_REENTRY_SUBPROCESS_RUN")
            return _orig_run(*args, **kwargs)
        subprocess.run = _blocked_run
    except Exception as e:
        _log("spawn_blocker_patch_error", {"target": "subprocess.run", "error": repr(e)})

    try:
        _orig_os_system = os.system
        def _blocked_os_system(cmd):
            if _looks_like_tbot_run_invocation(cmd):
                _log("blocked_os_system", {"cmd": cmd})
                raise RuntimeError("BLOCKED_REENTRY_OS_SYSTEM")
            return _orig_os_system(cmd)
        os.system = _blocked_os_system
    except Exception as e:
        _log("spawn_blocker_patch_error", {"target": "os.system", "error": repr(e)})

    def _patch_spawn_name(name: str):
        if not hasattr(os, name):
            return
        try:
            _orig = getattr(os, name)
            def _blocked_spawn(*args, **kwargs):
                probe = str(args)
                if _looks_like_tbot_run_invocation(probe):
                    _log("blocked_" + name, {"args": args, "kwargs": kwargs})
                    raise RuntimeError("BLOCKED_REENTRY_" + name.upper())
                return _orig(*args, **kwargs)
            setattr(os, name, _blocked_spawn)
        except Exception as e:
            _log("spawn_blocker_patch_error", {"target": "os." + name, "error": repr(e)})

    for nm in ["spawnv","spawnve","spawnvp","spawnvpe","spawnl","spawnle","spawnlp","spawnlpe"]:
        _patch_spawn_name(nm)

    try:
        _orig_mp_start = multiprocessing.process.BaseProcess.start
        def _blocked_mp_start(self, *args, **kwargs):
            _log("blocked_multiprocessing_start", {
                "process_class": self.__class__.__name__,
                "name": getattr(self, "name", None),
                "args": args,
                "kwargs": kwargs,
            })
            raise RuntimeError("BLOCKED_REENTRY_MULTIPROCESSING_START")
        multiprocessing.process.BaseProcess.start = _blocked_mp_start
    except Exception as e:
        _log("spawn_blocker_patch_error", {"target": "multiprocessing.process.BaseProcess.start", "error": repr(e)})

def _build_args_from_main_module(main_mod):
    # candidate parsers in descending priority
    if hasattr(main_mod, "parse_args") and callable(main_mod.parse_args):
        try:
            return main_mod.parse_args(["--run"])
        except TypeError:
            try:
                return main_mod.parse_args()
            except Exception:
                pass
        except Exception:
            pass

    for name in ["build_parser", "make_parser", "get_parser", "create_parser"]:
        fn = getattr(main_mod, name, None)
        if callable(fn):
            try:
                parser = fn()
                try:
                    return parser.parse_args(["--run"])
                except Exception:
                    return parser.parse_args([])
            except Exception:
                pass

    class _Args:
        pass

    args = _Args()
    setattr(args, "run", True)
    return args

def _normalize_args(args):
    # conservative normalization only if attribute exists
    for attr, value in [
        ("run", True),
        ("daemon", False),
        ("background", False),
        ("detach", False),
        ("spawn", False),
        ("fork", False),
        ("manager", False),
    ]:
        if hasattr(args, attr):
            try:
                setattr(args, attr, value)
            except Exception:
                pass
    return args

def main():
    try:
        os.environ["TBOT_RUNTIME_MANAGER"] = "1"
        os.environ["TBOT_SINGLE_PROCESS_BYPASS"] = "1"
        _install_spawn_blockers()
        _log("bypass_launcher_start", {})

        import tbot.main as main_mod
        from tbot.runtime.orchestrator import run_loop

        args = _build_args_from_main_module(main_mod)
        args = _normalize_args(args)

        _log("bypass_args_ready", {"args_repr": repr(args), "args_type": str(type(args))})

        while True:
            _log("before_run_loop", {})
            run_loop(args)
            _log("after_run_loop", {})
            time.sleep(0.25)

    except KeyboardInterrupt:
        _log("bypass_keyboard_interrupt", {})
        raise
    except SystemExit as e:
        _log("bypass_system_exit", {"code": getattr(e, "code", None)})
        raise
    except Exception as e:
        _log("bypass_exception", {"error": repr(e), "traceback": traceback.format_exc()})
        raise

if __name__ == "__main__":
    main()
