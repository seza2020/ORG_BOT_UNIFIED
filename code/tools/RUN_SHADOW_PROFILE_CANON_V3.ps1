param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$false)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [Parameter(Mandatory=$true)][string]$InnerScriptPath,
  [int]$Force = 0
)
$ErrorActionPreference="Stop"

function EnsureDir([string]$p){ if($p){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Finger([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $n=$s.Length
  $a=$s.Substring(0,[Math]::Min(4,$n))
  $b=$s.Substring([Math]::Max(0,$n-4))
  return ($a + "****" + $b)
}

# RUN_SHADOW_PROFILE_CANON_V3
if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
$prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

if([string]::IsNullOrWhiteSpace($RunRoot)){
  if($prof.runroot){ $RunRoot=[string]$prof.runroot }
  elseif($prof.runtime){ $RunRoot=[string]$prof.runtime }
}
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_EMPTY" }
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }
if(!(Test-Path $InnerScriptPath)){ throw ("INNER_SCRIPT_NOT_FOUND=" + $InnerScriptPath) }

$ops = Join-Path $RunRoot "logs\ops"
EnsureDir $ops

$ymd = (Get-Date).ToString("yyyyMMdd")
$lo  = Join-Path $ops ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
$le  = Join-Path $ops ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)
$hb  = Join-Path $ops "HEARTBEAT_SHADOW_RUNNER.txt"
$pidFile = Join-Path $RunRoot "PID"

# load secrets (SHADOW)
$ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
. $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# single instance check
if(Test-Path $pidFile){
  $oldPid = 0
  try{ $oldPid = [int]((Get-Content $pidFile -ErrorAction SilentlyContinue | Select -First 1).Trim()) } catch {}
  if($oldPid -gt 0){
    $p = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if($p -and $Force -ne 1){
      @(
        "PROFILE=SHADOW"
        ("RUNROOT=" + $RunRoot)
        ("BLOCK=already_running pid=" + $oldPid)
        ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))
      ) | Set-Content -Encoding UTF8 -Path $lo
      exit 0
    }
    if($p -and $Force -eq 1){
      try{ Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
}

# launch inner DETACHED (so this wrapper never hangs)
$pwsh="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwsh)){ $pwsh=(Get-Command powershell.exe).Source }

# IMPORTANT: redirect stdout/stderr directly to LIVE_*_LATEST
$argLine = @(
  "-NoProfile"
  "-ExecutionPolicy Bypass"
  ("-File `"" + $InnerScriptPath + "`"")
  ("-ProjectRoot `"" + $ProjectRoot + "`"")
  ("-RunRoot `"" + $RunRoot + "`"")
) -join " "

$proc = Start-Process -FilePath $pwsh -ArgumentList $argLine -WorkingDirectory $ProjectRoot `
  -RedirectStandardOutput $lo -RedirectStandardError $le -PassThru

# write PID + heartbeat (wrapper exits 0 always)
Set-Content -Encoding UTF8 -Path $pidFile -Value $proc.Id
@(
  ("ts=" + (Get-Date).ToString("s"))
  ("ymd=" + $ymd)
  ("core_exit=LAUNCHED pid=" + $proc.Id)
) | Set-Content -Encoding UTF8 -Path $hb

exit 0
