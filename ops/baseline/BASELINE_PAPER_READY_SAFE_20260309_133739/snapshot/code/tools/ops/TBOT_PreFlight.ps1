param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [switch]$LoadSecrets,
  [string]$ShadowPriceMode = "last",
  [string]$ShadowStopPct   = "0.003",
  [string]$ShadowRR        = "2.0"
)

$ErrorActionPreference = "Stop"
Set-Location $Root

Write-Host "=== 1) Python sanity ==="
python -V
python -c "import sys; print('exe=',sys.executable)"

Write-Host "=== 2) Compile critical modules ==="
python -m py_compile ".\tbot\runtime\shadow_pricing.py"
if ($LASTEXITCODE -ne 0) { throw "py_compile shadow_pricing failed" }

python -m py_compile ".\tbot\runtime\orchestrator.py"
if ($LASTEXITCODE -ne 0) { throw "py_compile orchestrator failed" }

Write-Host "=== 3) Verify exports ==="
python -c "import importlib; m=importlib.import_module('tbot.runtime.shadow_pricing'); print('compute_shadow_prices:', 'OK' if hasattr(m,'compute_shadow_prices') else 'MISSING'); print('price_shadow_plan:', 'OK' if hasattr(m,'price_shadow_plan') else 'MISSING')"

Write-Host "=== 4) Optional secrets check ==="
if ($LoadSecrets) {
  . "C:\alpaca-bot\secrets\alpaca_env.ps1"
  $k1 = Test-Path Env:APCA_API_KEY_ID
  $k2 = Test-Path Env:APCA_API_SECRET_KEY
  "{0,-18} {1}" -f "APCA_API_KEY_ID",     $k1
  "{0,-18} {1}" -f "APCA_API_SECRET_KEY", $k2
  if (-not $k1 -or -not $k2) { throw "APCA keys not loaded (env vars missing after sourcing secrets)" }
}

Write-Host "=== 5) Set shadow env (session-only) ==="
$env:TBOT_SHADOW_PRICE_MODE = $ShadowPriceMode
$env:TBOT_SHADOW_STOP_PCT   = $ShadowStopPct
$env:TBOT_SHADOW_RR         = $ShadowRR

"TBOT_SHADOW_PRICE_MODE","TBOT_SHADOW_STOP_PCT","TBOT_SHADOW_RR" |
  ForEach-Object {
    [pscustomobject]@{ Name = $_; Value = (Get-Item "Env:$_" -ErrorAction SilentlyContinue).Value }
  } | Format-Table -Auto

Write-Host "=== PRE-FLIGHT OK ===" -ForegroundColor Green
