param(
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [switch]$ShadowEnabled
)

$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"
if(!(Test-Path $PY)){ throw "MISSING_PY=$PY" }

$ops=Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force $ops | Out-Null
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"

$out=Join-Path $ops "DIAG2_OUT_$stamp.txt"
$err=Join-Path $ops "DIAG2_ERR_$stamp.txt"
$audit=Join-Path $ops "DIAG2_AUDIT_$stamp.txt"

$env:TBOT_RUNROOT=$RunRoot
$env:PYTHONFAULTHANDLER="1"

$shadowFlag = if($ShadowEnabled){ "1" } else { "0" }

$code = @"
import os, sys, traceback, time
def w(s): print(s, file=sys.stderr, flush=True)

w("DIAG2: begin")
w(f"DIAG2: pid={os.getpid()} argv={sys.argv!r}")
w("DIAG2: TBOT_RUNROOT=" + str(os.getenv("TBOT_RUNROOT")))
w("DIAG2: shadow_enabled=" + "$shadowFlag")

# --- capture BaseException for IMPORT ---
try:
    import tbot.main as m
    import inspect
    w("DIAG2: import tbot.main OK file=" + str(inspect.getsourcefile(m)))
except BaseException as e:
    w("DIAG2: IMPORT BaseException=" + repr(e))
    try:
        w("DIAG2: IMPORT type=" + str(type(e)))
        code = getattr(e, "code", None)
        w("DIAG2: IMPORT SystemExit.code=" + repr(code))
    except Exception:
        pass
    traceback.print_exc()
    raise

# mimic argv for argparse
sys.argv = [sys.argv[0], "--run"] + (["--shadow"] if "$shadowFlag"=="1" else [])
w("DIAG2: sys.argv set to " + repr(sys.argv))

# --- capture BaseException for ENTRYPOINT ---
try:
    rc = m.entrypoint()
    w(f"DIAG2: entrypoint returned rc={rc!r}")
    sys.exit(int(rc) if isinstance(rc,int) else 0)
except BaseException as e:
    w("DIAG2: ENTRY BaseException=" + repr(e))
    try:
        code = getattr(e, "code", None)
        w("DIAG2: ENTRY SystemExit.code=" + repr(code))
    except Exception:
        pass
    traceback.print_exc()
    raise
"@

& $PY -u -c $code 1> $out 2> $err
$rc=$LASTEXITCODE

@"
ts=$stamp
runroot=$RunRoot
shadow=$shadowFlag
rc=$rc
out=$out
err=$err
"@ | Set-Content -Encoding utf8 $audit

"AUDIT=$audit"
"RC=$rc"
exit $rc
