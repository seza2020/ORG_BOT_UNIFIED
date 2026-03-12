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

$mgrLog   = Join-Path $LOGS "manager_hard_v62_events.jsonl"
$mgrLock  = Join-Path $LOCKDIR "ORG_UNIFIED_RUNTIME_MANAGER_HARD_V62.lock"
$dupLog   = Join-Path $OutDir "audit\duplicate_kills.txt"
$result   = Join-Path $OutDir "RESULT.txt"

$ownerPid         = 0
$ownerPromotions  = 0
$dupKills         = 0
$count1           = -1
$count3           = -1
$count6           = -1
$count12          = -1
$count20          = -1
$metaGrowth       = -1
$failReason       = "UNSET"
$managerException = ""

function WL([string]$kind, [hashtable]$payload=@{}) {
  $row = [ordered]@{
    ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    kind = $kind
    host_pid = $PID
    payload = $payload
  } | ConvertTo-Json -Compress -Depth 10
  Add-Content -LiteralPath $mgrLog -Value $row -Encoding utf8
}

function Get-ProjectPython {
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object {
      $_.CommandLine -and $_.CommandLine -like "*ORG_BOT_UNIFIED*"
    } |
    Select-Object ProcessId,ParentProcessId,CommandLine
}

function Snapshot-Procs([string]$PathOut) {
  $pyProcs = Get-ProjectPython | Sort-Object ProcessId
  $pyProcs | Format-List | Out-File -LiteralPath $PathOut -Encoding utf8
  return @($pyProcs)
}

function Test-Alive([int]$ProcId) {
  try {
    $null = Get-Process -Id $ProcId -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

function Select-Successor($all, [int]$previousOwnerPid) {
  $directChild = @($all | Where-Object { $_.ParentProcessId -eq $previousOwnerPid })
  if (@($directChild).Count -eq 1) { return $directChild[0] }

  $entrysafe = @($all | Where-Object { $_.CommandLine -match "tbot\.entrysafe" })
  if (@($entrysafe).Count -eq 1) { return $entrysafe[0] }

  if (@($all).Count -eq 1) { return $all[0] }

  return $null
}

try {
  try {
    $fs = [System.IO.File]::Open($mgrLock,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None)
    try {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes("manager_pid=$PID`n")
      $fs.Write($bytes,0,$bytes.Length)
      $fs.Flush()
    } finally {
      $fs.Dispose()
    }
    WL "manager_lock_acquired" @{ lock = $mgrLock }
  } catch {
    $failReason = "MANAGER_LOCK_ALREADY_EXISTS"
    WL "manager_lock_blocked" @{ lock = $mgrLock; error = $_.Exception.Message }
    throw
  }

  $env:PYTHONPATH = $CODE
  $env:TBOT_RUNROOT = $RUNROOT
  $env:TBOT_PROFILE = $Profile
  $env:TBOT_MODE = $Profile
  $env:TBOT_RUNTIME_MANAGER = "1"
  $env:TBOT_LOGDIR = $LOGS

  $stdOut = Join-Path $OutDir "cert\runtime_stdout.txt"
  $stdErr = Join-Path $OutDir "cert\runtime_stderr.txt"
  $metaEv = Join-Path $LOGS "meta_events.jsonl"

  $metaBefore = if(Test-Path $metaEv){ (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines } else { 0 }

  $args = @("-u","-m","tbot.entrysafe","--run","--profile",$Profile,"--iters","999999","--sleep","0.5")
  $ownerProc = Start-Process -FilePath $PY -ArgumentList $args -WorkingDirectory $CODE -RedirectStandardOutput $stdOut -RedirectStandardError $stdErr -PassThru
  $ownerPid = $ownerProc.Id
  $failReason = "RUNNING"

  WL "owner_launch" @{ owner_pid = $ownerPid; args = ($args -join " ") }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $snap1 = $false
  $snap3 = $false
  $snap6 = $false
  $snap12 = $false
  $snap20 = $false

  while ($true) {
    Start-Sleep -Milliseconds 250

    $all = @(Get-ProjectPython | Sort-Object ProcessId)

    # handoff-aware owner promotion
    if (($ownerPid -gt 0) -and (-not (Test-Alive $ownerPid))) {
      $succ = Select-Successor -all $all -previousOwnerPid $ownerPid
      if ($null -ne $succ) {
        $oldOwner = $ownerPid
        $ownerPid = $succ.ProcessId
        $ownerPromotions++
        WL "owner_promoted" @{ old_owner = $oldOwner; new_owner = $ownerPid; new_ppid = $succ.ParentProcessId; cmd = $succ.CommandLine }
        $failReason = "RUNNING_AFTER_PROMOTION"
      } else {
        $failReason = "OWNER_EXIT_BEFORE_CERT_WINDOW"
        WL "owner_exit_without_successor" @{ old_owner = $ownerPid }
        break
      }
    }

    foreach($procObj in $all) {
      if ($procObj.ProcessId -ne $ownerPid) {
        try {
          Stop-Process -Id $procObj.ProcessId -Force -ErrorAction Stop
          $dupKills++
          Add-Content -LiteralPath $dupLog -Value ("KILLED PID=" + $procObj.ProcessId + " PPID=" + $procObj.ParentProcessId + " CMD=" + $procObj.CommandLine) -Encoding utf8
          WL "duplicate_kill" @{ owner_pid = $ownerPid; killed_pid = $procObj.ProcessId; ppid = $procObj.ParentProcessId; cmd = $procObj.CommandLine }
        } catch {
          Add-Content -LiteralPath $dupLog -Value ("KILL_FAIL PID=" + $procObj.ProcessId + " ERR=" + $_.Exception.Message) -Encoding utf8
          WL "duplicate_kill_fail" @{ owner_pid = $ownerPid; killed_pid = $procObj.ProcessId; error = $_.Exception.Message }
        }
      }
    }

    $sec = [int][Math]::Floor($sw.Elapsed.TotalSeconds)

    if (-not $snap1 -and $sec -ge 1) {
      $p1 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t1.txt")
      $count1 = @($p1).Count
      $snap1 = $true
      WL "snapshot_t1" @{ count = $count1 }
    }

    if (-not $snap3 -and $sec -ge 3) {
      $p3 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t3.txt")
      $count3 = @($p3).Count
      $snap3 = $true
      WL "snapshot_t3" @{ count = $count3 }
    }

    if (-not $snap6 -and $sec -ge 6) {
      $p6 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t6.txt")
      $count6 = @($p6).Count
      $snap6 = $true
      WL "snapshot_t6" @{ count = $count6 }
    }

    if (-not $snap12 -and $sec -ge 12) {
      $p12 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t12.txt")
      $count12 = @($p12).Count
      $snap12 = $true
      WL "snapshot_t12" @{ count = $count12 }
    }

    if (-not $snap20 -and $sec -ge 20) {
      $p20 = Snapshot-Procs -PathOut (Join-Path $OutDir "cert\processes_t20.txt")
      $count20 = @($p20).Count
      $snap20 = $true
      $failReason = "CERT_WINDOW_COMPLETE"
      WL "snapshot_t20" @{ count = $count20 }
      break
    }
  }

  try {
    $live = Get-ProjectPython
    foreach($procObj in $live){
      try { Stop-Process -Id $procObj.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
  } catch {}

  Start-Sleep -Seconds 2

  $metaAfter = if(Test-Path $metaEv){ (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines } else { 0 }
  $metaGrowth = [int]($metaAfter - $metaBefore)

} catch {
  $managerException = $_.Exception.ToString()
  if ($failReason -eq "UNSET") { $failReason = "MANAGER_EXCEPTION" }
  WL "manager_exception" @{ error = $managerException }
} finally {
  try {
    if(Test-Path $mgrLock){ Remove-Item -LiteralPath $mgrLock -Force -ErrorAction SilentlyContinue }
  } catch {}

  $pass = (($count20 -eq 1) -and ($metaGrowth -gt 0))

  @(
    "RESULT=" + ($(if($pass){"PASS"}else{"FAIL"}))
    "COUNT_AFTER_1S=$count1"
    "COUNT_AFTER_3S=$count3"
    "COUNT_AFTER_6S=$count6"
    "COUNT_AFTER_12S=$count12"
    "COUNT_AFTER_20S=$count20"
    "META_EVENTS_GROWTH=$metaGrowth"
    "DUPLICATE_KILL_COUNT=$dupKills"
    "OWNER_PROMOTIONS=$ownerPromotions"
    "FINAL_OWNER_PID=$ownerPid"
    "FAIL_REASON=$failReason"
    "MANAGER_EXCEPTION=$managerException"
    "MANAGER_LOG=$mgrLog"
    "DUPLICATE_KILL_LOG=$dupLog"
  ) | Out-File -LiteralPath $result -Encoding utf8
}
