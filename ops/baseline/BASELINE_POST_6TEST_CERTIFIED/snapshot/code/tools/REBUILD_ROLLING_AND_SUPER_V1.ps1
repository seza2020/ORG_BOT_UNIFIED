param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RollingDays = 10,
  [switch]$SkipTaskProofs
)

$ErrorActionPreference = "Stop"

function Assert-NotNull([string]$name, $val){
  if($null -eq $val -or ([string]::IsNullOrWhiteSpace([string]$val))){
    throw "NULL_GUARD: $name is null/empty. Do NOT run script fragments in console. Run via pwsh -File <tool.ps1> ..."
  }
}
function EnsureDir([string]$p){
  Assert-NotNull "EnsureDir.path" $p
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}
function Remove-WithRetry([string]$p, [int]$tries=25){
  for($i=1; $i -le $tries; $i++){
    try{
      if(Test-Path $p){ Remove-Item $p -Force -ErrorAction Stop }
      return
    } catch {
      Start-Sleep -Milliseconds 300
      [GC]::Collect(); [GC]::WaitForPendingFinalizers()
      if($i -eq $tries){ throw }
    }
  }
}
function Write-CanonEvidence([string]$canonPath, [string]$outPath){
  EnsureDir (Split-Path $outPath -Parent)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("EVIDENCE: CANON RUNNER AUDIT") | Out-Null
  $lines.Add(("CREATED={0}" -f (Get-Date -Format s))) | Out-Null
  $lines.Add(("CANON_PATH={0}" -f $canonPath)) | Out-Null
  $lines.Add("") | Out-Null

  if(!(Test-Path $canonPath)){
    $lines.Add("WARN: CANON_MISSING") | Out-Null
    $lines | Set-Content -Encoding UTF8 -Path $outPath
    return
  }

  $lines.Add("---- ts2/out/err ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern '\$ts2=\(Get-Date -Format','LIVE_OUT_','LIVE_ERR_','\$OPS' |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }

  $lines.Add("") | Out-Null
  $lines.Add("---- lock/force ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern 'RUN_SHADOW\.lock','\[int\]\$Force','STALE_LOCK_CLEARED','BLOCK:' |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }

  $lines | Set-Content -Encoding UTF8 -Path $outPath
}

# ---------- NULL GUARDS ----------
Assert-NotNull "Root" $Root
Assert-NotNull "RollingDays" $RollingDays
if(!(Test-Path $Root)){ throw "MISSING_ROOT: $Root" }
if($RollingDays -lt 1){ throw "BAD_ARG: RollingDays must be >= 1" }

# ---------- PATHS ----------
$Logs    = Join-Path $Root "logs"
$Ops     = Join-Path $Logs "ops"
$KC      = Join-Path $Ops  "knowledge_current"
$Docs    = Join-Path $KC   "docs"
$Zips    = Join-Path $KC   "zips"
$DailyDir= Join-Path $Zips "dailies"

$Stage   = Join-Path $Docs "stage_gates"
$Tasks   = Join-Path $Docs "tasks"

$Rolling = Join-Path $Zips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
$Super   = Join-Path $Zips "ORG_BOT_KNOWLEDGE_SUPER.zip"

$StaticOps  = Join-Path $Zips "ORG_BOT_STATIC_OPS.zip"
$StaticCode = Join-Path $Zips "ORG_BOT_STATIC_CODE.zip"

EnsureDir $Ops
EnsureDir $KC
EnsureDir $Docs
EnsureDir $Zips
EnsureDir $DailyDir
EnsureDir $Stage
EnsureDir $Tasks

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# ---------- ENSURE REQUIRED DOCS (create if missing) ----------
$sg1 = Join-Path $Stage "STAGE_GATE_SHADOW_TO_PAPER.md"
$sg2 = Join-Path $Stage "STAGE_GATE_PAPER_TO_LIVE.md"
$jr  = Join-Path $Docs  "PAPER_JOURNAL_TEMPLATE.csv"
$ev  = Join-Path $Docs  "EVIDENCE_CANON_RUNNER_AUDIT.txt"
$canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"

if(!(Test-Path $sg1)){
@"
# SHADOW -> PAPER Stage Gate (Auditable)
PASS:
- >= 3 full trading days with no exceptions/tracebacks
- FROM_META exists and used as count source
- EOD produces freeze + QC + clears lock
FAIL:
- any traceback/import error/exception
"@ | Set-Content -Encoding UTF8 -Path $sg1
}
if(!(Test-Path $sg2)){
@"
# PAPER -> LIVE Stage Gate (Auditable)
PASS:
- >= 30 paper trades
- positive expectancy + bounded drawdown
FAIL:
- repeated operational failures or DD breach
"@ | Set-Content -Encoding UTF8 -Path $sg2
}
if(!(Test-Path $jr)){
"date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes" | Set-Content -Encoding UTF8 -Path $jr
}

# always refresh evidence (cheap + deterministic)
Write-CanonEvidence -canonPath $canon -outPath $ev

# ---------- TASK PROOFS (best-effort) ----------
if(-not $SkipTaskProofs){
  $q = Join-Path $Tasks ("schtasks_query_{0}.txt" -f $ts)
  try {
    schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /V /FO LIST | Out-File -Encoding UTF8 $q -Append
  } catch { "WARN: query TBOT_RUN_SHADOW_DAILY_0630 failed" | Out-File -Encoding UTF8 $q -Append }
  try {
    schtasks /Query /TN "\TBOT_END_OF_DAY_1305" /V /FO LIST | Out-File -Encoding UTF8 $q -Append
  } catch { "WARN: query TBOT_END_OF_DAY_1305 failed" | Out-File -Encoding UTF8 $q -Append }

  try { schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /XML | Out-File -Encoding UTF8 (Join-Path $Tasks "TBOT_RUN_SHADOW_DAILY_0630.xml") } catch {}
  try { schtasks /Query /TN "\TBOT_END_OF_DAY_1305"       /XML | Out-File -Encoding UTF8 (Join-Path $Tasks "TBOT_END_OF_DAY_1305.xml") } catch {}
}

# ---------- BUILD ROLLING (atomic replace) ----------
$dailies = @(Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue | Sort-Object Name -Desc)
if($dailies.Count -eq 0){ throw "NO_DAILIES_FOUND: $DailyDir" }

$take = [Math]::Min($RollingDays, $dailies.Count)
$tmp = Join-Path $Zips ("_roll_{0}" -f $ts)
if(Test-Path $tmp){ Remove-Item $tmp -Recurse -Force }
EnsureDir $tmp

$dailies | Select-Object -First $take | Copy-Item -Destination $tmp -Force

$RollingNew = $Rolling + ".new"
Remove-WithRetry $RollingNew
Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $RollingNew -Force
Remove-Item $tmp -Recurse -Force

Remove-WithRetry $Rolling
Move-Item -Force $RollingNew $Rolling

# ---------- BUILD SUPER (atomic replace) ----------
$tmpS = Join-Path $Zips ("_super_{0}" -f $ts)
if(Test-Path $tmpS){ Remove-Item $tmpS -Recurse -Force }
EnsureDir $tmpS

Copy-Item -Recurse -Force $Docs (Join-Path $tmpS "docs")
Copy-Item -Force $Rolling (Join-Path $tmpS (Split-Path $Rolling -Leaf))

if(Test-Path $StaticOps){  Copy-Item -Force $StaticOps  (Join-Path $tmpS "ORG_BOT_STATIC_OPS.zip") }
if(Test-Path $StaticCode){ Copy-Item -Force $StaticCode (Join-Path $tmpS "ORG_BOT_STATIC_CODE.zip") }

@(
  ("CREATED={0}" -f (Get-Date -Format s))
  ("ROLLING_ZIP={0}" -f (Split-Path $Rolling -Leaf))
  ("ROLLING_COUNT={0}" -f $take)
  ("STATIC_OPS_PRESENT={0}" -f (Test-Path $StaticOps))
  ("STATIC_CODE_PRESENT={0}" -f (Test-Path $StaticCode))
  ("EVIDENCE_FILE=docs/EVIDENCE_CANON_RUNNER_AUDIT.txt")
) | Set-Content -Encoding UTF8 -Path (Join-Path $tmpS "MANIFEST.txt")

$SuperNew = $Super + ".new"
Remove-WithRetry $SuperNew
Compress-Archive -Path (Join-Path $tmpS "*") -DestinationPath $SuperNew -Force
Remove-Item $tmpS -Recurse -Force

Remove-WithRetry $Super
Move-Item -Force $SuperNew $Super

# ---------- FINAL AUDIT (super required items) ----------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$required = @(
  "MANIFEST.txt",
  "docs/",
  "docs/stage_gates/STAGE_GATE_SHADOW_TO_PAPER.md",
  "docs/stage_gates/STAGE_GATE_PAPER_TO_LIVE.md",
  "docs/PAPER_JOURNAL_TEMPLATE.csv",
  "docs/tasks/",
  "docs/EVIDENCE_CANON_RUNNER_AUDIT.txt",
  (Split-Path $Rolling -Leaf),
  "ORG_BOT_STATIC_OPS.zip",
  "ORG_BOT_STATIC_CODE.zip"
)

$missing = @()
$zs = $null
try{
  $zs = [IO.Compression.ZipFile]::OpenRead($Super)
  foreach($p in $required){
    $ok = $false
    if($p.EndsWith("/")){
      $ok = (@($zs.Entries | Where-Object { $_.FullName -like "$p*" }).Count -gt 0)
    } else {
      $ok = (@($zs.Entries | Where-Object { $_.FullName -eq $p }).Count -gt 0)
    }
    if(-not $ok){ $missing += $p }
  }
} finally {
  if($zs){ $zs.Dispose() }
}

"OK: DAILY_DIR=$DailyDir"
"OK: ROLLING_ZIP=$Rolling"
"OK: SUPER_ZIP=$Super"
if($missing.Count -eq 0){
  "AUDIT_PASS=True"
} else {
  "AUDIT_PASS=False"
  $missing | ForEach-Object { "MISSING:$($_)" }
  exit 2
}
