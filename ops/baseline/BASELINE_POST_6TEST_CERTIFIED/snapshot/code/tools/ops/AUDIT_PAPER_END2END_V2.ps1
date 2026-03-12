param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$rep = Join-Path $ops ("AUDIT_REPORT_{0}.txt" -f $ts)

$findings = New-Object System.Collections.Generic.List[string]
function AddFinding([string]$s){ $findings.Add($s) | Out-Null }
function WriteSection([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value ("`r`n=== {0} ===" -f $s) }
function WriteLine([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value $s }

WriteLine "AUDIT_TS=$ts"
WriteLine "PROJECT_ROOT=$ProjectRoot"
WriteLine "RUNROOT=$RunRoot"

# --- 0) Files exist ---
$reqPaths = @(
  (Join-Path $ProjectRoot "tools\profiles\paper.profile.json"),
  (Join-Path $ProjectRoot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $ProjectRoot "tools\PRECHECK_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"),
  (Join-Path $ProjectRoot "tools\paper\POLL_PAPER_ORDERS_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\RECON_PAPER_V1.ps1"),
  (Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"),
  (Join-Path $ProjectRoot "tools\analytics\money_machine_daily.py"),
  (Join-Path $ProjectRoot "tools\analytics\weekly_review.py"),
  (Join-Path $ProjectRoot "tools\analytics\realized_kpi_from_ledger.py")
)
WriteSection "FILES"
foreach($p in $reqPaths){
  if(Test-Path $p){ WriteLine ("OK_FILE=" + $p) } else { AddFinding("FAIL MISSING_FILE=" + $p); WriteLine ("FAIL MISSING_FILE=" + $p) }
}

# --- 1) Parse checks (PS scripts) ---
WriteSection "PARSE_PS"
$psFiles = @(
  (Join-Path $ProjectRoot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $ProjectRoot "tools\PRECHECK_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"),
  (Join-Path $ProjectRoot "tools\paper\POLL_PAPER_ORDERS_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\RECON_PAPER_V1.ps1")
)
foreach($f in $psFiles){
  if(!(Test-Path $f)){ continue }
  try { [ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 $f)) | Out-Null; WriteLine ("PARSE_OK=" + $f) }
  catch { AddFinding("FAIL PARSE=" + $f); WriteLine ("FAIL PARSE=" + $f) }
}

# --- 2) Config gates (today) ---
WriteSection "CONFIG_GATES_RUN"
$val = Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"
try{
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $val -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null
  WriteLine ("CONFIG_GATES_EXIT=" + $LASTEXITCODE)
  if($LASTEXITCODE -ne 0){ AddFinding("FAIL CONFIG_GATES_EXIT=" + $LASTEXITCODE) }
} catch {
  AddFinding("FAIL CONFIG_GATES_EXEC_EXCEPTION=" + $_.Exception.Message)
  WriteLine ("FAIL CONFIG_GATES_EXEC_EXCEPTION=" + $_.Exception.Message)
}

# --- 3) Scheduled tasks presence + key arg checks ---
WriteSection "TASKS"
$tasks=@(
  "ORG_BOT_PAPER_RUNNER",
  "ORG_BOT_PAPER_WATCHDOG",
  "ORG_BOT_PAPER_FREEZE",
  "ORG_BOT_PAPER_EXECUTOR",
  "ORG_BOT_PAPER_ORDER_POLL",
  "ORG_BOT_PAPER_WEEKLY_REVIEW"
)
foreach($t in $tasks){
  try{
    $st = Get-ScheduledTask -TaskName $t -ErrorAction Stop
    $si = Get-ScheduledTaskInfo -TaskName $t
    WriteLine ("TASK_OK name={0} last={1} result={2} next={3}" -f $t,$si.LastRunTime,$si.LastTaskResult,$si.NextRunTime)

    if($t -eq "ORG_BOT_PAPER_EXECUTOR"){
      $a = ($st.Actions | Select-Object -First 1)
      $args = [string]$a.Arguments
      if($args -notmatch '\-DryRun\s+1'){ AddFinding("FAIL EXECUTOR_NOT_DRYRUN1"); WriteLine "FAIL EXECUTOR_NOT_DRYRUN1" } else { WriteLine "OK_EXECUTOR_DRYRUN1=1" }
      if($args -notmatch [regex]::Escape($RunRoot)){ AddFinding("WARN EXECUTOR_RUNROOT_MISMATCH"); WriteLine "WARN EXECUTOR_RUNROOT_MISMATCH" }
    }
  } catch {
    AddFinding("FAIL TASK_MISSING=" + $t)
    WriteLine ("FAIL TASK_MISSING=" + $t)
  }
}

# --- 4) Marker duplication checks ---
WriteSection "MARKERS"
function CountMarker([string]$path,[string]$marker){
  if(!(Test-Path $path)){ return -1 }
  $t = Get-Content -Raw -Encoding UTF8 $path
  return ([regex]::Matches($t,[regex]::Escape($marker))).Count
}
$freeze = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V1.ps1"
$exec = Join-Path $ProjectRoot "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"
$runner = Join-Path $ProjectRoot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

$markers = @(
  @{p=$runner; m="CONFIG_GATES_RUNNER_V1"},
  @{p=$exec;   m="CONFIG_GATES_EXEC_V1"},
  @{p=$freeze; m="CONFIG_GATES_FREEZE_V1"},
  @{p=$freeze; m="REALIZED_KPI_FREEZE_V1"},
  @{p=$freeze; m="POST_FREEZE_INCLUDE_ANALYTICS_LEDGER_V2"},
  @{p=$freeze; m="POST_FREEZE_INCLUDE_CONFIG_GATES_V1"},
  @{p=$freeze; m="QC_FAIL_KILLSWITCH_V1"}
)
foreach($x in $markers){
  $c = CountMarker $x.p $x.m
  WriteLine ("MARKER {0} count={1} file={2}" -f $x.m,$c,$x.p)
  if($c -gt 1){ AddFinding("WARN DUP_MARKER=" + $x.m) }
  if($c -eq 0){ AddFinding("WARN MISSING_MARKER=" + $x.m) }
}

# --- 5) Latest FREEZE_BACKUP evidence completeness ---
WriteSection "EVIDENCE"
$bk = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if(!$bk){
  AddFinding("FAIL NO_FREEZE_BACKUP_DIR")
  WriteLine "FAIL NO_FREEZE_BACKUP_DIR"
} else {
  WriteLine ("LATEST_FREEZE_BACKUP=" + $bk.FullName)
  $ymd = $null
  if($bk.Name -match '^FREEZE_BACKUP_(\d{8})_'){ $ymd = $matches[1] }
  WriteLine ("BACKUP_YMD=" + $ymd)

  $need = @(
    "QC_$ymd.txt",
    "CONFIG_GATES_$ymd.txt",
    "KPI_$ymd.json",
    "LEDGER_SIM_$ymd.jsonl",
    "RECON_SIM_$ymd.json",
    "REALIZED_KPI_$ymd.json",
    "REALIZED_KPI_$ymd.md"
  )
  foreach($n in $need){
    $pp = Join-Path $bk.FullName $n
    if(Test-Path $pp){ WriteLine ("OK_EVID=" + $n) } else { AddFinding("FAIL MISSING_EVID=" + $n); WriteLine ("FAIL MISSING_EVID=" + $n) }
  }
}

# --- Summary ---
WriteSection "SUMMARY"
WriteLine ("FINDINGS_COUNT=" + $findings.Count)
if($findings.Count -gt 0){
  foreach($f in $findings){ WriteLine $f }
  WriteLine "AUDIT_RESULT=FAIL_OR_WARN"
} else {
  WriteLine "AUDIT_RESULT=PASS"
}
"REPORT_PATH=$rep" | Out-Host
Get-Content $rep -Tail 140 | Out-Host
