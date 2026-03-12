param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RestoreGitMissing = 0
)

$ErrorActionPreference="Stop"

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$Report = Join-Path $Root ("logs\ops\RESTORE_GAP_REPORT_V3_{0}.txt" -f $ts)
New-Item -ItemType Directory -Force -Path (Split-Path $Report) | Out-Null

function WL([string]$s){ Add-Content -Encoding UTF8 -LiteralPath $Report -Value $s }

WL ("REPORT_START=" + (Get-Date -Format s))
WL ("ROOT=" + $Root)

# --- Inventory quick ---
$dirs  = (Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue).Count
$files = (Get-ChildItem -LiteralPath $Root -File      -Recurse -Force -ErrorAction SilentlyContinue).Count
$bytes = (Get-ChildItem -LiteralPath $Root -File      -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
WL ""
WL "=== INVENTORY ==="
WL ("DIRS_COUNT=" + $dirs)
WL ("FILES_COUNT=" + $files)
WL ("TOTAL_BYTES=" + $bytes)

# --- Critical paths ---
$crit = @(
  ".venv\Scripts\python.exe",
  "tbot\main.py",
  "tbot\runtime\orchestrator.py",
  "tools\RUN_LIVE_SHADOW_CANON_V2.ps1",
  "tools\OPS_END_OF_DAY_V2.ps1",
  "tools\freeze_today_enterprise.ps1",
  "tools\freeze_today_enterprise_SAFE.ps1",
  "tools\recover_shadow_plans_from_meta.ps1",
  "tools\CLEAR_TBOT_LOCK.ps1"
)
WL ""
WL "=== CRITICAL_PATHS_CHECK ==="
$miss=0
foreach($r in $crit){
  $p = Join-Path $Root $r
  if(Test-Path $p){
    $it = Get-Item -LiteralPath $p
    WL ("OK: " + $r + " bytes=" + $it.Length + " mtime=" + $it.LastWriteTime.ToString("s"))
  } else {
    WL ("MISSING: " + $r)
    $miss++
  }
}
WL ("MISSING_CRITICAL_COUNT=" + $miss)

# --- Python import smoke (robust: inject Root into sys.path) ---
WL ""
WL "=== PY_IMPORT_SMOKE_V3 ==="
$py = Join-Path $Root ".venv\Scripts\python.exe"
if(Test-Path $py){
  $code = @"
import os,sys
print("EXE",sys.executable)
print("CWD",os.getcwd())
sys.path.insert(0, r"$Root")
import tbot
import tbot.runtime.orchestrator as o
print("IMPORT_OK", o.__file__)
"@
  try {
    Push-Location $Root
    $out = & $py -c $code 2>&1
    Pop-Location
    foreach($ln in $out){ WL $ln }
  } catch {
    Pop-Location -ErrorAction SilentlyContinue
    WL ("PY_IMPORT_EXCEPTION=" + $_.Exception.Message)
  }
} else {
  WL "PY_MISSING=.venv\\Scripts\\python.exe"
}

# --- Git tracked missing ---
WL ""
WL "=== GIT_TRACKED_MISSING_V3 ==="
$git = Join-Path $Root ".git"
if(Test-Path $git){
  Push-Location $Root
  $tracked = & git ls-files 2>$null
  $missingList = New-Object System.Collections.Generic.List[string]
  foreach($f in $tracked){
    if([string]::IsNullOrWhiteSpace($f)){ continue }
    $abs = Join-Path $Root $f
    if(!(Test-Path $abs)){
      WL ("GIT_MISSING: " + $f)
      $missingList.Add($f) | Out-Null
    }
  }
  WL ("GIT_TRACKED_COUNT=" + $tracked.Count)
  WL ("GIT_MISSING_COUNT=" + $missingList.Count)

  if($RestoreGitMissing -eq 1 -and $missingList.Count -gt 0){
    WL ""
    WL "=== GIT_RESTORE_MISSING ==="
    foreach($f in $missingList){
      try{
        & git restore --source=HEAD --worktree -- "$f" 2>$null
        WL ("RESTORED: " + $f)
      } catch {
        WL ("RESTORE_FAIL: " + $f)
      }
    }
  }
  Pop-Location
} else {
  WL "NO_GIT_DIR"
}

# --- Hash check vs latest freeze backup (key files only) ---
WL ""
WL "=== HASH_CHECK_V3 (LATEST FREEZE_BACKUP) ==="
$ops = Join-Path $Root "logs\ops"
$bk = Get-ChildItem -LiteralPath $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1
if($bk){
  WL ("LATEST_FREEZE_BACKUP=" + $bk.FullName)
  $hf = Get-ChildItem -LiteralPath $bk.FullName -File -Filter "file_hashes_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1
  if($hf){
    WL ("HASHFILE=" + $hf.FullName)
    $lines = Get-Content -LiteralPath $hf.FullName -ErrorAction SilentlyContinue
    $checked=0; $mismatch=0; $missing=0
    foreach($ln in $lines){
      if($ln -match '^SHA256\s+([0-9A-Fa-f]{64})\s+(.+)$'){
        $exp = $matches[1].ToLower()
        $abs = $matches[2].Trim()
        if($abs.StartsWith($Root,[System.StringComparison]::OrdinalIgnoreCase)){
          $rel = $abs.Substring($Root.Length).TrimStart('\')
        } else {
          $rel = $abs
        }
        $cur = Join-Path $Root $rel
        if(!(Test-Path $cur)){
          WL ("HASH_MISSING: " + $rel)
          $missing++; $checked++
          continue
        }
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $cur).Hash.ToLower()
        if($got -ne $exp){
          WL ("HASH_MISMATCH: " + $rel + " expected=" + $exp + " got=" + $got)
          $mismatch++
        } else {
          WL ("HASH_OK: " + $rel)
        }
        $checked++
      }
    }
    WL ("HASH_CHECKED=" + $checked)
    WL ("HASH_MISSING_COUNT=" + $missing)
    WL ("HASH_MISMATCH_COUNT=" + $mismatch)
  } else {
    WL "NO_HASHFILE_IN_BACKUP"
  }
} else {
  WL "NO_FREEZE_BACKUP_FOUND"
}

WL ""
WL ("REPORT_DONE=" + (Get-Date -Format s))
WL ("REPORT_FILE=" + $Report)

Log ("WROTE_REPORT=" + $Report)
