#requires -Version 7.0
[CmdletBinding()]
param(
  [double]$S01MinStrength = 0.00005,
  [double]$ShadowStopPct  = 0.003,
  [double]$ShadowRR       = 2.0
)

# === ORG STABILITY HEADER (auto) ===
$ErrorActionPreference = "Stop"

# 1) single-instance lock (prevents duplicate/parallel runs)
$global:TBOT_MUTEX = $null
try {
  $name = "Global\TBOT_ORG_SHADOW_LOCK"
  $m = New-Object System.Threading.Mutex($false, $name)
  $ok = $m.WaitOne(0, $false)
  if (-not $ok) {
    Write-Host "LOCKED: another instance is already running. exiting."
    exit 3
  }
  $global:TBOT_MUTEX = $m
} catch {
  Write-Host ("LOCK_WARN: mutex failed -> continuing without lock. " + $_.Exception.Message)
}

# 2) normalize root + PYTHONPATH
if (-not $Root) { $Root = "C:\alpaca-bot\org_bot" }
Set-Location $Root
$env:PYTHONPATH = $Root

# 3) resolve python (prefer venv)
$py1 = Join-Path $Root ".venv\Scripts\python.exe"
$py2 = Join-Path $Root "venv\Scripts\python.exe"
if (Test-Path -LiteralPath $py1) { $python = $py1 }
elseif (Test-Path -LiteralPath $py2) { $python = $py2 }
else { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }

Write-Host ("PY=" + $python)

# 4) preflight import to avoid morning 'module not found' loops
try {
  if ($env:TBOT_TEST_PREFLIGHT_FAIL -eq '1') { throw 'TEST_PREFLIGHT_FAIL' }
  & $python -c "import tbot; print('tbot=OK')" | Out-Host
} catch {
  $msg = 'ORG_FATAL_PREFLIGHT: cannot import tbot -> ' + $_.Exception.Message
  Write-Output $msg
  try {
    $opsDir = Join-Path $Root 'logs\ops'
    New-Item -ItemType Directory -Force -Path $opsDir | Out-Null
    $fatalLog = Join-Path $opsDir 'ORG_FATAL.log'
    Add-Content -Path $fatalLog -Value ((Get-Date -Format s).ToString() + ' ' + $msg) -Encoding UTF8
  } catch {}
  exit 2
}

# 5) daily cap persistence across restarts:
#    remaining = max_plans_per_day - accepted_today (counted from shadow_plans.jsonl)
$SP = Join-Path $Root "logs\shadow_plans.jsonl"
$GateMaxPlans = 150
$AcceptedToday = 0

if (Test-Path -LiteralPath $SP) {
  $today = (Get-Date).Date
  Get-Content -LiteralPath $SP -ErrorAction SilentlyContinue | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try { $r = $_ | ConvertFrom-Json } catch { return }
    try {
      $t = [datetime]$r.ts
      if ($t.Date -eq $today) { $AcceptedToday++ }
    } catch {}
  }
}

$RemainingPlans = [math]::Max(0, ($GateMaxPlans - $AcceptedToday))
Write-Host ("DAILY_CAP: max=" + $GateMaxPlans + " accepted_today=" + $AcceptedToday + " remaining=" + $RemainingPlans)

# === END ORG STABILITY HEADER ===



function Test-PathWritable {
  param([Parameter(Mandatory=$true)][string]$Path)

  try {
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $fs = [System.IO.File]::Open(
      $Path,
      [System.IO.FileMode]::OpenOrCreate,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::ReadWrite
    )
    try { } finally { $fs.Dispose() }
    return $true
  } catch {
    return $false
  }
}

function Get-OutPath {
  param(

    [Parameter(Mandatory=$true
  )
][string]$Root,
    [Parameter(Mandatory=$true)][string]$Stamp,
    [Parameter(Mandatory=$true)][int]$ProcId
  )

  $candidates = @()

  # A) original project ops dir
  $candidates += (Join-Path $Root "logs\ops")

  # B) ProgramData (usually not watched like project folders)
  $candidates += (Join-Path $env:ProgramData "TBOT\ops")

  # C) Temp fallback
  $candidates += (Join-Path $env:TEMP "TBOT\ops")

  foreach ($dir in $candidates) {
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch {}
    $p = Join-Path $dir ("LIVE_OUT_{0}_{1}_pid{2}.txt" -f $Stamp,(Get-Random -Minimum 100 -Maximum 999),$ProcId)
    if (Test-PathWritable -Path $p) { return $p }
  }

  throw "OUTDIR_FAIL: could not allocate writable OUT path in any candidate dir."

}
$ErrorActionPreference = "Stop"

$Root = "C:\alpaca-bot\org_bot"
Set-Location $Root

# --- backup snapshot
$stamp = (Get-Date -Format "yyyyMMdd_HHmmss_fff") + "_pid$PID"
$bkDir = Join-Path $Root ("logs\backups\SNAPSHOT_{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null

$pathsToBackup = @(
  (Join-Path $Root "tbot\runtime\orchestrator.py"),
  (Join-Path $Root "tbot\runtime\shadow_pricing.py"),
  (Join-Path $Root "tbot\main.py"),
  (Join-Path $Root "tools\run_shadow.ps1"),
  (Join-Path $Root "logs\shadow_plans.jsonl")
)

foreach ($p in $pathsToBackup) {
  if (Test-Path $p) {
    Copy-Item -Force $p (Join-Path $bkDir (Split-Path $p -Leaf))
  }
}

# env snapshot
Get-ChildItem Env:* | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name,$_.Value } `
  | Set-Content -LiteralPath (Join-Path $bkDir "env_snapshot.txt") -Encoding UTF8

Write-Host "BACKUP SNAPSHOT: $bkDir"

# --- kill stale python
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# --- load Alpaca keys (if file exists)
$alpacaEnv = "C:\alpaca-bot\secrets\alpaca_env.ps1"
if (Test-Path $alpacaEnv) { . $alpacaEnv }

# --- ensure module discovery (fix No module named tbot)
$env:PYTHONPATH = $Root

# --- runtime env
$env:TBOT_SHADOW_PRICE_MODE = "last"
$env:TBOT_SHADOW_STOP_PCT   = [string]$ShadowStopPct
$env:TBOT_SHADOW_RR         = [string]$ShadowRR

# --- S01 gate (for data collection; adjust anytime)
$env:TBOT_ENABLE_S01_LOGIC  = "1"
$env:TBOT_S01_MIN_STRENGTH  = [string]$S01MinStrength
# --- ops log output (robust OUT allocation with fallback)
$out = Get-OutPath -Root $Root -Stamp $stamp -ProcId $PID
Write-Host "OUT=$out"
# ORG_OUTSAFE: avoid transient file locks
function Write-OutSafe {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Value,
    [int]$Retries = 12,
    [int]$DelayMs = 150
  )

  $line = $Value + "`r`n"
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)

  for ($i=0; $i -lt $Retries; $i++) {
    try {
      $dir = Split-Path -Parent $Path
      if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

      $fs = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite
      )
      try {
        $fs.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush()
      } finally {
        $fs.Dispose()
      }
      return
    } catch {
      Start-Sleep -Milliseconds $DelayMs
    }
  }

  throw ("OUT_LOCK: could not write to " + $Path)
}# --- python path
# DISABLED_BY_ORG_STABILITY: $python = (Get-Command python -ErrorAction Stop).Source
# --- preflight
& $python -c "import sys; print('PY=',sys.executable); import tbot; print('tbot=OK')" | Tee-Object -FilePath $out -Append

# --- run (args array avoids PowerShell parsing bugs with --meta / backticks)
$args = @(
  "-m","tbot.main"
  "--run"
  "--iters","999999"
  "--sleep","0.25"
  "--shadow"

  "--meta",     (Join-Path $Root "logs\meta.jsonl")
  "--announce", (Join-Path $Root "logs\announce.log")

  "--gate_cooldown_sec","30"
  "--gate_max_plans_per_day",("$RemainingPlans")
  "--gate_max_risk_usd","500"
  "--gate_min_rr","1.0"
  "--gate_min_conf","0.0"

  "--sim_in_session","1"
  "--sim_pre_close","0"
)
Write-Host "RUNNING SHADOW..."
Write-Host "OUT=$out"
# ORG_TRANSCRIPT_DISABLED
Write-Host ("PRE_S01ENV: now=$([DateTime]::Now.ToString('s')) TBOT_ENABLE_S01_LOGIC=$env:TBOT_ENABLE_S01_LOGIC TBOT_S01_MIN_STRENGTH=$env:TBOT_S01_MIN_STRENGTH TBOT_S01_DEBUG_SHORT=$env:TBOT_S01_DEBUG_SHORT")
Write-Host "PRE_S01ENV: tool=run_shadow_final.ps1 pid=$PID now=$([DateTime]::Now.ToString('s')) TBOT_ENABLE_S01_LOGIC=$env:TBOT_ENABLE_S01_LOGIC TBOT_S01_MIN_STRENGTH=$env:TBOT_S01_MIN_STRENGTH"
$env:TBOT_S01_DEBUG_SHORT="1"
$env:PYTHONUNBUFFERED="1"
Write-Host "S01ENV: TBOT_S01_DEBUG_SHORT=$env:TBOT_S01_DEBUG_SHORT TBOT_ENABLE_S01_LOGIC=$env:TBOT_ENABLE_S01_LOGIC TBOT_S01_MIN_STRENGTH=$env:TBOT_S01_MIN_STRENGTH PYTHONUNBUFFERED=$env:PYTHONUNBUFFERED"
& $python @args 2>&1 | Tee-Object -FilePath $out














# ORG_TRANSCRIPT_OFF
try { Stop-Transcript | Out-Null } catch {}





