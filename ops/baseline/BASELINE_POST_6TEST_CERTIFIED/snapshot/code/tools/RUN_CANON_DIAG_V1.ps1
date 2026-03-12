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

$out=Join-Path $ops "DIAG_OUT_$stamp.txt"
$err=Join-Path $ops "DIAG_ERR_$stamp.txt"
$audit=Join-Path $ops "DIAG_AUDIT_$stamp.txt"

$env:TBOT_RUNROOT=$RunRoot
$env:PYTHONFAULTHANDLER="1"

# Build argv-like flags to mimic normal run
$shadowFlag = if($ShadowEnabled){ "1" } else { "0" }

$code = @"
import os, sys, traceback, time
print("DIAG: begin", file=sys.stderr, flush=True)
print("DIAG: argv=", sys.argv, file=sys.stderr, flush=True)
print("DIAG: TBOT_RUNROOT=", os.getenv("TBOT_RUNROOT"), file=sys.stderr, flush=True)
print("DIAG: shadow_enabled=", "$shadowFlag", file=sys.stderr, flush=True)

try:
    import tbot.main as m
    print("DIAG: imported tbot.main OK", file=sys.stderr, flush=True)

    # If you want to mimic flags inside sys.argv for argparse, you can set:
    sys.argv = [sys.argv[0], "--run"] + (["--shadow"] if "$shadowFlag"=="1" else [])
    print("DIAG: sys.argv set to", sys.argv, file=sys.stderr, flush=True)

    try:
        rc = m.entrypoint()
        print(f"DIAG: entrypoint() returned rc={rc!r}", file=sys.stderr, flush=True)
        sys.exit(int(rc) if isinstance(rc,int) else 0)
    except SystemExit as e:
        code = getattr(e, "code", None)
        print(f"DIAG: SystemExit repr={e!r} code={code!r} str={str(e)}", file=sys.stderr, flush=True)
        raise

except Exception as e:
    print("DIAG: EXCEPTION " + repr(e), file=sys.stderr, flush=True)
    traceback.print_exc()
    sys.exit(1)
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
