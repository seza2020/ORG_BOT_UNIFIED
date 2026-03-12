param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day  = "",   # yyyyMMdd ; default=Today (PT)
  [string]$TimeZoneId = "Pacific Standard Time"
)

$ErrorActionPreference="Stop"

function Log([string]$m){ $ts=(Get-Date -Format "HH:mm:ss"); Write-Host "[$ts] $m" }

if (-not $Day -or $Day.Trim() -eq "") {
  $Day = (Get-Date).ToString("yyyyMMdd")
}

$Ops = Join-Path $Root "logs\ops"
$Logs = Join-Path $Root "logs"
$Recover = Join-Path $Root "tools\recover_shadow_plans_from_meta.ps1"
$Freeze  = Join-Path $Root "tools\freeze_today_enterprise.ps1"
$ClearLock = Join-Path $Root "tools\CLEAR_TBOT_LOCK.ps1"

Log "OPS_END_OF_DAY"
Log "Root=$Root"
Log "Day=$Day"

# 1) TRIAGE ops logs for the day
$OutFiles = Get-ChildItem -Path $Ops -Filter ("LIVE_OUT_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
$ErrFiles = Get-ChildItem -Path $Ops -Filter ("LIVE_ERR_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

Log ("OUT_FILES=" + ($OutFiles.Count))
Log ("ERR_FILES=" + ($ErrFiles.Count))

if ($OutFiles.Count -gt 0) {
  $lastOut = $OutFiles | Select-Object -Last 1
  Log ("LAST_OUT=" + $lastOut.FullName)
  Log ("LAST_OUT_LEN=" + $lastOut.Length)
}

if ($ErrFiles.Count -gt 0) {
  $lastErr = $ErrFiles | Select-Object -Last 1
  Log ("LAST_ERR=" + $lastErr.FullName)
  Log ("LAST_ERR_LEN=" + $lastErr.Length)
}

# 2) Recover shadow_plans FROM_META (authoritative for analysis)
if (!(Test-Path $Recover)) { throw "Missing: $Recover" }
Log "RECOVER_FROM_META..."
pwsh -NoProfile -ExecutionPolicy Bypass -File $Recover -Root $Root -Day $Day -TimeZoneId $TimeZoneId

# 3) Freeze package (for sharing / backup)
if (Test-Path $Freeze) {
  Log "FREEZE_TODAY_ENTERPRISE..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File $Freeze -Root $Root
} else {
  Log "WARN: freeze_today_enterprise.ps1 not found, skipping freeze."
}

# 4) Clear project lock
if (Test-Path $ClearLock) {
  Log "CLEAR_LOCK..."
  pwsh -NoProfile -ExecutionPolicy Bypass -File $ClearLock
} else {
  Log "WARN: CLEAR_TBOT_LOCK.ps1 not found, skipping lock clear."
}

# 5) QA summary counts (FROM_META output)
$FromMeta = Join-Path $Logs ("shadow_daily\shadow_plans_{0}_FROM_META.jsonl" -f $Day)
if (Test-Path $FromMeta) {
  $cnt = (Get-Content $FromMeta | Measure-Object -Line).Lines
  $first = ""
  $last  = ""
  if ($cnt -gt 0) {
    $first = (Get-Content $FromMeta -TotalCount 1)
    $last  = (Get-Content $FromMeta -Tail 1)
  }
  Log ("FROM_META_FILE=" + $FromMeta)
  Log ("FROM_META_COUNT=" + $cnt)
  if ($cnt -gt 0) {
    Log ("FROM_META_FIRST_LINE=" + $first)
    Log ("FROM_META_LAST_LINE=" + $last)
  }
} else {
  Log ("WARN: FROM_META file missing: " + $FromMeta)
}

Log "DONE"
