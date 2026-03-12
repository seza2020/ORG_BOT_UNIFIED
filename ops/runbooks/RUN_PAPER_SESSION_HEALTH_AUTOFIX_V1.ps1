$ErrorActionPreference="Stop"

function WL($s){ Write-Host $s }

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$LOGDIR=Join-Path $RUNROOT "logs"
$OPS=Join-Path $ROOT "ops"
$PATCHES=Join-Path $OPS "patches"
$AUDIT=Join-Path $OPS "audit"
$STAMP=(Get-Date -Format "yyyyMMdd_HHmmss")
$PDir=Join-Path $PATCHES "PAPER_HEALTH_AUTOFIX_$STAMP"
$ADir=Join-Path $AUDIT "PAPER_HEALTH_AUTOFIX_$STAMP"
New-Item -ItemType Directory -Force $PDir | Out-Null
New-Item -ItemType Directory -Force $ADir | Out-Null

WL "ROOT=$ROOT"
WL "RUNROOT=$RUNROOT"
WL "LOGDIR=$LOGDIR"
WL "PATCHDIR=$PDir"
WL "AUDITDIR=$ADir"

# ---------- 0) HARD PRECHECK PATHS ----------
$need=@($ROOT,$CODE,$RUNROOT,$LOGDIR,$OPS)
foreach($p in $need){
  if(!(Test-Path $p)){ throw "MISSING_PATH=$p" }
}

# ---------- 1) STOP EXTRA TBOT PROCS (best-effort) ----------
try{
  $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match "tbot\.main" -and $_.CommandLine -match "ORG_BOT_UNIFIED" }
  if($procs.Count -gt 1){
    WL "MULTI_PID_DETECTED=$($procs.Count)  -> stopping all (safe reset)"
    foreach($p in $procs){
      try{ Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 2
  } else {
    WL "PID_OK=$($procs.Count)"
  }
} catch {
  WL "WARN:PROC_CHECK_FAILED=$($_.Exception.Message)"
}

# ---------- 2) SECRETS HARD BIND PATCH ----------
# Canonical vault (NO secret contents printed)
$CANON_VAULT = Join-Path $ROOT "ops\secrets\vault"
if(!(Test-Path $CANON_VAULT)){ throw "MISSING_CANON_VAULT=$CANON_VAULT" }

# Targets (best-effort)
$targets=@(
  (Join-Path $ROOT "code\tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"),
  (Join-Path $ROOT "ops\secrets\LOAD_PROFILE_SECRETS_V1.ps1"),
  (Join-Path $ROOT "LOAD_PROFILE_SECRETS_V1.ps1")
) | Select-Object -Unique

$patchedAny=$false
foreach($t in $targets){
  if(!(Test-Path $t)){ continue }
  WL "PATCH_SECRETS_FILE=$t"
  Copy-Item $t (Join-Path $PDir ("bak_" + (Split-Path $t -Leaf))) -Force

  $c = Get-Content $t -Raw

  # 2.1) Replace any org_bot_secrets root hardcode
  $c2 = $c -replace "C:\\alpaca-bot\\org_bot_secrets", $CANON_VAULT

  # 2.2) Replace any legacy org_bot tools secrets path if present
  $c2 = $c2 -replace "C:\\alpaca-bot\\org_bot\\tools\\secrets", (Join-Path $ROOT "code\tools\secrets")

  # 2.3) Enforce: if a param SecretRoot exists, clamp it to canon unless explicitly equal
  # If script defines $SecretRoot default, force it
  if($c2 -match '\[string\]\$SecretRoot'){
    # Try to force assignment after param block
    if($c2 -notmatch "TBOT_CANON_SECRETS_VAULT"){
      $inj = "`r`n`$env:TBOT_CANON_SECRETS_VAULT = `"$CANON_VAULT`"`r`n"
      $c2 = $inj + $c2
    }
  } else {
    if($c2 -notmatch "TBOT_CANON_SECRETS_VAULT"){
      $inj = "`r`n`$env:TBOT_CANON_SECRETS_VAULT = `"$CANON_VAULT`"`r`n"
      $c2 = $inj + $c2
    }
  }

  Set-Content -LiteralPath $t -Value $c2 -Encoding UTF8
  $patchedAny=$true
}

# 2.4) Repo-wide scan & replace (surgical): legacy string to canon
# This is the real root-cause you already have evidence for.
WL "SCAN_REPLACE_LEGACY_STRINGS_UNDER_CODE"
$codeFiles = Get-ChildItem $CODE -Recurse -File -Include "*.ps1","*.py","*.json","*.txt" -ErrorAction SilentlyContinue
foreach($f in $codeFiles){
  $raw = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if($null -eq $raw){ continue }
  if($raw -match "C:\\alpaca-bot\\org_bot_secrets"){
    Copy-Item $f.FullName (Join-Path $PDir ("bak_" + ($f.FullName -replace "[:\\\\]","_") + ".bak")) -Force
    $new = $raw -replace "C:\\alpaca-bot\\org_bot_secrets", $CANON_VAULT
    Set-Content -LiteralPath $f.FullName -Value $new -Encoding UTF8
    WL "REWROTE_LEGACY_REF=$($f.FullName)"
  }
}

# 2.5) Hard fail if any legacy ref remains
$hits = Get-ChildItem -Path $CODE -Recurse -File -ErrorAction SilentlyContinue |
         Select-String -SimpleMatch "C:\alpaca-bot\org_bot_secrets" -ErrorAction SilentlyContinue
if($hits){
  $hits | Select-Object -First 50 | ForEach-Object { $_.Path + ":" + $_.LineNumber } | Set-Content (Join-Path $ADir "LEGACY_SECRETS_HITS.txt")
  throw "LEGACY_SECRETS_REFERENCE_STILL_PRESENT (see AUDITDIR\\LEGACY_SECRETS_HITS.txt)"
}
WL "SECRETS_BINDING_OK_CANON=$CANON_VAULT"

# ---------- 3) LOG EXPLOSION CONTROL (best-effort patch common task scripts) ----------
# We patch poll/executor scripts if present to append to daily rolling file.
$paperTools = @(
  (Join-Path $CODE "tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1"),
  (Join-Path $CODE "tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1"),
  (Join-Path $ROOT "code\tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1"),
  (Join-Path $ROOT "code\tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1")
) | Select-Object -Unique

foreach($t in $paperTools){
  if(!(Test-Path $t)){ continue }
  WL "PATCH_LOG_APPEND=$t"
  Copy-Item $t (Join-Path $PDir ("bak_" + (Split-Path $t -Leaf))) -Force
  $c = Get-Content $t -Raw

  # Replace timestamp-per-run OUT/ERR style to daily rolling file if pattern detected
  # We clamp into $LOGDIR\ORDER_POLL_OUT_yyyyMMdd.txt / ERR_yyyyMMdd.txt
  $c = $c -replace "ORDER_POLL_OUT_`\$\([^\)]*\)\.txt", "ORDER_POLL_OUT_`$(Get-Date -Format yyyyMMdd).txt"
  $c = $c -replace "ORDER_POLL_ERR_`\$\([^\)]*\)\.txt", "ORDER_POLL_ERR_`$(Get-Date -Format yyyyMMdd).txt"

  # Ensure any redirections use append where possible (>>)
  $c = $c -replace ">\s*`"`$OUT`"", ">> `"`$OUT`""
  $c = $c -replace "2>\s*`"`$ERR`"", "2>> `"`$ERR`""

  Set-Content -LiteralPath $t -Value $c -Encoding UTF8
}

# ---------- 4) POST-BOOT HEALTH CHECKS ----------
# 4.1) Check for recent legacy spill files outside unified root (last 20 minutes)
WL "CHECK_LOG_SPILL_OUTSIDE_UNIFIED (last 20m)"
$cut=(Get-Date).AddMinutes(-20)
$spill = Get-ChildItem "C:\alpaca-bot" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -ge $cut -and $_.FullName -notlike "$ROOT*" } |
  Where-Object { $_.FullName -match "ORDER_POLL_(OUT|ERR)_" -or $_.FullName -match "meta_(events|engine)\.jsonl" }
if($spill){
  $spill | Select-Object FullName,Length,LastWriteTime | Export-Csv (Join-Path $ADir "LOG_SPILL_OUTSIDE_UNIFIED.csv") -NoTypeInformation
  throw "LOG_SPILL_OUTSIDE_UNIFIED_DETECTED (see AUDITDIR\\LOG_SPILL_OUTSIDE_UNIFIED.csv)"
}

# 4.2) Check latest error logs for MISSING_SECRETS_FILE
WL "CHECK_MISSING_SECRETS_FILE_IN_RECENT_ERRS"
$errHits = @()
try{
  $errs = Get-ChildItem $LOGDIR -Filter "ORDER_POLL_ERR_*.txt" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending | Select-Object -First 20
  foreach($e in $errs){
    $txt = Get-Content $e.FullName -Raw -ErrorAction SilentlyContinue
    if($txt -match "MISSING_SECRETS_FILE"){
      $errHits += $e.FullName
    }
  }
} catch {}
if($errHits.Count -gt 0){
  $errHits | Set-Content (Join-Path $ADir "MISSING_SECRETS_FILE_HITS.txt")
  throw "MISSING_SECRETS_FILE_DETECTED (see AUDITDIR\\MISSING_SECRETS_FILE_HITS.txt)"
}
WL "SECRETS_RUNTIME_ERRORS=0"

# 4.3) JSON integrity quick-check (meta_events/meta_engine if present)
function Check-Jsonl($path,$name){
  if(!(Test-Path $path)){ WL "SKIP_JSONL_MISSING=$name"; return }
  $bad=0; $lines=0
  Get-Content $path | ForEach-Object {
    $l=$_.Trim()
    if($l.Length -eq 0){ return }
    $lines++
    try{ $null = $l | ConvertFrom-Json } catch { $bad++ }
  }
  WL "JSONL_CHECK name=$name lines=$lines bad=$bad"
  if($bad -gt 0){ throw "BAD_JSON_DETECTED_IN_$name" }
}
Check-Jsonl (Join-Path $LOGDIR "meta_events.jsonl") "meta_events"
Check-Jsonl (Join-Path $LOGDIR "meta_engine.jsonl") "meta_engine"

# ---------- 5) EVIDENCE PACK ----------
WL "BUILD_EVIDENCE_PACK"
$ev=Join-Path $ADir "EVIDENCE"
New-Item -ItemType Directory -Force $ev | Out-Null

# copy key outputs (safe; no secrets content)
$toCopy=@(
  (Join-Path $LOGDIR "meta_events.jsonl"),
  (Join-Path $LOGDIR "meta_engine.jsonl")
)
foreach($p in $toCopy){
  if(Test-Path $p){ Copy-Item $p $ev -Force }
}

# copy latest poll out/err daily (if exist)
Get-ChildItem $LOGDIR -Filter "ORDER_POLL_*.txt" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 10 |
  ForEach-Object { Copy-Item $_.FullName $ev -Force }

# vault listing only (no secret content)
Get-ChildItem $CANON_VAULT -ErrorAction SilentlyContinue |
  Select-Object FullName,Length,LastWriteTime |
  Export-Csv (Join-Path $ev "VAULT_LIST.csv") -NoTypeInformation

$zip=Join-Path $ADir "EVIDENCE_$STAMP.zip"
Compress-Archive -Path "$ev\*" -DestinationPath $zip -Force

WL "PASS: PAPER_HEALTH_AUTOFIX_V1"
WL "EVIDENCE_ZIP=$zip"



