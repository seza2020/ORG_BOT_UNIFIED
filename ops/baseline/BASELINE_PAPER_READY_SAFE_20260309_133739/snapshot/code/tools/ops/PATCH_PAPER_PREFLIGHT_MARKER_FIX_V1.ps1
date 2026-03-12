param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$PRE = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
$HOOK = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1"

if(!(Test-Path $PRE)){ throw "MISSING: $PRE" }
if(!(Test-Path $HOOK)){ throw "MISSING: $HOOK" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $Root ("logs\ops\patches\PREFLIGHT_MARKER_FIX_" + $ts)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item -Force -LiteralPath $PRE -Destination (Join-Path $bakDir "PAPER_PREFLIGHT_CANON_V1.ps1.BEFORE")

# Read
$s = Get-Content -LiteralPath $PRE -Raw -Encoding UTF8

# 1) If preflight runs runner, we must remove it (it causes LOCK + exits before marker)
# Remove/disable line like:
# pwsh ... -File $RUN
# exit $LASTEXITCODE
# We'll replace with comment + exit 0 (after hook)
$s2 = $s

# Ensure hook exists and is reachable: move hook block before the first "exit"
# Strategy:
# - Remove any existing hook block (we will re-insert cleanly)
# - Remove runner invocation block
# - Insert hook just before exit, then force exit 0

# Remove old hook block (your file has a marker like PRE_OK_MARKER_HOOK)
$s2 = [regex]::Replace($s2, "(?ms)^\s*#\s*---\s*PRE_OK_MARKER_HOOK.*?^\s*#\s*---\s*end hook\s*---\s*\r?\n?", "")

# Remove "pwsh ... -File $RUN" line(s) and "exit $LASTEXITCODE"
$s2 = [regex]::Replace($s2, "(?m)^\s*pwsh\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+\$RUN\s*\r?\n", "  # [PATCH] Runner execution removed from Preflight (handled by Chain Runner)`r`n")
$s2 = [regex]::Replace($s2, "(?m)^\s*exit\s+\$LASTEXITCODE\s*\r?\n", "  # [PATCH] Preflight ends after writing marker`r`n")

# Now insert a reachable hook near end (append safely)
$hookBlock = @"
# --- PRE_OK_MARKER_HOOK (ops) ---
pwsh -NoProfile -ExecutionPolicy Bypass -File `"$HOOK`" -RunRoot `"$RunRoot`" -ProjectRoot `"$Root`"
if(`$LASTEXITCODE -ne 0){ throw `"NO_GO: PREFLIGHT_POST_OK_HOOK_FAIL`" }
# --- end hook ---
exit 0
"@

# If file already ends with exit 0, don't double insert. Otherwise append.
if($s2 -notmatch "(?m)^\s*exit\s+0\s*$"){
  $s2 = ($s2.TrimEnd() + "`r`n`r`n" + $hookBlock + "`r`n")
}

# Write back
Set-Content -Encoding UTF8 -LiteralPath $PRE -Value $s2

# Parse check
$null=[System.Management.Automation.Language.Parser]::ParseFile($PRE,[ref]$null,[ref]$null)
Write-Host "[OK] PS_PARSE_OK: PAPER_PREFLIGHT_CANON_V1.ps1"
Write-Host ("[OK] BKP_DIR=" + $bakDir)

# Smoke: run preflight now and verify marker exists
$MARK = Join-Path (Join-Path $RunRoot "logs\ops") "PREFLIGHT_OK.marker"
if(Test-Path $MARK){ Remove-Item -Force -LiteralPath $MARK -ErrorAction SilentlyContinue }

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $PRE -Root $Root -RunRoot $RunRoot
Write-Host ("PREFLIGHT_EXIT=" + $LASTEXITCODE)
if($LASTEXITCODE -ne 0){ throw "NO_GO: PREFLIGHT_EXIT=$LASTEXITCODE" }

Write-Host ("MARK_EXISTS=" + (Test-Path $MARK))
if(!(Test-Path $MARK)){ throw "NO_GO: MARKER_NOT_CREATED_AFTER_PATCH" }

Write-Host "[GO] PREFLIGHT_NOW_WRITES_MARKER"
exit 0
