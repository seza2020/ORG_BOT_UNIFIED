param([string]$Root="C:\alpaca-bot\org_bot")

$ErrorActionPreference="Stop"

function WL([string]$m){
  Write-Host $m
  if($script:Report){ Add-Content -Encoding UTF8 -LiteralPath $script:Report -Value $m }
}

if(!(Test-Path $Root)){ throw "ROOT_NOT_FOUND: $Root" }

$opsDir = Join-Path $Root "logs\ops"
New-Item -ItemType Directory -Force -Path $opsDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:Report = Join-Path $opsDir ("RESTORE_AUDIT_V2_{0}.txt" -f $stamp)

WL ("RESTORE_AUDIT_V2_START=" + (Get-Date -Format s))
WL ("ROOT=" + $Root)
WL ("REPORT=" + $script:Report)
WL ("PSVERSION=" + $PSVersionTable.PSVersion.ToString())
WL ""

# ---- A) Import smoke (fix: run from Root) ----
WL "=== PY_IMPORT_SMOKE_V2 ==="
$PY = Join-Path $Root ".venv\Scripts\python.exe"
if(Test-Path $PY){
  Push-Location -LiteralPath $Root
  try{
    $out = & $PY -c "import sys; print('CWD',sys.path[0]); import tbot; import tbot.runtime.orchestrator as o; print('IMPORT_OK', o.__file__)" 2>&1
    WL (($out | Out-String).TrimEnd())
  } catch {
    WL ("IMPORT_FAIL: " + $_.Exception.Message)
  }
  Pop-Location
}else{
  WL "SKIP: python.exe missing"
}
WL ""

# ---- B) Choose reference FREEZE_BACKUP (prefer one BEFORE restore-stage folder time if exists) ----
WL "=== FREEZE_BACKUP_REFERENCE_V2 ==="
$stage = Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^(?i)_restore_stage_(\d{8})_(\d{6})$' } |
  Sort-Object Name | Select-Object -First 1

$cutoff = $null
if($stage){
  $m = [regex]::Match($stage.Name,'_restore_stage_(\d{8})_(\d{6})')
  if($m.Success){
    $cutoff = [datetime]::ParseExact(($m.Groups[1].Value + $m.Groups[2].Value),'yyyyMMddHHmmss',$null)
    WL ("RESTORE_STAGE_DIR=" + $stage.FullName)
    WL ("RESTORE_STAGE_TS=" + $cutoff.ToString("s"))
  }
}

$bkRoot = Join-Path $Root "logs\ops"
$allBk = Get-ChildItem -LiteralPath $bkRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Desc

$bk = $null
if($cutoff){
  $bk = $allBk | Where-Object { $_.LastWriteTime -lt $cutoff } | Select-Object -First 1
}
if(-not $bk){
  $bk = $allBk | Select-Object -First 1
}

if(!$bk){
  WL "NO_FREEZE_BACKUP_FOUND"
  WL ""
}else{
  WL ("REF_FREEZE_BACKUP=" + $bk.FullName + " mtime=" + $bk.LastWriteTime.ToString("s"))
  $hashFile = Get-ChildItem -LiteralPath $bk.FullName -File -Filter "file_hashes_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Desc | Select-Object -First 1

  if(!$hashFile){
    WL "WARN: No file_hashes_*.txt found in REF_FREEZE_BACKUP"
    WL ""
  } else {
    WL ("HASHFILE=" + $hashFile.FullName)

    # parse lines:
    # 1) SHA256 <hash> <abs_path>
    # 2) <hash> <path>
    # 3) <path> <hash>
    $expected = New-Object System.Collections.Generic.List[object]
    $lines = Get-Content -LiteralPath $hashFile.FullName -ErrorAction SilentlyContinue

    foreach($ln in $lines){
      $t = $ln.Trim()
      if([string]::IsNullOrWhiteSpace($t)){ continue }

      if($t -match '^SHA256\s+([A-Fa-f0-9]{64})\s+(.+)$'){
        $h=$matches[1].ToLower(); $p=$matches[2].Trim()
      } elseif($t -match '^([A-Fa-f0-9]{64})\s+(.+)$'){
        $h=$matches[1].ToLower(); $p=$matches[2].Trim()
      } elseif($t -match '^(.+?)\s+([A-Fa-f0-9]{64})$'){
        $h=$matches[2].ToLower(); $p=$matches[1].Trim()
      } else {
        WL ("WARN_HASHLINE_UNPARSED=" + $t)
        continue
      }

      # normalize to relative path under Root if possible
      $rel = $p
      if($rel -like "$Root\*"){ $rel = $rel.Substring($Root.Length+1) }
      $expected.Add([pscustomobject]@{ hash=$h; rel=$rel }) | Out-Null
    }

    $miss=0; $mismatch=0; $checked=0
    foreach($e in $expected){
      $cur = Join-Path $Root $e.rel
      if(!(Test-Path $cur)){
        WL ("MISSING_FROM_REF: " + $e.rel)
        $miss++
        continue
      }
      try{
        $hcur = (Get-FileHash -Algorithm SHA256 -LiteralPath $cur).Hash.ToLower()
        $checked++
        if($hcur -ne $e.hash){
          WL ("HASH_MISMATCH: " + $e.rel + " expected=" + $e.hash + " got=" + $hcur)
          $mismatch++
        }
      } catch {
        WL ("HASH_READ_FAIL: " + $e.rel + " err=" + $_.Exception.Message)
      }
    }

    WL ("HASHLIST_ENTRIES=" + $expected.Count)
    WL ("HASHLIST_CHECKED=" + $checked)
    WL ("HASHLIST_MISSING=" + $miss)
    WL ("HASHLIST_MISMATCH=" + $mismatch)
    WL ""
  }
}

# ---- C) Git tracked missing (best for code loss) ----
WL "=== GIT_TRACKED_MISSING ==="
$git = (Get-Command git -ErrorAction SilentlyContinue)
if($git -and (Test-Path (Join-Path $Root ".git"))){
  try{
    $tracked = & git -C $Root ls-files 2>$null
    $gm = 0
    foreach($f in $tracked){
      $p = Join-Path $Root $f
      if(!(Test-Path $p)){
        WL ("GIT_MISSING: " + $f)
        $gm++
      }
    }
    WL ("GIT_TRACKED_COUNT=" + $tracked.Count)
    WL ("GIT_MISSING_COUNT=" + $gm)
  } catch {
    WL ("GIT_CHECK_FAIL: " + $_.Exception.Message)
  }
} else {
  WL "SKIP: git not found or .git missing"
}
WL ""

WL ("RESTORE_AUDIT_V2_DONE=" + (Get-Date -Format s))
WL ("REPORT_FILE=" + $script:Report)
