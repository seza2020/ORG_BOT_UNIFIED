# tools\PATCH_STRICT_LAST_GUARD_V2.ps1
# Force strict-last guard INSIDE compute_shadow_prices (early fail-closed)
# - If mode=last and strict=1 and market.<sym>.last missing => RuntimeError("no_market_last")
# Includes real failing test (non-zero exit on failure)

[CmdletBinding()]
param()

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_STRICT_LAST_GUARD_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

$sp = Join-Path $ROOT "tbot\runtime\shadow_pricing.py"
if(-not (Test-Path $sp)){ throw "Missing: $sp" }

Copy-Item -Force $sp (Join-Path $BAK "shadow_pricing.py.bak")

$marker = "TBOT_SHADOW_LAST_GUARD_V2"
$lines = Get-Content -Encoding UTF8 $sp
$text  = ($lines -join "`n")
if($text -match $marker){
  Write-Host "shadow_pricing.py already has guard => skip"
} else {
  # find def compute_shadow_prices(
  $defIdx = -1
  for($i=0; $i -lt $lines.Count; $i++){
    if($lines[$i] -match '^\s*def\s+compute_shadow_prices\s*\('){
      $defIdx = $i; break
    }
  }
  if($defIdx -lt 0){ throw "Could not find def compute_shadow_prices(" }

  $defIndent = ($lines[$defIdx] -replace '^(\s*).*','$1')
  $inIndent  = $defIndent + "    "

  # Insert AFTER docstring if present
  $ins = $defIdx + 1
  # skip blank lines
  while($ins -lt $lines.Count -and $lines[$ins].Trim() -eq ""){ $ins++ }

  if($ins -lt $lines.Count){
    $t = $lines[$ins].TrimStart()
    if($t.StartsWith('"""') -or $t.StartsWith("'''")){
      $delim = $t.Substring(0,3)
      # same-line docstring?
      if(($lines[$ins] -split [regex]::Escape($delim)).Count -ge 3){
        $ins = $ins + 1
      } else {
        $j = $ins + 1
        while($j -lt $lines.Count){
          if($lines[$j] -match [regex]::Escape($delim)){
            $ins = $j + 1
            break
          }
          $j++
        }
      }
    }
  }

  $guard = @(
    "${inIndent}# --- ${marker} BEGIN ---",
    "${inIndent}import os as _os",
    "${inIndent}mode = (_os.getenv('TBOT_SHADOW_PRICE_MODE','fixed') or 'fixed').strip().lower()",
    "${inIndent}strict = (_os.getenv('TBOT_SHADOW_LAST_STRICT','1') or '1').strip() != '0'",
    "${inIndent}if strict and mode == 'last':",
    "${inIndent}    _sym = None",
    "${inIndent}    try:",
    "${inIndent}        _sym = sig_payload.get('symbol') if isinstance(sig_payload, dict) else getattr(sig_payload, 'symbol', None)",
    "${inIndent}    except Exception:",
    "${inIndent}        _sym = None",
    "${inIndent}    if _sym:",
    "${inIndent}        try:",
    "${inIndent}            _snap = getattr(market, _sym, None)",
    "${inIndent}            _last = getattr(_snap, 'last', None)",
    "${inIndent}        except Exception:",
    "${inIndent}            _last = None",
    "${inIndent}        if _last is None:",
    "${inIndent}            raise RuntimeError('no_market_last')",
    "${inIndent}# --- ${marker} END ---",
    ""
  )

  $new = New-Object System.Collections.Generic.List[string]
  for($i=0; $i -lt $lines.Count; $i++){
    if($i -eq $ins){
      foreach($g in $guard){ $new.Add($g) }
    }
    $new.Add($lines[$i])
  }

  Set-Content -Encoding UTF8 -Path $sp -Value $new
  Write-Host "OK: inserted strict-last guard => $sp (at line $ins)"
}

Write-Host ""
Write-Host "TEST 1: py_compile"
& $PY -m py_compile "tbot\runtime\shadow_pricing.py"
if($LASTEXITCODE -ne 0){ throw "py_compile failed" }

Write-Host ""
Write-Host "TEST 2: strict-last MUST raise no_market_last (real fail if not)"
& $PY -c "import os; os.environ['TBOT_SHADOW_PRICE_MODE']='last'; os.environ['TBOT_SHADOW_LAST_STRICT']='1'; from tbot.runtime.shadow_pricing import compute_shadow_prices; 
class S: pass
class M: pass
m=M(); m.SPY=S()
try:
    compute_shadow_prices(sig_payload={'symbol':'SPY','side':'LONG'}, market=m, default_entry=100.0, default_stop=99.0, default_tp=102.0)
except RuntimeError as e:
    print('OK', str(e)); raise SystemExit(0)
print('FAIL no exception'); raise SystemExit(2)"
if($LASTEXITCODE -ne 0){ throw "TEST 2 failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK
