param([string]$ProjectRoot="C:\alpaca-bot\org_bot")
$ErrorActionPreference="Stop"

$Profile = Join-Path $ProjectRoot "tools\profiles\paper.profile.json"
if(!(Test-Path $Profile)){ throw "MISSING_PROFILE=$Profile" }
$prof = Get-Content -Raw -Encoding UTF8 $Profile | ConvertFrom-Json
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "PROFILE_BAD: runroot empty" }

"RUNROOT=$RunRoot"

# ---- required files ----
$reqFiles = @(
  (Join-Path $ProjectRoot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $ProjectRoot "tools\PRECHECK_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V1.ps1"),
  (Join-Path $ProjectRoot "tools\analytics\money_machine_daily.py"),
  (Join-Path $ProjectRoot "tools\analytics\weekly_review.py"),
  (Join-Path $ProjectRoot "tools\analytics\ledger_recon_sim.py"),
  (Join-Path $ProjectRoot "tools\paper\ALPACA_PAPER_REST_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\PAPER_SMOKE_CHECK_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"),
  (Join-Path $ProjectRoot "tools\paper\POLL_PAPER_ORDERS_V1.ps1"),
  (Join-Path $ProjectRoot "tools\paper\RECON_PAPER_V1.ps1")
)
$missing=@()
foreach($p in $reqFiles){ if(!(Test-Path $p)){ $missing += "MISSING_FILE=$p" } }
if($missing.Count -gt 0){ $missing; throw "PREP_FAIL_MISSING_FILES" }
"FILES_OK=1"

# ---- required dirs ----
$reqDirs=@(
  (Join-Path $RunRoot "logs\ops"),
  (Join-Path $RunRoot "logs\analytics"),
  (Join-Path $RunRoot "logs\ledger"),
  (Join-Path $RunRoot "state")
)
foreach($d in $reqDirs){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
"DIRS_OK=1"

# ---- safety flags ----
$ks = Join-Path $RunRoot "KILL_SWITCH"
$en = Join-Path $RunRoot "EXECUTE_ENABLED"
"SAFETY_KILL_SWITCH_PRESENT=" + (Test-Path $ks)
"SAFETY_EXECUTE_ENABLED_PRESENT=" + (Test-Path $en)

# ---- tasks ----
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
    Get-ScheduledTask -TaskName $t -ErrorAction Stop | Out-Null
    $i = Get-ScheduledTaskInfo -TaskName $t
    "TASK_OK name=$t last=$($i.LastRunTime) result=$($i.LastTaskResult) next=$($i.NextRunTime)"
  } catch {
    "TASK_MISSING name=$t"
    throw "PREP_FAIL_TASK_MISSING=$t"
  }
}

# ---- ensure executor is SAFE (DryRun=1) ----
$act = (Get-ScheduledTask -TaskName "ORG_BOT_PAPER_EXECUTOR").Actions | Select-Object -First 1
$arg = [string]$act.Arguments
if($arg -notmatch '\-DryRun\s+1'){ throw "EXECUTOR_NOT_SAFE (expected -DryRun 1)" }
"EXECUTOR_SAFE_DRYRUN=1"

# ---- smoke check paper connectivity (does NOT print secrets) ----
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
  -File (Join-Path $ProjectRoot "tools\paper\PAPER_SMOKE_CHECK_V1.ps1") -ProjectRoot $ProjectRoot

# ---- helper toggles (enable/disable flag) ----
$enable = Join-Path $ProjectRoot "tools\paper\ENABLE_EXECUTE_FLAG_V1.ps1"
@"
param([string]`$RunRoot=`"$RunRoot`")
New-Item -ItemType File -Force -Path (Join-Path `$RunRoot 'EXECUTE_ENABLED') | Out-Null
'OK=EXECUTE_ENABLED_CREATED'
"@ | Set-Content -Encoding UTF8 -Path $enable

$disable = Join-Path $ProjectRoot "tools\paper\DISABLE_EXECUTE_FLAG_V1.ps1"
@"
param([string]`$RunRoot=`"$RunRoot`")
Remove-Item -Force -ErrorAction SilentlyContinue -Path (Join-Path `$RunRoot 'EXECUTE_ENABLED')
'OK=EXECUTE_ENABLED_REMOVED'
"@ | Set-Content -Encoding UTF8 -Path $disable

"OK=MONDAY_READY"
