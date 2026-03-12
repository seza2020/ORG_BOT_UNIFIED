param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$Runner="tools\RUN_PAPER_PROFILE_CANON_V1.ps1"
)

$ErrorActionPreference="Stop"

function Parse-Lock([string]$p){
  $h=@{}
  if(!(Test-Path $p)){ return $h }
  foreach($line in (Get-Content $p -ErrorAction SilentlyContinue)){
    if($line -match '^\s*([^=]+)=(.*)\s*$'){
      $k=$Matches[1].Trim(); $v=$Matches[2].Trim()
      $h[$k]=$v
    }
  }
  return $h
}

$runroot = $env:TBOT_RUNROOT
if([string]::IsNullOrWhiteSpace($runroot)){
  $runroot="C:\alpaca-bot\org_bot_runtime\paper"
}

$lockDir = Join-Path $runroot "state\locks"
New-Item -ItemType Directory -Force $lockDir | Out-Null
$lockPath = Join-Path $lockDir "RUN_PAPER_PROFILE.lock"

# --- stale/active check ---
if(Test-Path $lockPath){
  $kv = Parse-Lock $lockPath

  $lockPidVal = 0
  if($kv.ContainsKey("pid")){
    [int]::TryParse($kv["pid"], [ref]$lockPidVal) | Out-Null
  }

  $alive=$false
  if($lockPidVal -gt 0){
    try { Get-Process -Id $lockPidVal -ErrorAction Stop | Out-Null; $alive=$true } catch { $alive=$false }
  }

  if($alive){
    Write-Host "LOCK_ACTIVE_ABORT: $lockPath pid=$lockPidVal"
    exit 3
  } else {
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $bak = Join-Path $lockDir ("RUN_PAPER_PROFILE.STALE_" + $stamp + ".lock")
    Move-Item $lockPath $bak -Force
    Write-Host "LOCK_STALE_ARCHIVED: $bak"
  }
}

# --- write fresh lock ---
$selfPid = $PID
$ts=(Get-Date).ToString("s")

@(
  "ts=$ts"
  "user=$env:USERNAME"
  "host=$env:COMPUTERNAME"
  "root=$Root"
  "pid=$selfPid"
  "runner=$Runner"
  "runroot=$runroot"
) | Set-Content -Encoding UTF8 $lockPath

Write-Host "LOCK_WRITTEN: $lockPath"

# --- run the real runner ---
& (Join-Path $Root $Runner)
$ec=$LASTEXITCODE
Write-Host "RUNNER_EXIT_CODE=$ec"
exit $ec
