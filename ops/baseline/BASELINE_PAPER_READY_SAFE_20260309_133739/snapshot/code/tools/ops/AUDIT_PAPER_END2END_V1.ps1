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
function AddF([string]$s){ $findings.Add($s) | Out-Null }
function H([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value ("`r`n=== {0} ===" -f $s) }
function L([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value $s }

L "AUDIT_TS=$ts"
L "PROJECT_ROOT=$ProjectRoot"
L "RUNROOT=$RunRoot"

# --- 0) Basic existence ---
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
H "FILES"
foreach($p in $reqPaths){
  if(Test-Path $p){ L ("OK_FILE=" + $p) } else { AddF("FAIL MISSING_FILE=" + $p); L ("FAIL MISSING_FILE=" + $p) }
}

# --- 1) Parse checks (PS scripts) ---
H "PARSE_PS"
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
  try { [ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 $f)) | Out-Null; L ("PARSE_OK=" + $f) }
  catch { AddF("FAIL PARSE=" + $f); L ("FAIL PARSE=" + $f) }
}

# --- 2) Config Gates validation (today) ---
H "CONFIG_GATES_RUN"
$val = Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"
try{
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $val -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null
  L ("CONFIG_GATES_EXIT=" + $LASTEXITCODE)
  if($LASTEXITCODE -ne 0){ AddF("FAIL CONFIG_GATES_EXIT=" + $LASTEXITCODE) }
} catch {
  AddF("FAIL CONFIG_GATES_EXEC_EXCEPTION=" + $_.Exception.Message)
  L ("FAIL CONFIG_GATES_EXEC_EXCEPTION=" + $_.Exception.Message)
}

# --- 3) Scheduled Tasks presence + key arg checks ---
H "TASKS"
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
    L ("TASK_OK name={0} last={1} result={2} next={3}" -f $t,$si.LastRunTime,$si.LastTaskResult,$si.NextRunTime)
    if($t -eq "ORG_BOT_PAPER_EXECUTOR"){
      $a = ($st.Actions | Select-Object -First 1)
      $args = [string]$a.Arguments
      if($args -notmatch '\-DryRun\s+1'){ AddF("FAIL EXECUTOR_NOT_DRYRUN1"); L "FAIL EXECUTOR_NOT_DRYRUN1" } else { L "OK_EXECUTOR_DRYRUN1=1" }
      if($args -notmatch [regex]::Escape($RunRoot)){ AddF("WARN EXECUTOR_RUNROOT_MISMATCH"); L "WARN EXECUTOR_RUNROOT_MISMATCH" }
    }
  } catch {
    AddF("FAIL TASK_MISSING=" + $t)
    L ("FAIL TASK_MISSING=" + $t)
  }
}

# --- 4) Marker checks (no duplicates) ---
H "MARKERS"
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
  L ("MARKER {0} count={1} file={2}" -f $x.m,$c,$x.p)
  if($c -gt 1){ AddF("WARN DUP_MARKER=" + $x.m) }
  if($c -eq 0){ AddF("WARN MISSING_MARKER=" + $x.m) }
}

# --- 5) Latest FREEZE_BACKUP evidence completeness ---
H "EVIDENCE"
$bk = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if(!$bk){
  AddF("FAIL NO_FREEZE_BACKUP_DIR")
  L "FAIL NO_FREEZE_BACKUP_DIR"
} else {
  L ("LATEST_FREEZE_BACKUP=" + $bk.FullName)

  # infer ymd from folder name FREEZE_BACKUP_YYYYMMDD_...
  $ymd = $null
  if($bk.Name -match '^FREEZE_BACKUP_(\d{8})_'){ $ymd = $matches[1] }
  L ("BACKUP_YMD=" + $ymd)

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
    if(Test-Path $pp){ L ("OK_EVID=" + $n) } else { AddF("FAIL MISSING_EVID=" + $n); L ("FAIL MISSING_EVID=" + $n) }
  }
}

# --- Summary ---
H "SUMMARY"
L ("FINDINGS_COUNT=" + $findings.Count)
if($findings.Count -gt 0){
  foreach($f in $findings){ L $f }
  L "AUDIT_RESULT=FAIL_OR_WARN"
} else {
  L "AUDIT_RESULT=PASS"
}
"REPORT_PATH=$rep" | Out-Host
Get-Content $rep -Tail 120 | Out-Host
