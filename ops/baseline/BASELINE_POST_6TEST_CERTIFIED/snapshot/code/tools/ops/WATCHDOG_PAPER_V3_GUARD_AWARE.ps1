param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$EverySec=60,
  [int]$FailStreakToRestart=2
)
$ErrorActionPreference="Continue"

$verify = Join-Path $Root "tools\ops\VERIFY_PAPER_V3.ps1"
$clean  = Join-Path $Root "tools\ops\RUN_PAPER_CLEAN_START_BASELINE_V1.ps1"
$opsDir = Join-Path $RunRoot "logs\ops"

"=== WATCHDOG_GUARD_AWARE_V3 START ==="
"RunRoot=$RunRoot EverySec=$EverySec FailStreakToRestart=$FailStreakToRestart"

$failStreak = 0
while($true){
  try{
    $out = & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $verify -RunRoot $RunRoot -MetaSlaSec 30 -HbSlaSec 30

    $metaOk = ($out | Select-String -SimpleMatch "META_OK=1") -ne $null
    $hbOk   = ($out | Select-String -SimpleMatch "HB_OK=1") -ne $null

    # Detect BOOT_GUARD hard stop in latest managed stderr/out if present
    $lastErr = Get-ChildItem -ErrorAction SilentlyContinue $opsDir -Filter "*STDERR*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $guardTripped = $false
    if($lastErr -and (Test-Path -LiteralPath $lastErr.FullName)){
      $tail = Get-Content -LiteralPath $lastErr.FullName -Tail 120 -ErrorAction SilentlyContinue
      if($tail -match "$begin:math:display$BOOT\_GUARD$end:math:display$\s+HARD_STOP"){ $guardTripped = $true }
    }

    if($guardTripped){
      "NO_GO: BOOT_GUARD_HARD_STOP detected. NOT restarting until next day. lastErr={0}" -f ($lastErr.FullName ?? "-")
      Start-Sleep -Seconds $EverySec
      continue
    }

    if($metaOk -and $hbOk){
      $failStreak = 0
    }else{
      $failStreak++
      "STALL failStreak=$failStreak metaOk=$metaOk hbOk=$hbOk"
      if($failStreak -ge $FailStreakToRestart){
        "RESTART => CLEAN_START_BASELINE"
        & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $clean -Root $Root -RunRoot $RunRoot -WarmupSec 10
        $failStreak = 0
      }
    }
  }catch{
    $_ | Out-Host
  }
  Start-Sleep -Seconds $EverySec
}
