param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [int]$EverySec = 60
)

$ErrorActionPreference="Stop"
$wd = Join-Path $Root "tools\ops\WATCHDOG_META_STALL_AUTOFIX_V1.ps1"

"=== WATCHDOG_LOOP START ===" | Out-Host
"Root=$Root" | Out-Host
"RunRoot=$RunRoot" | Out-Host
"WD=$wd" | Out-Host
"EverySec=$EverySec" | Out-Host

while($true){
  try{
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $wd -Root $Root -RunRoot $RunRoot
  } catch {
    $_ | Out-Host
  }
  Start-Sleep -Seconds $EverySec
}
