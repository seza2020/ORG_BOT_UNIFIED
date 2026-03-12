# === MUTEX_NAME_SANITIZE_V1 BEGIN ===
def _tbot_sanitize_mutex_name(name: str) -> str:
    try:
        import re
        if not isinstance(name, str):
            name = str(name)
        # Allow only safe Win32 mutex chars; replace others with '_'
        name = re.sub(r"[^A-Za-z0-9_\-:\\]", "_", name)
        # Trim to a reasonable length
        return name[:240] if len(name) > 240 else name
    except Exception:
        return "Local\\TBOT_MUTEX_FALLBACK"
# === MUTEX_NAME_SANITIZE_V1 END ===
def _tbot_safe_mutex_name(tag="ORG_UNIFIED_PAPER"):
    import os, hashlib
    rr = (os.environ.get("TBOT_RUNROOT") or "").strip().lower()
    h  = hashlib.sha1(rr.encode("utf-8")).hexdigest()[:16] if rr else "norunroot00000000"
    # Windows mutex name: keep it simple + valid
    return f"Local\\TBOT_{tag}_{h}"
# File: tbot/entry.py
# Purpose: Single, OS-enforced entrypoint that blocks all duplicate TBOT instances (Windows Named Mutex).
# Exit code 86 => duplicate instance blocked

import os
import sys
import time

def _win_named_mutex(name: str):
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

    CreateMutexW = kernel32.CreateMutexW
    CreateMutexW.argtypes = [wintypes.LPVOID, wintypes.BOOL, wintypes.LPCWSTR]
    CreateMutexW.restype  = wintypes.HANDLE

    GetLastError = kernel32.GetLastError
    GetLastError.argtypes = []
    GetLastError.restype  = wintypes.DWORD

    ERROR_ALREADY_EXISTS = 183

    h = CreateMutexW(None, False, _tbot_sanitize_mutex_name(name))
    if not h:
        # If mutex creation fails, fail safe by allowing (but log)
        sys.stderr.write(f"[ENTRY_MUTEX] CreateMutexW failed err={ctypes.get_last_error()} -> allow\\n")
        return None, False

    already = (GetLastError() == ERROR_ALREADY_EXISTS)
    return h, already

def _acquire_single_instance_or_exit():
    runroot = os.environ.get("TBOT_RUNROOT") or os.environ.get("tbot_runroot") or ""
    # Stable namespace based on runroot (paper vs shadow must be independent)
    tag = runroot.replace("\\\\", "/").lower()
mutex_name = _tbot_safe_mutex_name()

    h, already = _win_named_mutex(mutex_name)
    if already:
        sys.stderr.write(f"[ENTRY_MUTEX] DUPLICATE_BLOCKED mutex={mutex_name} pid={os.getpid()} -> exit 86\\n")
return  # [MUTEX_FAILOPEN]
def main():
    _acquire_single_instance_or_exit()

    # Import after mutex so any self-spawn / multiprocessing / re-exec gets blocked here.
    from tbot.main import main as _main
    return _main()

if __name__ == "__main__":
    raise SystemExit(main())




