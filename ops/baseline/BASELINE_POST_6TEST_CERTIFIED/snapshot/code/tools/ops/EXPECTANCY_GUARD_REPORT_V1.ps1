param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride="",          # YYYY-MM-DD (optional)
  [int]$WarnCount=50,
  [int]$FailCount=200,
  [int]$LookbackMinutes=0,             # 0 => full day, >0 => last N minutes
  [int]$KillOnFail=0                   # 1 => create KILL_SWITCH when FAIL
)
$ErrorActionPreference="Stop"
if([string]::IsNullOrWhiteSpace($IsoDayOverride)){ $IsoDayOverride=(Get-Date).ToString("yyyy-MM-dd") }
$ymd=$IsoDayOverride.Replace("-","")

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

$meta = Join-Path $RunRoot "logs\meta.jsonl"
if(!(Test-Path $meta)){ throw "MISSING_META=$meta" }

$cut = $null
if($LookbackMinutes -gt 0){
  $cut = (Get-Date).ToUniversalTime().AddMinutes(-$LookbackMinutes)
}

$neg=0; $totalSkip=0; $firstTs=$null

Get-Content -Encoding UTF8 $meta | ForEach-Object {
  try { $o = $_ | ConvertFrom-Json } catch { return }
  if($o.kind -ne "signal_skip"){ return }
  $totalSkip++
  $r = $o.payload.reason
  if($r -ne "negative_expectancy"){ return }

  # filter by isoday (preferred), optionally by lookback
  $tsStr = [string]$o.ts
  $use=$false

  if($tsStr -like ($IsoDayOverride + "*")){
    $use=$true
  } else {
    try {
      $dt = [datetime]::Parse($tsStr)
      if($dt.ToString("yyyy-MM-dd") -eq $IsoDayOverride){ $use=$true }
      if($use -and $cut){
        $utc = $dt.ToUniversalTime()
        if($utc -lt $cut){ $use=$false }
      }
    } catch {
      # if we cannot parse, we can't safely assign to day -> ignore
      $use=$false
    }
  }

  if(-not $use){ return }

  $neg++
  if(-not $firstTs){ $firstTs = $tsStr }
}

$status="PASS"
if($neg -ge $FailCount){ $status="FAIL" }
elseif($neg -ge $WarnCount){ $status="WARN" }

$rep = [ordered]@{
  isoday=$IsoDayOverride
  lookback_minutes=$LookbackMinutes
  negative_expectancy_count=$neg
  signal_skip_total_count=$totalSkip
  first_negative_expectancy_ts=$firstTs
  status=$status
}

$rj_ops = Join-Path $ops ("EXPECTANCY_GUARD_{0}.json" -f $ymd)
$rt_ops = Join-Path $ops ("EXPECTANCY_GUARD_{0}.txt"  -f $ymd)
$rj_ana = Join-Path $ana ("EXPECTANCY_GUARD_{0}.json" -f $ymd)
$rt_ana = Join-Path $ana ("EXPECTANCY_GUARD_{0}.txt"  -f $ymd)

($rep | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 -Path $rj_ops
($rep | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 -Path $rj_ana
@(
  "EXPECTANCY_GUARD_STATUS=$status",
  "isoday=$IsoDayOverride",
  "lookback_minutes=$LookbackMinutes",
  "negative_expectancy_count=$neg",
  "signal_skip_total_count=$totalSkip",
  "first_negative_expectancy_ts=$firstTs"
) | Set-Content -Encoding UTF8 -Path $rt_ops
Copy-Item $rt_ops $rt_ana -Force

if($status -eq "FAIL" -and $KillOnFail -eq 1){
  $ks = Join-Path $RunRoot "KILL_SWITCH"
  ("ts=" + (Get-Date -Format s) + " reason=negative_expectancy_guard") | Set-Content -Encoding UTF8 $ks
}

if($status -eq "FAIL"){ exit 2 }
elseif($status -eq "WARN"){ exit 1 }
else { exit 0 }
