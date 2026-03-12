param(
  [string]$Root="C:\alpaca-bot\ORG_BOT_UNIFIED\code",
  [string]$RunRoot="C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"
)
$ErrorActionPreference="Stop"

$HC = Join-Path $Root "tools\ops\OPS_HEALTHCHECK_CANON_V1.ps1"
$MG = Join-Path $Root "tools\ops\PAPER_META_GUARD_V1.ps1"
$GO = Join-Path $Root "tools\ops\PAPER_FREEZE_AUDIT_GO_NOGO_V1.ps1"
  # [PATCH_V2_1] Runner execution removed from Preflight (handled by Chain Runner)
if(!(Test-Path $GO)){ throw "MISSING: $GO" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $HC -NoRestore
if($LASTEXITCODE -ne 0){ throw "NO_GO: HEALTHCHECK_FAIL" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $MG -RunRoot $RunRoot -ProjectRoot $Root
if($LASTEXITCODE -ne 0){ throw "NO_GO: META_GUARD_FAIL" }

pwsh -NoProfile -ExecutionPolicy Bypass -File $GO -Root $Root -RunRoot $RunRoot
if($LASTEXITCODE -ne 0){ throw "NO_GO: FREEZE_GO_NOGO_FAIL" }

# If all OK -> run the actual runner
  # [PATCH_V2_1] Runner execution removed from Preflight (handled by Chain Runner)
# --- end hook ---

# --- PRE_OK_MARKER_HOOK (ops) ---
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1" -RunRoot "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper" -ProjectRoot "C:\alpaca-bot\ORG_BOT_UNIFIED\code"
if($LASTEXITCODE -ne 0){ throw "NO_GO: PREFLIGHT_POST_OK_HOOK_FAIL" }
# --- end hook ---
exit 0


