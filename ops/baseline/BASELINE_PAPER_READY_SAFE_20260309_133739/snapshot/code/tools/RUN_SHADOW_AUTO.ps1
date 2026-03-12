param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$GateCooldownSec = 30,
  [int]$GateMaxPlansPerDay = 150,
  [int]$GateMaxRiskUsd = 500,
  [double]$GateMinRR = 1.0,
  [double]$GateMinConf = 0.0
)

$ErrorActionPreference="Stop"

# paths
$Py = Join-Path $Root ".venv\Scripts\python.exe"
$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"
New-Item -ItemType Directory -Force -Path $Ops | Out-Null

# 0) kill stale python
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# 1) cd + env
Set-Location $Root
$env:PYTHONPATH = $Root

# 2) secrets
. "C:\alpaca-bot\secrets\alpaca_env.ps1"

# 3) shadow env
$env:TBOT_MVP="1"
$env:TBOT_ENABLE_S01_LOGIC="1"
$env:TBOT_S11_ENABLE="1"
$env:TBOT_SHADOW_PRICE_MODE="last"
$env:TBOT_SHADOW_RR="2.0"
$env:TBOT_SHADOW_STOP_PCT="0.003"

# 4) rotate shadow plans (fresh day file)
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "tools\rotate_shadow_plans.ps1") -Root $Root

# 5) preflight: enforce venv python + import tbot
if (-not (Test-Path $Py)) { throw "Venv python not found: $Py" }
$exe = & $Py -c "import sys; print(sys.executable)"
if (-not $exe.ToLower().EndsWith("\.venv\scripts\python.exe")) {
  throw "Preflight failed: not using venv python. exe=$exe"
}
& $Py -c "import tbot; import tbot.main; print('preflight_ok')"

# 6) run
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $Ops ("LIVE_OUT_{0}.txt" -f $stamp)
$err = Join-Path $Ops ("LIVE_ERR_{0}.txt" -f $stamp)

$args = @(
  "-m","tbot.main",
  "--shadow",
  "--gate_min_rr", [string]$GateMinRR,
  "--gate_min_conf", [string]$GateMinConf,
  "--gate_cooldown_sec", [string]$GateCooldownSec,
  "--gate_max_plans_per_day", [string]$GateMaxPlansPerDay,
  "--gate_max_risk_usd", [string]$GateMaxRiskUsd
)

Write-Host "RUN_SHADOW_AUTO..."
Write-Host ("PY=" + $exe)
Write-Host ("OUT=" + $out)
Write-Host ("ERR=" + $err)

& $Py @args 1> $out 2> $err

# 7) post QC: scan ALL outs/errs for today
$date = Get-Date -Format "yyyyMMdd"
$qc = & $Py (Join-Path $Root "tools\qc_ops_all.py") --root $Root --date $date
exit $LASTEXITCODE
