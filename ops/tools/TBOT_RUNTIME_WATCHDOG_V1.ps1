param(
  [Parameter(Mandatory=$false)][ValidateSet("PAPER","SHADOW","LIVE")][string]$Profile="PAPER",
  [Parameter(Mandatory=$false)][string]$Root="C:\alpaca-bot\ORG_BOT_UNIFIED",
  [Parameter(Mandatory=$false)][int]$IntervalSec=5,
  [Parameter(Mandatory=$false)][int]$MaxCount=1
)

$ErrorActionPreference="Stop"

$rt = Join-Path $Root ("runtime\" + $Profile.ToLower())
$logs = Join-Path $rt "logs"
$evidence = Join-Path (Join-Path $Root "ops") "evidence"
New-Item -ItemType Directory -Force $logs,$evidence | Out-Null

$logPath = Join-Path $logs "ops_watchdog.log"

function WL([string]$m){
  Add-Content -LiteralPath $logPath -Value (("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $m))
}

function GetTbotProcs(){
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match "tbot\.main" } |
    Select-Object ProcessId,ParentProcessId,CommandLine
}

function BundleEvidence([string]$reason){
  try {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $out = Join-Path $evidence ("WATCHDOG_INCIDENT_" + $Profile + "_" + $ts)
    $a = Join-Path $out "audit"
    $l = Join-Path $out "logs"
    New-Item -ItemType Directory -Force $out,$a,$l | Out-Null

    $procs = GetTbotProcs
    ($procs | Format-List | Out-String) | Out-File -LiteralPath (Join-Path $a "tbot_procs.txt") -Encoding utf8

    $srcLogs = @(
      "ops_guard.log","ops_watchdog.log",
      "meta_events.jsonl","meta_engine.jsonl",
      "spawn_trap.jsonl","createprocess_trap.jsonl",
      "supervisor_daemon.log","supervisor_runner.log"
    )
    foreach($f in $srcLogs){
      $src = Join-Path $logs $f
      if(Test-Path $src){
        Copy-Item -LiteralPath $src -Destination (Join-Path $l $f) -Force
      }
    }

    "REASON=$reason" | Out-File -LiteralPath (Join-Path $out "SUMMARY.txt") -Encoding utf8

    $zip = $out + ".zip"
    if(Test-Path $zip){ Remove-Item -Force $zip }
    Compress-Archive -Path $out -DestinationPath $zip -Force
    WL("EVIDENCE_ZIP=$zip")
  } catch {
    WL("EVIDENCE_FAIL ERR=$_")
  }
}

WL("WATCHDOG_START Profile=$Profile IntervalSec=$IntervalSec MaxCount=$MaxCount")

while($true){
  try {
    $procs = GetTbotProcs
    $cnt = $procs.Count
    if($cnt -gt $MaxCount){
      WL("INCIDENT DETECTED count=$cnt")
      $victim = $procs | Sort-Object ProcessId -Descending | Select-Object -First 1
      WL(("KILL PID={0} PPID={1}" -f $victim.ProcessId, $victim.ParentProcessId))
      try { Stop-Process -Id $victim.ProcessId -Force -ErrorAction Stop } catch { WL("KILL_FAIL ERR=$_") }
      BundleEvidence ("COUNT_GT_" + $MaxCount)
    }
  } catch {
    WL("LOOP_ERR ERR=$_")
  }
  Start-Sleep -Seconds $IntervalSec
}
