param(
  [string]\C:\alpaca-bot\org_bot = "C:\alpaca-bot\org_bot",
  [string]\C:\alpaca-bot\org_bot_runtime\paper = "C:\alpaca-bot\org_bot_runtime\paper"
)

\Stop="Stop"

function Stamp(){ Get-Date -Format "yyyyMMdd_HHmmss" }

\C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1  = Join-Path \C:\alpaca-bot\org_bot "tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
\C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1 = Join-Path \C:\alpaca-bot\org_bot "tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1"

if(!(Test-Path \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1)){ throw "PRE_NOT_FOUND=\C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1" }
if(!(Test-Path \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1)){ throw "HOOK_NOT_FOUND=\C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1" }

\ = Join-Path \C:\alpaca-bot\org_bot ("logs\ops\patches\PREFLIGHT_MARKER_HOOK_" + (Stamp))
New-Item -ItemType Directory -Force -Path \ | Out-Null
Copy-Item -Force -LiteralPath \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1 -Destination (Join-Path \ "PAPER_PREFLIGHT_CANON_V1.ps1.BEFORE")

# Read and patch
\ = Get-Content -LiteralPath \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1 -Raw

# We will inject a post-success hook call.
# Anchor: after the GO banner line, or after NOTE_WRITTEN line, whichever exists.
# We keep it safe: only insert if marker hook is not already referenced.
if(\ -match "PAPER_PREFLIGHT_POST_OK_HOOK_V1\.ps1"){
  Write-Host "[PATCH] Already referenced. No change."
  exit 0
}

\ = @'
# --- POST-OK HOOK (marker) ---
try {
  \ = Join-Path \C:\alpaca-bot\org_bot "tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1"
  if(Test-Path \){
    pwsh -NoProfile -ExecutionPolicy Bypass -File \ -Root \C:\alpaca-bot\org_bot -RunRoot \C:\alpaca-bot\org_bot_runtime\paper | Out-Host
  } else {
    Write-Host "[WARN] post-ok hook missing: "
  }
} catch {
  Write-Host "[WARN] post-ok hook failed: "
}
# --- END POST-OK HOOK ---
'@

# Prefer inserting right before any session guard exit (so it still runs even out_of_session)
# If no session guard, insert near the GO banner.
if(\ -match "\[SESSION_GUARD\]"){
  # insert before the first occurrence of SESSION_GUARD write
  \ = \.IndexOf("[SESSION_GUARD]")
  if(\ -gt 0){
    \ = \.Substring(0,\) + "
" + \ + "
" + \.Substring(\)
  } else {
    \ = \ + "
" + \ + "
"
  }
} elseif(\ -match "GO:\s*READY_FOR_TOMORROW"){
  # insert after GO line block
  \ = \ -replace "(GO:\s*READY_FOR_TOMORROW[\s\S]{0,400})", "$1

"
} else {
  # last resort append
  \ = \ + "
" + \ + "
"
}

Set-Content -Encoding UTF8 -LiteralPath \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1 -Value \

# Compile-parse (PowerShell AST parse)
\=[System.Management.Automation.Language.Parser]::ParseFile(\C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1,[ref]\,[ref]\)
Write-Host "[PATCH] PS_PARSE_OK"

# Hash after
Get-FileHash -Algorithm SHA256 -LiteralPath \C:\alpaca-bot\org_bot\tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1 |
  Format-List | Out-String | Set-Content -Encoding UTF8 (Join-Path \ "hash.sha256.txt")

Write-Host "[PATCH] DONE"
Write-Host ("[PATCH] BKP_DIR=" + \)
exit 0
