param(
  [string]$Root   = "C:\alpaca-bot\org_bot",
  [string]$OutDir = "F:\_TBOT_BACKUPS\ORG_BOT",
  [ValidateSet("CODE","OPS","FULL")]
  [string]$Mode   = "OPS",
  [int]$Keep      = 14,
  [int]$StopBot   = 0
)

$ErrorActionPreference = "Stop"

function Log([string]$m){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Write-Host "[$ts] $m"
}

function Ensure-Dir([string]$p){
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}

if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

# Ensure destination drive exists
$drive = ([System.IO.Path]::GetPathRoot($OutDir)).TrimEnd('\')
if([string]::IsNullOrWhiteSpace($drive)){ throw "Bad OutDir: $OutDir" }
if(!(Test-Path ($drive + "\"))){ throw "Destination drive not found: $drive" }

Ensure-Dir $OutDir

$ts    = Get-Date -Format "yyyyMMdd_HHmmss"
$stage = Join-Path $OutDir ("_stage_{0}_{1}" -f $Mode,$ts)
Ensure-Dir $stage

$zip = Join-Path $OutDir ("ORG_BOT_BACKUP_{0}_{1}.zip" -f $Mode,$ts)
$rep = Join-Path $OutDir ("ORG_BOT_BACKUP_{0}_{1}_REPORT.txt" -f $Mode,$ts)
$sha = $zip + ".sha256"

Log "ROOT=$Root"
Log "OUTDIR=$OutDir"
Log "MODE=$Mode"
Log "STAGE=$stage"
Log "ZIP=$zip"

# Optional: stop only org_bot python
if($StopBot -eq 1){
  $py = Join-Path $Root ".venv\Scripts\python.exe"
  Log "STOP_BOT=1 (project-only)"
  Get-Process python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $py } |
    ForEach-Object {
      try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
      Log ("KILLED_PID=" + $_.Id)
    }
}

# Excludes (secrets + noisy)
$XF = @("*.env","*alpaca_env.ps1*","*token*","*api_key*","*private_key*","*secret*")
$XD_FULL  = @("_quarantine","_restore_stage_*")
$XD_LIGHT = @(".venv","archive","backups",".git","__pycache__","replay","logs\archive")

function Run-RoboDir([string]$src,[string]$dst,[switch]$Mirror,[string[]]$XD,[string[]]$XF){
  if(!(Test-Path $src)){
    Log "SKIP (missing): $src"
    return
  }
  Ensure-Dir $dst
  $log = Join-Path $stage ("robocopy_{0}.log" -f ([IO.Path]::GetFileName($dst)))

  $args = @()
  $args += "`"$src`""
  $args += "`"$dst`""
  $args += "/R:2","/W:1","/NP","/NFL","/NDL"
  if($Mirror){ $args += "/MIR" } else { $args += "/E" }
  if($XD -and $XD.Count -gt 0){ $args += "/XD"; $args += $XD }
  if($XF -and $XF.Count -gt 0){ $args += "/XF"; $args += $XF }
  $args += "/LOG:`"$log`""

  Log ("ROBOCOPY: " + $src + " -> " + $dst)
  $p  = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -NoNewWindow -PassThru -Wait
  $rc = $p.ExitCode

  if($rc -ge 8){ throw "ROBOCOPY_FAIL: ExitCode=$rc Log=$log" }
  Log ("ROBOCOPY_OK: ExitCode=" + $rc)
}

function Copy-File([string]$src,[string]$dstDir){
  if(!(Test-Path $src)){ Log "SKIP_FILE (missing): $src"; return }
  Ensure-Dir $dstDir
  Copy-Item -Force -LiteralPath $src -Destination $dstDir
  Log ("COPY_FILE_OK: " + (Split-Path $src -Leaf))
}

# Copy plan
if($Mode -eq "CODE"){
  Run-RoboDir (Join-Path $Root "tbot")    (Join-Path $stage "tbot")    -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "tools")   (Join-Path $stage "tools")   -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "runtime") (Join-Path $stage "runtime") -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "docs")    (Join-Path $stage "docs")    -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF

  Copy-File (Join-Path $Root "VERSION_LOCK.txt") $stage
  Copy-File (Join-Path $Root ".gitignore")       $stage
  Copy-File (Join-Path $Root "run_shadow_spy.ps1") $stage
}
elseif($Mode -eq "OPS"){
  Run-RoboDir (Join-Path $Root "tbot")    (Join-Path $stage "tbot")    -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "tools")   (Join-Path $stage "tools")   -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "runtime") (Join-Path $stage "runtime") -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "docs")    (Join-Path $stage "docs")    -XD (@("__pycache__",".venv") + $XD_FULL) -XF $XF
  Run-RoboDir (Join-Path $Root "logs")    (Join-Path $stage "logs")    -XD (@("__pycache__") + $XD_FULL)        -XF $XF

  Copy-File (Join-Path $Root "VERSION_LOCK.txt") $stage
  Copy-File (Join-Path $Root ".gitignore")       $stage
  Copy-File (Join-Path $Root "run_shadow_spy.ps1") $stage
}
else {
  Run-RoboDir $Root $stage -Mirror -XD ($XD_FULL + $XD_LIGHT) -XF $XF
}

# Report
Log "REPORT=$rep"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BACKUP_TS=$ts")
$lines.Add("ROOT=$Root")
$lines.Add("MODE=$Mode")
$lines.Add("STAGE=$stage")
$lines.Add("ZIP=$zip")
$lines.Add("")

$files = Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction SilentlyContinue
$dirs  = Get-ChildItem -LiteralPath $stage -Recurse -Directory -ErrorAction SilentlyContinue
$totalBytes = ($files | Measure-Object Length -Sum).Sum

$lines.Add(("DIRS={0}" -f ($dirs.Count)))
$lines.Add(("FILES={0}" -f ($files.Count)))
$lines.Add(("TOTAL_BYTES={0}" -f $totalBytes))
$lines.Add(("TOTAL_MB={0:N2}" -f ($totalBytes/1MB)))
$lines.Add("")

$crit = @(
  "tbot\main.py",
  "tbot\runtime\orchestrator.py",
  "tools\RUN_LIVE_SHADOW_CANON_V2.ps1",
  "tools\OPS_END_OF_DAY_V2.ps1"
)
$lines.Add("CRITICAL_HASHES_SHA256:")
foreach($c in $crit){
  $p = Join-Path $stage $c
  if(Test-Path $p){
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash
    $lines.Add(("  {0}  {1}" -f $h,$c))
  } else {
    $lines.Add(("  MISSING {0}" -f $c))
  }
}
$lines.Add("")

Set-Content -Encoding UTF8 -LiteralPath $rep -Value ($lines -join "`r`n")

# ZIP (IMPORTANT: use -Path, not -LiteralPath, because of wildcard)
Log "ZIP_CREATE..."
if(Test-Path $zip){ Remove-Item -Force $zip -ErrorAction SilentlyContinue }

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force

if(!(Test-Path $zip)){ throw "ZIP_NOT_CREATED: $zip" }

$zHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash
Set-Content -Encoding ASCII -LiteralPath $sha -Value ($zHash + "  " + (Split-Path $zip -Leaf))
Log ("ZIP_SHA256=" + $zHash)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zf = [System.IO.Compression.ZipFile]::OpenRead($zip)
$entryCount = $zf.Entries.Count
$zf.Dispose()
Log ("ZIP_VERIFY_OK Entries=" + $entryCount)

# Cleanup stage
Log "CLEAN_STAGE..."
Remove-Item -Recurse -Force -LiteralPath $stage -ErrorAction SilentlyContinue

# Retention (zip + report + sha)
Log ("RETENTION Keep=" + $Keep)
$zips = Get-ChildItem -LiteralPath $OutDir -File -Filter "ORG_BOT_BACKUP_*.zip" | Sort-Object LastWriteTime -Descending
if($zips.Count -gt $Keep){
  $toRemove = $zips | Select-Object -Skip $Keep
  foreach($f in $toRemove){
    try{
      Remove-Item -Force -LiteralPath $f.FullName -ErrorAction SilentlyContinue
      $shaFile = $f.FullName + ".sha256"
      if(Test-Path $shaFile){ Remove-Item -Force -LiteralPath $shaFile -ErrorAction SilentlyContinue }
      $repFile = ($f.FullName -replace '\.zip$','_REPORT.txt')
      if(Test-Path $repFile){ Remove-Item -Force -LiteralPath $repFile -ErrorAction SilentlyContinue }
      Log ("REMOVED_OLD=" + $f.Name)
    }catch{}
  }
}

Log "DONE"
Log ("OUTPUT_ZIP=" + $zip)
Log ("OUTPUT_REPORT=" + $rep)
Log ("OUTPUT_SHA256=" + $sha)
