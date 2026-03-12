param(
  [int]$Force = 0  # 1 = if lock exists, override (use only if you are sure old run is dead)
)

$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$PY="$ROOT\.venv\Scripts\python.exe"
$OPS="$ROOT\logs\ops"
$LOCKDIR="$ROOT\logs\locks"
$LOCK=Join-Path $LOCKDIR "RUN_SHADOW.lock"
$ENVPS1="C:\alpaca-bot\secrets\alpaca_env.ps1"

function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

New-Item -ItemType Directory -Force -Path $OPS | Out-Null
New-Item -ItemType Directory -Force -Path $LOCKDIR | Out-Null

# Lock (project-only)
if ((Test-Path $LOCK) -and ($Force -ne 1)) {
  $msg = Get-Content $LOCK -ErrorAction SilentlyContinue | Select-Object -First 3
  Log "BLOCK: lock exists ($LOCK). Bot already running? Lock head:"
  $msg | ForEach-Object { Log ("  " + $_) }
  exit 0
}

# Write lock
$lockBody = @(
  "ts=" + (Get-Date -Format s),
  "user=" + $env:USERNAME,
  "host=" + $env:COMPUTERNAME,
  "root=" + $ROOT
)
$lockBody | Set-Content -Encoding UTF8 -Path $LOCK

try {
  Set-Location $ROOT
  $env:PYTHONPATH = $ROOT

  # secrets
  if(!(Test-Path $ENVPS1)){ throw "Missing secrets file: $ENVPS1" }
  . $ENVPS1

  # strategy toggles
  $env:TBOT_MVP="1"
  $env:TBOT_S01_ENABLE="1"
  $env:TBOT_S11_ENABLE="1"
  $env:TBOT_ENABLE_S01_LOGIC="1"

  # pricing knobs
  $env:TBOT_SHADOW_PRICE_MODE="last"
  $env:TBOT_SHADOW_RR="2.0"
  $env:TBOT_SHADOW_STOP_PCT="0.003"

  $ts=(Get-Date -Format "yyyyMMdd_HHmmss")
  $OUT="$OPS\LIVE_OUT_$ts.txt"
  $ERR="$OPS\LIVE_ERR_$ts.txt"

  Log "ROOT=$ROOT"
  Log "PY=$PY"
  Log "OUT=$OUT"
  Log "ERR=$ERR"
  Log "START LIVE shadow..."

  Start-Process -FilePath $PY -ArgumentList @(
    "-u","-m","tbot.main",
    "--run","--iters","999999","--sleep","0.25",
    "--shadow",
    "--meta", (Join-Path $ROOT "logs\meta.jsonl"),
    "--announce", (Join-Path $ROOT "logs\announce.log"),
    "--gate_min_rr","1.0",
    "--gate_min_conf","0.0",
    "--gate_cooldown_sec","180",
    "--gate_max_plans_per_day","60",
    "--gate_max_risk_usd","500"
  ) -WorkingDirectory $ROOT -RedirectStandardOutput $OUT -RedirectStandardError $ERR | Out-Null

  Start-Sleep -Seconds 2
  $livePid = (Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $PY } | Sort-Object StartTime | Select-Object -Last 1).Id
  Log "LIVE_PID=$livePid"
}
finally {
  # NOTE: We do NOT remove lock immediately because process is now detached.
  # Lock will be removed by end-of-day tool, or you can clear it manually if needed.
  Log "LOCK_LEFT_IN_PLACE=$LOCK"
}
