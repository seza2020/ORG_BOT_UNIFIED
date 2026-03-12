param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [string]$IsoDayOverride = ""
)
$ErrorActionPreference="Stop"

$opsRoot = Join-Path $RunRoot "logs\ops"
$anaRoot = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $opsRoot,$anaRoot | Out-Null

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $opsRoot ("FREEZE_OUT_{0}.txt" -f $ts)
$err = Join-Path $opsRoot ("FREEZE_ERR_{0}.txt" -f $ts)
"" | Set-Content -Encoding UTF8 -Path $out
"" | Set-Content -Encoding UTF8 -Path $err

function O([string]$s){ $s | Add-Content -Encoding UTF8 -Path $out }
function E([string]$s){ $s | Add-Content -Encoding UTF8 -Path $err }

try{
  # Load SHADOW secrets (no key printing)
  $ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
  if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
  . $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

  if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
    $IsoDayOverride = (Get-Date).ToString("yyyy-MM-dd")
  }
  $ymd = $IsoDayOverride.Replace("-","")
  O ("ISO_DAY_USED=" + $IsoDayOverride)

  $bk = Join-Path $opsRoot ("FREEZE_BACKUP_{0}_{1}" -f $ymd,$ts)
  New-Item -ItemType Directory -Force -Path $bk | Out-Null
  O ("RUNROOT_BACKUP_DIR=" + $bk)

  # TBOT env snapshot (TBOT_* only)
  $envFile = Join-Path $bk ("env_TBOT_SAFE_{0}.txt" -f $ymd)
  (Get-ChildItem Env:TBOT_* -ErrorAction SilentlyContinue | Sort Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) |
    Set-Content -Encoding UTF8 -Path $envFile

  # SHADOW_FREEZE_EVIDENCE_V2 (always include core logs + placeholders so ZIP always builds)
  try {
    Copy-Item $out (Join-Path $bk ("FREEZE_OUT_{0}_LATEST.txt" -f $ymd)) -Force
    Copy-Item $err (Join-Path $bk ("FREEZE_ERR_{0}_LATEST.txt" -f $ymd)) -Force
  } catch {}

  foreach($p in @(
    (Join-Path $bk ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)),
    (Join-Path $bk ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)),
    (Join-Path $bk ("WATCHDOG_{0}_LATEST.txt" -f $ymd)),
    (Join-Path $bk ("HEARTBEAT_{0}_LATEST.txt" -f $ymd))
  )){
    if(!(Test-Path $p)){
      @(
        "PLACEHOLDER=1"
        ("ymd=" + $ymd)
        "reason=source_missing_in_shadow_runroot"
      ) | Set-Content -Encoding UTF8 -Path $p
    }
  }

  function CopyLatest([string]$dir,[string]$glob,[string]$destName){
    $f = Get-ChildItem $dir -File -Filter $glob -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
    if($f){
      Copy-Item $f.FullName (Join-Path $bk $destName) -Force
      O ("COPIED=" + $destName + " from=" + $f.Name)
    } else {
      O ("MISSING_LATEST=" + $glob)
    }
  }

  # last ops logs
  CopyLatest $opsRoot "LIVE_OUT_*.txt"   ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
  CopyLatest $opsRoot "LIVE_ERR_*.txt"   ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)
  CopyLatest $opsRoot "WATCHDOG_*.txt"   ("WATCHDOG_{0}_LATEST.txt" -f $ymd)
  CopyLatest $opsRoot "HEARTBEAT_*.txt"  ("HEARTBEAT_{0}_LATEST.txt" -f $ymd)

  # meta + shadow plans (if exist)
  foreach($p in @(
    (Join-Path $RunRoot "logs\meta.jsonl"),
    (Join-Path $RunRoot "logs\shadow_plans.jsonl"),
    (Join-Path $RunRoot "logs\shadow_plans_FULL.jsonl")
  )){
    if(Test-Path $p){
      Copy-Item $p (Join-Path $bk ([IO.Path]::GetFileName($p))) -Force
      O ("COPIED=" + [IO.Path]::GetFileName($p))
    }
  }

  # minimal zip (for secret certify scan)
  $zip = Join-Path $bk ("FREEZE_TODAY_{0}_{1}_RUNROOT.zip" -f $ymd,$ts)
  $paths = Get-ChildItem $bk -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | Sort-Object -Unique
  if($paths.Count -lt 2){ throw "TOO_FEW_FILES_FOR_ZIP" }
  Compress-Archive -Path ($paths | Sort-Object -Unique) -DestinationPath $zip -Force
  O ("ZIP_CREATED=" + $zip)

  exit 0
}catch{
  E ("FREEZE_SHADOW_EXC=" + $_.Exception.Message)
  exit 1
}

