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
$bakDir = Join-Path $Root ("logs\ops\patches\PREFLIGHT_MARKER_FIX_V2_1_" + $ts)
New-Item -ItemType Directory -Force -Path $bakDir | Out-Null
Copy-Item -Force -LiteralPath $PRE -Destination (Join-Path $bakDir "PAPER_PREFLIGHT_CANON_V1.ps1.BEFORE")

$lines = Get-Content -LiteralPath $PRE -Encoding UTF8

$out = New-Object "System.Collections.Generic.List[string]"
$skipNext = 0

foreach($ln in $lines){

  if($skipNext -gt 0){
    $skipNext--
    continue
  }

  # Drop old hook blocks
  if($ln -match '^\s*#\s*---\s*PRE_OK_MARKER_HOOK'){
    $skipNext = 50
    continue
  }

  # Remove exit $LASTEXITCODE anywhere
  if($ln -match '^\s*exit\s+\$LASTEXITCODE\s*$'){
    continue
  }

  # Remove runner invocation (robust)
  if($ln -match '(-File\s+\$RUN\b)|RUN_PAPER_SHADOW_CANON|RUN_PAPER_SHADOW_CANON_V1\.ps1'){
    $out.Add("  # [PATCH_V2_1] Runner execution removed from Preflight (handled by Chain Runner)")
    $skipNext = 3
    continue
  }

  $out.Add([string]$ln)
}

# Trim trailing blanks
while($out.Count -gt 0 -and $out[$out.Count-1] -match '^\s*$'){ $out.RemoveAt($out.Count-1) }

# If last line is "exit 0", remove it so we can re-append clean hook+exit
if($out.Count -gt 0 -and $out[$out.Count-1] -match '^\s*exit\s+0\s*$'){
  $out.RemoveAt($out.Count-1)
}

# Hook block as *string[]* (not object[])
[string[]]$hookBlock = @(
"",
"# --- PRE_OK_MARKER_HOOK (ops) ---",
"pwsh -NoProfile -ExecutionPolicy Bypass -File `"$HOOK`" -RunRoot `"$RunRoot`" -ProjectRoot `"$Root`"",
"if(`$LASTEXITCODE -ne 0){ throw `"NO_GO: PREFLIGHT_POST_OK_HOOK_FAIL`" }",
"# --- end hook ---",
"exit 0",
""
)

foreach($h in $hookBlock){ $out.Add($h) }

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
if(!(Test-Path $MARK)){ throw "NO_GO: MARKER_NOT_CREATED_AFTER_PATCH_V2_1" }

Write-Host "[GO] PREFLIGHT_NOW_WRITES_MARKER"
exit 0
