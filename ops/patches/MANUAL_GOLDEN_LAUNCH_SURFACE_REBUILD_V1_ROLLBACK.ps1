$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"

$WRAPPER = Join-Path $WRAPDIR "ORG_UNIFIED_PAPER_RUN.ps1"
$MANAGER = Join-Path $WRAPDIR "ORG_UNIFIED_RUNTIME_MANAGER.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "MANUAL_GOLDEN_LAUNCH_SURFACE_REBUILD_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_REBUILD_BUNDLE_FOUND" }

$wrapperBak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_PAPER_RUN.ps1.bak"
$managerBak = Join-Path $latest.FullName "source_backup\ORG_UNIFIED_RUNTIME_MANAGER.ps1.bak"

if (Test-Path -LiteralPath $wrapperBak) {
  Copy-Item -LiteralPath $wrapperBak -Destination $WRAPPER -Force
}
if (Test-Path -LiteralPath $managerBak) {
  Copy-Item -LiteralPath $managerBak -Destination $MANAGER -Force
}

"ROLLBACK_OK"
("RESTORED_WRAPPER=" + $wrapperBak)
("RESTORED_MANAGER=" + $managerBak)
