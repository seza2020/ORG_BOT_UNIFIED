$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$CODE    = Join-Path $U "code"
$LOGS    = Join-Path $U "runtime\paper\logs"
$GUARD   = Join-Path $WRAPDIR "CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH.ps1"
$PWSH    = "C:\Program Files\PowerShell\7\pwsh.exe"

if (!(Test-Path -LiteralPath $GUARD)) { throw "GUARD_NOT_FOUND=$GUARD" }

function Get-LineCount {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return -3 }
  if (!(Test-Path -LiteralPath $Path)) { return -1 }
  try { return (Get-Content -LiteralPath $Path -Encoding UTF8 | Measure-Object -Line).Lines }
  catch { return -2 }
}

function Get-TbotProcesses {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId, ParentProcessId, Name, CommandLine)
  } catch {
    return @()
  }
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$SUM  = Join-Path $OUT "summary"
New-Item -ItemType Directory -Force -Path $OUT, $AUD, $SUM | Out-Null

$metaEvents = Join-Path $LOGS "meta_events.jsonl"
$metaEngine = Join-Path $LOGS "meta_engine.jsonl"
$guardLog   = Join-Path $LOGS "single_instance_guard_v2.jsonl"

$beforeMetaEvents = Get-LineCount -Path $metaEvents
$beforeMetaEngine = Get-LineCount -Path $metaEngine
$beforeGuardLog   = Get-LineCount -Path $guardLog

$stdout = Join-Path $AUD "guard_stdout.txt"
$stderr = Join-Path $AUD "guard_stderr.txt"

$proc = Start-Process -FilePath $PWSH `
  -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$GUARD) `
  -WorkingDirectory $CODE `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr `
  -PassThru

Start-Sleep -Seconds 12
$count12 = @(Get-TbotProcesses).Count
Start-Sleep -Seconds 8
$count20 = @(Get-TbotProcesses).Count

$guardAlive20 = $false
try {
  $probe = Get-Process -Id $proc.Id -ErrorAction Stop
  if ($probe) { $guardAlive20 = $true }
} catch {}

$guardExitCode = $null
try { $guardExitCode = $proc.ExitCode } catch {}

$afterMetaEvents = Get-LineCount -Path $metaEvents
$afterMetaEngine = Get-LineCount -Path $metaEngine
$afterGuardLog   = Get-LineCount -Path $guardLog

$metaEventsGrowth = $afterMetaEvents - $beforeMetaEvents
$metaEngineGrowth = $afterMetaEngine - $beforeMetaEngine
$guardLogGrowth   = $afterGuardLog - $beforeGuardLog

$decision = "UNKNOWN"
if (Test-Path -LiteralPath $guardLog) {
  try {
    $raw = Get-Content -LiteralPath $guardLog -Raw -Encoding UTF8
    if ($raw -match "post_launch_cert_pass") {
      $decision = "POST_LAUNCH_CERT_PASS"
    } elseif ($raw -match "launch_blocked_existing_process") {
      $decision = "ALREADY_RUNNING_BLOCKED"
    } elseif ($raw -match "post_launch_cert_fail_duplicate") {
      $decision = "POST_LAUNCH_CERT_FAIL_DUPLICATE"
    } elseif ($raw -match "post_launch_cert_fail_no_process") {
      $decision = "POST_LAUNCH_CERT_FAIL_NO_PROCESS"
    }
  } catch {}
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
try {
  if ($guardAlive20) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
} catch {}

@(
  "CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH_CERTIFY_DONE"
  ("OUT=" + $OUT)
  ("COUNT_AFTER_12S=" + $count12)
  ("COUNT_AFTER_20S=" + $count20)
  ("GUARD_ALIVE_AFTER_20S=" + $guardAlive20)
  ("GUARD_EXIT_CODE=" + $guardExitCode)
  ("META_EVENTS_GROWTH=" + $metaEventsGrowth)
  ("META_ENGINE_GROWTH=" + $metaEngineGrowth)
  ("GUARD_LOG_GROWTH=" + $guardLogGrowth)
  ("GUARD_DECISION=" + $decision)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $count12)
("COUNT_AFTER_20S=" + $count20)
("GUARD_ALIVE_AFTER_20S=" + $guardAlive20)
("GUARD_EXIT_CODE=" + $guardExitCode)
("META_EVENTS_GROWTH=" + $metaEventsGrowth)
("META_ENGINE_GROWTH=" + $metaEngineGrowth)
("GUARD_LOG_GROWTH=" + $guardLogGrowth)
("GUARD_DECISION=" + $decision)
