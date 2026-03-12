param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$EverySec=60
)
$ErrorActionPreference="Continue"

$clean = Join-Path $Root "tools\ops\RUN_PAPER_CLEAN_START_V3.ps1"
$verify= Join-Path $Root "tools\ops\VERIFY_PAPER_V2.ps1"

"=== WATCHDOG_METAHB_LOOP_V1 START ==="
"Root=$Root"
"RunRoot=$RunRoot"
"EverySec=$EverySec"
while($true){
  try{
    $out = & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -Root $Root -RunRoot $RunRoot -MetaSlaSec 20 -HbSlaSec 20
    $metaOk = ($out | Select-String -SimpleMatch "META_OK=1") -ne $null
    $hbOk   = ($out | Select-String -SimpleMatch "HB_OK=1") -ne $null
    if(-not $metaOk -or -not $hbOk){
      "STALL => RESTART (clean start)"
      & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $clean -Root $Root -RunRoot $RunRoot -WarmupSec 10
    }
  }catch{
    $_ | Out-Host
  }
  Start-Sleep -Seconds $EverySec
}
