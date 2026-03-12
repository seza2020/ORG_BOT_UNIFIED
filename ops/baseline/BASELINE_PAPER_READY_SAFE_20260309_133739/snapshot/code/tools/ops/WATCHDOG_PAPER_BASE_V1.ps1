param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$EverySec=60
)
$ErrorActionPreference="Continue"

$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_BASE_V1.ps1"
$clean  = Join-Path $Root "tools\ops\CLEAN_START_PAPER_BASE_V1.ps1"

"=== WATCHDOG_BASE START ==="
"RunRoot=$RunRoot EverySec=$EverySec"

$failStreak = 0
while($true){
  try{
    $out = & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -RunRoot $RunRoot -MetaSlaSec 20 -HbSlaSec 20
    $metaOk = ($out | Select-String -SimpleMatch "META_OK=1") -ne $null
    $hbOk   = ($out | Select-String -SimpleMatch "HB_OK=1") -ne $null

    if($metaOk -and $hbOk){
      $failStreak = 0
    }else{
      $failStreak++
      "STALL failStreak=$failStreak"
      if($failStreak -ge 2){
        "RESTART => CLEAN_START_BASE"
        & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $clean -Root $Root -RunRoot $RunRoot -WarmupSec 10
        $failStreak = 0
      }
    }
  }catch{
    $_ | Out-Host
  }
  Start-Sleep -Seconds $EverySec
}
