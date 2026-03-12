param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}

if(-not (Is-Admin)){
  throw "Run PowerShell as Administrator, then re-run this script."
}

# --- Paths (project-only) ---
$Pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $Pwsh)){
  $Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
}
if(!(Test-Path $Pwsh)){
  throw "pwsh not found. Install PowerShell 7 or fix path."
}

$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(!(Test-Path $Canon)){
  throw "Missing Canon runner: $Canon"
}

$EOD = Join-Path $Root "tools\OPS_END_OF_DAY_V2.ps1"
if(!(Test-Path $EOD)){
  throw "Missing EOD runner: $EOD"
}

# --- Backup task definitions (rollback safety) ---
$bkDir = Join-Path $Root ("logs\ops\tasks_backup_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Log "TASK_BACKUP_DIR=$bkDir"

function Backup-Task([string]$name){
  $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  if(!$t){ Log "SKIP backup: task not found ($name)"; return }
  $xml = Join-Path $bkDir ("{0}.xml" -f $name)
  Export-ScheduledTask -TaskName $name | Out-File -Encoding UTF8 $xml
  Log ("BACKED_UP=" + $xml)
}

Backup-Task "TBOT_RUN_SHADOW_DAILY_0630"
Backup-Task "TBOT_RUN_SHADOW_UI_0630"
Backup-Task "TBOT_Daily_R_Report"
Backup-Task "TBOT_END_OF_DAY_1305"

# --- Helper: set action safely ---
function Set-TaskActionFile([string]$taskName,[string]$filePath){
  $act = New-ScheduledTaskAction -Execute $Pwsh -Argument ("-NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $filePath)
  Set-ScheduledTask -TaskName $taskName -Action $act | Out-Null
  Log "ACTION_SET: $taskName -> FILE $filePath"
}

function Set-TaskActionCommand([string]$taskName,[string]$command){
  $act = New-ScheduledTaskAction -Execute $Pwsh -Argument ("-NoProfile -ExecutionPolicy Bypass -Command `"{0}`"" -f $command)
  Set-ScheduledTask -TaskName $taskName -Action $act | Out-Null
  Log "ACTION_SET: $taskName -> COMMAND"
}

# --- Helper: set settings (ignore new instance) ---
function Set-TaskIgnoreNew([string]$taskName){
  $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable
  Set-ScheduledTask -TaskName $taskName -Settings $settings | Out-Null
  Log "SETTINGS_SET: $taskName MultipleInstances=IgnoreNew"
}

# --- 1) TBOT_RUN_SHADOW_DAILY_0630 => Weekly Mon-Fri 06:30 + CANON_V2 + IgnoreNew + Enable ---
$task1 = Get-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" -ErrorAction SilentlyContinue
if($task1){
  $tr = New-ScheduledTaskTrigger -Weekly -At 6:30AM -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday
  Set-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" -Trigger $tr | Out-Null
  Log "TRIGGER_SET: TBOT_RUN_SHADOW_DAILY_0630 -> Weekly Mon-Fri 06:30"

  Set-TaskActionFile "TBOT_RUN_SHADOW_DAILY_0630" $Canon
  Set-TaskIgnoreNew "TBOT_RUN_SHADOW_DAILY_0630"

  Enable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Out-Null
  Log "ENABLED: TBOT_RUN_SHADOW_DAILY_0630"
}else{
  Log "SKIP: TBOT_RUN_SHADOW_DAILY_0630 not found"
}

# --- 2) TBOT_END_OF_DAY_1305 => Weekly Mon-Fri 13:05 + EOD_V2 with Day auto + IgnoreNew + Enable ---
$task2 = Get-ScheduledTask -TaskName "TBOT_END_OF_DAY_1305" -ErrorAction SilentlyContinue
if($task2){
  $tr2 = New-ScheduledTaskTrigger -Weekly -At 1:05PM -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday
  Set-ScheduledTask -TaskName "TBOT_END_OF_DAY_1305" -Trigger $tr2 | Out-Null
  Log "TRIGGER_SET: TBOT_END_OF_DAY_1305 -> Weekly Mon-Fri 13:05"

  # Compute Day at runtime (avoids hard-coded date)
  $cmd = "& `"$EOD`" -Root `"$Root`" -Day (Get-Date -Format yyyyMMdd) -StopBot 1"
  Set-TaskActionCommand "TBOT_END_OF_DAY_1305" $cmd
  Set-TaskIgnoreNew "TBOT_END_OF_DAY_1305"

  Enable-ScheduledTask -TaskName "TBOT_END_OF_DAY_1305" | Out-Null
  Log "ENABLED: TBOT_END_OF_DAY_1305"
}else{
  Log "SKIP: TBOT_END_OF_DAY_1305 not found"
}

# --- 3) Disable TBOT_RUN_SHADOW_UI_0630 (dup/legacy UI runner) ---
$taskUI = Get-ScheduledTask -TaskName "TBOT_RUN_SHADOW_UI_0630" -ErrorAction SilentlyContinue
if($taskUI){
  Disable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_UI_0630" | Out-Null
  Log "DISABLED: TBOT_RUN_SHADOW_UI_0630"
}

# --- 4) Disable TBOT_Daily_R_Report if it points to other project (alpaca-bt) ---
$taskR = Get-ScheduledTask -TaskName "TBOT_Daily_R_Report" -ErrorAction SilentlyContinue
if($taskR){
  $acts = $taskR.Actions | ForEach-Object { $_.Execute + " " + $_.Arguments } | Out-String
  if($acts -match "C:\\alpaca-bt\\"){
    Disable-ScheduledTask -TaskName "TBOT_Daily_R_Report" | Out-Null
    Log "DISABLED: TBOT_Daily_R_Report (belongs to C:\alpaca-bt\...)"
  }else{
    Log "KEEP: TBOT_Daily_R_Report (does not match C:\alpaca-bt\...)"
  }
}

# --- Final Verification ---
Log "=== VERIFY: TBOT_RUN_SHADOW_DAILY_0630 ==="
(Get-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630").Triggers | Format-List * | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Host
(Get-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630").Actions  | Format-List * | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Host
Get-ScheduledTaskInfo -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Format-List LastRunTime,NextRunTime,LastTaskResult

Log "=== VERIFY: TBOT_END_OF_DAY_1305 ==="
(Get-ScheduledTask -TaskName "TBOT_END_OF_DAY_1305").Triggers | Format-List * | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Host
(Get-ScheduledTask -TaskName "TBOT_END_OF_DAY_1305").Actions  | Format-List * | Out-String | ForEach-Object { $_.TrimEnd() } | Write-Host
Get-ScheduledTaskInfo -TaskName "TBOT_END_OF_DAY_1305" | Format-List LastRunTime,NextRunTime,LastTaskResult

Log "DONE"
