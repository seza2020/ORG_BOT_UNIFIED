param([string]$Root = "C:\alpaca-bot\org_bot")
$ErrorActionPreference = "Stop"
Set-Location $Root

$OpsLog = Get-ChildItem (Join-Path $Root "logs\ops\LIVE_OUT_*.txt") -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1

$Plans = Join-Path $Root "logs\shadow_plans.jsonl"

Write-Host ("OPS_LOG={0}" -f ($OpsLog.FullName)) -ForegroundColor Cyan
Write-Host ("PLANS={0}" -f $Plans) -ForegroundColor Cyan

if (Test-Path $Plans) {
  $it = Get-Item $Plans
  Write-Host ("shadow_plans len={0} lastWrite={1}" -f $it.Length, $it.LastWriteTime)
  Write-Host "=== Tail shadow_plans (last 5) ==="
  Get-Content $Plans -Tail 5
} else {
  Write-Host "shadow_plans.jsonl not found"
}

if ($OpsLog) {
  Write-Host "=== Ops highlights (last 120 matches) ==="
  Select-String -Path $OpsLog.FullName -Pattern "shadow_plan|shadow_accept|APCA_KEYS_MISSING|ImportError|Traceback|Exception" |
    Select-Object -Last 120 | ForEach-Object { $_.Line }
} else {
  Write-Host "No LIVE_OUT logs found"
}
