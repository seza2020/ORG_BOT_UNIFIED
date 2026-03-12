$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$RUNROOT="$ROOT\runtime\paper"
$STATE="$RUNROOT\state\risk"
if(!(Test-Path $STATE)){ throw "STATE_NOT_FOUND=$STATE" }

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$out="$ROOT\ops\audit\WEEKLY_REVIEW_$stamp"
New-Item -ItemType Directory -Force $out | Out-Null

$sum = Get-ChildItem $STATE -File -Filter "daily_summary_*.json" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 14

if(-not $sum){ throw "NO_DAILY_SUMMARIES_FOUND" }

Copy-Item $sum.FullName $out -Force

# crude KPI
$objs = foreach($f in $sum){ Get-Content $f.FullName -Raw | ConvertFrom-Json }
$commits = ($objs | Measure-Object -Property commit_count -Sum).Sum
$days = ($objs | Measure-Object).Count
$maxUsed = ($objs | Measure-Object -Property used_risk -Maximum).Maximum

$kpi = [pscustomobject]@{
  days = $days
  commits_sum = $commits
  used_risk_max = $maxUsed
}

$kpi | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out "weekly_kpi.json") -Encoding utf8

Write-Host "WEEKLY_REVIEW_OUT=$out"
Write-Host "DAYS=$days"
Write-Host "COMMITS_SUM=$commits"
Write-Host "USED_RISK_MAX=$maxUsed"
Write-Host "WEEKLY_REVIEW=OK"
