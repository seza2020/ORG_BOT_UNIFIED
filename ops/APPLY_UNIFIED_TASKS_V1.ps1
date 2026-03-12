param(
  [string]$UnifiedRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED",

  # زمان‌ها (فعلاً می‌سازیم ولی Disabled می‌مانند)
  [string]$ShadowTime = "06:30",
  [string]$PaperTime  = "06:25",

  # اگر 1 شود، Taskهای جدید Enable می‌شوند
  [int]$EnableNewTasks = 0
)

$ErrorActionPreference="Stop"

function Find-Pwsh {
  $candidates = @(
    "$env:ProgramFiles\PowerShell\7\pwsh.exe",
    "$env:ProgramFiles\PowerShell\pwsh.exe"
  )
  foreach($p in $candidates){ if(Test-Path $p){ return $p } }
  $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
  if($cmd){ return $cmd.Source }
  return (Get-Command powershell.exe).Source
}

$pwsh = Find-Pwsh
$runProfile = Join-Path $UnifiedRoot "ops\RUN_PROFILE.ps1"
if(!(Test-Path $runProfile)){ throw "MISSING_RUNNER: $runProfile" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $UnifiedRoot ("ops\logs\TASK_UNIFY_{0}" -f $ts)
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "APPLY_UNIFIED_TASKS.log"

function Log([string]$s){
  $line = ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $s)
  $line | Tee-Object -FilePath $log -Append | Out-Host
}

Log "UnifiedRoot=$UnifiedRoot"
Log "pwsh=$pwsh"
Log "runProfile=$runProfile"
Log "ShadowTime=$ShadowTime PaperTime=$PaperTime EnableNewTasks=$EnableNewTasks"
Log "----"

# 1) Collect tasks that are likely relevant
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
  Where-Object { $_.TaskName -match '(?i)(^TBOT_|^ORG_BOT_|P200K|PAPER|SHADOW)' }

if(!$tasks){
  Log "NO_MATCHED_TASKS (nothing to disable/archive)"
} else {
  Log ("MATCHED_TASKS={0}" -f $tasks.Count)
}

# 2) Archive XML for all matched tasks
$xmlDir = Join-Path $logDir "task_xml"
New-Item -ItemType Directory -Force $xmlDir | Out-Null

foreach($t in ($tasks | Sort-Object TaskName)){
  $safe = ($t.TaskPath + $t.TaskName) -replace '[\\/:*?"<>|]', '_'
  $xmlPath = Join-Path $xmlDir ("{0}.xml" -f $safe)
  try {
    Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath | Out-File -Encoding UTF8 $xmlPath
    Log ("XML_EXPORTED: {0} -> {1}" -f ($t.TaskPath+$t.TaskName), $xmlPath)
  } catch {
    Log ("XML_EXPORT_FAIL: {0} err={1}" -f ($t.TaskPath+$t.TaskName), $_.Exception.Message)
  }
}

# 3) Disable legacy tasks (keep none; we want a clean single-runner world)
#    If you want to keep something, add to this allowlist.
$allow = @(
  "ORG_UNIFIED_SHADOW_RUN",
  "ORG_UNIFIED_PAPER_RUN"
)

foreach($t in ($tasks | Sort-Object TaskName)){
  if($allow -contains $t.TaskName){
    Log ("SKIP_DISABLE_ALLOWLIST: {0}" -f ($t.TaskPath+$t.TaskName))
    continue
  }
  try {
    Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath | Out-Null
    Log ("DISABLED: {0}" -f ($t.TaskPath+$t.TaskName))
  } catch {
    Log ("DISABLE_FAIL: {0} err={1}" -f ($t.TaskPath+$t.TaskName), $_.Exception.Message)
  }
}

# 4) Create new unified tasks (Disabled by default)
function Create-UnifiedTask([string]$name, [string]$timeHHmm, [string]$profile){
  $taskLogDir = Join-Path $UnifiedRoot "runtime\logs\tasks"
  New-Item -ItemType Directory -Force $taskLogDir | Out-Null
  $taskLog = Join-Path $taskLogDir ("{0}.log" -f $name)

  # Use -Command to tee output into a file, so we always have evidence.
  $cmd = "& `"$runProfile`" -Profile $profile *>> `"$taskLog`""
  $args = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`""

  # Create a weekday task at given time; run as current user; highest privileges.
  # NOTE: /RL HIGHEST may require admin (you are running as admin).
  $create = @(
    "/Create","/F",
    "/TN", $name,
    "/SC","WEEKLY",
    "/D","MON,TUE,WED,THU,FRI",
    "/ST",$timeHHmm,
    "/RL","HIGHEST",
    "/TR", "`"$pwsh`" $args"
  )

  Log ("CREATE_TASK: {0} profile={1} time={2}" -f $name,$profile,$timeHHmm)
  $out = & schtasks.exe @create 2>&1
  ($out | Out-String).TrimEnd() | ForEach-Object { if($_){ Log ("SCHTASKS: " + $_) } }

  # Set MultipleInstances=IgnoreNew for the new task (best-effort)
  try {
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable
    Set-ScheduledTask -TaskName $name -Settings $settings | Out-Null
    Log ("SETTINGS_OK IgnoreNew: \{0}" -f $name)
  } catch {
    Log ("SETTINGS_FAIL IgnoreNew: \{0} err={1}" -f $name, $_.Exception.Message)
  }

  # Disable by default unless requested
  if($EnableNewTasks -eq 1){
    try { Enable-ScheduledTask -TaskName $name | Out-Null; Log ("ENABLED: \{0}" -f $name) } catch { Log ("ENABLE_FAIL: \{0} err={1}" -f $name,$_.Exception.Message) }
  } else {
    try { Disable-ScheduledTask -TaskName $name | Out-Null; Log ("DISABLED_NEW_DEFAULT: \{0}" -f $name) } catch { Log ("DISABLE_NEW_FAIL: \{0} err={1}" -f $name,$_.Exception.Message) }
  }
}

# Remove existing unified tasks (replace cleanly)
foreach($n in @("ORG_UNIFIED_SHADOW_RUN","ORG_UNIFIED_PAPER_RUN")){
  try { schtasks.exe /Delete /TN $n /F 2>$null | Out-Null; Log ("DELETED_OLD_UNIFIED_TASK: \{0}" -f $n) } catch {}
}

Create-UnifiedTask -name "ORG_UNIFIED_SHADOW_RUN" -timeHHmm $ShadowTime -profile "SHADOW"
Create-UnifiedTask -name "ORG_UNIFIED_PAPER_RUN"  -timeHHmm $PaperTime  -profile "PAPER"

# 5) Summary
Log "---- SUMMARY ----"
foreach($n in @("ORG_UNIFIED_SHADOW_RUN","ORG_UNIFIED_PAPER_RUN")){
  try {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction Stop
    Log ("TASK_OK: \{0} State={1} MultipleInstances={2}" -f $n,$t.State,$t.Settings.MultipleInstances)
    Log ("ACTION: Execute={0} Args={1}" -f $t.Actions.Execute, $t.Actions.Arguments)
  } catch {
    Log ("TASK_MISSING_OR_ERROR: \{0} err={1}" -f $n,$_.Exception.Message)
  }
}

Log ("LOGDIR={0}" -f $logDir)
Log "DONE"
