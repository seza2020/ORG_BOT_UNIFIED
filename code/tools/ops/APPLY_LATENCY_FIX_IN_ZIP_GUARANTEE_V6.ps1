param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function ParseOk([string]$p){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  return -not ($errs -and $errs.Count -gt 0)
}
function FirstParseError([string]$p){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  if($errs -and $errs.Count -gt 0){
    $e=$errs[0]
    return ("PARSE_FAIL: " + $e.Message + " line=" + $e.Extent.StartLineNumber + " col=" + $e.Extent.StartColumnNumber)
  }
  return "PARSE_OK"
}
function BackupFile([string]$p,[string]$tag){
  if(Test-Path $p){
    Copy-Item $p ($p + ".bak_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")) -Force
  }
}
function InsertAfterLineContains([string]$text,[string]$contains,[string]$block,[string]$marker){
  if($text -match [regex]::Escape($marker)){ return @{text=$text; changed=$false; note="ALREADY"} }
  $i = $text.IndexOf($contains)
  if($i -lt 0){ throw "NEEDLE_NOT_FOUND:$contains" }
  $nl = $text.IndexOf("`n",$i); if($nl -lt 0){ $nl = $text.Length-1 }
  $pos = $nl + 1
  $t2 = $text.Insert($pos, $block + "`r`n")
  return @{text=$t2; changed=$true; note="PATCHED"}
}
function InsertAfterNeedle([string]$text,[string]$needle,[string]$insert,[string]$marker){
  if($text -match [regex]::Escape($marker)){ return @{text=$text; changed=$false; note="ALREADY"} }
  $i = $text.IndexOf($needle)
  if($i -lt 0){ throw "NEEDLE_NOT_FOUND:$needle" }
  $pos = $i + $needle.Length
  $t2 = $text.Insert($pos, $insert)
  return @{text=$t2; changed=$true; note="PATCHED"}
}

# stop scheduled freeze if running (avoid overlaps)
try{
  $task="ORG_BOT_PAPER_FREEZE"
  $t=Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if($t -and $t.State -eq "Running"){ Stop-ScheduledTask -TaskName $task; Start-Sleep 2 }
}catch{}

$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }

# 1) restore newest parse-ok backup if current is broken
if(-not (ParseOk $v3)){
  "CURRENT_V3_PARSE=BAD" | Out-Host
  "CURRENT_V3_ERR=$(FirstParseError $v3)" | Out-Host

  $dir = Split-Path $v3
  $cands = Get-ChildItem $dir -File -Filter "FREEZE_PAPER_PROFILE_V3.ps1.bak_*" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

  $best=$null
  foreach($f in $cands){
    if(ParseOk $f.FullName){ $best=$f; break }
  }
  if(!$best){ throw "NO_PARSE_OK_BACKUP_FOUND" }

  BackupFile $v3 "before_restore_v6"
  Copy-Item $best.FullName $v3 -Force
  "RESTORED_FROM=$($best.Name)" | Out-Host

  if(-not (ParseOk $v3)){ throw ("RESTORED_BUT_STILL_BAD: " + (FirstParseError $v3)) }
  "RESTORE_PARSE_OK=1" | Out-Host
} else {
  "CURRENT_V3_PARSE=OK" | Out-Host
}

# 2) ensure latency script exists + parse ok
$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(!(Test-Path $lat)){ throw "MISSING_LATENCY_SCRIPT=$lat" }
if(-not (ParseOk $lat)){ throw ("LATENCY_SCRIPT_BAD: " + (FirstParseError $lat)) }
"LATENCY_SCRIPT_OK=1" | Out-Host

# 3) patch V3 داخل ZIP_GUARANTEE_SEL_COV_V1 (هم اجرا + هم include در need2)
$txt = Get-Content -Raw -Encoding UTF8 $v3

if($txt -notmatch "ZIP_GUARANTEE_SEL_COV_V1"){
  throw "MARKER_NOT_FOUND_IN_V3:ZIP_GUARANTEE_SEL_COV_V1"
}

# 3a) inject latency CALL right after the marker line
$callMarker="LATENCY_SLO_FROM_ZIP_GUARANTEE_V6"
$callBlock=@"
# $callMarker
try{
  `$ps = Join-Path `$ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
  if(Test-Path `$ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File `$ps -ProjectRoot `$ProjectRoot -RunRoot `$RunRoot -BackupDir `$bk2 -IsoDayOverride `$IsoDayOverride -OutPath `$out -ErrPath `$err
    "LATENCY_SLO_OK=1" | Add-Content -Encoding UTF8 -Path `$out
  } else {
    "LATENCY_SLO_MISSING=1" | Add-Content -Encoding UTF8 -Path `$err
  }
}catch{
  ("LATENCY_SLO_EXC=" + `$_.Exception.Message) | Add-Content -Encoding UTF8 -Path `$err
}

"@
$r1 = InsertAfterLineContains $txt "ZIP_GUARANTEE_SEL_COV_V1" $callBlock $callMarker
$txt = $r1.text
"PATCH_LATENCY_CALL=$($r1.note)" | Out-Host

# 3b) add LATENCY files into $need2 list (inside that guarantee block)
# we patch by inserting immediately after the QC_OBS line if present; otherwise after LIVE_ERR line
$needMarker="LATENCY_SLO_NEED_IN_NEED2_V6"

$insLines = @"
    ("LATENCY_SLO_{0}.json" -f `$ymd2),
    ("LATENCY_SLO_{0}.md" -f `$ymd2),
    # $needMarker
"@

if($txt -match [regex]::Escape($needMarker)){
  "PATCH_LATENCY_NEED=ALREADY" | Out-Host
} else {
  $needleA='("QC_OBS_{0}.txt" -f $ymd2),'
  $needleB='("LIVE_ERR_{0}_LATEST.txt" -f $ymd2)'
  if($txt.Contains($needleA)){
    $txt = $txt.Replace($needleA, ($needleA + "`r`n" + $insLines))
    "PATCH_LATENCY_NEED=PATCHED_AFTER_QC_OBS" | Out-Host
  } elseif($txt.Contains($needleB)){
    $txt = $txt.Replace($needleB, ($needleB + "`r`n" + $insLines))
    "PATCH_LATENCY_NEED=PATCHED_AFTER_LIVE_ERR" | Out-Host
  } else {
    throw "NEEDLE_NOT_FOUND_FOR_NEED2 (expected QC_OBS or LIVE_ERR in need2 list)"
  }
}

BackupFile $v3 "before_write_latency_v6"
Set-Content -Encoding UTF8 -Path $v3 -Value $txt

if(-not (ParseOk $v3)){ throw ("V3_PARSE_BAD_AFTER_PATCH: " + (FirstParseError $v3)) }
"V3_PARSE_OK=1" | Out-Host

# 4) Run freeze V3 once
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $v3 -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# 5) Verify BK + RUNROOT zip contains latency
$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" | Sort LastWriteTime -Desc | Select -First 1
$fe = Get-ChildItem $ops -File -Filter "FREEZE_ERR_*.txt" | Sort LastWriteTime -Desc | Select -First 1

"LAST_OUT=$($fo.FullName)" | Out-Host
Select-String -Path $fo.FullName -Pattern "RUNROOT_BACKUP_DIR=|LATENCY_SLO_OK=|MINZIP2_OK=|ZIP_HAS_LATENCY_SLO=" -ErrorAction SilentlyContinue |
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
Select-String -Path $fe.FullName -Pattern "LATENCY_SLO_EXC=|ZIP_MISSING_FILE=LATENCY_SLO_" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

"OK=LATENCY_SLO_V6_DONE" | Out-Host
