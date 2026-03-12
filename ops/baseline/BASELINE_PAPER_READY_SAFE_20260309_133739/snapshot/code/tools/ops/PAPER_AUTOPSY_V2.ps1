param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Continue"

function AgeSec($p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}

$ops = Join-Path $RunRoot "logs\ops"
$meta = Join-Path $RunRoot "logs\meta.jsonl"
$ann  = Join-Path $RunRoot "logs\announce.log"
$lock = Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"
$pidf = Join-Path $RunRoot "state\pid.txt"
$hb   = Join-Path $RunRoot "state\heartbeat.json"
$err  = Join-Path $RunRoot "state\heartbeat_err.txt"

"=== AUTOPSY_V2 START ==="
"TS_LOCAL={0}" -f (Get-Date)
"Root=$Root"
"RunRoot=$RunRoot"

"--- Latest LIVE_OUT/ERR ---"
$lastOut = Get-ChildItem $ops -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$lastErr = Get-ChildItem $ops -Filter "LIVE_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
"LAST_OUT=" + ($lastOut?.FullName ?? "-")
"LAST_ERR=" + ($lastErr?.FullName ?? "-")
if($lastOut){ "`n--- OUT_TAIL(80) ---"; Get-Content $lastOut.FullName -Tail 80 }
if($lastErr){ "`n--- ERR_TAIL(80) ---"; Get-Content $lastErr.FullName -Tail 80 }

"`n--- State files ---"
"LOCK_EXISTS=" + (Test-Path $lock)
if(Test-Path $lock){ "LOCK_TAIL:"; Get-Content $lock -Tail 20 }
"PIDFILE_EXISTS=" + (Test-Path $pidf)
if(Test-Path $pidf){ "PIDFILE=" + (Get-Content $pidf -Raw).Trim() }
"HB_EXISTS=" + (Test-Path $hb)
"HB_AGE_SEC=" + (AgeSec $hb ?? -1)
if(Test-Path $hb){ "HB_TAIL:"; Get-Content $hb -Tail 5 }
"HB_ERR_EXISTS=" + (Test-Path $err)
if(Test-Path $err){ "HB_ERR_TAIL:"; Get-Content $err -Tail 50 }

"`n--- Meta/Announce ---"
"META_EXISTS=" + (Test-Path $meta)
"META_AGE_SEC=" + (AgeSec $meta ?? -1)
if(Test-Path $meta){ "META_TAIL(40):"; Get-Content $meta -Tail 40 }
"ANN_EXISTS=" + (Test-Path $ann)
"ANN_AGE_SEC=" + (AgeSec $ann ?? -1)
if(Test-Path $ann){ "ANN_TAIL(80):"; Get-Content $ann -Tail 80 }

"`n--- Python processes (full CommandLine) ---"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Select-Object ProcessId,CommandLine |
  Sort-Object ProcessId |
  Format-List

"`n--- Candidate bot processes (contains runroot/meta/shadow) ---"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object {
    ($_.CommandLine -like "*org_bot_runtime\\paper*") -or
    ($_.CommandLine -like "*meta.jsonl*") -or
    ($_.CommandLine -like "*shadow_plans.jsonl*") -or
    ($_.CommandLine -like "*-m tbot.main*")
  } |
  Select-Object ProcessId,CommandLine |
  Format-List

"=== AUTOPSY_V2 END ==="
