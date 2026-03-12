param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [string]$Pwsh = "C:\Program Files\PowerShell\7\pwsh.exe",
  [string]$TaskName = "TBOT_PAPER_PREFLIGHT_0629_SYSTEM"
)

$ErrorActionPreference="Stop"
$pre = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
if(!(Test-Path $pre)){ throw "PRECHECK_MISSING: $pre" }
if(!(Test-Path $Pwsh)){ throw "PWSH_MISSING: $Pwsh" }

# schtasks wants a single string; quote pwsh + -File targets
$tr = "`"$Pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$pre`" -Root `"$Root`" -RunRoot `"$RunRoot`""

# Create/replace task: daily 06:29 as SYSTEM, highest
schtasks /create /f /tn "$TaskName" /sc daily /st 06:29 /ru "SYSTEM" /rl HIGHEST /tr "$tr" | Out-Null

Write-Host "[OK] TASK_CREATED=$TaskName"
schtasks /query /tn "$TaskName" /v /fo LIST | findstr /i "TaskName Next Run Time Logon Mode Run As User Task To Run" | Out-Host

# Test-run now
schtasks /run /tn "$TaskName" | Out-Null
Start-Sleep -Seconds 5
schtasks /query /tn "$TaskName" /v /fo LIST | findstr /i "Last Run Time Last Result" | Out-Host

exit 0
