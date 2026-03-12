param(
  [string]$Root   = "C:\alpaca-bot\org_bot",
  [string]$RunRoot= "C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec = 8
)

$ErrorActionPreference="Stop"

function TailFile([string]$p,[int]$n=200){
  if(Test-Path -LiteralPath $p){
    "---- TAIL: $p ----"
    Get-Content -LiteralPath $p -Tail $n
  } else {
    "---- MISSING: $p ----"
  }
}

function AgeSec([string]$p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  return [int](([DateTime]::UtcNow - (Get-Item -LiteralPath $p).LastWriteTimeUtc).TotalSeconds)
}

"=== AUTOPSY START ==="
"TS_LOCAL=" + (Get-Date)
"Root=$Root"
"RunRoot=$RunRoot"

$ops = Join-Path $RunRoot "logs\ops"
$meta = Join-Path $RunRoot "logs\meta.jsonl"
$ann  = Join-Path $RunRoot "logs\announce.log"
$lock = Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"
$pidf = Join-Path $RunRoot "state\pid.txt"
$hb   = Join-Path $RunRoot "state\heartbeat.json"

$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
if(!(Test-Path -LiteralPath $runner)){ throw "MISSING_RUNNER=$runner" }

# 1) Kill any stray paper bots
"STEP1: KILL stray paper bots (tbot.main + paper runroot)"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\paper*" } |
  ForEach-Object { "KILL PID=" + $_.ProcessId; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2) Remove lock (hard reset)
"STEP2: REMOVE lock"
Remove-Item -Force -ErrorAction SilentlyContinue $lock
"LOCK_EXISTS=" + (Test-Path -LiteralPath $lock)

# 3) Run runner (Force=1)
"STEP3: RUN runner (Force=1)"
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Force 1
$ec = $LASTEXITCODE
"RUNNER_EXITCODE=$ec"

Start-Sleep -Seconds $WarmupSec

# 4) Check if python is alive
"STEP4: CHECK liveness"
$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\paper*" }

"BOT_PROC_COUNT=" + @($procs).Count
if(@($procs).Count -gt 0){
  $procs | Select-Object ProcessId,CommandLine | Format-List
}

# 5) Pull latest OUT/ERR and meta/announce tails
"STEP5: PULL tails"
$lastOut = Get-ChildItem $ops -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$lastErr = Get-ChildItem $ops -Filter "LIVE_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if($lastOut){ TailFile $lastOut.FullName 240 } else { "NO LIVE_OUT found" }
if($lastErr){ TailFile $lastErr.FullName 240 } else { "NO LIVE_ERR found" }

TailFile $ann 120
TailFile $meta 80

# 6) Ages (meta/hb/pid) for stall diagnosis
"STEP6: AGES"
"meta_age_sec=" + ((AgeSec $meta) ?? -1)
"hb_age_sec="   + ((AgeSec $hb) ?? -1)
"pid_age_sec="  + ((AgeSec $pidf) ?? -1)
"lock_exists="  + (Test-Path -LiteralPath $lock)

"=== AUTOPSY END ==="
