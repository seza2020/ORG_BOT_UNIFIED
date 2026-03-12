param()

$lockPath = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\locks\tbot_main.lock"
$lockPid = $null

if (Test-Path $lockPath) {
  try {
    $txt = (Get-Content $lockPath -Raw).Trim()
    if ($txt) { $lockPid = [int]$txt }
  } catch {}
}

$allPy = @(
  Get-CimInstance Win32_Process -Filter "Name='python.exe'"
)

$procs = @(
  $allPy | Where-Object {
    ($_.CommandLine -match "tbot\.main") -or
    ($_.ExecutablePath -match "ORG_BOT_UNIFIED\\code\\\.venv\\Scripts\\python\.exe") -or
    ($_.ExecutablePath -match "C:\\Python313\\python\.exe") -or
    ($lockPid -ne $null -and [int]$_.ProcessId -eq $lockPid)
  }
)

$byPid = @{}
foreach ($p in $procs) { $byPid[[int]$p.ProcessId] = $p }

function Get-RootPid([int]$targetPid, $map) {
  $seen = @{}
  $cur = $targetPid
  while ($true) {
    if ($seen.ContainsKey($cur)) { return $cur }
    $seen[$cur] = $true

    if (-not $map.ContainsKey($cur)) { return $cur }

    $proc = $map[$cur]
    $parentPid = [int]$proc.ParentProcessId

    if ($parentPid -le 0) { return $cur }
    if (-not $map.ContainsKey($parentPid)) { return $cur }

    $parent = $map[$parentPid]

    $parentIsPython = ($parent.Name -eq "python.exe")
    $sameTree = (
      ($parent.CommandLine -match "tbot\.main") -or
      ($parent.ExecutablePath -match "ORG_BOT_UNIFIED\\code\\\.venv\\Scripts\\python\.exe") -or
      ($parent.ExecutablePath -match "C:\\Python313\\python\.exe") -or
      ($lockPid -ne $null -and [int]$parent.ProcessId -eq $lockPid)
    )

    if ($parentIsPython -and $sameTree) {
      $cur = $parentPid
      continue
    }

    return $cur
  }
}

$rows = foreach ($p in $procs) {
  [PSCustomObject]@{
    RootPid         = Get-RootPid -targetPid ([int]$p.ProcessId) -map $byPid
    ProcessId       = [int]$p.ProcessId
    ParentProcessId = [int]$p.ParentProcessId
    Name            = $p.Name
    ExecutablePath  = $p.ExecutablePath
    CommandLine     = $p.CommandLine
    IsLockPid       = ($lockPid -ne $null -and [int]$p.ProcessId -eq $lockPid)
  }
}

$families = $rows | Group-Object RootPid | ForEach-Object {
  $items = $_.Group | Sort-Object ProcessId
  [PSCustomObject]@{
    RootPid         = [int]$_.Name
    MemberCount     = $items.Count
    MemberPids      = (($items.ProcessId) -join ",")
    LockPidPresent  = (($items | Where-Object { $_.IsLockPid }).Count -gt 0)
    ExecutablePaths = (($items.ExecutablePath | Select-Object -Unique) -join " | ")
    CommandLines    = (($items.CommandLine | Select-Object -Unique) -join " || ")
  }
}

$families | Sort-Object RootPid
