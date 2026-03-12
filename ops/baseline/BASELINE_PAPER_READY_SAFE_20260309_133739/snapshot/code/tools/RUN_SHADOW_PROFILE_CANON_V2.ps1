param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot",
  [string]$RunRoot     = "C:\alpaca-bot\org_bot_runtime\shadow",
  [string]$ProfilePath = "C:\alpaca-bot\org_bot\tools\profiles\shadow.profile.json",
  [string]$InnerScriptPath = "",  # backward-compat (ignored)
  
# OBS_ENV_INJECT_V1
$env:TBOT_RUNROOT = "C:\alpaca-bot\org_bot_runtime\shadow"
$env:TBOT_RUNTIME = $env:TBOT_RUNROOT
[int]$Force = 0
)
$ErrorActionPreference="Stop"

# SHADOW_WRAPPER_ROOTFIX_V1 (no hang; PID-based; no prompts)

function EnsureDir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Finger([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $n=$s.Length
  ($s.Substring(0,[Math]::Min(4,$n)) + "****" + $s.Substring([Math]::Max(0,$n-4)))
}
function W([string]$p,[string]$s){ Add-Content -Encoding UTF8 -Path $p -Value $s }

if([string]::IsNullOrWhiteSpace($RunRoot)){ $RunRoot="C:\alpaca-bot\org_bot_runtime\shadow" }
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }

$logs = Join-Path $RunRoot "logs"
$ops  = Join-Path $logs "ops"
EnsureDir $logs; EnsureDir $ops

$ymd = (Get-Date).ToString("yyyyMMdd")
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"

$liveOutLatest = Join-Path $ops ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
$liveErrLatest = Join-Path $ops ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)

$wrapOut = Join-Path $ops ("LIVE_OUT_{0}_{1}.txt" -f $ymd,$ts)
$pyOut   = Join-Path $ops ("PY_OUT_{0}_{1}.txt"   -f $ymd,$ts)
$pyErr   = Join-Path $ops ("PY_ERR_{0}_{1}.txt"   -f $ymd,$ts)

"" | Set-Content -Encoding UTF8 -Path $wrapOut
"" | Set-Content -Encoding UTF8 -Path $pyOut
"" | Set-Content -Encoding UTF8 -Path $pyErr

$hb   = Join-Path $ops "HEARTBEAT_SHADOW_RUNNER.txt"
$pidf = Join-Path $RunRoot "PID"

function StampLatest(){
  try{ Copy-Item $wrapOut $liveOutLatest -Force } catch {}
  try{ Copy-Item $pyErr   $liveErrLatest -Force } catch {}
}
function WriteHB([string]$msg,[string]$pidValue=""){
  @(
    ("ts=" + (Get-Date).ToString("s")),
    ("ymd=" + $ymd),
    ("core_exit=" + $msg)
  ) + ($(if($pidValue){ @("pid=" + $pidValue) } else { @() })) | Set-Content -Encoding UTF8 -Path $hb
}

function GetPidLock(){
  try{
    if(Test-Path $pidf){
      $s = (Get-Content -Raw -Encoding UTF8 $pidf).Trim()
      if($s -match '^\d+$'){ return [int]$s }
    }
  } catch {}
  return $null
}

function IsShadowTbotPid([int]$pidValue){
  # quick check: does process exist?
  try { $p = Get-Process -Id $pidValue -ErrorAction Stop } catch { return $false }

  # safe check: fetch commandline ONLY for this PID (timeout)
  try{
    $ci = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $pidValue) -OperationTimeoutSec 2 -ErrorAction SilentlyContinue
    if($ci -and $ci.CommandLine){
      if($ci.CommandLine -match 'tbot\.main' -and $ci.CommandLine -match '(?i)--shadow\b'){ return $true }
      # if PID file points to python but cmdline missing, still treat as ours (conservative)
      if($ci.Name -match '(?i)python'){ return $true }
      return $false
    }
  } catch {}
  # if CIM fails, but PID exists and is python, assume ours (avoid duplicate runs)
  try{
    if($p.ProcessName -match '(?i)python'){ return $true }
  } catch {}
  return $false
}

try{
  W $wrapOut ("ts=" + (Get-Date).ToString("s"))
  W $wrapOut "PROFILE=SHADOW"
  W $wrapOut ("RUNROOT=" + $RunRoot)

  if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
  $prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

  # load secrets (masked output only)
  $ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
  if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
  . $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

  $act = ([string]$env:TBOT_PROFILE).Trim().ToUpper()
  if($act -ne "SHADOW"){ throw ("TBOT_PROFILE_MISMATCH expected=SHADOW actual=" + $act) }

  # Always enforce boot guard bypass for shadow
  $env:TBOT_ALLOW_BOOT_OVERRUN = "1"
  $env:TBOT_MAX_BOOTS_PER_DAY  = "50"

  # Apply profile.env (all first, TBOT_SHADOW_PRICE_MODE LAST)
  if($prof.env){
    foreach($p in $prof.env.PSObject.Properties){
      if($p.Name -ne "TBOT_SHADOW_PRICE_MODE"){
        Set-Item -Path ("Env:" + $p.Name) -Value ([string]$p.Value) -ErrorAction SilentlyContinue
      }
    }
    if($prof.env.TBOT_SHADOW_PRICE_MODE){
      Set-Item -Path "Env:TBOT_SHADOW_PRICE_MODE" -Value ([string]$prof.env.TBOT_SHADOW_PRICE_MODE) -ErrorAction SilentlyContinue
    }
  }

  W $wrapOut ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))

  # PID-lock based running guard (NO global scan)
  $lockPid = GetPidLock
  if($lockPid){
    if(IsShadowTbotPid $lockPid){
      if($Force -ne 1){
        W $wrapOut ("BLOCK_BY_PID pid=" + $lockPid + " (use -Force 1)")
        StampLatest
        WriteHB ("BLOCK_BY_PID pid=" + $lockPid) ([string]$lockPid)
        exit 0
      } else {
        try{ Stop-Process -Id $lockPid -Force -ErrorAction SilentlyContinue } catch {}
        Start-Sleep -Seconds 2
      }
    }
    # stale/unknown -> clear
    try{ Remove-Item $pidf -Force -ErrorAction SilentlyContinue } catch {}
  }

  # python exe
  $py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $py)){ $py = "python" }

  # args (NO positional RunRoot)
  $meta = Join-Path $RunRoot "logs\meta.jsonl"
  $ann  = Join-Path $RunRoot "logs\announce_shadow.log"
  $led  = Join-Path $RunRoot "logs\ledger"
  EnsureDir (Split-Path $led -Parent); EnsureDir $led

  $args = @(
    "-u","-m","tbot.main",
    "--run","--iters","999999","--sleep","0.25",
    "--meta",$meta,
    "--announce",$ann,
    "--ledger_dir",$led,
    "--shadow",
    "--shadow_path",$RunRoot
  )

  try{
    $g = $prof.gate
    if($g){
      if($null -ne $g.min_rr){             $args += @("--gate_min_rr",            ([string]$g.min_rr)) }
      if($null -ne $g.min_confidence){    $args += @("--gate_min_conf",          ([string]$g.min_confidence)) }
      elseif($null -ne $g.min_conf){      $args += @("--gate_min_conf",          ([string]$g.min_conf)) }
      if($null -ne $g.cooldown_sec){      $args += @("--gate_cooldown_sec",      ([string]$g.cooldown_sec)) }
      if($null -ne $g.max_plans_per_day){ $args += @("--gate_max_plans_per_day", ([string]$g.max_plans_per_day)) }
      if($null -ne $g.max_risk_usd){      $args += @("--gate_max_risk_usd",      ([string]$g.max_risk_usd)) }
    }
  } catch {}

  try{
    if($prof.sim -and ($prof.sim.in_session -eq 1)){ $args += @("--sim_in_session","1") }
  } catch {}

  W $wrapOut ("PY=" + $py)
  W $wrapOut ("ARGS=" + ($args -join " "))

  $proc = Start-Process -FilePath $py -ArgumentList $args -WorkingDirectory $ProjectRoot -PassThru `
    -RedirectStandardOutput $pyOut -RedirectStandardError $pyErr

  Set-Content -Encoding UTF8 -Path $pidf -Value $proc.Id

  Start-Sleep -Seconds 2
  if($proc.HasExited){
    $code = $proc.ExitCode
    W $wrapOut ("EXITED_IMMEDIATELY exitcode=" + $code + " pid=" + $proc.Id)
    StampLatest
    WriteHB ("EXITED_IMMEDIATELY exitcode=" + $code) ([string]$proc.Id)
    exit 0
  }

  W $wrapOut ("LAUNCHED pid=" + $proc.Id)
  StampLatest
  WriteHB ("LAUNCHED pid=" + $proc.Id) ([string]$proc.Id)
  exit 0
}catch{
  W $wrapOut ("WRAPPER_EXC=" + $_.Exception.Message)
  StampLatest
  WriteHB "WRAPPER_EXC"
  exit 1
}


