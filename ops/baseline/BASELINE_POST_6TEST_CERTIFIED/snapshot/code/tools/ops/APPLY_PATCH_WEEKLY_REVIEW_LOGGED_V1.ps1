param([string]$ProjectRoot="C:\alpaca-bot\org_bot")
$ErrorActionPreference="Stop"

# RunRoot from profile
$Profile = Join-Path $ProjectRoot "tools\profiles\paper.profile.json"
$prof = Get-Content -Raw -Encoding UTF8 $Profile | ConvertFrom-Json
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "PROFILE_BAD: runroot empty" }

# Wrapper (logged)
$wrap = Join-Path $ProjectRoot "tools\analytics\RUN_WEEKLY_REVIEW_PAPER_V1.ps1"
@"
param(
  [string]`$ProjectRoot = `"$ProjectRoot`",
  [string]`$RunRoot = `"$RunRoot`"
)
`$ErrorActionPreference="Stop"
`$ops = Join-Path `$RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path `$ops | Out-Null
`$ts = Get-Date -Format "yyyyMMdd_HHmmss"
`$out = Join-Path `$ops ("WEEKLY_REVIEW_OUT_{0}.txt" -f `$ts)
`$err = Join-Path `$ops ("WEEKLY_REVIEW_ERR_{0}.txt" -f `$ts)

`$py = Join-Path `$ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path `$py)){ `$py = "python" }

`$wk = (Get-Date -Format 'yyyy') + 'W' + ([System.Globalization.ISOWeek]::GetWeekOfYear([datetime]::Now))
`$script = Join-Path `$ProjectRoot "tools\analytics\weekly_review.py"

& `$py `$script --runroot `$RunRoot --weeksuffix `$wk 1> `$out 2> `$err
"OK=WEEKLY_REVIEW_DONE weeksuffix=`$wk OUT=`$out ERR=`$err"
"@ | Set-Content -Encoding UTF8 -Path $wrap

# Register task (weekly Sunday 14:00)
$task="ORG_BOT_PAPER_WEEKLY_REVIEW"
$pwsh="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh=(Get-Command powershell.exe).Source }
$userId="$env:USERDOMAIN\$env:USERNAME"

$args = "-NoProfile -ExecutionPolicy Bypass -File `"$wrap`" -ProjectRoot `"$ProjectRoot`" -RunRoot `"$RunRoot`""
$action = New-ScheduledTaskAction -Execute $pwsh -Argument $args
$tr = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 14:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

$ok=$false
foreach($rl in @("Highest","Limited")){
  try{
    try{ Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel $rl
    Register-ScheduledTask -TaskName $task -InputObject (New-ScheduledTask -Action $action -Trigger $tr -Principal $principal -Settings $settings) -ErrorAction Stop | Out-Null
    "WEEKLY_TASK_OK_RUNLEVEL=$rl" | Out-Host
    $ok=$true
    break
  } catch {
    "WEEKLY_TASK_FAIL_RUNLEVEL=$rl ERR=$($_.Exception.Message)" | Out-Host
  }
}
if(-not $ok){ throw "WEEKLY_TASK_NOT_INSTALLED" }

# Trigger once for verification
Start-ScheduledTask -TaskName $task
Start-Sleep -Seconds 8
Get-ScheduledTaskInfo -TaskName $task | Format-List LastRunTime,LastTaskResult,NextRunTime

# Show latest logged output
$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -Filter "WEEKLY_REVIEW_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
$fe = Get-ChildItem $ops -Filter "WEEKLY_REVIEW_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if($fo){ "LAST_WEEKLY_OUT=$($fo.FullName)"; Get-Content $fo.FullName -Tail 60 } else { "LAST_WEEKLY_OUT=NONE" }
if($fe){ "LAST_WEEKLY_ERR=$($fe.FullName)"; Get-Content $fe.FullName -Tail 120 } else { "LAST_WEEKLY_ERR=NONE" }

"OK=PATCH_WEEKLY_REVIEW_LOGGED_DONE" | Out-Host
