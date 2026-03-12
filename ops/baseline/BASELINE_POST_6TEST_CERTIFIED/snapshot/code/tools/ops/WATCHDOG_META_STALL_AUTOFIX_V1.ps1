param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [int]$MetaStallSec = 120,
  [int]$HbStallSec = 120,
  [int]$WarmupSec = 10,
  [int]$MaxRestarts = 2
)

$ErrorActionPreference="Stop"

function UtcNow(){ [DateTime]::UtcNow }
function AgeSec([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(!(Test-Path -LiteralPath $Path)){ return $null }
  return [int]((UtcNow) - (Get-Item -LiteralPath $Path).LastWriteTimeUtc).TotalSeconds
}
function Log([string]$msg){
  $ts = (UtcNow).ToString("s") + "Z"
  $msg2 = "$ts $msg"
  $msg2 | Out-Host
  Add-Content -Encoding UTF8 -LiteralPath $Audit -Value $msg2
}

$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Audit = Join-Path $ops ("WATCHDOG_META_STALL_{0}.log" -f $stamp)

$meta = Join-Path $RunRoot "logs\meta.jsonl"
$hb   = Join-Path $RunRoot "state\heartbeat.json"
$pidf = Join-Path $RunRoot "state\pid.txt"
$lock = Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"
$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

Log "START Root=$Root RunRoot=$RunRoot MetaStallSec=$MetaStallSec HbStallSec=$HbStallSec WarmupSec=$WarmupSec MaxRestarts=$MaxRestarts"
Log "PATH meta=$meta hb=$hb pid=$pidf lock=$lock runner=$runner"

function ReadBotPid(){
  if(Test-Path -LiteralPath $pidf){
    $s = (Get-Content -Raw -LiteralPath $pidf -ErrorAction SilentlyContinue)
    if($s){ return $s.Trim() }
  }
  return $null
}

function KillPaperBots(){
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\paper*" } |
    ForEach-Object {
      Log ("KILL python pid={0}" -f $_.ProcessId)
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function ClearLock(){
  if(Test-Path -LiteralPath $lock){
    Log "REMOVE_LOCK $lock"
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
  }
}

function StartRunner(){
  Log "START_RUNNER Force=1"
  # note: runner itself should spawn python; we just invoke it
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Force 1
  $ec = $LASTEXITCODE
  Log ("RUNNER_EXITCODE={0}" -f $ec)
  return $ec
}

# -------------------------
# 2) Check + optional restart loop
# -------------------------
for($r=0; $r -le $MaxRestarts; $r++){
  $botPid = ReadBotPid
  $alive = $false
  if($botPid -and ($botPid -match '^\d+$')){
    $alive = [bool](Get-Process -Id ([int]$botPid) -ErrorAction SilentlyContinue)
  }

  $metaAge = AgeSec $meta
  $hbAge   = AgeSec $hb

  Log ("CHECK r={0} botpid={1} alive={2} metaAge={3} hbAge={4}" -f $r,($botPid ?? "-"),$alive,($metaAge ?? -1),($hbAge ?? -1))

  $metaStale = ($metaAge -ne $null) -and ($metaAge -ge $MetaStallSec)
  $hbStale   = ($hbAge   -ne $null) -and ($hbAge   -ge $HbStallSec)

  if(-not $metaStale -and -not $hbStale){
    Log "OK meta/hb not stale => DONE"
    break
  }

  if($r -eq $MaxRestarts){
    Log "FATAL stale after max restarts"
    break
  }

  Log "STALL detected => RESTART sequence"
  KillPaperBots
  ClearLock

  $ec = StartRunner

  Log ("WARMUP {0}s" -f $WarmupSec)
  Start-Sleep -Seconds $WarmupSec

  $metaAge2 = AgeSec $meta
  $hbAge2   = AgeSec $hb
  Log ("POSTCHECK metaAge={0} hbAge={1}" -f ($metaAge2 ?? -1), ($hbAge2 ?? -1))

  if(($metaAge2 -ne $null) -and ($metaAge2 -le [Math]::Min(15,$MetaStallSec))){
    Log "RECOVERED meta fresh => DONE"
    break
  }
}

Log "END"
"AuditLog=$Audit" | Out-Host
