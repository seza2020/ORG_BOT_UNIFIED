param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day  = ""
)

$ErrorActionPreference="Continue"

$orig = Join-Path $Root "tools\freeze_today_enterprise.ps1"
if(!(Test-Path $orig)){ throw "Missing: $orig" }

# Run original freeze (forward args)
if([string]::IsNullOrWhiteSpace($Day)){
  pwsh -NoProfile -ExecutionPolicy Bypass -File $orig -Root $Root
} else {
  pwsh -NoProfile -ExecutionPolicy Bypass -File $orig -Root $Root -Day $Day
}
$code = $LASTEXITCODE

# Find latest backup folder + QC result
$ops = Join-Path $Root "logs\ops"
$bk  = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Desc | Select-Object -First 1

if($bk){
  $qc = Get-ChildItem $bk.FullName -Filter "QC_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if($qc){
    $txt = Get-Content $qc.FullName -ErrorAction SilentlyContinue
    $qcLine = $txt | Where-Object { $_ -like "QC_RESULT=*" } | Select-Object -First 1
    $qcResult = ""
    if($qcLine){ $qcResult = $qcLine -replace "^QC_RESULT=","" }
    if($qcResult){ Write-Host ("SAFE_QC_RESULT=" + $qcResult) }

    # downgrade WARN to exit 0 (keep FAIL as non-zero)
    if($code -ne 0 -and $qcResult -eq "WARN"){
      Write-Host "SAFE_DOWNGRADE_EXITCODE: WARN -> 0"
      exit 0
    }
  }
}

exit $code
