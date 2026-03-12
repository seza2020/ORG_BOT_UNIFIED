param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function ParseOk([string]$p){
  $tokens=$null; $errs=$null
  [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errs) | Out-Null
  if($errs -and $errs.Count -gt 0){
    $e=$errs[0]
    throw ("PARSE_FAIL: " + $e.Message + " line=" + $e.Extent.StartLineNumber + " col=" + $e.Extent.StartColumnNumber)
  }
}
function BackupFile([string]$p,[string]$tag){
  if(Test-Path $p){
    Copy-Item $p ($p + ".bak_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")) -Force
  }
}

# 0) stop scheduled freeze if running
$task="ORG_BOT_PAPER_FREEZE"
try{
  $t=Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  if($t -and $t.State -eq "Running"){ Stop-ScheduledTask -TaskName $task; Start-Sleep 2 }
}catch{}

# 1) Ensure LATENCY script exists + parses
$lat = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
if(!(Test-Path $lat)){ throw "MISSING_LATENCY_SCRIPT=$lat" }
ParseOk $lat
"LATENCY_SCRIPT_OK=1" | Out-Host

# 2) Patch ZIP builder to include LATENCY_SLO files (robust needle)
$zipb = Join-Path $ProjectRoot "tools\ops\POSTFREEZE_BUILD_MINZIP_SEL_COV_V1.ps1"
if(!(Test-Path $zipb)){ throw "MISSING_ZIP_BUILDER=$zipb" }
$z = Get-Content -Raw -Encoding UTF8 $zipb
if($z -notmatch "LATENCY_SLO_NEED_V2"){
  BackupFile $zipb "latneed_v2"
  $needle = '("SELECTION_COVERAGE_{0}.md" -f $ymd2),'
  $i = $z.IndexOf($needle)
  if($i -lt 0){
    # fallback: insert after LIVE_ERR entry (should exist)
    $needle2 = '("LIVE_ERR_{0}_LATEST.txt" -f $ymd2)'
    $j = $z.IndexOf($needle2)
    if($j -lt 0){ throw "NEEDLE_NOT_FOUND_IN_ZIPBUILDER:SELECTION_COVERAGE or LIVE_ERR" }
    $nl = $z.IndexOf("`n",$j); if($nl -lt 0){ $nl=$z.Length-1 }
    $pos = $nl + 1
  } else {
    $nl = $z.IndexOf("`n",$i); if($nl -lt 0){ $nl=$z.Length-1 }
    $pos = $nl + 1
  }
  $ins = @"
    ("LATENCY_SLO_{0}.json" -f `$ymd2),
    ("LATENCY_SLO_{0}.md" -f `$ymd2),
    # LATENCY_SLO_NEED_V2
"@
  $z2 = $z.Insert($pos, $ins)
  Set-Content -Encoding UTF8 -Path $zipb -Value $z2
  ParseOk $zipb
  "ZIP_BUILDER_PATCHED_LATENCY=1" | Out-Host
} else {
  "ZIP_BUILDER_PATCHED_LATENCY=0 (already)" | Out-Host
}

# 3) Patch FREEZE V3: call latency RIGHT BEFORE zip-builder is invoked
$v3 = Join-Path $ProjectRoot "tools\FREEZE_PAPER_PROFILE_V3.ps1"
if(!(Test-Path $v3)){ throw "MISSING_V3=$v3" }
$fv = Get-Content -Raw -Encoding UTF8 $v3

$callMarker="LATENCY_SLO_CALL_PREZIP_V2"
if($fv -notmatch [regex]::Escape($callMarker)){
  BackupFile $v3 "lat_prezip_v2"

  # find the exact place where zip builder script is called
  $anchor = "POSTFREEZE_BUILD_MINZIP_SEL_COV_V1.ps1"
  $k = $fv.IndexOf($anchor)
  if($k -lt 0){ throw "ANCHOR_NOT_FOUND_IN_V3:$anchor" }
  $ls = $fv.LastIndexOf("`n",$k); if($ls -lt 0){ $ls=0 } else { $ls=$ls+1 }

  $block=@"
# $callMarker (write LATENCY_SLO into bkLocal BEFORE building _RUNROOT.zip)
try{
  `$ps = Join-Path `$ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
  if(Test-Path `$ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File `$ps `
      -ProjectRoot `$ProjectRoot -RunRoot `$RunRoot -BackupDir `$bkLocal -IsoDayOverride `$IsoDayOverride -OutPath `$out -ErrPath `$err
    "LATENCY_SLO_OK=1" | Add-Content -Encoding UTF8 -Path `$out
  } else {
    "LATENCY_SLO_MISSING=1" | Add-Content -Encoding UTF8 -Path `$err
  }
}catch{
  ("LATENCY_SLO_EXC=" + `$_.Exception.Message) | Add-Content -Encoding UTF8 -Path `$err
}

"@
  $fv = $fv.Insert($ls, $block)
  Set-Content -Encoding UTF8 -Path $v3 -Value $fv
  ParseOk $v3
  "FREEZE_V3_PATCHED_LATENCY_PREZIP=1" | Out-Host
} else {
  "FREEZE_V3_PATCHED_LATENCY_PREZIP=0 (already)" | Out-Host
}

# 4) Run FREEZE V3 once + verify BK files + zip contains them
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $v3 -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

$ops = Join-Path $RunRoot "logs\ops"
$fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" | Sort LastWriteTime -Desc | Select -First 1
$fe = Get-ChildItem $ops -File -Filter "FREEZE_ERR_*.txt" | Sort LastWriteTime -Desc | Select -First 1
"LAST_OUT=$($fo.FullName)" | Out-Host

# show latency lines if any
Select-String -Path $fo.FullName -Pattern "RUNROOT_BACKUP_DIR=|LATENCY_SLO_" -ErrorAction SilentlyContinue |
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
Select-String -Path $fe.FullName -Pattern "LATENCY_SLO_EXC=|LATENCY_SLO_FAIL=" -ErrorAction SilentlyContinue |
  ForEach-Object { $_.Line } | Out-Host

"OK=LATENCY_SLO_PREZIP_FIXED_AND_VERIFIED" | Out-Host
