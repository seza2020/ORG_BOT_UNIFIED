param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$PRE  = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
$HOOK = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1"

if(!(Test-Path $PRE)){ throw "MISSING: $PRE" }
if(!(Test-Path $HOOK)){ throw "MISSING: $HOOK" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$bakDir = Join-Path $Root ("logs\ops\patches\PREFLIGHT_MARKER_FIX_V2_" + $ts)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item -Force -LiteralPath $PRE -Destination (Join-Path $bakDir "PAPER_PREFLIGHT_CANON_V1.ps1.BEFORE")

# Read lines
$lines = Get-Content -LiteralPath $PRE -Encoding UTF8

# We will:
# - remove any runner invocation referencing $RUN or RUN_PAPER_SHADOW_CANON
# - remove "exit $LASTEXITCODE"
# - remove stale hook blocks and re-add a clean one at the end
$out = New-Object System.Collections.Generic.List[string]

# State for skipping wrapped runner call
$skipNext = 0

foreach($ln in $lines){

  if($skipNext -gt 0){
    $skipNext--
    continue
  }

  # Drop old hook blocks (your file had them after exit)
  if($ln -match '^\s*#\s*---\s*PRE_OK_MARKER_HOOK'){
    # skip until end hook
    $skipNext = 50
    continue
  }

  # Remove exit $LASTEXITCODE anywhere
  if($ln -match '^\s*exit\s+\$LASTEXITCODE\s*$'){
    continue
  }

  # Detect runner invocation (robust):
  # Any line containing -File $RUN OR RUN_PAPER_SHADOW_CANON OR RUN_PAPER_SHADOW_CANON_V1.ps1
  if($ln -match '(-File\s+\$RUN\b)|RUN_PAPER_SHADOW_CANON|RUN_PAPER_SHADOW_CANON_V1\.ps1'){
    $out.Add("  # [PATCH_V2] Runner execution removed from Preflight (handled by Chain Runner)")
    # also skip a couple of following lines if the command is wrapped
    $skipNext = 3
    continue
  }

  $out.Add($ln)
}

# Ensure we end with a clean hook + exit 0
$hookBlock = @(
"",
"# --- PRE_OK_MARKER_HOOK (ops) ---",
"pwsh -NoProfile -ExecutionPolicy Bypass -File `"$HOOK`" -RunRoot `"$RunRoot`" -ProjectRoot `"$Root`"",
"if(`$LASTEXITCODE -ne 0){ throw `"NO_GO: PREFLIGHT_POST_OK_HOOK_FAIL`" }",
"# --- end hook ---",
"exit 0",
""
)

# If there is already an exit 0 at end, we still want hook right before it.
# Simplest: remove trailing exit 0 then append hookBlock.
while($out.Count -gt 0 -and $out[$out.Count-1] -match '^\s*$'){ $out.RemoveAt($out.Count-1) }
if($out.Count -gt 0 -and $out[$out.Count-1] -match '^\s*exit\s+0\s*$'){
  $out.RemoveAt($out.Count-1)
}

$out.AddRange($hookBlock)

# Write back
Set-Content -LiteralPath $PRE -Encoding UTF8 -Value $out

# Parse check
$null=[System.Management.Automation.Language.Parser]::ParseFile($PRE,[ref]$null,[ref]$null)
Write-Host "[OK] PS_PARSE_OK: PAPER_PREFLIGHT_CANON_V1.ps1"
Write-Host ("[OK] BKP_DIR=" + $bakDir)

# Smoke: run preflight now and verify marker exists
$opsDir = Join-Path (Join-Path $RunRoot "logs") "ops"
New-Item -ItemType Directory -Force -Path $opsDir | Out-Null
$MARK = Join-Path $opsDir "PREFLIGHT_OK.marker"
if(Test-Path $MARK){ Remove-Item -Force -LiteralPath $MARK -ErrorAction SilentlyContinue }

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $PRE -Root $Root -RunRoot $RunRoot
Write-Host ("PREFLIGHT_EXIT=" + $LASTEXITCODE)
if($LASTEXITCODE -ne 0){ throw "NO_GO: PREFLIGHT_EXIT=$LASTEXITCODE" }

Write-Host ("MARK_EXISTS=" + (Test-Path $MARK))
if(!(Test-Path $MARK)){ throw "NO_GO: MARKER_NOT_CREATED_AFTER_PATCH_V2" }

Write-Host "[GO] PREFLIGHT_NOW_WRITES_MARKER"
exit 0
