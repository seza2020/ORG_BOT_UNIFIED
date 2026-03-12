param([string]$ProjectRoot="C:\alpaca-bot\org_bot")
$ErrorActionPreference="Stop"

$orch = Join-Path $ProjectRoot "tbot\runtime\orchestrator.py"
if(!(Test-Path $orch)){ throw "MISSING_ORCH=$orch" }

$txt = Get-Content -Raw -Encoding UTF8 $orch

# --- Ensure imports json/os exist AFTER future-import block (never before it) ---
$lines = Get-Content -Encoding UTF8 $orch

# locate future import block
$fi=-1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match '^\s*from\s+__future__\s+import\s+'){ $fi=$i; break }
}
if($fi -lt 0){ throw "NO_FUTURE_IMPORT_FOUND" }

$fl=$fi
while($fl+1 -lt $lines.Count -and $lines[$fl+1] -match '^\s*from\s+__future__\s+import\s+'){ $fl++ }

# We'll inject imports right after the future block and any blank line immediately following it
$ins = $fl+1
while($ins -lt $lines.Count -and $lines[$ins] -match '^\s*$'){ $ins++ }

function HasLine($arr,$pat){
  foreach($l in $arr){ if($l -match $pat){ return $true } }
  return $false
}

$need_os   = -not (HasLine $lines '^\s*import\s+os\s*$')
$need_json = -not (HasLine $lines '^\s*import\s+json\s*$')

# Deduplicate exact duplicate "import os" / "import json" lines (keep first occurrence)
$seen_os=$false; $seen_json=$false
$clean = New-Object System.Collections.Generic.List[string]
foreach($l in $lines){
  if($l -match '^\s*import\s+os\s*$'){
    if($seen_os){ continue } else { $seen_os=$true }
  }
  if($l -match '^\s*import\s+json\s*$'){
    if($seen_json){ continue } else { $seen_json=$true }
  }
  $clean.Add($l) | Out-Null
}
$lines = $clean.ToArray()

# recompute insertion point after cleanup
$fi=-1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match '^\s*from\s+__future__\s+import\s+'){ $fi=$i; break }
}
$fl=$fi
while($fl+1 -lt $lines.Count -and $lines[$fl+1] -match '^\s*from\s+__future__\s+import\s+'){ $fl++ }
$ins=$fl+1
while($ins -lt $lines.Count -and $lines[$ins] -match '^\s*$'){ $ins++ }

$importsToAdd = @()
if($need_json){ $importsToAdd += "import json" }
if($need_os){   $importsToAdd += "import os" }

if($importsToAdd.Count -gt 0){
  $new = @()
  $new += $lines[0..($ins-1)]
  $new += $importsToAdd
  $new += ""  # blank line
  $new += $lines[$ins..($lines.Count-1)]
  Set-Content -Encoding UTF8 -Path $orch -Value $new
} else {
  # still write back cleaned (dedup) lines
  Set-Content -Encoding UTF8 -Path $orch -Value $lines
}

$txt = Get-Content -Raw -Encoding UTF8 $orch

# --- Apply heartbeat patch (insert after heartbeat emit block) ---
if($txt -match "#\s*HEARTBEAT_FILE_V1"){
  Write-Host "PATCH_ALREADY_PRESENT=1"
} else {
  $pattern = 'ev = make_event\(level="INFO", kind="heartbeat", payload=heartbeat\)\s*\r?\n\s*meta\.emit\(ev\);\s*announce\.emit\(ev\)\s*\r?\n'
  $m = [regex]::Match($txt, $pattern)
  if(-not $m.Success){ throw "NEEDLE_NOT_FOUND: heartbeat emit block" }

  $NL = "`r`n"
  $insert = @(
    "        # HEARTBEAT_FILE_V1",
    "        try:",
    "            rr = (os.getenv(""TBOT_RUNROOT"") or """").strip() or "".""",
    "            hb_path = os.path.join(rr, ""state"", ""heartbeat.json"")",
    "            os.makedirs(os.path.dirname(hb_path), exist_ok=True)",
    "            hb = dict(heartbeat)",
    "            hb[""ts_iso""] = now.isoformat() if hasattr(now, ""isoformat"") else str(now)",
    "            hb[""pid""] = os.getpid()",
    "            with open(hb_path, ""w"", encoding=""utf-8"") as f:",
    "                f.write(json.dumps(hb, ensure_ascii=False))",
    "            pid_path = os.path.join(rr, ""state"", ""pid.txt"")",
    "            with open(pid_path, ""w"", encoding=""utf-8"") as f:",
    "                f.write(str(os.getpid()))",
    "        except Exception:",
    "            pass",
    ""
  ) -join $NL

  $txt2 = $txt.Remove($m.Index + $m.Length, 0).Insert($m.Index + $m.Length, $insert)
  Set-Content -Encoding UTF8 -Path $orch -Value $txt2
  Write-Host "PATCH_APPLIED=1"
}

# --- VERIFY: marker exists ---
$txtV = Get-Content -Raw -Encoding UTF8 $orch
if($txtV -match "#\s*HEARTBEAT_FILE_V1"){ Write-Host "VERIFY_MARKER=1" } else { throw "VERIFY_MARKER=0" }

# --- VERIFY: compile (if venv exists) ---
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(Test-Path $py){
  & $py -m py_compile $orch
  if($LASTEXITCODE -ne 0){ throw "VERIFY_PY_COMPILE=0" }
  Write-Host "VERIFY_PY_COMPILE=1"
}else{
  Write-Host "VERIFY_PY_COMPILE=SKIP(.venv missing)"
}

Write-Host "OK=HEARTBEAT_FILE_PATCH_DONE"
