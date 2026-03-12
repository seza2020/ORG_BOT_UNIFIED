param(
  [string]$Profile = "PAPER",
  [string]$OutDir,
  [int]$CertSeconds = 20,
  [switch]$Certification
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE    = Join-Path $U "code"
$PY      = Join-Path $CODE ".venv\Scripts\python.exe"
$RUNROOT = Join-Path $U "runtime\paper"
$LOGS    = Join-Path $RUNROOT "logs"
$LOCKDIR = Join-Path $RUNROOT "state\locks"
New-Item -ItemType Directory -Force $LOGS,$LOCKDIR | Out-Null

$mgrLog  = Join-Path $LOGS "manager_hard_v31_events.jsonl"
$mgrLock = Join-Path $LOCKDIR "ORG_UNIFIED_RUNTIME_MANAGER_HARD_V31.lock"

function WL([string]$kind, [hashtable]$payload=@{}) {
  $row = [ordered]@{
    ts      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    kind    = $kind
    host_pid = $PID
    payload = $payload
  } | ConvertTo-Json -Compress -Depth 10
  Add-Content -LiteralPath $mgrLog -Value $row -Encoding utf8
}

function Snapshot-Procs([string]$PathOut) {
  $pyProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine -match "tbot\.main" -and
      $_.CommandLine -like "*ORG_BOT_UNIFIED*"
    } |
    Select-Object ProcessId,ParentProcessId,CommandLine
  $pyProcs | Format-List | Out-File -LiteralPath $PathOut -Encoding utf8
  return @($pyProcs)
}

try {
  $fs = [System.IO.File]::Open($mgrLock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("manager_pid=$PID`n")
    $fs.Write($bytes,0,$bytes.Length)
    $fs.Flush()
  } finally {
    $fs.Dispose()
  }
  WL "manager_lock_acquired" @{ lock = $mgrLock }
} catch {
  WL "manager_lock_blocked" @{ lock = $mgrLock; error = $_.Exception.Message }
  throw "MANAGER_LOCK_ALREADY_EXISTS=$mgrLock"
}

try {
  $env:PYTHONPATH = $CODE
  $env:TBOT_RUNROOT = $RUNROOT
  $env:TBOT_PROFILE = $Profile
  $env:TBOT_MODE = $Profile
  $env:TBOT_RUNTIME_MANAGER = "1"
  $env:TBOT_LOGDIR = $LOGS

  $stdOut = Join-Path $OutDir "cert\runtime_stdout.txt"
  $stdErr = Join-Path $OutDir "cert\runtime_stderr.txt"
  $metaEv = Join-Path $LOGS "meta_events.jsonl"
  $metaEn = Join-Path $LOGS "meta_engine.jsonl"

  $metaBefore = if(Test-Path $metaEv){ (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines } else { 0 }
  $engBefore  = if(Test-Path $metaEn){ (Get-Content -LiteralPath $metaEn | Measure-Object -Line).Lines } else { 0 }

  $args = @("-u","-m","tbot.main","--run","--iters","999999","--sleep","0.5")
  $ownerProc = Start-Process -FilePath $PY -ArgumentList $args -WorkingDirectory $CODE -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr -PassThru
  $ownerPid = $ownerProc.Id
  $dupKills = 0

  WL "owner_launch" @{ owner_pid = $ownerPid; args = ($args -join " ") }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $snap12 = $false
  $snap20 = $false

  while ($true) {
    Start-Sleep -Milliseconds 1000

    $pyProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match "tbot\.main" -and
        $_.CommandLine -like "*ORG_BOT_UNIFIED*"
      } |
      Sort-Object ProcessId

    if (@($pyProcs).Count -gt 1) {
      foreach($procObj in $pyProcs) {
        if ($procObj.ProcessId -ne $ownerPid) {
          try {
            Stop-Process -Id $procObj.ProcessId -Force -ErrorAction Stop
            $dupKills++
            WL "duplicate_kill" @{ owner_pid = $ownerPid; killed_pid = $procObj.ProcessId; ppid = $procObj.ParentProcessId }
          } catch {
            WL "duplicate_kill_fail" @{ owner_pid = $ownerPid; killed_pid = $procObj.ProcessId; error = $_.Exception.Message }
          }
        }
      }
    }

    $sec = [int][Math]::Floor($sw.Elapsed.TotalSeconds)

    if (-not $snap12 -and $sec -ge 12) {
      $p12 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t12.txt")
      $snap12 = $true
      WL "snapshot_t12" @{ count = @($p12).Count }
    }

    if (-not $snap20 -and $sec -ge 20) {
      $p20 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t20.txt")
      $snap20 = $true
      WL "snapshot_t20" @{ count = @($p20).Count }
    }

    $ownerAlive = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
    if (-not $ownerAlive) {
      WL "owner_exit_detected" @{ sec = $sec; owner_pid = $ownerPid }
      break
    }

    if ($Certification -and $sec -ge $CertSeconds) {
      WL "cert_window_complete" @{ sec = $sec; owner_pid = $ownerPid }
      break
    }
  }

  try {
    Stop-Process -Id $ownerPid -Force -ErrorAction SilentlyContinue
    WL "owner_stopped" @{ owner_pid = $ownerPid }
  } catch {}

  Start-Sleep -Seconds 2

  $p12f = if(Test-Path (Join-Path $OutDir "cert\processes_t12.txt")) {
    (Get-Content -LiteralPath (Join-Path $OutDir "cert\processes_t12.txt") | Select-String "ProcessId").Count
  } else { 0 }

  $p20f = if(Test-Path (Join-Path $OutDir "cert\processes_t20.txt")) {
    (Get-Content -LiteralPath (Join-Path $OutDir "cert\processes_t20.txt") | Select-String "ProcessId").Count
  } else { 0 }

  $metaAfter = if(Test-Path $metaEv){ (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines } else { 0 }
  $engAfter  = if(Test-Path $metaEn){ (Get-Content -LiteralPath $metaEn | Measure-Object -Line).Lines } else { 0 }

  $metaGrowth = [int]($metaAfter - $metaBefore)
  $engGrowth  = [int]($engAfter - $engBefore)
  $pass = ($p20f -eq 1 -and $metaGrowth -gt 0)

  @(
    "RESULT=" + ($(if($pass){"PASS"}else{"FAIL"}))
    "COUNT_AFTER_12S=$p12f"
    "COUNT_AFTER_20S=$p20f"
    "META_EVENTS_GROWTH=$metaGrowth"
    "META_ENGINE_GROWTH=$engGrowth"
    "DUPLICATE_KILL_COUNT=$dupKills"
    "OWNER_PID=$ownerPid"
    "MANAGER_LOG=$mgrLog"
  ) | Out-File -LiteralPath (Join-Path $OutDir "RESULT.txt") -Encoding utf8

} finally {
  try {
    if(Test-Path $mgrLock){ Remove-Item -LiteralPath $mgrLock -Force -ErrorAction SilentlyContinue }
  } catch {}
}
