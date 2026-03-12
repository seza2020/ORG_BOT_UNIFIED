param([string]$Root="C:\alpaca-bot\org_bot")

$ErrorActionPreference="Stop"

$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(!(Test-Path $Canon)){ throw "Missing: $Canon" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bak = "$Canon.bak_pidfix_$ts"
Copy-Item -Force $Canon $bak

$txt  = Get-Content -Raw -LiteralPath $Canon

# Replace any $pid or $PID tokens with $livePid (PowerShell is case-insensitive)
$txt2 = $txt -replace '\$pid\b', '$livePid'

Set-Content -Encoding UTF8 -LiteralPath $Canon -Value $txt2

# Verify no remaining $pid tokens
$left = Select-String -LiteralPath $Canon -Pattern '\$pid\b' -AllMatches -ErrorAction SilentlyContinue
if($left){
  throw "PATCH_INCOMPLETE: still found `$pid tokens. Check file manually."
}

"OK_PATCHED_CANON_V2"
"BACKUP=$bak"
