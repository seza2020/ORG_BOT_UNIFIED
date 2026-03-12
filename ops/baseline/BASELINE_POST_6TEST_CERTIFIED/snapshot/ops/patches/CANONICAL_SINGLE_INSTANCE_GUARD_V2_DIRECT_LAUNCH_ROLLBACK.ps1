$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$GUARD   = Join-Path $WRAPDIR "CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_GUARD_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\CANONICAL_SINGLE_INSTANCE_GUARD_V2_DIRECT_LAUNCH.ps1.bak"

if (Test-Path -LiteralPath $bak) {
  Copy-Item -LiteralPath $bak -Destination $GUARD -Force
  "ROLLBACK_OK"
  ("RESTORED_GUARD=" + $bak)
} else {
  if (Test-Path -LiteralPath $GUARD) {
    Remove-Item -LiteralPath $GUARD -Force
  }
  "ROLLBACK_OK"
  "RESTORED_GUARD=REMOVED_NEW_FILE"
}
