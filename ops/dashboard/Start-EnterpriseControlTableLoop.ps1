param(
  [int]$IntervalSeconds = 60
)

$ErrorActionPreference = "Continue"
$gen = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\dashboard\Generate-EnterpriseControlTable.ps1"

if (!(Test-Path $gen)) {
  throw "GENERATOR_NOT_FOUND=$gen"
}

Write-Host "ENTERPRISE_CONTROL_LOOP_STARTED"
Write-Host "GENERATOR=$gen"
Write-Host "INTERVAL_SECONDS=$IntervalSeconds"

while ($true) {
  try {
    & $gen
  } catch {
    Write-Host ("GENERATOR_ERROR=" + $_.Exception.Message)
  }
  Start-Sleep -Seconds $IntervalSeconds
}
