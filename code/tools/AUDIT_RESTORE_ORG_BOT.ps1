param(
  [string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference="Stop"

function WriteLine([string]$m){
  Write-Host $m
  if($script:Report){ Add-Content -Encoding UTF8 -LiteralPath $script:Report -Value $m }
}

if(!(Test-Path $Root)){ throw "ROOT_NOT_FOUND: $Root" }

$opsDir = Join-Path $Root "logs\ops"
New-Item -ItemType Directory -Force -Path $opsDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:Report = Join-Path $opsDir ("RESTORE_AUDIT_{0}.txt" -f $stamp)

WriteLine ("RESTORE_AUDIT_START=" + (Get-Date -Format s))
WriteLine ("ROOT=" + $Root)
WriteLine ("REPORT=" + $script:Report)
WriteLine ("PSVERSION=" + $PSVersionTable.PSVersion.ToString())
WriteLine ""

# ---- 1) High-level inventory ----
$allFiles = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue
$allDirs  = Get-ChildItem -LiteralPath $Root -Recurse -Force -Directory -ErrorAction SilentlyContinue

$bytes = 0L
foreach($f in $allFiles){ $bytes += [int64]$f.Length }

WriteLine "=== INVENTORY ==="
WriteLine ("DIRS_COUNT=" + $allDirs.Count)
WriteLine ("FILES_COUNT=" + $allFiles.Count)
WriteLine ("TOTAL_BYTES=" + $bytes)
WriteLine ("TOTAL_MB=" + [math]::Round($bytes/1MB,2))
WriteLine ""

WriteLine "=== TOP_LEVEL ==="
Get-ChildItem -LiteralPath $Root -Force | Sort-Object Name | ForEach-Object {
  if($_.PSIsContainer){
    WriteLine ("DIR  " + $_.Name)
  } else {
    WriteLine ("FILE " + $_.Name + " bytes=" + $_.Length)
  }
}
WriteLine ""

# ---- 2) Critical paths check ----
WriteLine "=== CRITICAL_PATHS_CHECK ==="
$criticalRel = @(
  ".venv\Scripts\python.exe",
  "tbot\main.py",
  "tbot\runtime\orchestrator.py",
  "tools\RUN_LIVE_SHADOW_CANON_V2.ps1",
  "tools\OPS_END_OF_DAY_V2.ps1",
  "tools\freeze_today_enterprise.ps1",
  "tools\freeze_today_enterprise_SAFE.ps1",
  "tools\recover_shadow_plans_from_meta.ps1",
  "tools\CLEAR_TBOT_LOCK.ps1",
  "tools\APPLY_SCHED_CLEANUP_WEEK2.ps1",
  "tools\run_shadow.ps1",
  "tools\RUN_SHADOW_UI.ps1",
  "logs\meta.jsonl",
  "logs\announce.log",
  "logs\shadow_plans.jsonl"
)

$missingCritical = New-Object System.Collections.Generic.List[string]
foreach($rel in $criticalRel){
  $p = Join-Path $Root $rel
  if(Test-Path $p){
    $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if($fi -and -not $fi.PSIsContainer){
      WriteLine ("OK: " + $rel + " bytes=" + $fi.Length + " mtime=" + $fi.LastWriteTime.ToString("s"))
    } else {
      WriteLine ("OK: " + $rel)
    }
  } else {
    WriteLine ("MISSING: " + $rel)
    $missingCritical.Add($rel) | Out-Null
  }
}
WriteLine ("MISSING_CRITICAL_COUNT=" + $missingCritical.Count)
WriteLine ""

# ---- 3) Python import smoke test (project-only) ----
WriteLine "=== PY_IMPORT_SMOKE ==="
$PY = Join-Path $Root ".venv\Scripts\python.exe"
if(Test-Path $PY){
  try{
    $out = & $PY -c "import tbot; import tbot.runtime.orchestrator as o; print('IMPORT_OK', o.__file__)" 2>&1
    WriteLine ($out | Out-String).TrimEnd()
  } catch {
    WriteLine ("IMPORT_FAIL: " + $_.Exception.Message)
  }
} else {
  WriteLine "SKIP: python.exe missing"
}
WriteLine ""

# ---- 4) Compare against latest FREEZE_BACKUP (if exists) ----
WriteLine "=== FREEZE_BACKUP_REFERENCE ==="
$bkRoot = Join-Path $Root "logs\ops"
$bk = Get-ChildItem -LiteralPath $bkRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc | Select-Object -First 1

if($bk){
  WriteLine ("LATEST_FREEZE_BACKUP=" + $bk.FullName)
  $hashFile = Get-ChildItem -LiteralPath $bk.FullName -File -Filter "file_hashes_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1

  if($hashFile){
    WriteLine ("HASHFILE=" + $hashFile.FullName)
    $lines = Get-Content -LiteralPath $hashFile.FullName -ErrorAction SilentlyContinue
    $expected = @()

    foreach($ln in $lines){
      $t = $ln.Trim()
      if([string]::IsNullOrWhiteSpace($t)){ continue }

      # Try: HASH + PATH
      if($t -match '^([A-Fa-f0-9]{64})\s+(.+)$'){
        $expected += [pscustomobject]@{ hash=$matches[1].ToLower(); rel=$matches[2].Trim() }
        continue
      }
      # Try: PATH + HASH
      if($t -match '^(.+?)\s+([A-Fa-f0-9]{64})$'){
        $expected += [pscustomobject]@{ hash=$matches[2].ToLower(); rel=$matches[1].Trim() }
        continue
      }
      # Unknown line format
      WriteLine ("WARN_HASHLINE_UNPARSED=" + $t)
    }

    $miss = 0
    $mismatch = 0
    foreach($e in $expected){
      $p = Join-Path $Root $e.rel
      if(!(Test-Path $p)){
        WriteLine ("MISSING_FROM_HASHLIST: " + $e.rel)
        $miss++
        continue
      }
      try{
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower()
        if($h -ne $e.hash){
          WriteLine ("HASH_MISMATCH: " + $e.rel + " expected=" + $e.hash + " got=" + $h)
          $mismatch++
        }
      } catch {
        WriteLine ("HASH_READ_FAIL: " + $e.rel + " err=" + $_.Exception.Message)
      }
    }
    WriteLine ("HASHLIST_ENTRIES=" + $expected.Count)
    WriteLine ("HASHLIST_MISSING=" + $miss)
    WriteLine ("HASHLIST_MISMATCH=" + $mismatch)
  } else {
    WriteLine "WARN: No file_hashes_*.txt found in latest FREEZE_BACKUP"
  }
} else {
  WriteLine "NO_FREEZE_BACKUP_FOUND"
}
WriteLine ""

# ---- 5) Scheduled tasks sanity check ----
WriteLine "=== SCHEDULED_TASKS_CHECK ==="
$taskNames = @(
  "TBOT_RUN_SHADOW_DAILY_0630",
  "TBOT_END_OF_DAY_1305",
  "TBOT_RUN_SHADOW_UI_0630",
  "TBOT_Daily_R_Report",
  "P200K_SHADOW_PIPELINE_0630"
)

foreach($tn in $taskNames){
  $t = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
  if(!$t){
    WriteLine ("TASK_NOT_FOUND: " + $tn)
    continue
  }

  WriteLine ("--- TASK=" + $tn + " STATE=" + $t.State + " ---")
  try{
    $acts = $t.Actions | ForEach-Object {
      ("EXEC=" + $_.Execute + " ARGS=" + $_.Arguments)
    }
    foreach($a in $acts){ WriteLine $a }
  } catch {
    WriteLine ("TASK_ACTION_READ_FAIL: " + $tn)
  }

  # Check if action references org_bot files and if they exist
  try{
    $argText = ($t.Actions | ForEach-Object { $_.Arguments } | Out-String)
    $paths = @()
    $m = [regex]::Matches($argText,'[A-Za-z]:\\[^"]+\.ps1')
    foreach($x in $m){ $paths += $x.Value }
    $paths = $paths | Select-Object -Unique

    foreach($pp in $paths){
      if($pp -like "C:\alpaca-bot\org_bot\*"){
        if(Test-Path $pp){ WriteLine ("OK_TASK_PATH: " + $pp) }
        else { WriteLine ("MISSING_TASK_PATH: " + $pp) }
      }
      if($pp -like "C:\alpaca-bt\*"){
        WriteLine ("WARN_OTHER_PROJECT_TASK_PATH: " + $pp)
      }
    }
  } catch { }

  WriteLine ""
}

WriteLine "=== SUMMARY ==="
WriteLine ("MISSING_CRITICAL_COUNT=" + $missingCritical.Count)
if($missingCritical.Count -gt 0){
  foreach($m in $missingCritical){ WriteLine ("MISSING_CRITICAL: " + $m) }
}

WriteLine ("RESTORE_AUDIT_DONE=" + (Get-Date -Format s))
WriteLine ("REPORT_FILE=" + $script:Report)
