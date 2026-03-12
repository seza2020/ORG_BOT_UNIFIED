param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)
$ErrorActionPreference="Stop"
$Logs = Join-Path $Root "logs"
$Arch = Join-Path $Logs "archive"
New-Item -ItemType Directory -Force -Path $Arch | Out-Null

$sp = Join-Path $Logs "shadow_plans.jsonl"
if (Test-Path $sp) {
  $len = (Get-Item $sp).Length
  if ($len -gt 0) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dst = Join-Path $Arch ("shadow_plans_{0}.jsonl" -f $stamp)
    Move-Item -Force $sp $dst
  } else {
    Remove-Item -Force $sp
  }
}
# create fresh file
New-Item -ItemType File -Force -Path $sp | Out-Null
