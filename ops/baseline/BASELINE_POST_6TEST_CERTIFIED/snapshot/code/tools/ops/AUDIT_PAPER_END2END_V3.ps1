param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$rep = Join-Path $ops ("AUDIT_REPORT_V3_{0}.txt" -f $ts)

$findings = New-Object System.Collections.Generic.List[string]
function AddFinding([string]$s){ $findings.Add($s) | Out-Null }
function WriteSection([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value ("`r`n=== {0} ===" -f $s) }
function WriteLine([string]$s){ Add-Content -Encoding UTF8 -Path $rep -Value $s }

WriteLine "AUDIT_TS=$ts"
WriteLine "PROJECT_ROOT=$ProjectRoot"
WriteLine "RUNROOT=$RunRoot"

# 0) Core files
WriteSection "FILES"
$req = @(
  "tools\profiles\paper.profile.json",
  "tools\RUN_PAPER_SHADOW_CANON_V1.ps1",
  "tools\PRECHECK_PAPER_PROFILE_V1.ps1",
  "tools\FREEZE_PAPER_PROFILE_V1.ps1",
  "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1",
  "tools\paper\POLL_PAPER_ORDERS_V1.ps1",
  "tools\paper\RECON_PAPER_V1.ps1",
  "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1",
  "tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1",
  "tools\analytics\money_machine_daily.py",
  "tools\analytics\weekly_review.py",
  "tools\analytics\realized_kpi_from_ledger.py"
)
foreach($r in $req){
  $p = Join-Path $ProjectRoot $r
  if(Test-Path $p){ WriteLine "OK_FILE=$r" } else { AddFinding "FAIL MISSING_FILE=$r"; WriteLine "FAIL MISSING_FILE=$r" }
}

# 1) Parse key PS files
WriteSection "PARSE_PS"
$psFiles = @(
  "tools\RUN_PAPER_SHADOW_CANON_V1.ps1",
  "tools\PRECHECK_PAPER_PROFILE_V1.ps1",
  "tools\FREEZE_PAPER_PROFILE_V1.ps1",
  "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1",
  "tools\paper\POLL_PAPER_ORDERS_V1.ps1",
  "tools\paper\RECON_PAPER_V1.ps1",
  "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1",
  "tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1"
)
foreach($rel in $psFiles){
  $f = Join-Path $ProjectRoot $rel
  if(!(Test-Path $f)){ continue }
  try { [ScriptBlock]::Create((Get-Content -Raw -Encoding UTF8 $f)) | Out-Null; WriteLine "PARSE_OK=$rel" }
  catch { AddFinding "FAIL PARSE=$rel"; WriteLine "FAIL PARSE=$rel" }
}

# 2) Python compile (best effort)
WriteSection "PY_COMPILE"
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(Test-Path $py){
  $pyFiles = @("tools\analytics\money_machine_daily.py","tools\analytics\weekly_review.py","tools\analytics\realized_kpi_from_ledger.py")
  foreach($rel in $pyFiles){
    $f = Join-Path $ProjectRoot $rel
    if(!(Test-Path $f)){ continue }
    & $py -m py_compile $f
    if($LASTEXITCODE -ne 0){ AddFinding "FAIL PY_COMPILE=$rel"; WriteLine "FAIL PY_COMPILE=$rel" } else { WriteLine "PY_COMPILE_OK=$rel" }
  }
} else {
  WriteLine "PY_COMPILE=SKIP(.venv missing)"
}

# 3) Config gates now
WriteSection "CONFIG_GATES"
$val = Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"
try{
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $val -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null
  WriteLine ("CONFIG_GATES_EXIT=" + $LASTEXITCODE)
  if($LASTEXITCODE -ne 0){ AddFinding ("FAIL CONFIG_GATES_EXIT=" + $LASTEXITCODE) }
} catch {
  AddFinding ("FAIL CONFIG_GATES_EXC=" + $_.Exception.Message)
  WriteLine ("FAIL CONFIG_GATES_EXC=" + $_.Exception.Message)
}

# 4) Tasks + freeze stuck detection
WriteSection "TASKS"
$tasks=@("ORG_BOT_PAPER_RUNNER","ORG_BOT_PAPER_WATCHDOG","ORG_BOT_PAPER_FREEZE","ORG_BOT_PAPER_EXECUTOR","ORG_BOT_PAPER_ORDER_POLL","ORG_BOT_PAPER_WEEKLY_REVIEW")
foreach($t in $tasks){
  try{
    $st = Get-ScheduledTask -TaskName $t -ErrorAction Stop
    $si = Get-ScheduledTaskInfo -TaskName $t
    WriteLine ("TASK_OK name={0} state={1} last={2} result={3} next={4}" -f $t,$st.State,$si.LastRunTime,$si.LastTaskResult,$si.NextRunTime)

    if($t -eq "ORG_BOT_PAPER_EXECUTOR"){
      $a = ($st.Actions | Select-Object -First 1)
      $args = [string]$a.Arguments
      if($args -notmatch '\-DryRun\s+1'){ AddFinding "FAIL EXECUTOR_NOT_DRYRUN1"; WriteLine "FAIL EXECUTOR_NOT_DRYRUN1" } else { WriteLine "OK_EXECUTOR_DRYRUN1=1" }
    }

    if($t -eq "ORG_BOT_PAPER_FREEZE" -and $st.State -eq "Running"){
      $ageMin = [int]((Get-Date) - $si.LastRunTime).TotalMinutes
      WriteLine ("FREEZE_RUNNING_AGE_MIN={0}" -f $ageMin)
      if($ageMin -ge 20){ AddFinding ("WARN FREEZE_STUCK_POSSIBLE age_min=" + $ageMin); WriteLine ("WARN FREEZE_STUCK_POSSIBLE age_min=" + $ageMin) }
    }
  } catch {
    AddFinding ("FAIL TASK_MISSING=" + $t)
    WriteLine ("FAIL TASK_MISSING=" + $t)
  }
}

# 5) Freeze wrapper marker sanity (must be 1 each)
WriteSection "FREEZE_MARKERS"
$fw = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V1.ps1"
function CountMarker([string]$path,[string]$marker){
  if(!(Test-Path $path)){ return -1 }
  $t = Get-Content -Raw -Encoding UTF8 $path
  return ([regex]::Matches($t,[regex]::Escape($marker))).Count
}
$needMarkers = @(
  "CONFIG_GATES_FREEZE_V1",
  "REALIZED_KPI_FREEZE_V1",
  "POST_FREEZE_INCLUDE_ANALYTICS_LEDGER_V2",
  "POST_FREEZE_INCLUDE_CONFIG_GATES_V1",
  "QC_FAIL_KILLSWITCH_V1",
  "POLICY_SNAPSHOT_AFTER_ISO_DAY_USED_V5",
  "POLICY_SNAPSHOT_COPY_INTO_BACKUP_V1"
)
foreach($m in $needMarkers){
  $c = CountMarker $fw $m
  WriteLine ("MARKER {0} count={1}" -f $m,$c)
  if($c -eq 0){ AddFinding ("FAIL MISSING_MARKER=" + $m) }
  if($c -gt 1){ AddFinding ("WARN DUP_MARKER=" + $m) }
}

# 6) Latest Freeze OUT includes policy OK + evidence contains policy
WriteSection "LATEST_FREEZE_EVIDENCE"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
if($fo){
  WriteLine ("LAST_FREEZE_OUT=" + $fo.FullName)
  $pol = Select-String -Path $fo.FullName -Pattern 'POLICY_SNAPSHOT_WRITER_OK=|POLICY_SNAPSHOT_COPIED=' -ErrorAction SilentlyContinue
  if($pol){ foreach($x in $pol){ WriteLine ("OUT_LINE=" + $x.Line.Trim()) } } else { AddFinding "WARN NO_POLICY_LINES_IN_OUT"; WriteLine "WARN NO_POLICY_LINES_IN_OUT" }
} else {
  AddFinding "FAIL NO_FREEZE_OUT"
  WriteLine "FAIL NO_FREEZE_OUT"
}

$bk = Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
if($bk){
  WriteLine ("LATEST_BACKUP=" + $bk.FullName)
  $ymd=$null
  if($bk.Name -match '^FREEZE_BACKUP_(\d{8})_'){ $ymd=$matches[1] }
  WriteLine ("BACKUP_YMD=" + $ymd)
  $need = @("QC_$ymd.txt","CONFIG_GATES_$ymd.txt","KPI_$ymd.json","LEDGER_SIM_$ymd.jsonl","RECON_SIM_$ymd.json","REALIZED_KPI_$ymd.json","REALIZED_KPI_$ymd.md","POLICY_SNAPSHOT_$ymd.md","POLICY_SNAPSHOT_$ymd.json")
  foreach($n in $need){
    $pp = Join-Path $bk.FullName $n
    if(Test-Path $pp){ WriteLine ("OK_EVID=" + $n) } else { AddFinding ("FAIL MISSING_EVID=" + $n); WriteLine ("FAIL MISSING_EVID=" + $n) }
  }
} else {
  AddFinding "FAIL NO_FREEZE_BACKUP_DIR"
  WriteLine "FAIL NO_FREEZE_BACKUP_DIR"
}

# Summary
WriteSection "SUMMARY"
WriteLine ("FINDINGS_COUNT=" + $findings.Count)
if($findings.Count -gt 0){
  foreach($f in $findings){ WriteLine $f }
  WriteLine "AUDIT_RESULT=FAIL_OR_WARN"
} else {
  WriteLine "AUDIT_RESULT=PASS"
}
"REPORT_PATH=$rep" | Out-Host
Get-Content $rep -Tail 180 | Out-Host
