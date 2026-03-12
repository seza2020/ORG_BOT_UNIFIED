param()
$ErrorActionPreference="SilentlyContinue"
$hits = @()
Get-ScheduledTask | ForEach-Object {
  $_task = $_
  try {
    $xml = Export-ScheduledTask -TaskName $_task.TaskName -TaskPath $_task.TaskPath
    if ($xml -match "C:\\\\Python313\\\\python\.exe" -or $xml -match "tbot\.main" -or $xml -match "alpaca-bot\\\\org_bot") {
      $hits += [pscustomobject]@{
        TaskName = $_task.TaskName
        TaskPath = $_task.TaskPath
      }
    }
  } catch {}
}
if ($hits.Count -eq 0) {
  "NO_MATCHING_TASKS"
} else {
  $hits | Format-Table -Auto
  "TIP: For any old task that runs system python, point it to tools\\RUN_SHADOW_AUTO.ps1 instead."
}
