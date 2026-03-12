# tools\FIX_STRICT_LAST_GUARD_V3.ps1
# Repairs shadow_pricing.py after bad guard insertion (inside multiline signature)
# - restores from latest PATCH_STRICT_LAST_GUARD_* backup
# - re-inserts guard after signature END + after docstring (keeps docstring valid)
# - runs py_compile + strict-last test with real failure exit code

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
$BAK = Join-Path $OPS ("FIX_STRICT_LAST_GUARD_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

$sp = Join-Path $ROOT "tbot\runtime\shadow_pricing.py"
if(-not (Test-Path $sp)){ throw "Missing: $sp" }
Copy-Item -Force $sp (Join-Path $BAK "shadow_pricing.py.before_fix.bak")

# ---- restore from latest PATCH_STRICT_LAST_GUARD_* backup ----
$restored = $false
$patchDirs = Get-ChildItem -Path $OPS -Directory -Filter "PATCH_STRICT_LAST_GUARD_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending

foreach($d in $patchDirs){
  $cand = Join-Path $d.FullName "shadow_pricing.py.bak"
  if(Test-Path $cand){
    Copy-Item -Force $cand $sp
    Write-Host "OK: restored shadow_pricing.py from => $cand"
    $restored = $true
    break
  }
}
if(-not $restored){
  Write-Host "WARN: no PATCH_STRICT_LAST_GUARD_*\\shadow_pricing.py.bak found. Will attempt remove markers in-place."
}

# ---- remove any previous guard blocks (V2/V3) to avoid duplicates ----
$raw = Get-Content -Raw -Encoding UTF8 $sp
$raw2 = [regex]::Replace($raw, "(?s)\r?\n\s*# --- TBOT_SHADOW_LAST_GUARD_V2 BEGIN ---.*?# --- TBOT_SHADOW_LAST_GUARD_V2 END ---\s*\r?\n", "`r`n")
$raw2 = [regex]::Replace($raw2,"(?s)\r?\n\s*# --- TBOT_SHADOW_LAST_GUARD_V3 BEGIN ---.*?# --- TBOT_SHADOW_LAST_GUARD_V3 END ---\s*\r?\n", "`r`n")
if($raw2 -ne $raw){
  Set-Content -Encoding UTF8 -Path $sp -Value $raw2
  Write-Host "OK: removed old guard blocks (if any)"
}

$lines = Get-Content -Encoding UTF8 $sp
$marker = "TBOT_SHADOW_LAST_GUARD_V3"

# ---- find def compute_shadow_prices ----
$defIdx = -1
for($i=0; $i -lt $lines.Count; $i++){
  if($lines[$i] -match '^\s*def\s+compute_shadow_prices\s*\('){
    $defIdx = $i; break
  }
}
if($defIdx -lt 0){ throw "Could not find def compute_shadow_prices(" }

$defIndent = ($lines[$defIdx] -replace '^(\s*).*','$1')
$inIndent  = $defIndent + "    "

# ---- find end of multiline signature by paren-balance until line endswith ':' ----
$balance = 0
$started = $false
$sigEnd  = -1

for($i=$defIdx; $i -lt $lines.Count; $i++){
  $ln = $lines[$i]

  if(-not $started){
    if($ln -match '\('){ $started = $true }
  }
  if($started){
    $balance += ([regex]::Matches($ln, "\(")).Count
    $balance -= ([regex]::Matches($ln, "\)")).Count
  }

  if($started -and $balance -eq 0 -and $ln.TrimEnd().EndsWith(":")){
    $sigEnd = $i
    break
  }
}
if($sigEnd -lt 0){ throw "Could not find end of compute_shadow_prices signature (missing ':' or parens unbalanced)." }

# ---- insert point: after signature, after docstring (keep docstring as first statement) ----
$ins = $sigEnd + 1
while($ins -lt $lines.Count -and $lines[$ins].Trim() -eq ""){ $ins++ }

if($ins -lt $lines.Count){
  $t = $lines[$ins].TrimStart()
  if($t.StartsWith('"""') -or $t.StartsWith("'''")){
    $delim = $t.Substring(0,3)
    $occ = ([regex]::Matches($lines[$ins], [regex]::Escape($delim))).Count
    if($occ -ge 2){
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
Write-Host "OK: re-inserted guard after signature+docstring at line $ins"

Write-Host ""
Write-Host "TEST 1: py_compile shadow_pricing"
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
Write-Host "FIX_OK. Backup dir:"
Write-Host $BAK
