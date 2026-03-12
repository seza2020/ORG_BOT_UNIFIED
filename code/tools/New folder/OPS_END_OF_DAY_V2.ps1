param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day  = "",
  [string]$TimeZoneId = "Pacific Standard Time",
  [int]$StopBot = 1
)

$ErrorActionPreference="Stop"
function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

if (-not $Day -or $Day.Trim() -eq "") { $Day = (Get-Date).ToString("yyyyMMdd") }

$Ops = Join-Path $Root "logs\ops"
$Logs = Join-Path $Root "logs"
$PY = Join-Path $Root ".venv\Scripts\python.exe"
$Recover = Join-Path $Root "tools\recover_shadow_plans_from_meta.ps1"
$Freeze  = Join-Path $Root "tools\freeze_today_enterprise_SAFE.ps1"
$ClearLock = Join-Path $Root "tools\CLEAR_TBOT_LOCK.ps1"

Log "OPS_END_OF_DAY_V2"
Log "Root=$Root"
Log "Day=$Day"

# Stop bot (project-only)
if ($StopBot -eq 1) {
  Log "STOP_BOT..."
  $alive = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $PY -and $_.CommandLine -match "tbot\.main" }
  foreach($p in $alive){
    try {
      Log ("KILL_PID=" + $p.ProcessId)
      Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    } catch {}
  }
}

# TRIAGE
$OutFiles = Get-ChildItem -Path $Ops -Filter ("LIVE_OUT_$Day*.txt") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
$ErrFiles = Get-ChildItem -Path $Ops -Filter ("LIVE_ERR_$Day*.txt") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
Log ("OUT_FILES=" + ($OutFiles.Count))
Log ("ERR_FILES=" + ($ErrFiles.Count))

# RECOVER
if(!(Test-Path $Recover)){ throw "Missing: $Recover" }
Log "RECOVER_FROM_META..."
pwsh -NoProfile -ExecutionPolicy Bypass -File $Recover -Root $Root -Day $Day -TimeZoneId $TimeZoneId

# FREEZE
if(Test-Path $Freeze){
  Log "FREEZE_TODAY_ENTERPRISE..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File $Freeze -Root $Root
}else{
  Log "WARN: freeze_today_enterprise.ps1 not found, skipping freeze."
}

# CLEAR LOCK
if(Test-Path $ClearLock){
  Log "CLEAR_LOCK..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File $ClearLock
}else{
  Log "WARN: CLEAR_TBOT_LOCK.ps1 not found, skipping lock clear."
}

# QA COUNT (FROM_META)
$FromMeta = Join-Path $Logs ("shadow_daily\shadow_plans_${Day}_FROM_META.jsonl")
if(Test-Path $FromMeta){
  $cnt = (Get-Content $FromMeta | Measure-Object -Line).Lines
  Log ("FROM_META_COUNT=" + $cnt)
  if ($cnt -gt 0) {
    Log ("FIRST_LINE=" + (Get-Content $FromMeta -TotalCount 1))
    Log ("LAST_LINE=" + (Get-Content $FromMeta -Tail 1))
  }
}else{
  Log ("WARN: FROM_META missing: " + $FromMeta)
}

Log "DONE"

