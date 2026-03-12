$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$WRAPPER = Join-Path $WRAPDIR "CANONICAL_LOADER_WRAPPER_V1.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "CANONICAL_LOADER_WRAPPER_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_LOADER_WRAPPER_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\CANONICAL_LOADER_WRAPPER_V1.ps1.bak"

if (Test-Path -LiteralPath $bak) {
  Copy-Item -LiteralPath $bak -Destination $WRAPPER -Force
  "ROLLBACK_OK"
  ("RESTORED_WRAPPER=" + $bak)
} else {
  if (Test-Path -LiteralPath $WRAPPER) {
    Remove-Item -LiteralPath $WRAPPER -Force
  }
  "ROLLBACK_OK"
  "RESTORED_WRAPPER=REMOVED_NEW_FILE"
}
