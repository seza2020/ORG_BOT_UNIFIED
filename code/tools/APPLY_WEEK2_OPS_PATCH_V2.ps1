$ErrorActionPreference="Stop"
function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"

# 0) Disable UI task (safety)
try {
  Disable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_UI_0630" -ErrorAction SilentlyContinue | Out-Null
  Log "OK: TBOT_RUN_SHADOW_UI_0630 disabled (or already)."
} catch {
  Log "WARN: Could not disable TBOT_RUN_SHADOW_UI_0630."
}

# 1) Create CANON_V2 runner (stale-lock auto-heal + project-only)
$CanonV2 = Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"

@"
param(
  [int]`$Force = 0
)

`$ErrorActionPreference="Stop"
`$ROOT="C:\alpaca-bot\org_bot"
`$PY="`$ROOT\.venv\Scripts\python.exe"
`$OPS="`$ROOT\logs\ops"
`$LOCKDIR="`$ROOT\logs\locks"
`$LOCK=Join-Path `$LOCKDIR "RUN_SHADOW.lock"
`$ENVPS1="C:\alpaca-bot\secrets\alpaca_env.ps1"

function Log([string]`$m){ `$ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[`$ts] `$m" }

New-Item -ItemType Directory -Force -Path `$OPS | Out-Null
New-Item -ItemType Directory -Force -Path `$LOCKDIR | Out-Null

# Auto-heal stale lock (project-only):
# If lock exists BUT no python from THIS venv running tbot.main -> clear lock.
if ((Test-Path `$LOCK) -and (`$Force -ne 1)) {
  `$alive = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { `$_.ExecutablePath -eq `$PY -and `$_.CommandLine -match "tbot\.main" }

  if (-not `$alive -or `$alive.Count -eq 0) {
    Remove-Item `$LOCK -Force -ErrorAction SilentlyContinue
    Log "STALE_LOCK_CLEARED"
  }
}

# Lock
if ((Test-Path `$LOCK) -and (`$Force -ne 1)) {
  Log "BLOCK: lock exists (`$LOCK). Use -Force 1 only if you are sure old run is dead."
  Get-Content `$LOCK -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object { Log ("  " + `$_) }
  exit 0
}

@(
  "ts=" + (Get-Date -Format s),
  "user=" + `$env:USERNAME,
  "host=" + `$env:COMPUTERNAME,
  "root=" + `$ROOT
) | Set-Content -Encoding UTF8 -Path `$LOCK

try {
  Set-Location `$ROOT
  `$env:PYTHONPATH = `$ROOT

  if(!(Test-Path `$ENVPS1)){ throw "Missing secrets file: `$ENVPS1" }
  . `$ENVPS1

  # strategy toggles
  `$env:TBOT_MVP="1"
  `$env:TBOT_S01_ENABLE="1"
  `$env:TBOT_S11_ENABLE="1"
  `$env:TBOT_ENABLE_S01_LOGIC="1"

  # pricing knobs
  `$env:TBOT_SHADOW_PRICE_MODE="last"
  `$env:TBOT_SHADOW_RR="2.0"
  `$env:TBOT_SHADOW_STOP_PCT="0.003"

  `$ts=(Get-Date -Format "yyyyMMdd_HHmmss")
  `$OUT="`$OPS\LIVE_OUT_`$ts.txt"
  `$ERR="`$OPS\LIVE_ERR_`$ts.txt"

  Log "ROOT=`$ROOT"
  Log "PY=`$PY"
  Log "OUT=`$OUT"
  Log "ERR=`$ERR"
  Log "START LIVE shadow..."

  Start-Process -FilePath `$PY -ArgumentList @(
    "-u","-m","tbot.main",
    "--run","--iters","999999","--sleep","0.25",
    "--shadow",
    "--meta", (Join-Path `$ROOT "logs\meta.jsonl"),
    "--announce", (Join-Path `$ROOT "logs\announce.log"),
    "--gate_min_rr","1.0",
    "--gate_min_conf","0.0",
    "--gate_cooldown_sec","180",
    "--gate_max_plans_per_day","60",
    "--gate_max_risk_usd","500"
  ) -WorkingDirectory `$ROOT -RedirectStandardOutput `$OUT -RedirectStandardError `$ERR | Out-Null

  Start-Sleep -Seconds 2
  `$livePid = (Get-Process python -ErrorAction SilentlyContinue |
    Where-Object { `$_.Path -eq `$PY } |
    Sort-Object StartTime | Select-Object -Last 1).Id
  Log "LIVE_PID=`$livePid"
}
finally {
  Log "LOCK_LEFT_IN_PLACE=`$LOCK"
}
"@ | Set-Content -Encoding UTF8 -Path $CanonV2

Log ("OK: Created " + $CanonV2)

# 2) Create OPS_END_OF_DAY_V2 (project-only StopBot + recover + freeze + clear lock)
$EODV2 = Join-Path $ROOT "tools\OPS_END_OF_DAY_V2.ps1"

@"
param(
  [string]`$Root = "C:\alpaca-bot\org_bot",
  [string]`$Day  = "",
  [string]`$TimeZoneId = "Pacific Standard Time",
  [int]`$StopBot = 1
)

`$ErrorActionPreference="Stop"
function Log([string]`$m){ `$ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[`$ts] `$m" }

if (-not `$Day -or `$Day.Trim() -eq "") { `$Day = (Get-Date).ToString("yyyyMMdd") }

`$Ops = Join-Path `$Root "logs\ops"
`$Logs = Join-Path `$Root "logs"
`$PY = Join-Path `$Root ".venv\Scripts\python.exe"
`$Recover = Join-Path `$Root "tools\recover_shadow_plans_from_meta.ps1"
`$Freeze  = Join-Path `$Root "tools\freeze_today_enterprise.ps1"
`$ClearLock = Join-Path `$Root "tools\CLEAR_TBOT_LOCK.ps1"

Log "OPS_END_OF_DAY_V2"
Log "Root=`$Root"
Log "Day=`$Day"

# Stop bot (project-only)
if (`$StopBot -eq 1) {
  Log "STOP_BOT..."
  `$alive = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { `$_.ExecutablePath -eq `$PY -and `$_.CommandLine -match "tbot\.main" }
  foreach(`$p in `$alive){
    try {
      Log ("KILL_PID=" + `$p.ProcessId)
      Stop-Process -Id `$p.ProcessId -Force -ErrorAction SilentlyContinue
    } catch {}
  }
}

# TRIAGE
`$OutFiles = Get-ChildItem -Path `$Ops -Filter ("LIVE_OUT_`$Day*.txt") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
`$ErrFiles = Get-ChildItem -Path `$Ops -Filter ("LIVE_ERR_`$Day*.txt") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
Log ("OUT_FILES=" + (`$OutFiles.Count))
Log ("ERR_FILES=" + (`$ErrFiles.Count))

# RECOVER
if(!(Test-Path `$Recover)){ throw "Missing: `$Recover" }
Log "RECOVER_FROM_META..."
pwsh -NoProfile -ExecutionPolicy Bypass -File `$Recover -Root `$Root -Day `$Day -TimeZoneId `$TimeZoneId

# FREEZE
if(Test-Path `$Freeze){
  Log "FREEZE_TODAY_ENTERPRISE..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File `$Freeze -Root `$Root
}else{
  Log "WARN: freeze_today_enterprise.ps1 not found, skipping freeze."
}

# CLEAR LOCK
if(Test-Path `$ClearLock){
  Log "CLEAR_LOCK..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File `$ClearLock
}else{
  Log "WARN: CLEAR_TBOT_LOCK.ps1 not found, skipping lock clear."
}

# QA COUNT (FROM_META)
`$FromMeta = Join-Path `$Logs ("shadow_daily\shadow_plans_`$Day`_FROM_META.jsonl")
if(Test-Path `$FromMeta){
  `$cnt = (Get-Content `$FromMeta | Measure-Object -Line).Lines
  Log ("FROM_META_COUNT=" + `$cnt)
  if (`$cnt -gt 0) {
    Log ("FIRST_LINE=" + (Get-Content `$FromMeta -TotalCount 1))
    Log ("LAST_LINE=" + (Get-Content `$FromMeta -Tail 1))
  }
}else{
  Log ("WARN: FROM_META missing: " + `$FromMeta)
}

Log "DONE"
"@ | Set-Content -Encoding UTF8 -Path $EODV2

Log ("OK: Created " + $EODV2)

# 3) Convert legacy runners to safe wrappers
$runShadow = Join-Path $ROOT "tools\run_shadow.ps1"
@"
param([string]`$Root="C:\alpaca-bot\org_bot",[int]`$Force=0)
`$ErrorActionPreference="Stop"
`$canon = Join-Path `$Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File `$canon -Force `$Force
"@ | Set-Content -Encoding UTF8 -Path $runShadow
Log "OK: tools\run_shadow.ps1 -> SAFE wrapper (CANON_V2)."

$uiShadow = Join-Path $ROOT "tools\RUN_SHADOW_UI.ps1"
@"
`$ErrorActionPreference="Stop"
Write-Host "=== TBOT SHADOW UI (SAFE WRAPPER) ==="
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\alpaca-bot\org_bot\tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
Write-Host "DONE."
"@ | Set-Content -Encoding UTF8 -Path $uiShadow
Log "OK: tools\RUN_SHADOW_UI.ps1 -> SAFE wrapper (CANON_V2)."

Log "PATCH_V2_DONE"
