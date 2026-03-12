# File: tools/shadow_run.ps1
param(
  [int]$Iters = 400,
  [double]$Sleep = 0.5,
  [string]$Symbols = "SPY,QQQ",
  [double]$RiskUsd = 250.0,
  [double]$GateMinRR = 1.0,
  [double]$GateMinConf = 0.0,
  [int]$GateCooldownSec = 60,
  [int]$GateMaxPlansPerDay = 20,
  [double]$GateMaxRiskUsd = 500.0
)


# --- SESSION_GUARD_RTH_V1 (RTH only) ---
try {
  $nowLocal = Get-Date
  $tzET = [TimeZoneInfo]::FindSystemTimeZoneById("Eastern Standard Time")
  $nowET = [TimeZoneInfo]::ConvertTime($nowLocal, $tzET)

  # RTH window in ET: 09:30 - 16:00
  $startET = Get-Date -Date $nowET.Date.AddHours(9).AddMinutes(30)
  $endET   = Get-Date -Date $nowET.Date.AddHours(16).AddMinutes(0)

  if($nowET -lt $startET -or $nowET -gt $endET){
    $msg = ("[SESSION_GUARD] OUT_OF_SESSION: nowET={0} window=09:30-16:00 ET. Exiting 86." -f $nowET.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Host $msg
    $286
  }
} catch {
  # Fail-open: do not block run if timezone conversion fails
}
# --- SESSION_GUARD_RTH_V1 END ---


$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path (Resolve-Path ".\logs").Path ("shadow_runs\" + $ts)
New-Item -ItemType Directory -Force $outDir | Out-Null

$meta = Join-Path $outDir "meta.jsonl"
$ann  = Join-Path $outDir "announce.log"
$shadow = Join-Path $outDir "shadow_plans.jsonl"

# --- ENV: deterministic + enterprise toggles ---
$env:TBOT_ENV = "PAPER"
$env:TBOT_SYMBOLS = $Symbols

# Regime + Scorecard overlay enabled
$env:TBOT_REGIME_ENABLE = "1"

# Optional: set a default secondary alpha SID (can be changed per run)
# $env:TBOT_ALPHA_SECONDARY_SID = "S12"

# Strategy policy default (edit as needed)
# NOTE: keep S12/S08 disabled by default unless you are explicitly testing them.
$env:TBOT_STRATEGY_POLICY_JSON = '{
  "S01":{"enabled":true,"weight":1.0,"min_conf":0.0,"max_fires_per_day":10000,"max_accepts_per_day":10000,"cooldown_sec":0},
  "S11":{"enabled":true,"weight":1.0,"min_conf":0.0,"max_fires_per_day":10000,"max_accepts_per_day":10000,"cooldown_sec":0},
  "S12":{"enabled":false},
  "S08":{"enabled":false}
}'

Write-Host "OUTDIR=$outDir"
Write-Host "META=$meta"
Write-Host "ANN=$ann"
Write-Host "SHADOW=$shadow"
Write-Host "SYMBOLS=$Symbols  ITERS=$Iters  SLEEP=$Sleep"

# --- Run orchestrator (shadow only, no orders) ---
python -m tbot.main --run `
  --iters $Iters `
  --sleep $Sleep `
  --meta $meta `
  --announce $ann `
  --shadow `
  --shadow_path $shadow `
  --risk_usd $RiskUsd `
  --gate_min_rr $GateMinRR `
  --gate_min_conf $GateMinConf `
  --gate_cooldown_sec $GateCooldownSec `
  --gate_max_plans_per_day $GateMaxPlansPerDay `
  --gate_max_risk_usd $GateMaxRiskUsd

$rc = $LASTEXITCODE
Write-Host "EXITCODE(run)=$rc"

# --- Scorecard on this run ---
python .\tools\scorecard_daily.py --meta $meta
Write-Host "EXITCODE(scorecard)=$LASTEXITCODE"

# Clean up env vars that should not leak
Remove-Item Env:\TBOT_SYMBOLS -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_STRATEGY_POLICY_JSON -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_ALPHA_SECONDARY_SID -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_REGIME_ENABLE -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_ENV -ErrorAction SilentlyContinue

exit $rc




