from __future__ import annotations

import hashlib
import json
import os
import sys
import time

_EXIT_CODE = 86
_ENTERED = False

def _e(msg: str) -> None:
    try:
        sys.stderr.write(msg.rstrip() + "\n")
    except Exception:
        pass

def _sha1(s: str) -> str:
    return hashlib.sha1(s.encode("utf-8", errors="ignore")).hexdigest()

def _runroot() -> str | None:
    rr = os.environ.get("TBOT_RUNROOT") or os.environ.get("tbot_runroot")
    if rr and isinstance(rr, str) and rr.strip():
        return rr.strip()
    return None

def _profile_guess(runroot: str | None) -> str:
    p = (os.environ.get("TBOT_PROFILE") or os.environ.get("tbot_profile") or "").strip().upper()
    if p in ("PAPER","SHADOW"):
        return p
    rr = (runroot or "").lower()
    if "\\runtime\\shadow" in rr or rr.endswith("\\shadow"):
        return "SHADOW"
    return "PAPER"

def _lock_dir(runroot: str) -> str:
    return os.path.join(runroot, "state", "locks")

def _lock_path(runroot: str, profile: str) -> str:
    return os.path.join(_lock_dir(runroot), f"TBOT_SINGLE_INSTANCE_{profile}.lock")

def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

def _read_lock(path: str) -> dict | None:
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read().strip()
        if not raw:
            return None
        if raw.isdigit():
            return {"pid": int(raw)}
        return json.loads(raw)
    except Exception:
        return None

def _remove(path: str) -> None:
    try:
        os.remove(path)
    except Exception:
        pass

def _atomic_create(path: str) -> int:
    return os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)

def _mutex_name(runroot: str, profile: str) -> str:
    key = f"{profile}|{os.path.abspath(runroot)}"
    return "Local\\TBOT_ORG_UNIFIED_" + profile + "_" + _sha1(key)[:16]

def _acquire_mutex(name: str) -> bool:
    """
    Windows named mutex best-effort. On non-Windows, return True.
    """
    if os.name != "nt":
        return True
    try:
        import ctypes
        from ctypes import wintypes
        CreateMutexW = ctypes.windll.kernel32.CreateMutexW
        GetLastError = ctypes.windll.kernel32.GetLastError

        CreateMutexW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.LPCWSTR]
        CreateMutexW.restype = wintypes.HANDLE

        h = CreateMutexW(None, False, name)
        if not h:
            _e(f"[SINGLE_INSTANCE] MUTEX_CREATE_FAILED name={name} err={GetLastError()}")
            return True  # fail-open (file lock still protects)
        err = GetLastError()
        # ERROR_ALREADY_EXISTS = 183
        if err == 183:
            _e(f"[SINGLE_INSTANCE] MUTEX_EXISTS name={name} -> exit {_EXIT_CODE}")
            raise SystemExit(_EXIT_CODE)
        _e(f"[SINGLE_INSTANCE] MUTEX_ACQUIRED name={name}")
        return True
    except SystemExit:
        raise
    except Exception as e:
        _e(f"[SINGLE_INSTANCE] MUTEX_EXCEPTION name={name} err={repr(e)} -> continue")
        return True

def _pid_exe_path(pid: int):
    if os.name != "nt":
        return None
    try:
        import ctypes
        from ctypes import wintypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        OpenProcess = kernel32.OpenProcess
        OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        OpenProcess.restype = wintypes.HANDLE

        QueryFullProcessImageNameW = kernel32.QueryFullProcessImageNameW
        QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
        QueryFullProcessImageNameW.restype = wintypes.BOOL

        CloseHandle = kernel32.CloseHandle
        CloseHandle.argtypes = [wintypes.HANDLE]
        CloseHandle.restype = wintypes.BOOL

        h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, int(pid))
        if not h:
            return None
        try:
            size = wintypes.DWORD(32768)
            buf = ctypes.create_unicode_buffer(size.value)
            if not QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)):
                return None
            return buf.value
        finally:
            CloseHandle(h)
    except BaseException:
        return None


def _pid_owner_state(pid: int):
    exe_path = _pid_exe_path(pid)
    if not exe_path:
        return "UNKNOWN"
    try:
        lhs = os.path.normcase(os.path.normpath(exe_path))
        rhs = os.path.normcase(os.path.normpath(sys.executable))
        if lhs == rhs:
            return "MATCH"
        return "FOREIGN"
    except BaseException:
        return "UNKNOWN"

def enforce_single_instance(profile: str | None = None, runroot: str | None = None) -> None:
    global _ENTERED
    if _ENTERED:
        return
    _ENTERED = True

    rr = runroot or _runroot()
    if not rr:
        _e("[SINGLE_INSTANCE] TBOT_RUNROOT missing -> ABORT (fail-closed)")
        return

    prof = (profile or _profile_guess(rr)).strip().upper()
    if prof not in ("PAPER","SHADOW"):
        prof = "PAPER"

    os.makedirs(_lock_dir(rr), exist_ok=True)

    # Mutex first (fast fail)
    mname = _mutex_name(rr, prof)
    _acquire_mutex(mname)

    # File lock (authoritative)
    lp = _lock_path(rr, prof)
    try:
        fd = _atomic_create(lp)
    except FileExistsError:
        info = _read_lock(lp) or {}
        pid = info.get("pid")
        if isinstance(pid, int) and pid > 0 and _pid_alive(pid):
            owner_pid = int(pid)
            owner_state = _pid_owner_state(owner_pid)
            if owner_state == "MATCH":
                _e(f"TBOT_SINGLE_INSTANCE_BLOCK {owner_pid}")
                _e(f"[SINGLE_INSTANCE] FILE_LOCK_EXISTS path={lp} owner_pid={owner_pid} authoritative=true owner_state={owner_state} -> exit {_EXIT_CODE}")
                raise SystemExit(_EXIT_CODE)
            if owner_state == "FOREIGN":
                _e(f"[SINGLE_INSTANCE] FILE_LOCK_FOREIGN_OWNER_RECLAIM path={lp} owner_pid={owner_pid} authoritative=true owner_state={owner_state}")
            else:
                _e(f"[SINGLE_INSTANCE] FILE_LOCK_OWNER_UNRESOLVED path={lp} owner_pid={owner_pid} authoritative=true owner_state={owner_state} -> exit {_EXIT_CODE}")
                raise SystemExit(_EXIT_CODE)
        _e(f"[SINGLE_INSTANCE] FILE_LOCK_STALE path={lp} owner={json.dumps(info, ensure_ascii=False)} -> removing")
        _remove(lp)
        try:
            fd = _atomic_create(lp)
        except Exception:
            _e(f"[SINGLE_INSTANCE] FILE_LOCK_RETRY_FAILED path={lp} -> exit {_EXIT_CODE}")
            raise SystemExit(_EXIT_CODE)
    except SystemExit:
        raise
    except Exception as e:
        _e(f"[SINGLE_INSTANCE] FILE_LOCK_CREATE_FAILED path={lp} err={repr(e)} -> fail-open")
        return

    try:
        payload = {"pid": os.getpid(), "ppid": os.getppid(), "ts": time.time(), "argv": sys.argv, "profile": prof, "runroot": os.path.abspath(rr)}
        os.write(fd, json.dumps(payload).encode("utf-8"))
        _e(f"[SINGLE_INSTANCE] FILE_LOCK_ACQUIRED path={lp}")
    finally:
        try:
            os.close(fd)
        except Exception:
            pass

    # Cleanup on exit if still owner
    try:
        import atexit
        mypid = os.getpid()
        def _cleanup() -> None:
            try:
                info2 = _read_lock(lp) or {}
                if info2.get("pid") == mypid:
                    _remove(lp)
                    _e(f"[SINGLE_INSTANCE] FILE_LOCK_RELEASED path={lp}")
            except Exception:
                pass
        atexit.register(_cleanup)
    except Exception:
        pass

