
# ---- AUTO: strategy enable switches (authoritative) ----
$env:TBOT_ENABLE_S01_LOGIC = "1"
# Optional tuning:
# $env:TBOT_S01_MIN_STRENGTH = "0.45"
# ----------------------------------------------------------


$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"
$OPS="$ROOT\logs\ops"
$SP="$ROOT\logs\shadow_plans.jsonl"
$ENVPS1="C:\alpaca-bot\secrets\alpaca_env.ps1"

function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

Set-Location $ROOT
$env:PYTHONPATH = $ROOT

# secrets
if(!(Test-Path $ENVPS1)){ throw "Missing secrets file: $ENVPS1" }
. $ENVPS1

# Shadow toggles (force enable strategies for shadow planning)
$env:TBOT_MVP="1"
$env:TBOT_S01_ENABLE="1"
$env:TBOT_S11_ENABLE="1"

# pricing knobs
$env:TBOT_SHADOW_PRICE_MODE="last"
$env:TBOT_SHADOW_RR="2.0"
$env:TBOT_SHADOW_STOP_PCT="0.003"

# ensure folders
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
if(!(Test-Path $SP)){ New-Item -ItemType File -Force -Path $SP | Out-Null }

Log "ROOT=$ROOT"
Log "PY=$PY"
Log "PYTHONPATH=$env:PYTHONPATH"
Log "TBOT_MVP=$env:TBOT_MVP  TBOT_S01_ENABLE=$env:TBOT_S01_ENABLE  TBOT_S11_ENABLE=$env:TBOT_S11_ENABLE"
Log "TBOT_SHADOW_PRICE_MODE=$env:TBOT_SHADOW_PRICE_MODE RR=$env:TBOT_SHADOW_RR STOP_PCT=$env:TBOT_SHADOW_STOP_PCT"

# import proof
& $PY -c "import tbot; import tbot.runtime.orchestrator as o; print('IMPORT_OK', o.__file__)" 2>$null

# kill old bot procs (only venv python)
if($KillOld -eq 1){
  $old = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $PY }
  foreach($p in $old){
    Log ("KILL old PID=" + $p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
}

# start live shadow with file logs
$ts=(Get-Date -Format "yyyyMMdd_HHmmss")
$OUT="$OPS\LIVE_OUT_$ts.txt"
$ERR="$OPS\LIVE_ERR_$ts.txt"

Log "OUT=$OUT"
Log "ERR=$ERR"
Log "START LIVE shadow..."

Start-Process -FilePath $PY -ArgumentList @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep","0.25",
  "--shadow",
  "--gate_min_rr","1.0",
  "--gate_min_conf","0.0",
  "--gate_cooldown_sec","180",
  "--gate_max_plans_per_day","60",
  "--gate_max_risk_usd","500"
) -WorkingDirectory $ROOT -RedirectStandardOutput $OUT -RedirectStandardError $ERR | Out-Null

Start-Sleep -Seconds 2
$livePid = (Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $PY } | Sort-Object StartTime | Select-Object -Last 1).Id
Log "LIVE_PID=$livePid"

Log "TIP: Tail logs with:"
Log "  Get-Content -Wait -Tail 60 `"$OUT`""
Log "  Get-Content -Wait -Tail 60 `"$ERR`""






