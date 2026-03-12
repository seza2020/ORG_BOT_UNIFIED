$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U        = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS      = Join-Path $U "ops"
$EVID     = Join-Path $OPS "evidence"
$LOGS     = Join-Path $U "runtime\paper\logs"
$TASKNAME = "\ORG_UNIFIED_PAPER_CANONICAL_V1"

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

function Export-Tail {
  param([string]$Source,[string]$Dest,[int]$Last = 200)
  if (Test-Path -LiteralPath $Source) {
    try {
      Get-Content -LiteralPath $Source -Tail $Last -Encoding UTF8 |
        Set-Content -LiteralPath $Dest -Encoding UTF8
    } catch {
      @("TAIL_READ_ERROR=$Source", $_.Exception.Message) |
        Set-Content -LiteralPath $Dest -Encoding UTF8
    }
  } else {
    "MISSING=$Source" | Set-Content -LiteralPath $Dest -Encoding UTF8
  }
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("PATCH_RUNTIME_CHAIN_V1_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$TAIL = Join-Path $OUT "tails"
$SUM  = Join-Path $OUT "summary"

New-Item -ItemType Directory -Force -Path $OUT,$AUD,$TAIL,$SUM | Out-Null

$metaEvents  = Join-Path $LOGS "meta_events.jsonl"
$metaEngine  = Join-Path $LOGS "meta_engine.jsonl"
$launcherLog = Join-Path $LOGS "canonical_task_xml_launcher_v1.jsonl"
$loaderLog   = Join-Path $LOGS "canonical_loader_wrapper_v1.jsonl"
$paperStdout = Join-Path $LOGS "org_unified_paper_run.stdout.log"
$paperStderr = Join-Path $LOGS "org_unified_paper_run.stderr.log"

$beforeMetaEvents = Get-LineCount -Path $metaEvents
$beforeMetaEngine = Get-LineCount -Path $metaEngine
$beforeLauncher   = Get-LineCount -Path $launcherLog
$beforeLoader     = Get-LineCount -Path $loaderLog

schtasks /run /tn $TASKNAME 1> (Join-Path $AUD "schtasks_run_stdout.txt") 2> (Join-Path $AUD "schtasks_run_stderr.txt")

Start-Sleep -Seconds 12
$procs12 = @(Get-TbotProcesses)
$count12 = $procs12.Count
$procs12 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_12s.csv")

Start-Sleep -Seconds 8
$procs20 = @(Get-TbotProcesses)
$count20 = $procs20.Count
$procs20 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_20s.csv")

$afterMetaEvents = Get-LineCount -Path $metaEvents
$afterMetaEngine = Get-LineCount -Path $metaEngine
$afterLauncher   = Get-LineCount -Path $launcherLog
$afterLoader     = Get-LineCount -Path $loaderLog

$metaEventsGrowth = $afterMetaEvents - $beforeMetaEvents
$metaEngineGrowth = $afterMetaEngine - $beforeMetaEngine
$launcherGrowth   = $afterLauncher - $beforeLauncher
$loaderGrowth     = $afterLoader - $beforeLoader

foreach ($f in @($metaEvents,$metaEngine,$launcherLog,$loaderLog,$paperStdout,$paperStderr)) {
  $leaf = Split-Path $f -Leaf
  Export-Tail -Source $f -Dest (Join-Path $TAIL ($leaf + ".tail.txt")) -Last 250
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

@(
  "PATCH_RUNTIME_CHAIN_V1_CERTIFY_DONE"
  ("OUT=" + $OUT)
  ("COUNT_AFTER_12S=" + $count12)
  ("COUNT_AFTER_20S=" + $count20)
  ("META_EVENTS_GROWTH=" + $metaEventsGrowth)
  ("META_ENGINE_GROWTH=" + $metaEngineGrowth)
  ("LAUNCHER_LOG_GROWTH=" + $launcherGrowth)
  ("LOADER_LOG_GROWTH=" + $loaderGrowth)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"PATCH_RUNTIME_CHAIN_V1_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $count12)
("COUNT_AFTER_20S=" + $count20)
("META_EVENTS_GROWTH=" + $metaEventsGrowth)
("META_ENGINE_GROWTH=" + $metaEngineGrowth)
("LAUNCHER_LOG_GROWTH=" + $launcherGrowth)
("LOADER_LOG_GROWTH=" + $loaderGrowth)
