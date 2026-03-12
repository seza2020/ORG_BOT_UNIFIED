param([string]$Root="C:\alpaca-bot\org_bot")

$ErrorActionPreference="Stop"

$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(!(Test-Path $Canon)){ throw "Missing: $Canon" }

$PY   = Join-Path $Root ".venv\Scripts\python.exe"
$OPS  = Join-Path $Root "logs\ops"
$LOCKDIR = Join-Path $Root "logs\locks"
$LOCK = Join-Path $LOCKDIR "RUN_SHADOW.lock"
$ENVPS1="C:\alpaca-bot\secrets\alpaca_env.ps1"

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = "$Canon.bak_strict_singleinstance_$ts"
Copy-Item -Force $Canon $bak

@"
param(
  [string]`$Root = "C:\alpaca-bot\org_bot",
  [int]`$Force = 0
)

`$ErrorActionPreference="Stop"

function Log([string]`$m){ `$ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[`$ts] `$m" }

`$ROOT=`$Root
`$PY = Join-Path `$ROOT ".venv\Scripts\python.exe"
`$OPS = Join-Path `$ROOT "logs\ops"
`$LOCKDIR = Join-Path `$ROOT "logs\locks"
`$LOCK = Join-Path `$LOCKDIR "RUN_SHADOW.lock"
`$ENVPS1="C:\alpaca-bot\secrets\alpaca_env.ps1"

New-Item -ItemType Directory -Force -Path `$OPS | Out-Null
New-Item -ItemType Directory -Force -Path `$LOCKDIR | Out-Null

# --- STRICT SINGLE INSTANCE ---
if(Test-Path `$LOCK){
  `$lines = Get-Content `$LOCK -ErrorAction SilentlyContinue
  `$lockPid = `$null
  foreach(`$ln in `$lines){
    if(`$ln -match '^pid=(\d+)$'){ `$lockPid = [int]`$matches[1]; break }
  }

  `$alive = `$false
  if(`$lockPid){
    `$p = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
      Where-Object { `$_.ProcessId -eq `$lockPid } | Select-Object -First 1
    if(`$p -and `$p.ExecutablePath -eq `$PY){ `$alive = `$true }
  }

  if(`$alive){
    if(`$Force -eq 1){
      Log ("FORCE_KILL_PID=" + `$lockPid)
      Stop-Process -Id `$lockPid -Force -ErrorAction SilentlyContinue
      Start-Sleep 1
      Remove-Item `$LOCK -Force -ErrorAction SilentlyContinue
      Log "LOCK_CLEARED_FORCE"
    } else {
      Log "BLOCK: lock exists and process alive. Use -Force 1 only if you are sure."
      foreach(`$ln in (`$lines | Select-Object -First 6)){ Log ("  " + `$ln) }
      exit 3
    }
  } else {
    Remove-Item `$LOCK -Force -ErrorAction SilentlyContinue
    Log "STALE_LOCK_CLEARED"
  }
}

Set-Location `$ROOT
`$env:PYTHONPATH = `$ROOT

if(!(Test-Path `$ENVPS1)){ throw "Missing secrets file: `$ENVPS1" }
. `$ENVPS1

# Shadow toggles
`$env:TBOT_MVP="1"
`$env:TBOT_S01_ENABLE="1"
`$env:TBOT_S11_ENABLE="1"

# pricing knobs
`$env:TBOT_SHADOW_PRICE_MODE="last"
`$env:TBOT_SHADOW_RR="2.0"
`$env:TBOT_SHADOW_STOP_PCT="0.003"

`$ts=(Get-Date -Format "yyyyMMdd_HHmmss")
`$OUT=Join-Path `$OPS ("LIVE_OUT_`$ts.txt")
`$ERR=Join-Path `$OPS ("LIVE_ERR_`$ts.txt")

Log ("ROOT=" + `$ROOT)
Log ("PY=" + `$PY)
Log ("OUT=" + `$OUT)
Log ("ERR=" + `$ERR)
Log "START LIVE shadow..."

# import proof (non-fatal)
& `$PY -c "import tbot; import tbot.runtime.orchestrator as o; print('IMPORT_OK', o.__file__)" 2>`$null | Out-Null

# Start + get PID reliably
`$proc = Start-Process -FilePath `$PY -ArgumentList @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep","0.25",
  "--shadow",
  "--gate_min_rr","1.0",
  "--gate_min_conf","0.0",
  "--gate_cooldown_sec","180",
  "--gate_max_plans_per_day","60",
  "--gate_max_risk_usd","500"
) -WorkingDirectory `$ROOT -RedirectStandardOutput `$OUT -RedirectStandardError `$ERR -PassThru

`$livePid = `$proc.Id
Log ("LIVE_PID=" + `$livePid)

@(
  ("ts={0} user={1} host={2} root={3}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), `$env:USERNAME, `$env:COMPUTERNAME, `$ROOT),
  ("pid={0}" -f `$livePid),
  ("out={0}" -f `$OUT),
  ("err={0}" -f `$ERR)
) | Set-Content -Encoding UTF8 -Path `$LOCK

Start-Sleep -Seconds 3
if(-not (Get-Process -Id `$livePid -ErrorAction SilentlyContinue)){
  Log "FAIL_START: process exited early."
  Remove-Item `$LOCK -Force -ErrorAction SilentlyContinue
  Log "LOCK_CLEARED_ON_FAIL"
  if(Test-Path `$ERR){ Log "=== ERR tail (120) ==="; Get-Content -Tail 120 `$ERR }
  if(Test-Path `$OUT){ Log "=== OUT tail (120) ==="; Get-Content -Tail 120 `$OUT }
  exit 2
}

Log "HEALTHCHECK_OK"
Log "TIP: Tail logs with:"
Log ("  Get-Content -Wait -Tail 80 `"`$OUT`"")
Log ("  Get-Content -Wait -Tail 80 `"`$ERR`"")
"@ | Set-Content -Encoding UTF8 -Path `$Canon

"OK_PATCHED"
"BACKUP=$bak"
