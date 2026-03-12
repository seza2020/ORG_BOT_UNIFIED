& {
  $ErrorActionPreference="Stop"
  $ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
  $CODE=Join-Path $ROOT "code"
  $RUNROOT=Join-Path $ROOT "runtime\paper"
  $EXE=Join-Path $CODE "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"
  $ORCH=Join-Path $CODE "tbot\runtime\orchestrator.py"

  $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
  $ADIR=Join-Path $ROOT ("ops\audit\PAPER_PREFLIGHT_" + $stamp)
  New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

  function FAIL([string]$reason){
    $p=Join-Path $ADIR "FAIL.txt"
    $reason | Set-Content -LiteralPath $p -Encoding utf8
    Write-Host ("PREFLIGHT_FAIL=" + $reason)
    Write-Host ("AUDIT_DIR=" + $ADIR)
    exit 88
  }

  if(!(Test-Path -LiteralPath $ROOT)){ FAIL "ROOT_MISSING" }
  if(!(Test-Path -LiteralPath $CODE)){ FAIL "CODE_MISSING" }
  if(!(Test-Path -LiteralPath $RUNROOT)){ FAIL "RUNROOT_MISSING" }
  if(!(Test-Path -LiteralPath $EXE)){ FAIL "EXEC_MISSING" }
  if(!(Test-Path -LiteralPath $ORCH)){ FAIL "ORCH_MISSING" }

  $ops = Join-Path $RUNROOT "logs\ops"
  try { New-Item -ItemType Directory -Force -Path $ops | Out-Null } catch { FAIL ("OPS_DIR_CREATE_FAIL " + $_.Exception.Message) }
  $touch = Join-Path $ops ("preflight_touch_" + $stamp + ".txt")
  try { "ok" | Set-Content -LiteralPath $touch -Encoding utf8 } catch { FAIL ("OPS_DIR_NOT_WRITABLE " + $_.Exception.Message) }

  $raw = Get-Content -LiteralPath $EXE -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ FAIL "EXEC_EMPTY" }
  if($raw -notmatch "HARD_RISK_CEILING_BEGIN"){ FAIL "HARD_CEILING_NOT_INSTALLED" }

  $lp = Join-Path $RUNROOT "state\risk\risk_ledger.json"
  if(Test-Path -LiteralPath $lp){
    try {
      $null = Get-Content -LiteralPath $lp -Raw -Encoding utf8 | ConvertFrom-Json
      "LEDGER_OK" | Set-Content (Join-Path $ADIR "ledger_ok.txt") -Encoding utf8
    } catch {
      FAIL ("LEDGER_BAD_JSON " + $_.Exception.Message)
    }
  }

  try {
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId,CommandLine
    $procs | Export-Csv (Join-Path $ADIR "python_tbot_main.csv") -NoTypeInformation
    if(@($procs).Count -gt 1){ FAIL "MULTI_TBOT_MAIN_PROCS" }
  } catch {}

  Write-Host "PREFLIGHT=PASS"
  Write-Host ("AUDIT_DIR=" + $ADIR)
  Write-Host "NEXT=When market open: run guarded paper live; then TRACE_PAPER_LOG_DESTINATIONS"
}
