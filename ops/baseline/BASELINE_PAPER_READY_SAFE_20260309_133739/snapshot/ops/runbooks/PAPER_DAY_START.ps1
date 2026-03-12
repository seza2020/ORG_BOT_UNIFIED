$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$PAPER_RUN="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\task_wrappers\ORG_UNIFIED_PAPER_RUN.ps1"
$PRECHECK="C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\PRECHECK_PAPER_PROFILE_V1.ps1"

Write-Host "=== PAPER_DAY_START ==="
Write-Host "ROOT=$ROOT"
Write-Host "PRECHECK=$PRECHECK"
Write-Host "RUN=$PAPER_RUN"

# 1) Precheck gate
& $PRECHECK
if($LASTEXITCODE -ne 0){ throw "PRECHECK_FAILED_EXITCODE=$LASTEXITCODE" }
Write-Host "PRECHECK=PASS"

# 2) Single PID guard (best-effort)
$procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" }
$cnt = @($procs).Count
Write-Host "TBOT_PY_COUNT=$cnt"
if($cnt -gt 1){
  $procs | Select-Object ProcessId,CommandLine | Format-Table -AutoSize | Out-String | Write-Host
  throw "DUAL_PID_DETECTED"
}

# 3) Run paper wrapper (foreground)
& $PAPER_RUN
Write-Host "PAPER_RUN_EXITCODE=$LASTEXITCODE"
