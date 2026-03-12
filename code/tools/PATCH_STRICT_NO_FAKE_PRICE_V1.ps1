# SHADOW_PRICE_NO_HARDSTOP_V1 (auto)  2026-02-22T20:02:01
# tools\PATCH_STRICT_NO_FAKE_PRICE_V1.ps1
# - Strict last pricing: if TBOT_SHADOW_PRICE_MODE=last and market.last missing => NO fallback => hard stop
# - Disable forced_signal_test unless TBOT_ALLOW_FORCE_SIGNAL_TEST=1
# - Enforce shadow mode last on shadow runs unless TBOT_ALLOW_FIXED_SHADOW_PRICE=1
# Safe: project-only edits + backups + py_compile tests

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot (current: $ROOT)" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_STRICT_NO_FAKE_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

function Backup($path){
  if(Test-Path $path){
    Copy-Item -Force $path (Join-Path $BAK ([IO.Path]::GetFileName($path) + ".bak"))
  }
}

# -------------------------
# (A) shadow_pricing.py: strict mode => raise RuntimeError("no_market_last") instead of returning defaults
# -------------------------
$sp = Join-Path $ROOT "tbot\runtime\shadow_pricing.py"
if(-not (Test-Path $sp)){ throw "Missing: $sp" }
$markerA = "TBOT_SHADOW_LAST_STRICT_V1"

$lines = Get-Content -Encoding UTF8 $sp
if(($lines -join "`n") -match $markerA){
  Write-Host "shadow_pricing.py already patched => skip"
} else {
  Backup $sp
  $out = New-Object System.Collections.Generic.List[string]
  for($i=0; $i -lt $lines.Count; $i++){
    $line = $lines[$i]
    if($line -match '^\s*if\s+last\s+is\s+None\s*:\s*$'){
      # expect next line is: return ShadowPrices(entry=entry, stop=stop, tp=tp)
      $next = ($i+1 -lt $lines.Count) ? $lines[$i+1] : ""
      if($next -match '^\s*return\s+ShadowPrices\(entry=entry,\s*stop=stop,\s*tp=tp\)\s*$'){
        $ind = ($line -replace '^(\s*).*','$1')
        $out.Add($line)
        $out.Add("${ind}    # --- ${markerA} BEGIN ---")
        $out.Add("${ind}    strict = (os.getenv('TBOT_SHADOW_LAST_STRICT','1') or '1').strip() != '0'")
        $out.Add("${ind}    if strict:")
        $out.Add("${ind}        raise RuntimeError('no_market_last')")
        $out.Add("${ind}    # --- ${markerA} END ---")
        $out.Add("${ind}    return ShadowPrices(entry=entry, stop=stop, tp=tp)")
        $i += 1
        continue
      }
    }
    $out.Add($line)
  }
  Set-Content -Encoding UTF8 -Path $sp -Value $out
  Write-Host "OK: patched => $sp"
}

# -------------------------
# (B) orchestrator.py:
#   1) helper _tbot_safe_shadow_prices that hard-stops on no_market_last
#   2) replace compute_shadow_prices calls -> _tbot_safe_shadow_prices
#   3) disable forced_signal_test unless TBOT_ALLOW_FORCE_SIGNAL_TEST=1
# -------------------------
$orc = Join-Path $ROOT "tbot\runtime\orchestrator.py"
if(-not (Test-Path $orc)){ throw "Missing: $orc" }

$markerB1 = "TBOT_SAFE_SHADOW_PRICES_V1"
$markerB2 = "TBOT_DISABLE_FORCED_SIGNAL_TEST_V1"

$text = Get-Content -Raw -Encoding UTF8 $orc
if($text -notmatch $markerB1){
  Backup $orc

  # insert helper after import line
  $importLine = "from tbot.runtime.shadow_pricing import compute_shadow_prices"
  $idx = $text.IndexOf($importLine)
  if($idx -lt 0){ throw "Could not find import compute_shadow_prices in orchestrator.py" }

  $insertAt = $idx + $importLine.Length
  $helper = @"
`r`n
# --- $markerB1 BEGIN ---
def _tbot_safe_shadow_prices(**kwargs):
    try:
        return compute_shadow_prices(**kwargs)
    except RuntimeError as e:
        if "no_market_last" in str(e):
            import os as _os
            # fail-closed: never allow fallback to defaults when mode=last
            raise SystemExit("[NO_LAST] hard-stop: TBOT_SHADOW_PRICE_MODE=last but market.last unavailable (no fallback). "
                             "Check market data feed / symbol snapshot.")
        raise
# --- $markerB1 END ---
`r`n
"@
  $text = $text.Insert($insertAt, $helper)
}

# replace calls
$text = $text -replace "prices\s*=\s*compute_shadow_prices\(", "prices = _tbot_safe_shadow_prices("

# disable forced signal test after forced_remaining line
if($text -notmatch $markerB2){
  $pat = [regex]::new("(?m)^(?<ind>\s*)forced_remaining\s*=\s*int\(force_signal_repeat\)\s*if\s*force_signal_sid\s*else\s*0\s*$")
  $m = $pat.Match($text)
  if(-not $m.Success){ throw "Could not find forced_remaining assignment in orchestrator.py" }
  $ind = $m.Groups["ind"].Value
  $block = @"
`r`n${ind}# --- $markerB2 BEGIN ---
${ind}import os as _tbot_os
${ind}if force_signal_sid and (_tbot_os.getenv('TBOT_ALLOW_FORCE_SIGNAL_TEST','0') != '1'):
${ind}    try:
${ind}        ev = make_event(level='WARN', kind='signal_skip', payload={'sid': str(force_signal_sid), 'reason': 'forced_signal_disabled'})
${ind}        meta.emit(ev); announce.emit(ev)
${ind}    except Exception:
${ind}        pass
${ind}    force_signal_sid = None
${ind}    forced_remaining = 0
${ind}# --- $markerB2 END ---
"@
  $insertPos = $m.Index + $m.Length
  $text = $text.Insert($insertPos, $block)
}

Set-Content -Encoding UTF8 -Path $orc -Value $text
Write-Host "OK: patched => $orc"

# -------------------------
# (C) main.py: enforce shadow price mode last on shadow runs + default strict env
# -------------------------
$main = Join-Path $ROOT "tbot\main.py"
if(-not (Test-Path $main)){ throw "Missing: $main" }
$markerC = "TBOT_ENFORCE_SHADOW_LAST_V1"

$mainText = Get-Content -Raw -Encoding UTF8 $main
if($mainText -notmatch $markerC){
  Backup $main

  # insert after TBOT_PERSIST_CAP_V1 END if present else after parse_args assignment line
  $insPos = -1
  $mEnd = [regex]::Match($mainText, "(?m)^\s*# --- TBOT_PERSIST_CAP_V1 END ---\s*$")
  if($mEnd.Success){
    $insPos = $mEnd.Index + $mEnd.Length
  } else {
    $mArgs = [regex]::Match($mainText, "(?m)^\s*(\w+)\s*=\s*.*parse_args\([^\)]*\)\s*$")
    if(-not $mArgs.Success){ throw "Could not find parse_args assignment in main.py" }
    $insPos = $mArgs.Index + $mArgs.Length
  }

  $block = @"
`r`n
# --- $markerC BEGIN ---
try:
    import os as _os
    if getattr(args, "shadow", False):
        # default strict = ON
        if "TBOT_SHADOW_LAST_STRICT" not in _os.environ:
            _os.environ["TBOT_SHADOW_LAST_STRICT"] = "1"
        mode = (_os.getenv("TBOT_SHADOW_PRICE_MODE","fixed") or "fixed").strip().lower()
        if mode != "last" and (_os.getenv("TBOT_ALLOW_FIXED_SHADOW_PRICE","0") != "1"):
            raise SystemExit(f"[SHADOW_PRICE] WARN_CONTINUE: TBOT_SHADOW_PRICE_MODE must be 'last' for shadow runs (got {mode}).")
except SystemExit:
    raise
except Exception:
    raise
# --- $markerC END ---
`r`n
"@
  $mainText = $mainText.Insert($insPos, $block)
  Set-Content -Encoding UTF8 -Path $main -Value $mainText
  Write-Host "OK: patched => $main"
} else {
  Write-Host "main.py already patched for enforce-shadow-last => skip"
}

# -------------------------
# Tests
# -------------------------
Write-Host ""
Write-Host "TEST 1: py_compile"
& $PY -m py_compile "tbot\runtime\shadow_pricing.py" "tbot\runtime\orchestrator.py" "tbot\main.py"
if($LASTEXITCODE -ne 0){ throw "py_compile failed" }

Write-Host ""
Write-Host "TEST 2: strict-last raises when last missing"
& $PY -c "import os; os.environ['TBOT_SHADOW_PRICE_MODE']='last'; os.environ['TBOT_SHADOW_LAST_STRICT']='1'; from tbot.runtime.shadow_pricing import compute_shadow_prices; 
class S: pass
class M: pass
m=M(); m.SPY=S()  # no .last
try:
    compute_shadow_prices(sig_payload={'symbol':'SPY','side':'LONG'}, market=m, default_entry=100.0, default_stop=99.0, default_tp=102.0)
    raise SystemExit('FAIL expected RuntimeError')
except RuntimeError as e:
    print('OK', str(e))"
if($LASTEXITCODE -ne 0){ throw "TEST 2 failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK
Write-Host ""
Write-Host "Operational behavior (Week2):"
Write-Host "- If mode=last and market.last missing => bot hard-stops (no fallback to defaults, no fake 100)."
Write-Host "- forced_signal_test disabled unless TBOT_ALLOW_FORCE_SIGNAL_TEST=1."
Write-Host "- shadow runs require TBOT_SHADOW_PRICE_MODE=last unless TBOT_ALLOW_FIXED_SHADOW_PRICE=1."
