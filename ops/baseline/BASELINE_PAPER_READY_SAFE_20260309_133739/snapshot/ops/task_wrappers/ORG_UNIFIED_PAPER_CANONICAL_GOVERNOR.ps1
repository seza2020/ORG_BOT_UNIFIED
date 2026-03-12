param(
  [string]$Profile = "PAPER",
  [string]$OutDir,
  [int]$CertSeconds = 20
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U         = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE      = Join-Path $U "code"
$ENTRYSAFE = Join-Path $CODE "tbot\entrysafe.py"
$PY        = Join-Path $CODE ".venv\Scripts\python.exe"
$RUNROOT   = Join-Path $U "runtime\paper"
$LOGS      = Join-Path $RUNROOT "logs"
$LOCKDIR   = Join-Path $RUNROOT "state\locks"
New-Item -ItemType Directory -Force $LOGS,$LOCKDIR | Out-Null

$mgrLog     = Join-Path $LOGS "family_aware_governor_v1_events.jsonl"
$mgrLock    = Join-Path $LOCKDIR "ORG_UNIFIED_FAMILY_AWARE_GOVERNOR_V1.lock"
$resultPath = Join-Path $OutDir "RESULT.txt"
$rogueLog   = Join-Path $OutDir "audit\rogue_family_kills.txt"
$extraLog   = Join-Path $OutDir "audit\extra_member_kills.txt"
$famSnap    = Join-Path $OutDir "audit\family_snapshots.jsonl"

$primaryRootPid          = 0
$ownerPid                = 0
$rogueFamilyKillCount    = 0
$extraMemberKillCount    = 0
$count1                  = -1
$count3                  = -1
$count12                 = -1
$count20                 = -1
$familyCount20           = -1
$primaryMemberCount20    = -1
$metaGrowth              = -1
$failReason              = "UNSET"
$managerException        = ""

function WL([string]$kind, [hashtable]$payload=@{}) {
  $row = [ordered]@{
    ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    kind = $kind
    host_pid = $PID
    payload = $payload
  } | ConvertTo-Json -Compress -Depth 12
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
  $pyProcs = @(Get-ProjectPython | Sort-Object ProcessId)
  $pyProcs | Format-List | Out-File -LiteralPath $PathOut -Encoding utf8
  return $pyProcs
}

function Build-Families($procs) {
  $procMap = @{}
  foreach($p in $procs){
    $procMap[[string]$p.ProcessId] = $p
  }

  $roots = @{}
  foreach($p in $procs){
    $current = $p
    $safety = 0
    while ($true) {
      $safety++
      if ($safety -gt 20) { break }

      $parentId = [int]$current.ParentProcessId
      if ($parentId -le 0) { break }

      $parentKey = [string]$parentId
      if (-not $procMap.ContainsKey($parentKey)) { break }

      $current = $procMap[$parentKey]
    }
    $rootPid = [int]$current.ProcessId
    if (-not $roots.ContainsKey($rootPid)) {
      $roots[$rootPid] = New-Object System.Collections.ArrayList
    }
    [void]$roots[$rootPid].Add($p)
  }

  return $roots
}

function Write-FamilySnapshot($families, [int]$sec) {
  $payload = @()
  foreach($k in ($families.Keys | Sort-Object)){
    $members = @($families[$k] | Sort-Object ProcessId | ForEach-Object {
      [ordered]@{
        pid  = $_.ProcessId
        ppid = $_.ParentProcessId
        cmd  = $_.CommandLine
      }
    })
    $payload += [ordered]@{
      root_pid = [int]$k
      member_count = @($families[$k]).Count
      members = $members
    }
  }

  $row = [ordered]@{
    ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    sec = $sec
    family_count = @($families.Keys).Count
    families = $payload
  } | ConvertTo-Json -Compress -Depth 15

  Add-Content -LiteralPath $famSnap -Value $row -Encoding utf8
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
    WL "governor_lock_acquired" @{ lock = $mgrLock }
  } catch {
    $failReason = "GOVERNOR_LOCK_ALREADY_EXISTS"
    WL "governor_lock_blocked" @{ lock = $mgrLock; error = $_.Exception.Message }
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

  $metaBefore = if(Test-Path $metaEv){
    (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines
  } else { 0 }

  $args = @($ENTRYSAFE,"--run","--profile",$Profile,"--iters","999999","--sleep","0.5")
  $launchProc = Start-Process -FilePath $PY `
    -ArgumentList $args `
    -WorkingDirectory $CODE `
    -RedirectStandardOutput $stdOut `
    -RedirectStandardError  $stdErr `
    -PassThru

  $ownerPid = $launchProc.Id
  $primaryRootPid = $ownerPid
  $failReason = "RUNNING"

  WL "primary_launch" @{
    owner_pid = $ownerPid
    root_pid  = $primaryRootPid
    args      = ($args -join " ")
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $snap1 = $false
  $snap3 = $false
  $snap12 = $false
  $snap20 = $false

  while ($true) {
    Start-Sleep -Milliseconds 500

    $all = @(Get-ProjectPython | Sort-Object ProcessId)
    $families = Build-Families $all
    Write-FamilySnapshot -families $families -sec ([int][Math]::Floor($sw.Elapsed.TotalSeconds))

    # اگر root واقعی family owner تغییر کرد ولی همان family است، primaryRootPid را sync کن
    if ($families.ContainsKey($primaryRootPid)) {
      # good
    } else {
      foreach($rootPid in $families.Keys){
        $members = @($families[$rootPid])
        $hasOwner = @($members | Where-Object { $_.ProcessId -eq $ownerPid }).Count -gt 0
        if ($hasOwner) {
          $primaryRootPid = [int]$rootPid
          WL "primary_root_rebased" @{ new_root_pid = $primaryRootPid; owner_pid = $ownerPid }
          break
        }
      }
    }

    # kill rogue families
    foreach($rootPid in @($families.Keys)) {
      if ([int]$rootPid -ne [int]$primaryRootPid) {
        $members = @($families[$rootPid])
        foreach($procObj in $members) {
          try {
            Stop-Process -Id $procObj.ProcessId -Force -ErrorAction Stop
            $rogueFamilyKillCount++
            Add-Content -LiteralPath $rogueLog -Value ("KILLED_ROGUE PID=" + $procObj.ProcessId + " ROOT=" + $rootPid + " PPID=" + $procObj.ParentProcessId + " CMD=" + $procObj.CommandLine) -Encoding utf8
            WL "rogue_family_kill" @{ root_pid = [int]$rootPid; killed_pid = $procObj.ProcessId; ppid = $procObj.ParentProcessId }
          } catch {
            Add-Content -LiteralPath $rogueLog -Value ("KILL_FAIL PID=" + $procObj.ProcessId + " ROOT=" + $rootPid + " ERR=" + $_.Exception.Message) -Encoding utf8
            WL "rogue_family_kill_fail" @{ root_pid = [int]$rootPid; killed_pid = $procObj.ProcessId; error = $_.Exception.Message }
          }
        }
      }
    }

    # rebuild after rogue kills
    $all = @(Get-ProjectPython | Sort-Object ProcessId)
    $families = Build-Families $all

    # trim primary family to max 2 members
    if ($families.ContainsKey($primaryRootPid)) {
      $primaryMembers = @($families[$primaryRootPid] | Sort-Object ProcessId)
      if (@($primaryMembers).Count -gt 2) {
        $toKeep = @()
        $rootMember = $primaryMembers | Where-Object { $_.ProcessId -eq $primaryRootPid } | Select-Object -First 1
        if ($null -ne $rootMember) { $toKeep += $rootMember }
        $childOfRoot = $primaryMembers | Where-Object { $_.ParentProcessId -eq $primaryRootPid } | Select-Object -First 1
        if (($null -ne $childOfRoot) -and ($toKeep.ProcessId -notcontains $childOfRoot.ProcessId)) { $toKeep += $childOfRoot }
        if (@($toKeep).Count -lt 2) {
          foreach($m in $primaryMembers) {
            if (@($toKeep | ForEach-Object { $_.ProcessId }) -notcontains $m.ProcessId) {
              $toKeep += $m
              if (@($toKeep).Count -ge 2) { break }
            }
          }
        }

        $keepIds = @($toKeep | ForEach-Object { $_.ProcessId })
        foreach($procObj in $primaryMembers) {
          if ($keepIds -notcontains $procObj.ProcessId) {
            try {
              Stop-Process -Id $procObj.ProcessId -Force -ErrorAction Stop
              $extraMemberKillCount++
              Add-Content -LiteralPath $extraLog -Value ("KILLED_EXTRA_MEMBER PID=" + $procObj.ProcessId + " ROOT=" + $primaryRootPid + " PPID=" + $procObj.ParentProcessId + " CMD=" + $procObj.CommandLine) -Encoding utf8
              WL "extra_member_kill" @{ root_pid = [int]$primaryRootPid; killed_pid = $procObj.ProcessId; ppid = $procObj.ParentProcessId }
            } catch {
              Add-Content -LiteralPath $extraLog -Value ("KILL_FAIL_EXTRA PID=" + $procObj.ProcessId + " ERR=" + $_.Exception.Message) -Encoding utf8
              WL "extra_member_kill_fail" @{ root_pid = [int]$primaryRootPid; killed_pid = $procObj.ProcessId; error = $_.Exception.Message }
            }
          }
        }
      }
    }

    $sec = [int][Math]::Floor($sw.Elapsed.TotalSeconds)

    if (-not $snap1 -and $sec -ge 1) {
      $p1 = @(Snapshot-Procs (Join-Path $OutDir "cert\processes_t1.txt"))
      $count1 = @($p1).Count
      $snap1 = $true
      WL "snapshot_t1" @{ count = $count1 }
    }

    if (-not $snap3 -and $sec -ge 3) {
      $p3 = @(Snapshot-Procs (Join-Path $OutDir "cert\processes_t3.txt"))
      $count3 = @($p3).Count
      $snap3 = $true
      WL "snapshot_t3" @{ count = $count3 }
    }

    if (-not $snap12 -and $sec -ge 12) {
      $p12 = @(Snapshot-Procs (Join-Path $OutDir "cert\processes_t12.txt"))
      $count12 = @($p12).Count
      $snap12 = $true
      WL "snapshot_t12" @{ count = $count12 }
    }

    if (-not $snap20 -and $sec -ge 20) {
      $p20 = @(Snapshot-Procs (Join-Path $OutDir "cert\processes_t20.txt"))
      $count20 = @($p20).Count
      $snap20 = $true

      $all20 = @(Get-ProjectPython | Sort-Object ProcessId)
      $families20 = Build-Families $all20
      $familyCount20 = @($families20.Keys).Count
      if ($families20.ContainsKey($primaryRootPid)) {
        $primaryMemberCount20 = @($families20[$primaryRootPid]).Count
      } else {
        $primaryMemberCount20 = 0
      }

      $failReason = "CERT_WINDOW_COMPLETE"
      WL "snapshot_t20" @{
        count = $count20
        family_count = $familyCount20
        primary_member_count = $primaryMemberCount20
      }
      break
    }
  }

  if (Test-Path $metaEv) {
    Get-Content -LiteralPath $metaEv -Tail 120 |
      Out-File -LiteralPath (Join-Path $OutDir "audit\meta_events_tail120.txt") -Encoding utf8
  }

  $metaAfter = if(Test-Path $metaEv){
    (Get-Content -LiteralPath $metaEv | Measure-Object -Line).Lines
  } else { 0 }
  $metaGrowth = [int]($metaAfter - $metaBefore)

} catch {
  $managerException = $_.Exception.ToString()
  if ($failReason -eq "UNSET") { $failReason = "GOVERNOR_EXCEPTION" }
  WL "governor_exception" @{ error = $managerException }
} finally {
  try {
    $live = @(Get-ProjectPython)
    foreach($procObj in $live){
      try { Stop-Process -Id $procObj.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
  } catch {}

  try {
    if(Test-Path $mgrLock){ Remove-Item -LiteralPath $mgrLock -Force -ErrorAction SilentlyContinue }
  } catch {}

  $pass = (($familyCount20 -eq 1) -and ($primaryMemberCount20 -ge 1) -and ($primaryMemberCount20 -le 2) -and ($metaGrowth -gt 0))

  @(
    "RESULT=" + ($(if($pass){"PASS"}else{"FAIL"}))
    "PRIMARY_FAMILY_ROOT_PID=$primaryRootPid"
    "OWNER_PID=$ownerPid"
    "COUNT_AFTER_1S=$count1"
    "COUNT_AFTER_3S=$count3"
    "COUNT_AFTER_12S=$count12"
    "COUNT_AFTER_20S=$count20"
    "FAMILY_COUNT_T20=$familyCount20"
    "PRIMARY_FAMILY_MEMBER_COUNT_T20=$primaryMemberCount20"
    "ROGUE_FAMILY_KILL_COUNT=$rogueFamilyKillCount"
    "EXTRA_MEMBER_KILL_COUNT=$extraMemberKillCount"
    "META_EVENTS_GROWTH=$metaGrowth"
    "FAIL_REASON=$failReason"
    "MANAGER_EXCEPTION=$managerException"
    "GOVERNOR_LOG=$mgrLog"
    "ROGUE_FAMILY_KILL_LOG=$rogueLog"
    "EXTRA_MEMBER_KILL_LOG=$extraLog"
  ) | Out-File -LiteralPath $resultPath -Encoding utf8
}
