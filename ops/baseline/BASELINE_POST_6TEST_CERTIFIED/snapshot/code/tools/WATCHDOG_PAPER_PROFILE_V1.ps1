param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot",
  [string]$ProfilePath = "C:\alpaca-bot\org_bot\tools\profiles\paper.profile.json",
  [string]$RunnerPath  = "C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1",
  [int]$SelfTest = 0
)
$ErrorActionPreference="Stop"

# LOAD_SECRETS_PAPER_ENFORCED_V2
try{
  $rr2 = $RunRoot
  if([string]::IsNullOrWhiteSpace($rr2)){
    try{
      $p = Join-Path $ProjectRoot 'tools\profiles\paper.profile.json'
      if(Test-Path $p){
        $j = Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json
        if($j.runroot){ $rr2=[string]$j.runroot } elseif($j.runtime){ $rr2=[string]$j.runtime }
      }
    } catch {}
  }
  if([string]::IsNullOrWhiteSpace($rr2)){ $rr2='C:\alpaca-bot\org_bot_runtime\paper' }
  $ldr = Join-Path $ProjectRoot 'tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1'
  . $ldr -Profile 'PAPER' -ProjectRoot $ProjectRoot -RunRoot $rr2 | Out-Null
} catch { throw }

if(!(Test-Path $ProfilePath)){ throw "MISSING_PROFILE=$ProfilePath" }
$prof = (Get-Content -Raw $ProfilePath | ConvertFrom-Json)
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "PROFILE_BAD: runroot empty" }

$hbMax = 180
$maxRestarts = 5
try { if($prof.watchdog.heartbeat_max_age_sec){ $hbMax = [int]$prof.watchdog.heartbeat_max_age_sec } } catch {}
try { if($prof.watchdog.max_restarts_per_day){ $maxRestarts = [int]$prof.watchdog.max_restarts_per_day } } catch {}

$orch = Join-Path $ProjectRoot "tbot\runtime\orchestrator.py"
if(!(Test-Path $orch)){ throw "MISSING_ORCH=$orch" }

if($SelfTest -eq 1){
  $t = Get-Content -Raw -Encoding UTF8 $orch
  if($t -notmatch "#\s*KILL_SWITCH_V1"){ throw "SELFTEST_FAIL: KILL_SWITCH_V1 missing" }
  if($t -notmatch "#\s*HEARTBEAT_FILE_V1"){ throw "SELFTEST_FAIL: HEARTBEAT_FILE_V1 missing" }

  if(!(Test-Path $RunRoot)){ throw "SELFTEST_FAIL: runroot missing: $RunRoot" }
  New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot "logs\ops"),(Join-Path $RunRoot "state\watchdog") | Out-Null

  $hbPath = Join-Path $RunRoot "state\heartbeat.json"
  if(Test-Path $hbPath){
    $age = ([DateTime]::UtcNow - (Get-Item $hbPath).LastWriteTimeUtc).TotalSeconds
    Write-Host ("SELFTEST_HEARTBEAT_PRESENT=1 age_sec≈{0}" -f [int]$age)
  } else {
    Write-Host "SELFTEST_HEARTBEAT_PRESENT=0 (OK if bot not running yet)"
  }

  Write-Host ("RUNROOT={0}" -f $RunRoot)
  Write-Host ("HEARTBEAT_MAX_AGE_SEC={0}" -f $hbMax)
  Write-Host ("MAX_RESTARTS_PER_DAY={0}" -f $maxRestarts)

  Write-Host "SELFTEST_OK=1"
  exit 0
}

# --- Normal watchdog mode (will kill+restart when unhealthy) ---
$opsDir = Join-Path $RunRoot "logs\ops"
$wdDir  = Join-Path $RunRoot "state\watchdog"
New-Item -ItemType Directory -Force -Path $opsDir,$wdDir | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $opsDir ("WATCHDOG_{0}.txt" -f $ts)

function LogLine($s){
  $s2 = ("{0} {1}" -f (Get-Date -Format s), $s)
  Add-Content -Encoding UTF8 -Path $log -Value $s2
  Write-Host $s2
}

$killSwitch = Join-Path $RunRoot "KILL_SWITCH"
if(Test-Path $killSwitch){
  LogLine "KILL_SWITCH_PRESENT=1 (no restart)"
  exit 0
}

$hbPath = Join-Path $RunRoot "state\heartbeat.json"
$age = 999999
if(Test-Path $hbPath){
  $age = ([DateTime]::UtcNow - (Get-Item $hbPath).LastWriteTimeUtc).TotalSeconds
  LogLine ("HEARTBEAT_AGE_SEC={0}" -f [int]$age)
} else {
  LogLine "HEARTBEAT_MISSING=1"
}

if($age -le $hbMax){
  LogLine "HEALTH=OK"
  exit 0
}

# restart budget
$day = Get-Date -Format "yyyyMMdd"
$budgetFile = Join-Path $wdDir ("restarts_{0}.txt" -f $day)
$cnt = 0
if(Test-Path $budgetFile){ $cnt = [int](Get-Content -Raw $budgetFile) }
if($cnt -ge $maxRestarts){
  LogLine ("RESTART_BUDGET_EXCEEDED count={0} max={1}" -f $cnt, $maxRestarts)
  exit 4
}

# targeted kill using pid.txt
$pidFile = Join-Path $RunRoot "state\pid.txt"
if(Test-Path $pidFile){
  $pid = (Get-Content -Raw $pidFile).Trim()
  if($pid -match '^\d+$'){
    try {
      $p = Get-Process -Id ([int]$pid) -ErrorAction Stop
      LogLine ("KILLING pid={0} name={1}" -f $p.Id, $p.Name)
      Stop-Process -Id $p.Id -Force
      Start-Sleep -Seconds 2
    } catch {
      LogLine ("PID_NOT_RUNNING pid={0}" -f $pid)
    }
  } else {
    LogLine "PID_INVALID"
  }
} else {
  LogLine "PID_MISSING=1"
}

# increment budget
$cnt2 = $cnt + 1
Set-Content -Encoding UTF8 -Path $budgetFile -Value $cnt2
LogLine ("RESTART_COUNT_TODAY={0}" -f $cnt2)

# restart via runner
if(!(Test-Path $RunnerPath)){
  LogLine ("RUNNER_MISSING={0}" -f $RunnerPath)
  exit 5
}

LogLine ("RESTARTING via runner={0}" -f $RunnerPath)
pwsh -NoProfile -ExecutionPolicy Bypass -File $RunnerPath -ProjectRoot $ProjectRoot -ProfilePath $ProfilePath -Force 1
LogLine "RESTART_DONE"
exit 0

