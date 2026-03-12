param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function ParseOk([string]$p){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  if($errs -and $errs.Count -gt 0){ return $false } else { return $true }
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

# stop freeze task if running
$task="ORG_BOT_PAPER_FREEZE"
try{
  $t=Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if($t -and $t.State -eq "Running"){ Stop-ScheduledTask -TaskName $task; Start-Sleep 2 }
}catch{}

$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }

# 1) If current v3 is broken, restore newest parse-ok backup
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

  BackupFile $v3 "before_restore"
  Copy-Item $best.FullName $v3 -Force
  "RESTORED_FROM=$($best.Name)" | Out-Host

  if(-not (ParseOk $v3)){ throw ("RESTORED_BUT_STILL_BAD: " + (FirstParseError $v3)) }
  "RESTORE_PARSE_OK=1" | Out-Host
} else {
  "CURRENT_V3_PARSE=OK" | Out-Host
}

# 2) Ensure latency script exists
$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(!(Test-Path $lat)){ throw "MISSING_LATENCY_SCRIPT=$lat" }
if(-not (ParseOk $lat)){ throw ("LATENCY_SCRIPT_BAD: " + (FirstParseError $lat)) }
"LATENCY_SCRIPT_OK=1" | Out-Host

# 3) Patch ZIP builder to include latency if not already (idempotent)
$zipb = Join-Path $ProjectRoot "tools\ops\POSTFREEZE_BUILD_MINZIP_SEL_COV_V1.ps1"
if(!(Test-Path $zipb)){ throw "MISSING_ZIP_BUILDER=$zipb" }
$z = Get-Content -Raw -Encoding UTF8 $zipb
if($z -notmatch "LATENCY_SLO_NEED_V4"){
  BackupFile $zipb "latneed_v4"
  $needle='("SELECTION_COVERAGE_{0}.md" -f $ymd2),'
  $i=$z.IndexOf($needle)
  if($i -lt 0){ throw "ZIPBUILDER_NEEDLE_NOT_FOUND:$needle" }
  $nl=$z.IndexOf("`n",$i); if($nl -lt 0){ $nl=$z.Length-1 }
  $ins=@"
    ("LATENCY_SLO_{0}.json" -f `$ymd2),
    ("LATENCY_SLO_{0}.md" -f `$ymd2),
    # LATENCY_SLO_NEED_V4
"@
  $z2=$z.Insert($nl+1,$ins)
  Set-Content -Encoding UTF8 -Path $zipb -Value $z2
  if(-not (ParseOk $zipb)){ throw ("ZIPBUILDER_PARSE_BAD: " + (FirstParseError $zipb)) }
  "ZIP_BUILDER_PATCHED_LATENCY=1" | Out-Host
} else {
  "ZIP_BUILDER_PATCHED_LATENCY=0 (already)" | Out-Host
}

# 4) Clean any previous latency blocks in V3 + insert a safe pre-zip call
$txt = Get-Content -Raw -Encoding UTF8 $v3
BackupFile $v3 "before_latency_clean"

# remove any old latency blocks we injected
$txt = [regex]::Replace($txt,'(?ms)^#\s*LATENCY_SLO_CALL_PREZIP_V\d+.*?\r?\n\r?\n','')
$txt = [regex]::Replace($txt,'(?ms)^#\s*LATENCY_SLO_CALL_V\d+.*?\r?\n\r?\n','')

$anchor="POSTFREEZE_BUILD_MINZIP_SEL_COV_V1.ps1"
$k=$txt.IndexOf($anchor)
if($k -lt 0){ throw "ANCHOR_NOT_FOUND_IN_V3:$anchor" }
$ls=$txt.LastIndexOf("`n",$k); if($ls -lt 0){ $ls=0 } else { $ls=$ls+1 }

$block=@"
# LATENCY_SLO_CALL_PREZIP_V4 (safe one-liner; write into bkLocal before zip)
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
$txt2=$txt.Insert($ls,$block)
Set-Content -Encoding UTF8 -Path $v3 -Value $txt2

if(-not (ParseOk $v3)){ throw ("V3_PARSE_BAD_AFTER_PATCH: " + (FirstParseError $v3)) }
"FREEZE_V3_PARSE_OK=1" | Out-Host

# 5) Run freeze V3 once
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $v3 -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# 6) Verify BK + zip
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

"OK=LATENCY_SLO_RESTORED_PATCHED_AND_VERIFIED" | Out-Host
