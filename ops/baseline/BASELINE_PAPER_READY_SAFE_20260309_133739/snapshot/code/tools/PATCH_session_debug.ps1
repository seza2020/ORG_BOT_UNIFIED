$ErrorActionPreference = "Stop"

$root   = "C:\alpaca-bot\org_bot"
$target = Join-Path $root "tbot\runtime\orchestrator.py"
$patcher = Join-Path $root "tools\patch_session_debug.py"

if (-not (Test-Path $target)) { throw "Missing target: $target" }

# Write python patcher (idempotent)
@"
import re
import sys
from datetime import datetime

def backup(path: str) -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = f"{path}.bak_{ts}"
    with open(path, "rb") as fsrc, open(bak, "wb") as fdst:
        fdst.write(fsrc.read())
    return bak

HELPER = r'''
# SESSION_DEBUG (auto patch)
def _session_debug_dump(state, now_dt=None):
    try:
        from datetime import datetime, timezone
        now = now_dt or datetime.now()
        now_utc = datetime.now(timezone.utc)

        parts = {
            "now_local": now.isoformat() if hasattr(now, "isoformat") else str(now),
            "now_utc": now_utc.isoformat() if hasattr(now_utc, "isoformat") else str(now_utc),
        }

        # common fields if present
        keys = ("in_session","pre_close","session_reason","market_open","market_close","is_holiday","weekday","tz","now_et")
        for k in keys:
            if isinstance(state, dict) and k in state:
                parts[k] = state.get(k)
            else:
                v = getattr(state, k, None)
                if v is not None:
                    parts[k] = v
        return parts
    except Exception as e:
        return {"session_debug_error": str(e)}
'''

def insert_helper(src: str) -> str:
    if "SESSION_DEBUG (auto patch)" in src:
        return src

    lines = src.splitlines(True)
    i = 0

    # Skip shebang/encoding/comments/blanks
    while i < len(lines) and (lines[i].startswith("#") or lines[i].strip() == ""):
        i += 1

    # Include consecutive import blocks
    j = i
    while j < len(lines):
        s = lines[j].lstrip()
        if s.startswith("import ") or s.startswith("from "):
            j += 1
            continue
        # allow blank lines inside import region
        if lines[j].strip() == "":
            j += 1
            continue
        break

    # Insert helper after import block (or after initial header)
    insert_at = j
    out = "".join(lines[:insert_at]) + HELPER + "\n" + "".join(lines[insert_at:])
    return out

def find_heartbeat_line(src: str):
    # find first line that contains HEARTBEAT (log emission)
    lines = src.splitlines(True)
    for idx, line in enumerate(lines):
        if "HEARTBEAT" in line and ("logger." in line or "log." in line):
            return idx, line, lines
    # fallback: any HEARTBEAT mention
    for idx, line in enumerate(lines):
        if "HEARTBEAT" in line:
            return idx, line, lines
    return None, None, lines

def infer_state_var(line: str) -> str:
    # Try to infer variable used for .in_session
    m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\.in_session", line)
    if m:
        return m.group(1)
    return "state"

def insert_debug_before_heartbeat(src: str) -> str:
    if "SESSION_DEBUG %s" in src:
        return src

    idx, hb_line, lines = find_heartbeat_line(src)
    if idx is None:
        return src  # no-op if not found

    indent = re.match(r"^(\s*)", hb_line).group(1)
    st = infer_state_var(hb_line)

    block = (
        f"{indent}# SESSION_DEBUG\n"
        f"{indent}try:\n"
        f"{indent}    if not getattr({st}, 'in_session', False):\n"
        f"{indent}        logger.info('SESSION_DEBUG %s', _session_debug_dump({st}))\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )

    out = "".join(lines[:idx]) + block + "".join(lines[idx:])
    return out

def main():
    if len(sys.argv) < 2:
        print("Usage: patch_session_debug.py <path_to_orchestrator.py>")
        return 2

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()

    if "SESSION_DEBUG (auto patch)" in src and "SESSION_DEBUG %s" in src:
        print("OK: SESSION_DEBUG already present")
        return 0

    bak = backup(path)
    print(f"BACKUP={bak}")

    src2 = insert_helper(src)
    src3 = insert_debug_before_heartbeat(src2)

    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(src3)

    print("OK: patched")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"@ | Set-Content -LiteralPath $patcher -Encoding UTF8

python $patcher $target
python -m py_compile $target
"OK: py_compile passed for $target"
