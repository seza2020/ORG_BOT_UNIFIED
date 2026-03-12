param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$Day="20260213"
)

$ErrorActionPreference="Stop"
$Logs=Join-Path $Root "logs"
$Ops =Join-Path $Logs "ops"

"=== TRIAGE (Day=$Day) ==="

# 1) List runs (OUT/ERR) for day
$outs = Get-ChildItem $Ops -Filter ("LIVE_OUT_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
$errs = Get-ChildItem $Ops -Filter ("LIVE_ERR_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
"OUT_FILES=" + $outs.Count
"ERR_FILES=" + $errs.Count
$outs | Select Name,Length,LastWriteTime | Format-Table -Auto
$errs | Select Name,Length,LastWriteTime | Format-Table -Auto

# 2) Search logs for keywords around plan file handling
$patterns = @(
  "shadow_plans",
  "shadow_daily",
  "Rotate",
  "rotat",
  "Move-Item",
  "Set-Content",
  "truncate",
  "lock",
  "RUN_SHADOW",
  "START",
  "FREEZE",
  "SNAPSHOT"
)

function ScanFiles($files, $label) {
  "=== SCAN $label ==="
  foreach ($p in $patterns) {
    $c = 0
    foreach ($f in $files) {
      $m = Select-String -Path $f.FullName -Pattern $p -SimpleMatch -ErrorAction SilentlyContinue
      if ($m) { $c += $m.Count }
    }
    if ($c -gt 0) { "{0} => {1}" -f $p, $c }
  }
}

ScanFiles $outs "LIVE_OUT"
ScanFiles $errs "LIVE_ERR"

# 3) Show FREEZE_BACKUP times (should be after session)
"=== FREEZE_BACKUP TIMES ==="
Get-ChildItem $Ops -Filter ("FREEZE_BACKUP_{0}_*" -f $Day) -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime |
  Select Name,Length,LastWriteTime | Format-Table -Auto

# 4) Find any scripts that touch shadow_plans
"=== CODE TOUCHPOINTS (tools) ==="
$tools = Join-Path $Root "tools"
if (Test-Path $tools) {
  Get-ChildItem $tools -Recurse -File -Include *.ps1,*.py -ErrorAction SilentlyContinue |
    ForEach-Object {
      $hit = Select-String -Path $_.FullName -Pattern "shadow_plans" -SimpleMatch -ErrorAction SilentlyContinue
      if ($hit) { $_.FullName }
    } | Sort-Object -Unique
}

# 5) Scheduled tasks that ran around 06:50-07:10 local time (Pacific)
"=== TASKS RUN 06:50-07:10 LOCAL ==="
$dayDt = [datetime]::ParseExact($Day,'yyyyMMdd',$null)
$w1 = $dayDt.AddHours(6).AddMinutes(50)
$w2 = $dayDt.AddHours(7).AddMinutes(10)

Get-ScheduledTask | ForEach-Object {
  try {
    $i = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath
    [pscustomobject]@{
      TaskPath=$_.TaskPath
      TaskName=$_.TaskName
      LastRunTime=$i.LastRunTime
      LastTaskResult=$i.LastTaskResult
    }
  } catch { $null }
} | Where-Object { $_ -and $_.LastRunTime -ge $w1 -and $_.LastRunTime -le $w2 } |
  Sort-Object LastRunTime | Format-Table -Auto

"=== END TRIAGE ==="
