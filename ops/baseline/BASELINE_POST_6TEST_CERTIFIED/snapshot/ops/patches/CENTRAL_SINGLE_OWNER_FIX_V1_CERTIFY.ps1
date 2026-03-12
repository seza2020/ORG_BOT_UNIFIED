$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U     = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS   = Join-Path $U "ops"
$EVID  = Join-Path $OPS "evidence"
$LOGS  = Join-Path $U "runtime\paper\logs"
$TASK  = "\ORG_UNIFIED_PAPER_CANONICAL_V1"

function Get-TbotProcs {
  try {
    return @(
      Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId, ParentProcessId, Name, CommandLine, CreationDate
    )
  } catch {
    return @()
  }
}

function Get-LineCount {
  param([string]$Path)
  if (!(Test-Path -LiteralPath $Path)) { return -1 }
  try { return (Get-Content -LiteralPath $Path -Encoding UTF8 | Measure-Object -Line).Lines }
  catch { return -2 }
}

function Export-Tail {
  param([string]$Source,[string]$Dest,[int]$Last=200)
  if (Test-Path -LiteralPath $Source) {
    Get-Content -LiteralPath $Source -Tail $Last -Encoding UTF8 |
      Set-Content -LiteralPath $Dest -Encoding UTF8
  } else {
    "MISSING=$Source" | Set-Content -LiteralPath $Dest -Encoding UTF8
  }
}

Get-TbotProcs | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("CENTRAL_SINGLE_OWNER_FIX_V1_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$TAIL = Join-Path $OUT "tails"
$SUM  = Join-Path $OUT "summary"

New-Item -ItemType Directory -Force -Path $OUT,$AUD,$TAIL,$SUM | Out-Null

$metaEvents = Join-Path $LOGS "meta_events.jsonl"
$metaEngine = Join-Path $LOGS "meta_engine.jsonl"
$managerLog = Join-Path $LOGS "org_unified_runtime_manager_v1.log"
$launcherLog= Join-Path $LOGS "canonical_task_xml_launcher_v1.jsonl"
$guardLog   = Join-Path $LOGS "dualpid_guard_perm.log"
$spawnLog   = Join-Path $LOGS "spawn_trace.log"

$beforeMetaEvents = Get-LineCount -Path $metaEvents
$beforeMetaEngine = Get-LineCount -Path $metaEngine

schtasks /run /tn $TASK 1> (Join-Path $AUD "schtasks_run_stdout.txt") 2> (Join-Path $AUD "schtasks_run_stderr.txt")

Start-Sleep -Seconds 12
$p12 = @(Get-TbotProcs)
$c12 = $p12.Count
$p12 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_12s.csv")

Start-Sleep -Seconds 8
$p20 = @(Get-TbotProcs)
$c20 = $p20.Count
$p20 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_20s.csv")

$afterMetaEvents = Get-LineCount -Path $metaEvents
$afterMetaEngine = Get-LineCount -Path $metaEngine

foreach ($f in @($metaEvents,$metaEngine,$managerLog,$launcherLog,$guardLog,$spawnLog)) {
  $leaf = Split-Path $f -Leaf
  Export-Tail -Source $f -Dest (Join-Path $TAIL ($leaf + ".tail.txt")) -Last 250
}

Get-TbotProcs | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

@(
  "CENTRAL_SINGLE_OWNER_FIX_V1_CERTIFY_DONE"
  ("OUT=" + $OUT)
  ("COUNT_AFTER_12S=" + $c12)
  ("COUNT_AFTER_20S=" + $c20)
  ("META_EVENTS_GROWTH=" + ($afterMetaEvents - $beforeMetaEvents))
  ("META_ENGINE_GROWTH=" + ($afterMetaEngine - $beforeMetaEngine))
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"CENTRAL_SINGLE_OWNER_FIX_V1_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $c12)
("COUNT_AFTER_20S=" + $c20)
("META_EVENTS_GROWTH=" + ($afterMetaEvents - $beforeMetaEvents))
("META_ENGINE_GROWTH=" + ($afterMetaEngine - $beforeMetaEngine))
