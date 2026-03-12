# _LIB_SINGLE_INSTANCE.ps1 (English-only)
Set-StrictMode -Version Latest

function Enter-OrgUnifiedSingleInstance {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("PAPER","SHADOW")] [string]$Profile,
    [Parameter(Mandatory=$true)] [string]$RuntimeRoot,
    [Parameter(Mandatory=$true)] [string]$WrapperLogPath
  )

  $lockDir = Join-Path $RuntimeRoot "state\locks"
  New-Item -ItemType Directory -Force -Path $lockDir | Out-Null

  # HARD RULE: only ONE of PAPER/SHADOW may run at a time
  $anyName = "Global\ORG_BOT_UNIFIED_ANY"
  $anyCreated = $false
  $anyMutex = New-Object System.Threading.Mutex($true, $anyName, [ref]$anyCreated)
  if(-not $anyCreated){
    "[SINGLE_INSTANCE] BLOCKED: system already running (ANY lock): $anyName" | Out-File -FilePath $WrapperLogPath -Append -Encoding utf8
    return $null
  }

  # Per-profile mutex (secondary)
  $profName = "Global\ORG_BOT_UNIFIED_$Profile"
  $profCreated = $false
  $profMutex = New-Object System.Threading.Mutex($true, $profName, [ref]$profCreated)
  if(-not $profCreated){
    "[SINGLE_INSTANCE] BLOCKED: profile already held: $profName" | Out-File -FilePath $WrapperLogPath -Append -Encoding utf8
    try { $anyMutex.ReleaseMutex() } catch {}
    return $null
  }

  # Secondary guard: process scan (array-safe)
  $needle = "-m tbot.main"
  $procs = @(
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
      Where-Object { $_.CommandLine -and $_.CommandLine -like "*$needle*" }
  )

  $isShadow = ($Profile -eq "SHADOW")
  $match = @(
    $procs | Where-Object {
      if($isShadow){ $_.CommandLine -like "* --shadow *" } else { $_.CommandLine -notlike "* --shadow *" }
    }
  )

  if($match.Count -gt 0){
    "[SINGLE_INSTANCE] BLOCKED: existing process(es) detected: $($match.Count)" | Out-File -FilePath $WrapperLogPath -Append -Encoding utf8
    try { $profMutex.ReleaseMutex() } catch {}
    try { $anyMutex.ReleaseMutex() } catch {}
    return $null
  }

  # Return BOTH mutexes so wrapper can release both
  return @($anyMutex, $profMutex)
}
