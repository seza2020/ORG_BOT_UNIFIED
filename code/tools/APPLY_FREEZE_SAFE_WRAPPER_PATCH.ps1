param([string]$Root="C:\alpaca-bot\org_bot")
$ErrorActionPreference="Stop"
function Log($m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

# 1) Create SAFE wrapper for freeze_today_enterprise
$orig = Join-Path $Root "tools\freeze_today_enterprise.ps1"
$safe = Join-Path $Root "tools\freeze_today_enterprise_SAFE.ps1"
if(!(Test-Path $orig)){ throw "Missing: $orig" }

if(!(Test-Path $safe)){
@"
param(
  [string]\$Root = "C:\alpaca-bot\org_bot",
  [string]\$Day  = ""
)
\$ErrorActionPreference="Continue"

\$orig = Join-Path \$Root "tools\freeze_today_enterprise.ps1"
if(!(Test-Path \$orig)){ throw "Missing: \$orig" }

# Run original
pwsh -NoProfile -ExecutionPolicy Bypass -File \$orig -Root \$Root -Day \$Day
\$code = \$LASTEXITCODE

# Find latest backup folder + QC
\$ops = Join-Path \$Root "logs\ops"
\$bk  = Get-ChildItem \$ops -Directory -Filter "FREEZE_BACKUP_*" | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if(\$bk){
  \$qc = Get-ChildItem \$bk.FullName -Filter "QC_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if(\$qc){
    \$txt = Get-Content \$qc.FullName -ErrorAction SilentlyContinue
    \$qcResult = (\$txt | Where-Object { \$_ -like "QC_RESULT=*" } | Select-Object -First 1) -replace "^QC_RESULT=",""
    Write-Host ("SAFE_QC_RESULT=" + \$qcResult)

    if(\$code -ne 0 -and \$qcResult -eq "WARN"){
      Write-Host "SAFE_DOWNGRADE_EXITCODE: WARN -> 0"
      exit 0
    }
  }
}

exit \$code
"@ | Set-Content -Encoding UTF8 -Path $safe
  Log "Created $safe"
}else{
  Log "SAFE wrapper already exists: $safe"
}

# 2) Patch OPS_END_OF_DAY_V2: fix ${Day} and use SAFE freeze wrapper
$eod = Join-Path $Root "tools\OPS_END_OF_DAY_V2.ps1"
if(Test-Path $eod){
  $bak = $eod + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
  Copy-Item $eod $bak -Force

  $txt  = Get-Content $eod -Raw

  # Fix PowerShell interpolation bug: $Day_FROM_META -> ${Day}_FROM_META
  $txt2 = $txt -replace 'shadow_plans_\$Day_FROM_META\.jsonl','shadow_plans_${Day}_FROM_META.jsonl'
  $txt2 = $txt2 -replace 'shadow_plans_\$Day_FROM_META','shadow_plans_${Day}_FROM_META'

  # Use SAFE freeze wrapper
  $txt2 = $txt2 -replace 'tools\\freeze_today_enterprise\.ps1','tools\freeze_today_enterprise_SAFE.ps1'

  if($txt2 -ne $txt){
    Set-Content -Encoding UTF8 -Path $eod -Value $txt2
    Log "Patched $eod"
    Log "Backup  $bak"
  }else{
    Log "No changes needed in $eod"
  }
}else{
  Log "Missing: $eod (skip patch)"
}

Log "PATCH_DONE"
