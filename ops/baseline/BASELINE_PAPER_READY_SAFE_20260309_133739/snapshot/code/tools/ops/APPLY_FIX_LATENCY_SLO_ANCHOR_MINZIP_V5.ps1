param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
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
function BackupFile([string]$p,[string]$tag){
  if(Test-Path $p){
    Copy-Item $p ($p + ".bak_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")) -Force
  }
}

# stop scheduled freeze if running
try{
  $task="ORG_BOT_PAPER_FREEZE"
  $t=Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if($t -and $t.State -eq "Running"){ Stop-ScheduledTask -TaskName $task; Start-Sleep 2 }
}catch{}

$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }

$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(!(Test-Path $lat)){ throw "MISSING_LATENCY_SCRIPT=$lat" }
ParseOrThrow $lat "LATENCY_SCRIPT"
"LATENCY_SCRIPT_OK=1" | Out-Host

# read + clean any old latency blocks (all versions)
$txt = Get-Content -Raw -Encoding UTF8 $v3
BackupFile $v3 "before_latency_v5"

$txt = [regex]::Replace($txt,'(?ms)^#\s*LATENCY_SLO_CALL_PREZIP_V\d+.*?\r?\n\r?\n','')
$txt = [regex]::Replace($txt,'(?ms)^#\s*LATENCY_SLO_CALL_V\d+.*?\r?\n\r?\n','')

# find a safe insertion point: BEFORE MinZip status log (means before zip build finished)
$anchor1="MINZIP2_OK"
$anchor2="MIN_ZIP_EXC"
$idx = $txt.IndexOf($anchor1)
if($idx -lt 0){ $idx = $txt.IndexOf($anchor2) }
if($idx -lt 0){
  # fallback: after RUNROOT_BACKUP_DIR log line
  $idx = $txt.IndexOf("RUNROOT_BACKUP_DIR=")
}
if($idx -lt 0){ throw "NO_ANCHOR_FOUND_IN_V3 (need MINZIP2_OK or MIN_ZIP_EXC or RUNROOT_BACKUP_DIR=)" }

# insert at start of the line containing the anchor (so it runs before zip section)
$ls = $txt.LastIndexOf("`n",$idx)
if($ls -lt 0){ $ls=0 } else { $ls=$ls+1 }

$block = @"
# LATENCY_SLO_CALL_PREZIP_V5 (safe one-liner; runs before MinZip/Zip)
try{
  `$ps = Join-Path `$ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
  if(Test-Path `$ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File `$ps -ProjectRoot `$ProjectRoot -RunRoot `$RunRoot -BackupDir `$bkLocal -IsoDayOverride `$IsoDayOverride -OutPath `$out -ErrPath `$err
    "LATENCY_SLO_OK=1" | Add-Content -Encoding UTF8 -Path `$out
  } else {
    "LATENCY_SLO_MISSING=1" | Add-Content -Encoding UTF8 -Path `$err
  }
}catch{
  ("LATENCY_SLO_EXC=" + `$_.Exception.Message) | Add-Content -Encoding UTF8 -Path `$err
}

"@

$txt2 = $txt.Insert($ls, $block)
Set-Content -Encoding UTF8 -Path $v3 -Value $txt2
ParseOrThrow $v3 "FREEZE_V3_AFTER_PATCH"
"FREEZE_V3_PARSE_OK=1" | Out-Host

# run freeze v3 once
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $v3 -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# verify in BK + in RUNROOT zip
$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" | Sort LastWriteTime -Desc | Select -First 1
$fe = Get-ChildItem $ops -File -Filter "FREEZE_ERR_*.txt" | Sort LastWriteTime -Desc | Select -First 1

"LAST_OUT=$($fo.FullName)" | Out-Host
Select-String -Path $fo.FullName -Pattern "RUNROOT_BACKUP_DIR=|LATENCY_SLO_OK=|LATENCY_SLO_STATUS=" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

$bk = (Select-String -Path $fo.FullName -Pattern '^RUNROOT_BACKUP_DIR=' | Select -First 1).Line.Split("=",2)[1].Trim()
$ymd = ($bk -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
"BK=$bk ymd=$ymd" | Out-Host

"BK_FILES_LATENCY:" | Out-Host
Get-ChildItem $bk -File -Filter ("LATENCY_SLO_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
  Select Name,Length,LastWriteTime | Out-Host

$zip = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*_RUNROOT.zip" -f $ymd) -ErrorAction SilentlyContinue |
  Sort LastWriteTime -Desc | Select -First 1

if($zip){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
  $has=$false
  foreach($e in $z.Entries){
    if($e.FullName -match ("LATENCY_SLO_{0}\." -f $ymd)){ $has=$true; break }
  }
  $z.Dispose()
  if($has){ "ZIP_HAS_LATENCY_SLO=1 zip=$($zip.Name)" | Out-Host } else { "ZIP_HAS_LATENCY_SLO=0 zip=$($zip.Name)" | Out-Host }
} else {
  "ZIP_NOT_FOUND_IN_BK=1" | Out-Host
}

"LAST_ERR=$($fe.FullName)" | Out-Host
Select-String -Path $fe.FullName -Pattern "LATENCY_SLO_EXC=" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

"OK=LATENCY_SLO_V5_DONE" | Out-Host
