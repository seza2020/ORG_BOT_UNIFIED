$ErrorActionPreference="Stop"

function Log([string]$m){
  $ts = (Get-Date).ToString("HH:mm:ss")
  Write-Host "[$ts] $m"
}

$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"
$OPS="$ROOT\logs\ops"
$SP="$ROOT\logs\shadow_plans.jsonl"

New-Item -ItemType Directory -Force -Path $OPS | Out-Null

# Kill ONLY venv python processes for this project (avoid killing system python)
$procs = Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $PY }
if($procs){
  foreach($p in $procs){
    Log ("KILL PID=" + $p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
}

# Working dir + base env
Set-Location -LiteralPath $ROOT

# Secrets (APCA keys, etc.)
. "C:\alpaca-bot\secrets\alpaca_env.ps1"

# Shadow-only toggles (must reflect in logs: mvp_env='1' and enable=1)
$env:PYTHONPATH = $ROOT
$env:TBOT_MVP = "1"
$env:TBOT_S01_ENABLE = "1"
$env:TBOT_S11_ENABLE = "1"

# Shadow pricing knobs
$env:TBOT_SHADOW_PRICE_MODE = "last"
$env:TBOT_SHADOW_RR = "2.0"
$env:TBOT_SHADOW_STOP_PCT = "0.003"

# Log files
$ts=(Get-Date -Format "yyyyMMdd_HHmmss")
$LIVE_OUT="$OPS\LIVE_OUT_$ts.txt"
$LIVE_ERR="$OPS\LIVE_ERR_$ts.txt"

Log "ROOT=$ROOT"
Log "PY=$PY"
Log "PYTHONPATH=$env:PYTHONPATH"
Log "TBOT_MVP=$env:TBOT_MVP  TBOT_S01_ENABLE=$env:TBOT_S01_ENABLE  TBOT_S11_ENABLE=$env:TBOT_S11_ENABLE"
Log "LIVE_OUT=$LIVE_OUT"
Log "LIVE_ERR=$LIVE_ERR"

# Quick import proof (ensures this process can see tbot)
& $PY -c "import tbot; import tbot.runtime.orchestrator as o; print('IMPORT_OK', o.__file__)" 2>$null
if($LASTEXITCODE -ne 0){ throw "IMPORT_FAILED" }

# Launch LIVE shadow runner
$arg = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep","0.25",
  "--shadow",
  "--gate_min_rr","1.0",
  "--gate_min_conf","0.0",
  "--gate_cooldown_sec","20",
  "--gate_max_plans_per_day","50",
  "--gate_max_risk_usd","500"
)

Log ("CMD=" + $PY + " " + ($arg -join " "))

Start-Process -FilePath $PY -ArgumentList $arg -WorkingDirectory $ROOT -RedirectStandardOutput $LIVE_OUT -RedirectStandardError $LIVE_ERR | Out-Null
Start-Sleep -Seconds 3

# Verify PID + verify env took effect by reading log patterns
$livePid = (Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $PY } | Sort-Object StartTime | Select-Object -Last 1).Id
Log ("LIVE_PID=" + $livePid)

Log "=== VERIFY (tail + S01DBG) ==="
if(Test-Path $LIVE_OUT){
  Get-Content -LiteralPath $LIVE_OUT -Tail 120 -ErrorAction SilentlyContinue
  $dbg = Select-String -LiteralPath $LIVE_OUT -Pattern "\[S01DBG\]" -ErrorAction SilentlyContinue | Select-Object -Last 5
  if($dbg){ $dbg | ForEach-Object { $_.Line } } else { Log "NO_S01DBG_LINES_YET" }
}
if(Test-Path $LIVE_ERR){
  $e = Get-Content -LiteralPath $LIVE_ERR -Tail 40 -ErrorAction SilentlyContinue
  if($e){ Log "=== LIVE_ERR_TAIL ==="; $e }
}

Log "DONE"
