param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$Iters = 999999,
  [double]$Sleep = 0.25,
  [string]$S01MinStrength = "0.45",
  [string]$ShadowPriceMode = "last",
  [string]$ShadowStopPct   = "0.003",
  [string]$ShadowRR        = "2.0"
)

$ErrorActionPreference = "Stop"
Set-Location $Root

# Kill stale python
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force

# Pre-flight + secrets + shadow env
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "tools\ops\TBOT_PreFlight.ps1") `
  -Root $Root -LoadSecrets `
  -ShadowPriceMode $ShadowPriceMode -ShadowStopPct $ShadowStopPct -ShadowRR $ShadowRR

# Strategy env (session-only)
$env:TBOT_ENABLE_S01_LOGIC = "1"
$env:TBOT_S01_MIN_STRENGTH = $S01MinStrength

# Logs
$OpsLogDir = Join-Path $Root "logs\ops"
New-Item -ItemType Directory -Force $OpsLogDir | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $OpsLogDir ("LIVE_OUT_{0}.txt" -f $Stamp)

Write-Host "RUNNING..."
Write-Host ("OUT={0}" -f $out)

python -m tbot.main --run --iters $Iters --sleep $Sleep --shadow `
  --meta (Join-Path $Root "logs\meta.jsonl") `
  --announce (Join-Path $Root "logs\announce.log") `
  --sim_in_session 1 --sim_pre_close 0 `
  --gate_max_plans_per_day 9999 --gate_cooldown_sec 5 `
  2>&1 | Tee-Object -FilePath $out
