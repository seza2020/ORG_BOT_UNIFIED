& {
  $ErrorActionPreference="Stop"

  $ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
  $CODE=Join-Path $ROOT "code"
  $RUNROOT=Join-Path $ROOT "runtime\paper"
  $OPS=Join-Path $RUNROOT "logs\ops"
  $EXE=Join-Path $CODE "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"

  $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
  $ADIR=Join-Path $ROOT ("ops\audit\PREFLIGHT_HARDENED_" + $stamp)
  New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

  function FAIL([string]$reason){
    $reason | Set-Content (Join-Path $ADIR "FAIL.txt") -Encoding utf8
    Write-Host ("PREFLIGHT_HARDENED_FAIL=" + $reason)
    Write-Host ("AUDIT_DIR=" + $ADIR)
    exit 88
  }

  # 1) Must exist
  if(!(Test-Path -LiteralPath $ROOT)){ FAIL "ROOT_MISSING" }
  if(!(Test-Path -LiteralPath $CODE)){ FAIL "CODE_MISSING" }
  if(!(Test-Path -LiteralPath $RUNROOT)){ FAIL "RUNROOT_MISSING" }
  if(!(Test-Path -LiteralPath $EXE)){ FAIL "EXEC_MISSING" }

  # 2) ops dir writable
  try { New-Item -ItemType Directory -Force -Path $OPS | Out-Null } catch { FAIL ("OPS_DIR_CREATE_FAIL " + $_.Exception.Message) }
  try { "ok" | Set-Content (Join-Path $OPS ("hardened_touch_" + $stamp + ".txt")) -Encoding utf8 } catch { FAIL ("OPS_DIR_NOT_WRITABLE " + $_.Exception.Message) }

  # 3) Ensure hard ceiling installed
  $raw=Get-Content -LiteralPath $EXE -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ FAIL "EXEC_EMPTY" }
  if($raw -notmatch "HARD_RISK_CEILING_BEGIN"){ FAIL "HARD_CEILING_NOT_INSTALLED" }

  # 4) Ensure risk ledger json ok (if exists)
  $LEDGER=Join-Path $RUNROOT "state\risk\risk_ledger.json"
  if(Test-Path -LiteralPath $LEDGER){
    try { $null = Get-Content -LiteralPath $LEDGER -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { FAIL ("LEDGER_BAD_JSON " + $_.Exception.Message) }
  }

  # 5) Single instance check
  try {
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId,CommandLine
    $procs | Export-Csv (Join-Path $ADIR "python_tbot_main.csv") -NoTypeInformation
    if(@($procs).Count -gt 1){ FAIL "MULTI_TBOT_MAIN_PROCS" }
  } catch {}

  # 6) Evidence pack baseline
  try {
    Get-ChildItem -LiteralPath $OPS -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 80 FullName,Length,LastWriteTime |
      Export-Csv (Join-Path $ADIR "ops_files_head80.csv") -NoTypeInformation
  } catch {}

  Write-Host "PREFLIGHT_HARDENED=PASS"
  Write-Host ("AUDIT_DIR=" + $ADIR)
  Write-Host "NEXT=When market open: run RUN_PAPER_LIVE_10MIN_GUARDED then TRACE_PAPER_LOG_DESTINATIONS then rerun this for evidence."
}
