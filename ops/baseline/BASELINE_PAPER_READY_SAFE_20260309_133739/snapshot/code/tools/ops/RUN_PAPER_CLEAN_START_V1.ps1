param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec = 8,
  [int]$MetaFreshSec = 10,
  [int]$WatchSec = 30,
  [int]$Force = 1
)

$ErrorActionPreference="Stop"
$Runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$Lock   = Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"
$Meta   = Join-Path $RunRoot "logs\meta.jsonl"
$Hb     = Join-Path $RunRoot "state\heartbeat.json"
$Pidf   = Join-Path $RunRoot "state\pid.txt"
$Ops    = Join-Path $RunRoot "logs\ops"

function AgeSec([string]$p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  return [int](([DateTime]::UtcNow-(Get-Item -LiteralPath $p).LastWriteTimeUtc).TotalSeconds)
}
function ReadBotPid(){
  if(Test-Path -LiteralPath $Pidf){
    $v=(Get-Content -Raw -LiteralPath $Pidf).Trim()
    if($v -match '^\d+$'){ return [int]$v }
  }
  return $null
}
function IsAlive([int]$botpid){
  if($botpid -eq $null){ return $false }
  return [bool](Get-Process -Id $botpid -ErrorAction SilentlyContinue)
}
function TailLatest($filter,[int]$n){
  $f = Get-ChildItem $Ops -Filter $filter -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($f){
    "`n--- " + $f.Name + " (tail " + $n + ") ---"
    Get-Content -LiteralPath $f.FullName -Tail $n -ErrorAction SilentlyContinue
  } else {
    "`n--- NO_FILE: $filter ---"
  }
}

"=== CLEAN_START BEGIN ==="
"ROOT=$Root"
"RUNROOT=$RunRoot"
"RUNNER=$Runner"

# 1) Kill any stray paper bot (tbot.main + paper runroot)
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\paper*" } |
  ForEach-Object { "KILL_PAPER_BOT PID=$($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2) Remove lock + stale state files (this is the KEY fix for your current symptom)
Remove-Item -LiteralPath $Lock -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Pidf -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Hb   -Force -ErrorAction SilentlyContinue

"STATE_CLEARED lock/pid/hb"

# 3) Start runner
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $Runner -Force $Force
"RUNNER_EXITCODE=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec

# 4) Verify: pid must be alive AND meta must be fresh
$bp = ReadBotPid
$alive = IsAlive $bp
$ma = AgeSec $Meta
$ha = AgeSec $Hb

"POST_WARMUP BOTPID=" + ($bp ?? "-")
"POST_WARMUP ALIVE=" + $alive
"POST_WARMUP META_AGE_SEC=" + ($ma ?? -1)
"POST_WARMUP HB_AGE_SEC=" + ($ha ?? -1)

if($alive -and ($ma -ne $null) -and ($ma -le $MetaFreshSec)){
  "OK: BOT_RUNNING + META_FRESH"
  exit 0
}

# 5) Watch for up to WatchSec seconds (maybe pid file arrives late)
for($k=1;$k -le $WatchSec;$k++){
  $bp = ReadBotPid
  $alive = IsAlive $bp
  $ma = AgeSec $Meta
  $ha = AgeSec $Hb
  "{0:HH:mm:ss} k={1} BOTPID={2} ALIVE={3} META_AGE={4} HB_AGE={5}" -f (Get-Date),$k,($bp ?? "-"),$alive,($ma ?? -1),($ha ?? -1)
  if($alive -and ($ma -ne $null) -and ($ma -le $MetaFreshSec)){
    "RECOVERED: BOT_RUNNING + META_FRESH"
    exit 0
  }
  Start-Sleep 1
}

# 6) Autopsy bundle (organizational)
"NO_GO: BOT_NOT_STABLE => AUTOPSY"
TailLatest "LIVE_OUT_*.txt" 120
TailLatest "LIVE_ERR_*.txt" 200

"`n--- PYTHON PROCS (tbot.main) ---"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like "*-m tbot.main*" } |
  Select-Object ProcessId,CommandLine | Format-List

exit 11
