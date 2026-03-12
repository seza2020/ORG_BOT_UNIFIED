$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$TASKDIR = Join-Path $OPS "tasks"

$TASKNAME = "\ORG_UNIFIED_PAPER_CANONICAL_V1"
$LAUNCHER = Join-Path $WRAPDIR "CANONICAL_TASK_XML_LAUNCHER_V1.ps1"
$XMLPATH  = Join-Path $TASKDIR "ORG_UNIFIED_PAPER_CANONICAL_V1.xml"

try {
  schtasks /delete /tn $TASKNAME /f 1> $null 2>&1
} catch {}

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "CANONICAL_TASK_XML_REBUILD_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_TASK_XML_REBUILD_BUNDLE_FOUND" }

$launcherBak = Join-Path $latest.FullName "source_backup\CANONICAL_TASK_XML_LAUNCHER_V1.ps1.bak"
$xmlBak      = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_PAPER_CANONICAL_V1.xml.bak"

if (Test-Path -LiteralPath $launcherBak) {
  Copy-Item -LiteralPath $launcherBak -Destination $LAUNCHER -Force
} else {
  if (Test-Path -LiteralPath $LAUNCHER) { Remove-Item -LiteralPath $LAUNCHER -Force }
}

if (Test-Path -LiteralPath $xmlBak) {
  Copy-Item -LiteralPath $xmlBak -Destination $XMLPATH -Force
} else {
  if (Test-Path -LiteralPath $XMLPATH) { Remove-Item -LiteralPath $XMLPATH -Force }
}

"ROLLBACK_OK"
("RESTORED_LAUNCHER=" + $launcherBak)
("RESTORED_XML=" + $xmlBak)
