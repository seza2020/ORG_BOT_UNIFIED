param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot",
  [string]$ProfilePath = "C:\alpaca-bot\org_bot\tools\profiles\paper.profile.json",
  [string]$RunnerPath  = "C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1",
  [string]$WatchdogPath= "C:\alpaca-bot\org_bot\tools\WATCHDOG_PAPER_PROFILE_V1.ps1",

  # زمان‌های پیشنهادی (Local machine time)
  [string]$RunnerDailyTime = "06:25",
  [string]$FreezeDailyTime = "13:05",

  # Freeze را اگر هنوز آماده نکردی، خاموش بگذار
  [int]$EnableFreezeTask = 0
)

$ErrorActionPreference="Stop"

if(!(Test-Path $ProfilePath)){ throw "MISSING_PROFILE=$ProfilePath" }
if(!(Test-Path $RunnerPath)){ throw "MISSING_RUNNER=$RunnerPath" }
if(!(Test-Path $WatchdogPath)){ throw "MISSING_WATCHDOG=$WatchdogPath" }

$prof = (Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json)
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "PROFILE_BAD: runroot empty" }

# Find pwsh.exe (PowerShell 7) or fallback to powershell.exe
$pwsh = $null
$pwshCandidates = @(
  "$env:ProgramFiles\PowerShell\7\pwsh.exe",
  "$env:ProgramFiles\PowerShell\pwsh.exe"
)
foreach($c in $pwshCandidates){ if(Test-Path $c){ $pwsh=$c; break } }
if(-not $pwsh){ $pwsh = (Get-Command powershell.exe).Source }

# Principal: run only when user is logged on (no password needed)
$userId = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest

# Common settings
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -DontStopIfGoingOnBatteries `
  -StartWhenAvailable `
  -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 8)

# ---- Task Names (Paper only) ----
$TRunner   = "ORG_BOT_PAPER_RUNNER"
$TWatchdog = "ORG_BOT_PAPER_WATCHDOG"
$TFreeze   = "ORG_BOT_PAPER_FREEZE"

# ---- Actions ----
$runnerArgs   = "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" -ProjectRoot `"$ProjectRoot`" -ProfilePath `"$ProfilePath`" -Force 1"
$watchdogArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$WatchdogPath`" -ProjectRoot `"$ProjectRoot`""

$actionRunner   = New-ScheduledTaskAction -Execute $pwsh -Argument $runnerArgs
$actionWatchdog = New-ScheduledTaskAction -Execute $pwsh -Argument $watchdogArgs

# ---- Triggers ----
# Runner: Daily at RunnerDailyTime + OnLogon (clean bootstrap)
$trRunnerDaily = New-ScheduledTaskTrigger -Daily -At $RunnerDailyTime
$trRunnerLogon = New-ScheduledTaskTrigger -AtLogOn

# Watchdog: every 1 minute (Daily trigger + repetition for 1 day; auto-renews daily)
$trWd = New-ScheduledTaskTrigger -Daily -At "00:00"
$trWd.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 1)).Repetition

# Freeze: daily at FreezeDailyTime (optional; requires your freeze script readiness)
$freezeScript = Join-Path $ProjectRoot "tools\freeze_today_enterprise.ps1"
$freezeArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$freezeScript`" -RunRoot `"$RunRoot`""
$actionFreeze = New-ScheduledTaskAction -Execute $pwsh -Argument $freezeArgs
$trFreezeDaily = New-ScheduledTaskTrigger -Daily -At $FreezeDailyTime

function UpsertTask($name, $action, $triggers){
  try { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
  $task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings $settings
  Register-ScheduledTask -TaskName $name -InputObject $task | Out-Null
  "TASK_UPSERTED=$name"
}

# Install/Update tasks
UpsertTask -name $TRunner   -action $actionRunner   -triggers @($trRunnerDaily,$trRunnerLogon) | Out-Host
UpsertTask -name $TWatchdog -action $actionWatchdog -triggers @($trWd) | Out-Host

if($EnableFreezeTask -eq 1){
  if(!(Test-Path $freezeScript)){ throw "MISSING_FREEZE_SCRIPT=$freezeScript" }
  # NOTE: freeze_today_enterprise.ps1 must support -RunRoot
  UpsertTask -name $TFreeze -action $actionFreeze -triggers @($trFreezeDaily) | Out-Host
} else {
  "TASK_SKIPPED=$TFreeze (EnableFreezeTask=0)" | Out-Host
}

# ---- VERIFY ----
$names = @($TRunner,$TWatchdog) + @($TFreeze)
foreach($n in $names){
  $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
  if($t){ "VERIFY_TASK_PRESENT=1 name=$n" } else { "VERIFY_TASK_PRESENT=0 name=$n" }
}

"VERIFY_USER=$userId"
"VERIFY_PWSH=$pwsh"
"VERIFY_RUNROOT=$RunRoot"
"OK=APPLY_SCHED_PAPER_PROFILE_DONE"

