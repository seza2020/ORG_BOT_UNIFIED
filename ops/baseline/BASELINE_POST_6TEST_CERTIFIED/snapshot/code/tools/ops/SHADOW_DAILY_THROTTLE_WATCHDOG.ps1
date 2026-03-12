param(
  [string]$Root="C:\alpaca-bot\org_bot",

  # هدف: cap تا قبل این ساعت پر نشود
  [string]$TargetTimePt="13:00",     # HH:mm (PT)
  [int]$TargetUsed=60,               # تا قبل TargetTimePt بیشتر از این مصرف نشود

  # اگر True شود، وقتی limit خورد یک stop-safe اجرا می‌کند (اختیاری)
  [int]$EnforceStop=0,
  [string]$StopScript="C:\alpaca-bot\org_bot\tools\TBOT_PRE_CLOSE_STOP_SAFE.ps1"
)

$ErrorActionPreference="SilentlyContinue"

$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"

# latest status json
$st = Get-ChildItem $Ops -Filter "shadow_gate_status_*.json" | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $st) { return }

$j = (Get-Content $st.FullName -Raw) | ConvertFrom-Json

# time in PT
$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
$nowUtc = [datetime]::UtcNow
$nowPt  = [System.TimeZoneInfo]::ConvertTimeFromUtc($nowUtc, $tz)

# parse target time today in PT
$hh, $mm = $TargetTimePt.Split(":")
$targetPt = (Get-Date -Date $nowPt.Date).AddHours([int]$hh).AddMinutes([int]$mm)

# allowed_used schedule:
# - before target: linear ramp 0..TargetUsed
# - after target: allow remaining linearly until close (use midnight as simple end)
$cap = $j.gate.max_plans_per_day
$used = $j.gate.plans_used

$allowed = $cap
if ($nowPt -lt $targetPt) {
  $elapsed = ($nowPt - $nowPt.Date).TotalSeconds
  $total   = ($targetPt - $nowPt.Date).TotalSeconds
  if ($total -le 0) { $allowed = $TargetUsed } else {
    $allowed = [int][Math]::Floor($TargetUsed * ($elapsed / $total))
  }
} else {
  # after target: ramp from TargetUsed to cap until midnight
  $elapsed2 = ($nowPt - $targetPt).TotalSeconds
  $total2   = ((Get-Date -Date $nowPt.Date).AddDays(1) - $targetPt).TotalSeconds
  if ($total2 -le 0) { $allowed = $cap } else {
    $allowed = [int][Math]::Floor($TargetUsed + (($cap - $TargetUsed) * ($elapsed2 / $total2)))
  }
}

if ($allowed -gt $cap) { $allowed = $cap }
if ($allowed -lt 0) { $allowed = 0 }

$hit = $false
if ($used -ne $null -and $used -gt $allowed) { $hit = $true }

# write a small throttle status file + optional one-shot alert
$day = $nowPt.ToString("yyyyMMdd")
$status = Join-Path $Ops ("shadow_throttle_status_{0}.json" -f $day)

$obj = [ordered]@{
  ts_pt = $nowPt.ToString("o")
  target_time_pt = $targetPt.ToString("o")
  target_used = $TargetUsed
  cap = $cap
  used = $used
  allowed_used = $allowed
  rate_limited = $hit
}

($obj | ConvertTo-Json -Depth 6) | Set-Content -Encoding UTF8 $status

if ($hit) {
  $alert = Join-Path $Ops ("RATE_LIMIT_HIT_{0}.log" -f $day)
  if (-not (Test-Path $alert)) {
    $msg = "RATE_LIMIT_HIT ts_pt=$($nowPt.ToString('o')) used=$used allowed=$allowed target_used=$TargetUsed target_time_pt=$($targetPt.ToString('o'))"
    $msg | Set-Content -Encoding UTF8 $alert
  }

  if ($EnforceStop -eq 1 -and (Test-Path $StopScript)) {
    try { & $StopScript -Root $Root *>> (Join-Path $Ops ("RATE_LIMIT_STOP_{0}.log" -f $day)) } catch {}
  }
}
