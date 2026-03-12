$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$RUNNER  = Join-Path $WRAPDIR "CANONICAL_TASK_CONTEXT_RUNNER_V1.ps1"

$latest = Get-ChildItem -LiteralPath $EVID -Directory -Filter "CANONICAL_TASK_CONTEXT_RUNNER_V1_*" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $latest) { throw "NO_RUNNER_BUNDLE_FOUND" }

$bak = Join-Path $latest.FullName "source_backup\CANONICAL_TASK_CONTEXT_RUNNER_V1.ps1.bak"

if (Test-Path -LiteralPath $bak) {
  Copy-Item -LiteralPath $bak -Destination $RUNNER -Force
  "ROLLBACK_OK"
  ("RESTORED_RUNNER=" + $bak)
} else {
  if (Test-Path -LiteralPath $RUNNER) {
    Remove-Item -LiteralPath $RUNNER -Force
  }
  "ROLLBACK_OK"
  "RESTORED_RUNNER=REMOVED_NEW_FILE"
}
