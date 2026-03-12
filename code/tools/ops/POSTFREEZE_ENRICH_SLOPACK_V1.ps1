param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$BackupDir=""
)
$ErrorActionPreference="Stop"

function FindLatestBackup([string]$opsRoot){
  Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort LastWriteTime -Desc | Select -First 1
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
function ZipHasPattern([string]$zipPath,[string]$pattern){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[System.IO.Compression.ZipFile]::OpenRead($zipPath)
  foreach($e in $z.Entries){
    if($e.FullName -match $pattern){ $z.Dispose(); return $true }
  }
  $z.Dispose()
  return $false
}

$opsRoot = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $opsRoot ("POSTFREEZE_SLOPACK_OUT_{0}.txt" -f $ts)
$err = Join-Path $opsRoot ("POSTFREEZE_SLOPACK_ERR_{0}.txt" -f $ts)
"" | Set-Content -Encoding UTF8 -Path $err  # ALWAYS exists

$bkObj=$null
if(-not [string]::IsNullOrWhiteSpace($BackupDir) -and (Test-Path $BackupDir)){ $bkObj=Get-Item $BackupDir } else { $bkObj=FindLatestBackup $opsRoot }
if(!$bkObj){ throw "NO_BACKUP_DIR_FOUND" }
$bk=$bkObj.FullName
$ymd=GetYmdFromName $bkObj.Name
if([string]::IsNullOrWhiteSpace($ymd)){ throw "CANNOT_PARSE_YMD" }
$iso = "{0}-{1}-{2}" -f $ymd.Substring(0,4),$ymd.Substring(4,2),$ymd.Substring(6,2)

"RUNROOT_BACKUP_DIR=$bk" | Set-Content -Encoding UTF8 -Path $out
"YMD=$ymd" | Add-Content -Encoding UTF8 -Path $out
"ISO_DAY=$iso" | Add-Content -Encoding UTF8 -Path $out

$pwsh="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwsh)){ $pwsh=(Get-Command powershell.exe).Source }

# LATENCY (already installed by you)
$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(Test-Path $lat){
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $lat -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bk -IsoDayOverride $iso -OutPath $out -ErrPath $err
  "LATENCY_DONE=1 exit=$LASTEXITCODE" | Add-Content -Encoding UTF8 -Path $out
} else {
  "LATENCY_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
}

# ORDER_POLL_LAG
$poll = Join-Path $ProjectRoot "tools\ops\ORDER_POLL_LAG_SLO_REPORT_V1.ps1"
if(Test-Path $poll){
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $poll -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bk -IsoDayOverride $iso -OutPath $out -ErrPath $err
  "ORDER_POLL_LAG_DONE=1 exit=$LASTEXITCODE" | Add-Content -Encoding UTF8 -Path $out
} else {
  "ORDER_POLL_LAG_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
}

# DECISION_TO_ORDER
$d2o = Join-Path $ProjectRoot "tools\ops\DECISION_TO_ORDER_SLO_REPORT_V1.ps1"
if(Test-Path $d2o){
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $d2o -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bk -IsoDayOverride $iso -OutPath $out -ErrPath $err
  "DECISION_TO_ORDER_DONE=1 exit=$LASTEXITCODE" | Add-Content -Encoding UTF8 -Path $out
} else {
  "DECISION_TO_ORDER_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
}

# Build RUNROOT_PLUS zip: include all BK files except older zips
$zip = Join-Path $bk ("FREEZE_TODAY_{0}_{1}_RUNROOT_PLUS.zip" -f $ymd,$ts)
$paths = Get-ChildItem $bk -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notlike "FREEZE_TODAY_*.zip" } |
  Select-Object -ExpandProperty FullName
$paths = DedupPaths $paths
if($paths.Count -lt 5){ throw ("ZIP_TOO_FEW_FILES count=" + $paths.Count) }
if(Test-Path $zip){ Remove-Item $zip -Force -ErrorAction SilentlyContinue }
Compress-Archive -Path $paths -DestinationPath $zip -Force
("ZIP_CREATED=" + $zip) | Add-Content -Encoding UTF8 -Path $out

$ok1 = ZipHasPattern $zip ("LATENCY_SLO_{0}\." -f $ymd)
$ok2 = ZipHasPattern $zip ("ORDER_POLL_LAG_SLO_{0}\." -f $ymd)
$ok3 = ZipHasPattern $zip ("DECISION_TO_ORDER_SLO_{0}\." -f $ymd)

("ZIP_HAS_LATENCY_SLO=" + [int]$ok1) | Add-Content -Encoding UTF8 -Path $out
("ZIP_HAS_ORDER_POLL_LAG_SLO=" + [int]$ok2) | Add-Content -Encoding UTF8 -Path $out
("ZIP_HAS_D2O_SLO=" + [int]$ok3) | Add-Content -Encoding UTF8 -Path $out

"OK=POSTFREEZE_SLOPACK_DONE" | Add-Content -Encoding UTF8 -Path $out
"OUT=$out" | Out-Host
"ERR=$err" | Out-Host
