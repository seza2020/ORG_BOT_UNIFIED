param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"
$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("WEEKLY_REVIEW_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("WEEKLY_REVIEW_ERR_{0}.txt" -f $ts)

$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path $py)){ $py = "python" }

$wk = (Get-Date -Format 'yyyy') + 'W' + ([System.Globalization.ISOWeek]::GetWeekOfYear([datetime]::Now))
$script = Join-Path $ProjectRoot "tools\analytics\weekly_review.py"

& $py $script --runroot $RunRoot --weeksuffix $wk 1> $out 2> $err
"OK=WEEKLY_REVIEW_DONE weeksuffix=$wk OUT=$out ERR=$err"
