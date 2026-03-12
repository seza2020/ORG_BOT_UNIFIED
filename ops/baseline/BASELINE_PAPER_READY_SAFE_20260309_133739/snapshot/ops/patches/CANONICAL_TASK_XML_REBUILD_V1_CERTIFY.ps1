$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$LOGS    = Join-Path $U "runtime\paper\logs"
$TASKNAME= "\ORG_UNIFIED_PAPER_CANONICAL_V1"

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
$OUT  = Join-Path $EVID ("CANONICAL_TASK_XML_REBUILD_V1_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$SUM  = Join-Path $OUT "summary"
New-Item -ItemType Directory -Force -Path $OUT,$AUD,$SUM | Out-Null

$metaEvents  = Join-Path $LOGS "meta_events.jsonl"
$metaEngine  = Join-Path $LOGS "meta_engine.jsonl"
$launcherLog = Join-Path $LOGS "canonical_task_xml_launcher_v1.jsonl"
$loaderLog   = Join-Path $LOGS "canonical_loader_wrapper_v1.jsonl"
$regLog      = Join-Path $LOGS "canonical_task_xml_rebuild_v1_register.log"

$beforeMetaEvents = Get-LineCount -Path $metaEvents
$beforeMetaEngine = Get-LineCount -Path $metaEngine
$beforeLauncher   = Get-LineCount -Path $launcherLog
$beforeLoader     = Get-LineCount -Path $loaderLog

schtasks /run /tn $TASKNAME 1> (Join-Path $AUD "schtasks_run_stdout.txt") 2> (Join-Path $AUD "schtasks_run_stderr.txt")

Start-Sleep -Seconds 12
$count12 = @(Get-TbotProcesses).Count
Start-Sleep -Seconds 8
$count20 = @(Get-TbotProcesses).Count

$afterMetaEvents = Get-LineCount -Path $metaEvents
$afterMetaEngine = Get-LineCount -Path $metaEngine
$afterLauncher   = Get-LineCount -Path $launcherLog
$afterLoader     = Get-LineCount -Path $loaderLog

$metaEventsGrowth = $afterMetaEvents - $beforeMetaEvents
$metaEngineGrowth = $afterMetaEngine - $beforeMetaEngine
$launcherGrowth   = $afterLauncher - $beforeLauncher
$loaderGrowth     = $afterLoader - $beforeLoader

foreach ($f in @($launcherLog,$loaderLog,$regLog)) {
  if (Test-Path -LiteralPath $f) {
    Get-Content -LiteralPath $f -Tail 120 -Encoding UTF8 |
      Set-Content -LiteralPath (Join-Path $AUD ((Split-Path $f -Leaf) + ".tail.txt")) -Encoding UTF8
  } else {
    "MISSING=$f" | Set-Content -LiteralPath (Join-Path $AUD ((Split-Path $f -Leaf) + ".tail.txt")) -Encoding UTF8
  }
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

@(
  "CANONICAL_TASK_XML_REBUILD_V1_CERTIFY_DONE"
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

"CANONICAL_TASK_XML_REBUILD_V1_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $count12)
("COUNT_AFTER_20S=" + $count20)
("META_EVENTS_GROWTH=" + $metaEventsGrowth)
("META_ENGINE_GROWTH=" + $metaEngineGrowth)
("LAUNCHER_LOG_GROWTH=" + $launcherGrowth)
("LOADER_LOG_GROWTH=" + $loaderGrowth)
