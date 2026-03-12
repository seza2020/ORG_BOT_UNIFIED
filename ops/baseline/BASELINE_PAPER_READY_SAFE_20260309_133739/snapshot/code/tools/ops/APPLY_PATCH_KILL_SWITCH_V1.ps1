param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot"
)
$ErrorActionPreference="Stop"

$orch = Join-Path $ProjectRoot "tbot\runtime\orchestrator.py"
if(!(Test-Path $orch)){ throw "MISSING_ORCH=$orch" }

$txt = Get-Content -Raw -Encoding UTF8 $orch

# Ensure import os exists (required for the inserted snippet)
if($txt -notmatch '^\s*import\s+os\b' -and $txt -notmatch '^\s*from\s+os\b'){
  $m = [regex]::Match($txt, '^(.*\r?\n)*?(?=\s*(import|from)\s+)', [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if($m.Success){
    $pos = $m.Length
    $txt = $txt.Insert($pos, "import os`r`n")
  } else {
    # fallback: prepend
    $txt = "import os`r`n" + $txt
  }
}

if($txt -match "#\s*KILL_SWITCH_V1"){
  Write-Host "PATCH_ALREADY_PRESENT=1"
} else {

  $NL = "`r`n"
  $insert = @(
    "        # KILL_SWITCH_V1",
    "        try:",
    "            rr = (os.getenv(""TBOT_RUNROOT"") or """").strip() or "".""",
    "            ks = os.path.join(rr, ""KILL_SWITCH"")",
    "            if os.path.exists(ks):",
    "                ev = make_event(level=""WARN"", kind=""shutdown"", payload={""reason"": ""kill_switch"", ""runroot"": rr})",
    "                meta.emit(ev); announce.emit(ev)",
    "                break",
    "        except Exception:",
    "            pass",
    ""
  ) -join $NL

  # Preferred needle
  $needle = "now = now_fn()"
  if($txt -match [regex]::Escape($needle)){
    $txt2 = $txt -replace ([regex]::Escape($needle) + "\s*\r?\n"), ($needle + $NL + $insert)
    if($txt2 -eq $txt){ throw "PATCH_FAILED_NO_CHANGE" }
    $txt = $txt2
    Write-Host "PATCH_APPLIED=1 (after now = now_fn())"
  } else {
    # Fallback: insert after loop header "for ... in range("
    $m2 = [regex]::Match($txt, '^\s*(for\s+.*\s+in\s+range\(.+\)\s*:)\s*\r?\n', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if(-not $m2.Success){ throw "NEEDLE_NOT_FOUND: now = now_fn() OR for ... in range(...):" }

    $indent = " " * 0
    # infer indent of block after for-line (add 4 spaces to existing indentation of 'for' line)
    $forLine = $m2.Groups[1].Value
    $leading = ([regex]::Match($forLine, '^\s*')).Value
    $blockIndent = $leading + "    "

    $insert2 = $insert -replace "^\s{8}", $blockIndent  # normalize to current indent
    $txt = $txt.Remove($m2.Index + $m2.Length, 0).Insert($m2.Index + $m2.Length, $insert2)
    Write-Host "PATCH_APPLIED=1 (after for ... in range(...):)"
  }
}

Set-Content -Encoding UTF8 -Path $orch -Value $txt

# VERIFY marker
$txtV = Get-Content -Raw -Encoding UTF8 $orch
if($txtV -match "#\s*KILL_SWITCH_V1"){ Write-Host "VERIFY_MARKER=1" } else { throw "VERIFY_MARKER=0" }

# VERIFY compile (if venv exists)
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(Test-Path $py){
  & $py -m py_compile $orch
  if($LASTEXITCODE -ne 0){ throw "VERIFY_PY_COMPILE=0" }
  Write-Host "VERIFY_PY_COMPILE=1"
} else {
  Write-Host "VERIFY_PY_COMPILE=SKIP(.venv missing)"
}

Write-Host "OK=KILL_SWITCH_PATCH_DONE"
