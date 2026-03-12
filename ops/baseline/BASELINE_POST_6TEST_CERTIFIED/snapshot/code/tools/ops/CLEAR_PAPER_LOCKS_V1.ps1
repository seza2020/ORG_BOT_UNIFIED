param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [Parameter(Mandatory=$false)][int]$Force = 0
)

$ErrorActionPreference="Stop"

function WL([string]$m){ Write-Host $m }

function Read-ProfileRunRoot([string]$p){
  if(!(Test-Path -LiteralPath $p)){ throw "PROFILE_NOT_FOUND=$p" }
  $prof = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
  $rr = [string]$prof.runroot
  if([string]::IsNullOrWhiteSpace($rr)){ throw "PROFILE_RUNROOT_MISSING" }
  return $rr
}

$RUNROOT = Read-ProfileRunRoot $ProfilePath
$LOCKDIR = Join-Path $RUNROOT "state\locks"
$LOCK    = Join-Path $LOCKDIR "RUN_PAPER_PROFILE.lock"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$repDir = Join-Path $ProjectRoot "logs\ops\runner_reports"
New-Item -ItemType Directory -Force -Path $repDir | Out-Null
$rep = Join-Path $repDir ("CLEAR_PAPER_LOCKS_{0}.txt" -f $ts)

@(
  ("TS={0}" -f $ts),
  ("PROJECT_ROOT={0}" -f $ProjectRoot),
  ("PROFILE={0}" -f $ProfilePath),
  ("RUNROOT={0}" -f $RUNROOT),
  ("LOCK={0}" -f $LOCK),
  ("FORCE={0}" -f $Force)
) | Out-File -Encoding utf8 -LiteralPath $rep

WL ("REPORT=" + $rep)

if(!(Test-Path -LiteralPath $LOCK)){
  WL "LOCK_STATUS=NOT_FOUND"
  "LOCK_STATUS=NOT_FOUND" | Out-File -Encoding utf8 -LiteralPath $rep -Append
  exit 0
}

WL "LOCK_STATUS=FOUND"
"LOCK_STATUS=FOUND" | Out-File -Encoding utf8 -LiteralPath $rep -Append

$lockText = Get-Content -LiteralPath $LOCK -ErrorAction SilentlyContinue
"--- LOCK_CONTENT_BEGIN ---" | Out-File -Encoding utf8 -LiteralPath $rep -Append
$lockText | Out-File -Encoding utf8 -LiteralPath $rep -Append
"--- LOCK_CONTENT_END ---" | Out-File -Encoding utf8 -LiteralPath $rep -Append

# Parse pid/out/err if present (best-effort)
$pidVal = $null
$outVal = $null
$errVal = $null

foreach($ln in $lockText){
  if($ln -match '^\s*pid\s*=\s*(\d+)\s*$'){ $pidVal = [int]$Matches[1] }
  if($ln -match '^\s*out\s*=\s*(.+)\s*$'){ $outVal = $Matches[1].Trim() }
  if($ln -match '^\s*err\s*=\s*(.+)\s*$'){ $errVal = $Matches[1].Trim() }
}

$alive = $false
if($pidVal){
  $p = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
  if($p){ $alive = $true }
}

if($alive -and $Force -ne 1){
  WL ("DECISION=ACTIVE_RUN pid={0} -> DO_NOT_REMOVE_LOCK" -f $pidVal)
  ("DECISION=ACTIVE_RUN pid={0}" -f $pidVal) | Out-File -Encoding utf8 -LiteralPath $rep -Append

  if($errVal -and (Test-Path -LiteralPath $errVal)){
    WL "=== ERR_TAIL(80) ==="
    Get-Content -LiteralPath $errVal -Tail 80
  }
  if($outVal -and (Test-Path -LiteralPath $outVal)){
    WL "=== OUT_TAIL(80) ==="
    Get-Content -LiteralPath $outVal -Tail 80
  }
  exit 0
}

WL "DECISION=STALE_LOCK -> SAFE_REMOVE"
"DECISION=STALE_LOCK" | Out-File -Encoding utf8 -LiteralPath $rep -Append

# Remove lock
try { Remove-Item -LiteralPath $LOCK -Force -ErrorAction SilentlyContinue } catch {}
WL "LOCK_REMOVED=1"
"LOCK_REMOVED=1" | Out-File -Encoding utf8 -LiteralPath $rep -Append

# Kill python engine processes (ONLY tbot/orchestrator/main under org_bot)
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object {
    $_.CommandLine -match "alpaca-bot\\org_bot" -and
    ($_.CommandLine -match "tbot" -or $_.CommandLine -match "orchestrator" -or $_.CommandLine -match "tbot\.main")
  } |
  ForEach-Object {
    WL ("KILL_PY_PID={0}" -f $_.ProcessId)
    ("KILL_PY_PID={0}" -f $_.ProcessId) | Out-File -Encoding utf8 -LiteralPath $rep -Append
    try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
  }

WL "DONE=1"
"DONE=1" | Out-File -Encoding utf8 -LiteralPath $rep -Append
exit 0