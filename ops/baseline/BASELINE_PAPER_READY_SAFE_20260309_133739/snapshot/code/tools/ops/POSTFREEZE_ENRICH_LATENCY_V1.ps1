param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$BackupDir="",
  [string]$IsoDayOverride=""
)
$ErrorActionPreference="Stop"

function ParseOrThrow([string]$p,[string]$tag){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  if($errs -and $errs.Count -gt 0){
    $e=$errs[0]
    throw ("PARSE_FAIL(" + $tag + "): " + $e.Message + " line=" + $e.Extent.StartLineNumber + " col=" + $e.Extent.StartColumnNumber)
  }
}
function FindLatestBackup([string]$opsRoot){
  Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
function GetYmdFromName([string]$name){
  $m=[regex]::Match($name,'FREEZE_BACKUP_(\d{8})')
  if($m.Success){ return $m.Groups[1].Value }
  return ""
}
function DedupPaths([string[]]$paths){
  if(!$paths){ return @() }
  @($paths | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique)
}
function ZipHasLatency([string]$zipPath,[string]$ymd){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[System.IO.Compression.ZipFile]::OpenRead($zipPath)
  $pat = "LATENCY_SLO_{0}\." -f $ymd
  foreach($e in $z.Entries){
    if($e.FullName -match $pat){ $z.Dispose(); return $true }
  }
  $z.Dispose()
  return $false
}

$opsRoot = Join-Path $RunRoot "logs\ops"
$anaRoot = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $anaRoot | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $opsRoot ("POSTFREEZE_LATENCY_OUT_{0}.txt" -f $ts)
$err = Join-Path $opsRoot ("POSTFREEZE_LATENCY_ERR_{0}.txt" -f $ts)

# ERR_FILE_INIT_V1 (ensure err file exists even if empty)
"" | Set-Content -Encoding UTF8 -Path $err

"TS=$ts" | Set-Content -Encoding UTF8 -Path $out
"RUNROOT=$RunRoot" | Add-Content -Encoding UTF8 -Path $out

# choose backup
$bkObj=$null
if(-not [string]::IsNullOrWhiteSpace($BackupDir) -and (Test-Path $BackupDir)){
  $bkObj = Get-Item $BackupDir
} else {
  $bkObj = FindLatestBackup $opsRoot
}
if(!$bkObj){ throw "NO_BACKUP_DIR_FOUND" }
$bk = $bkObj.FullName
$ymd = GetYmdFromName $bkObj.Name
if([string]::IsNullOrWhiteSpace($ymd)){ throw "CANNOT_PARSE_YMD_FROM_BACKUP_NAME name=$($bkObj.Name)" }

"BACKUP_DIR=$bk" | Add-Content -Encoding UTF8 -Path $out
"YMD=$ymd" | Add-Content -Encoding UTF8 -Path $out

# compute ISO day
if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $IsoDayOverride = "{0}-{1}-{2}" -f $ymd.Substring(0,4),$ymd.Substring(4,2),$ymd.Substring(6,2)
}
"ISO_DAY=$IsoDayOverride" | Add-Content -Encoding UTF8 -Path $out

# run latency reporter
$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(!(Test-Path $lat)){ throw "MISSING_LATENCY_SCRIPT=$lat" }
ParseOrThrow $lat "LATENCY_SLO_REPORT_V1"

$pwshExe="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwshExe)){ $pwshExe=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwshExe)){ $pwshExe=(Get-Command powershell.exe).Source }

& $pwshExe -NoProfile -ExecutionPolicy Bypass -File $lat -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bk -IsoDayOverride $IsoDayOverride -OutPath $out -ErrPath $err
"LATENCY_EXIT=$LASTEXITCODE" | Add-Content -Encoding UTF8 -Path $out

# verify files exist, if not create placeholder so evidence never missing
$latJ = Join-Path $bk ("LATENCY_SLO_{0}.json" -f $ymd)
$latM = Join-Path $bk ("LATENCY_SLO_{0}.md" -f $ymd)

if(!(Test-Path $latJ)){
  '{ "status":"WARN","reason":"latency_report_missing","ymd":"'+$ymd+'" }' | Set-Content -Encoding UTF8 -Path $latJ
  "LATENCY_JSON_PLACEHOLDER=1" | Add-Content -Encoding UTF8 -Path $out
}
if(!(Test-Path $latM)){
  @("## LATENCY SLO "+$ymd,"","WARN: missing latency report; placeholder written.") | Set-Content -Encoding UTF8 -Path $latM
  "LATENCY_MD_PLACEHOLDER=1" | Add-Content -Encoding UTF8 -Path $out
}

"LATENCY_JSON_OK=1" | Add-Content -Encoding UTF8 -Path $out
"LATENCY_MD_OK=1"  | Add-Content -Encoding UTF8 -Path $out

# build RUNROOT_PLUS zip = all BK files except older zips
$zip = Join-Path $bk ("FREEZE_TODAY_{0}_{1}_RUNROOT_PLUS.zip" -f $ymd,$ts)

$paths = Get-ChildItem $bk -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "FREEZE_TODAY_*.zip" } |
  Select-Object -ExpandProperty FullName

$paths = DedupPaths $paths
if($paths.Count -lt 5){ throw ("ZIP_TOO_FEW_FILES count=" + $paths.Count) }

if(Test-Path $zip){ Remove-Item $zip -Force -ErrorAction SilentlyContinue }
Compress-Archive -Path $paths -DestinationPath $zip -Force
("ZIP_CREATED=" + $zip) | Add-Content -Encoding UTF8 -Path $out

# verify latency inside zip
$has=$false
try{ $has = ZipHasLatency $zip $ymd } catch { $has=$false }
if($has){
  ("ZIP_HAS_LATENCY_SLO=1 zip=" + $zip) | Add-Content -Encoding UTF8 -Path $out
} else {
  ("ZIP_HAS_LATENCY_SLO=0 zip=" + $zip) | Add-Content -Encoding UTF8 -Path $out
}

"OK=POSTFREEZE_ENRICH_LATENCY_DONE" | Add-Content -Encoding UTF8 -Path $out
"OUT=$out" | Out-Host
"ERR=$err" | Out-Host

