$ErrorActionPreference="Stop"

# Always run from project root so `tbot` imports work
Set-Location "C:\alpaca-bot\org_bot"

# Load secrets (dot-source)
$secrets="C:\alpaca-bot\secrets\alpaca_env.ps1"
if (-not (Test-Path $secrets)) { throw "Missing secrets file: $secrets" }
. $secrets

# Ensure symbol
$env:TBOT_SYMBOLS="SPY"

# Validate Alpaca keys
$need=@("APCA_API_KEY_ID","APCA_API_SECRET_KEY","APCA_API_BASE_URL")
$missing=@()
foreach ($k in $need) {
  $v = (Get-Item "Env:$k" -ErrorAction SilentlyContinue).Value
  if ([string]::IsNullOrWhiteSpace($v)) { $missing += $k }
}
if ($missing.Count -gt 0) { throw ("APCA_KEYS_MISSING: " + ($missing -join ",")) }

Write-Host ("PWD=" + (Get-Location).Path)
Write-Host ("TBOT_SYMBOLS=" + $env:TBOT_SYMBOLS)
Write-Host ("APCA_API_BASE_URL=" + $env:APCA_API_BASE_URL)
Write-Host "KEYS_OK=YES"

# Run test
python -m tbot.main --run --shadow --iters 120 --sleep 1 --sim_in_session 1 --sim_pre_close 0
exit $LASTEXITCODE
