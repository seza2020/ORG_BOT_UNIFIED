# SHADOW_PRICE_NO_HARDSTOP_V1 (auto)  2026-02-22T20:02:01
# tools\FIX_MAIN_ENFORCE_SHADOW_LAST_V1.ps1
# Fix main.py after bad indent injection of TBOT_ENFORCE_SHADOW_LAST_V1
# - restores main.py from latest PATCH_STRICT_NO_FAKE_* backup
# - re-inserts enforce block with correct indentation (inside function, after parse_args)
# - runs py_compile on main + orchestrator + shadow_pricing

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
$BAK = Join-Path $OPS ("FIX_MAIN_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

$mainPy = Join-Path $ROOT "tbot\main.py"
if(-not (Test-Path $mainPy)){ throw "Missing: $mainPy" }
Copy-Item -Force $mainPy (Join-Path $BAK "main.py.before_fix.bak")

# ---- Find latest strict patch backup containing main.py.bak ----
$patchDirs = Get-ChildItem -Path (Join-Path $ROOT "logs\ops") -Directory -Filter "PATCH_STRICT_NO_FAKE_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending

$restored = $false
foreach($d in $patchDirs){
  $cand = Join-Path $d.FullName "main.py.bak"
  if(Test-Path $cand){
    Copy-Item -Force $cand $mainPy
    Write-Host "OK: restored main.py from => $cand"
    $restored = $true
    break
  }
}
if(-not $restored){
  Write-Host "WARN: could not find PATCH_STRICT_NO_FAKE_*\\main.py.bak. Will try to remove broken block by markers."
}

# ---- Remove any existing TBOT_ENFORCE_SHADOW_LAST_V1 block (if still present) ----
$txt = Get-Content -Raw -Encoding UTF8 $mainPy
$txt2 = [regex]::Replace(
  $txt,
  "(?s)\r?\n\s*# --- TBOT_ENFORCE_SHADOW_LAST_V1 BEGIN ---.*?# --- TBOT_ENFORCE_SHADOW_LAST_V1 END ---\s*\r?\n",
  "`r`n"
)
if($txt2 -ne $txt){
  Set-Content -Encoding UTF8 -Path $mainPy -Value $txt2
  Write-Host "OK: removed old TBOT_ENFORCE_SHADOW_LAST_V1 block"
}
$lines = Get-Content -Encoding UTF8 $mainPy

# ---- Locate parse_args assignment line to get indentation + args var name ----
$idx = -1; $indent = ""; $var = ""
for($i=0; $i -lt $lines.Count; $i++){
  if($lines[$i] -match '^\s*(\w+)\s*=\s*.*\bparse_args\('){
    $idx = $i
    $var = $matches[1]
    $indent = ($lines[$i] -replace '^(\s*).*','$1')
    break
  }
}
if($idx -lt 0){ throw "Could not find parse_args assignment in main.py" }

$indent2 = $indent + "    "
$marker = "TBOT_ENFORCE_SHADOW_LAST_V1"

$block = @(
  "${indent}# --- ${marker} BEGIN ---",
  "${indent}try:",
  "${indent2}import os as _os",
  "${indent2}# Enforce shadow pricing safety (Week2): mode=last unless explicitly overridden",
  "${indent2}if getattr(${var}, 'shadow', False):",
  "${indent2}    if 'TBOT_SHADOW_LAST_STRICT' not in _os.environ:",
  "${indent2}        _os.environ['TBOT_SHADOW_LAST_STRICT'] = '1'",
  "${indent2}    mode = (_os.getenv('TBOT_SHADOW_PRICE_MODE','fixed') or 'fixed').strip().lower()",
  "${indent2}    if mode != 'last' and (_os.getenv('TBOT_ALLOW_FIXED_SHADOW_PRICE','0') != '1'):",
  "${indent2}        raise SystemExit(f'[SHADOW_PRICE] WARN_CONTINUE: TBOT_SHADOW_PRICE_MODE must be last for shadow runs (got {mode}).')",
  "${indent}except SystemExit:",
  "${indent2}raise",
  "${indent}except Exception:",
  "${indent2}# fail-closed",
  "${indent2}raise",
  "${indent}# --- ${marker} END ---"
)

# ---- Insert block right after parse_args line (inside same function indent) ----
$new = New-Object System.Collections.Generic.List[string]
for($i=0; $i -lt $lines.Count; $i++){
  $new.Add($lines[$i])
  if($i -eq $idx){
    $new.Add("")
    foreach($b in $block){ $new.Add($b) }
    $new.Add("")
  }
}
Set-Content -Encoding UTF8 -Path $mainPy -Value $new
Write-Host "OK: inserted enforce block after parse_args (var=$var indent_len=$($indent.Length))"

# ---- Compile tests ----
Write-Host ""
Write-Host "TEST: py_compile main + orchestrator + shadow_pricing"
& $PY -m py_compile "tbot\main.py" "tbot\runtime\orchestrator.py" "tbot\runtime\shadow_pricing.py"
if($LASTEXITCODE -ne 0){ throw "py_compile failed" }

Write-Host ""
Write-Host "FIX_OK. Backup dir:"
Write-Host $BAK
