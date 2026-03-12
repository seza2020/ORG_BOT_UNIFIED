param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function Ensure-File([string]$p){
  $d = Split-Path $p -Parent
  if($d){ New-Item -ItemType Directory -Force -Path $d | Out-Null }
  if(!(Test-Path $p)){ "" | Set-Content -Encoding UTF8 -Path $p }
}

$opsRoot = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $opsRoot ("POSTFREEZE_INVENTORY_OUT_{0}.txt" -f $ts)
$err = Join-Path $opsRoot ("POSTFREEZE_INVENTORY_ERR_{0}.txt" -f $ts)
Ensure-File $out; Ensure-File $err

try{
  # Resolve latest backup dir from last FREEZE_OUT
  $fo = Get-ChildItem $opsRoot -File -Filter "FREEZE_OUT_*.txt" -ErrorAction SilentlyContinue |
        Sort LastWriteTime -Desc | Select -First 1
  if(!$fo){ throw "NO_FREEZE_OUT_FOUND" }

  $bkLine = (Select-String -Path $fo.FullName -Pattern '^RUNROOT_BACKUP_DIR=' -ErrorAction SilentlyContinue | Select -First 1)
  $bk = $null
  if($bkLine){ $bk = $bkLine.Line.Split("=",2)[1].Trim() }

  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){
    $bk = (Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
           Sort LastWriteTime -Desc | Select -First 1).FullName
  }
  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){ throw "BK_NOT_FOUND" }

  $ymd = ($bk -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
  if($ymd -notmatch '^\d{8}$'){ $ymd = (Get-Date).ToString("yyyyMMdd") }

  ("TS=" + $ts) | Add-Content -Encoding UTF8 -Path $out
  ("PROJECT_ROOT=" + $ProjectRoot) | Add-Content -Encoding UTF8 -Path $out
  ("RUNROOT=" + $RunRoot) | Add-Content -Encoding UTF8 -Path $out
  ("FREEZE_OUT=" + $fo.FullName) | Add-Content -Encoding UTF8 -Path $out
  ("RUNROOT_BACKUP_DIR=" + $bk) | Add-Content -Encoding UTF8 -Path $out
  ("YMD=" + $ymd) | Add-Content -Encoding UTF8 -Path $out

  # Shadow RunRoot (best effort)
  $ShadowRunRoot="C:\alpaca-bot\org_bot_runtime\shadow"
  try{
    $sp=Join-Path $ProjectRoot "tools\profiles\shadow.profile.json"
    if(Test-Path $sp){
      $sj=Get-Content -Raw -Encoding UTF8 $sp | ConvertFrom-Json
      if($sj.runroot){ $ShadowRunRoot=[string]$sj.runroot }
    }
  }catch{}

  $invName = "INVENTORY_PAPER_SHADOW_ALL_{0}.txt" -f $ts
  $invPath = Join-Path $bk $invName

  @(
    "===== INVENTORY START ====="
    ("TIME=" + (Get-Date))
    ("PROJECT_ROOT=" + $ProjectRoot)
    ("PAPER_RUNROOT=" + $RunRoot)
    ("SHADOW_RUNROOT=" + $ShadowRunRoot)
    ""
    "===== ENV (TBOT_*) ====="
  ) | Set-Content -Encoding UTF8 $invPath

  (Get-ChildItem Env:TBOT_* -ErrorAction SilentlyContinue | Sort Name | Format-Table -AutoSize | Out-String) |
    Add-Content -Encoding UTF8 $invPath

  Add-Content -Encoding UTF8 $invPath -Value "`r`n===== TASKS (ORG_BOT/TBOT) ====="
  try{
    $all = Get-ScheduledTask -ErrorAction SilentlyContinue |
      Where-Object { $_.TaskName -match "^(TBOT|ORG_BOT)" } |
      Select TaskName,State,TaskPath
    if($all){
      ($all | Sort TaskName | Format-Table -AutoSize | Out-String) | Add-Content -Encoding UTF8 $invPath
    } else {
      "NO_TASKS_FOUND=1" | Add-Content -Encoding UTF8 $invPath
    }
  }catch{
    ("TASK_ENUM_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 $invPath
  }

  Add-Content -Encoding UTF8 $invPath -Value "`r`n===== SNAPSHOT END ====="

  ("INVENTORY_WRITTEN=" + $invPath) | Add-Content -Encoding UTF8 -Path $out

  # Zip inventory inside backup
  $zip = Join-Path $bk ("INVENTORY_{0}_{1}.zip" -f $ymd,$ts)
  if(Test-Path $zip){ Remove-Item $zip -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path $invPath -DestinationPath $zip -Force
  ("INVENTORY_ZIP_CREATED=" + $zip) | Add-Content -Encoding UTF8 -Path $out

# ZIPPLUS_ADD_INVENTORY_V1 (also embed inventory into latest RUNROOT_PLUS zip)
try{
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

  # find latest RUNROOT_PLUS zip in backup dir
  $zipPlus = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*_RUNROOT_PLUS.zip" -f $ymd) -ErrorAction SilentlyContinue |
             Sort LastWriteTime -Desc | Select -First 1
  if(!$zipPlus){
    # fallback: any *_RUNROOT_PLUS.zip
    $zipPlus = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_*_RUNROOT_PLUS.zip") -ErrorAction SilentlyContinue |
               Sort LastWriteTime -Desc | Select -First 1
  }

  if($zipPlus){
    $entryName = ("INVENTORY_PAPER_SHADOW_ALL_{0}.txt" -f $ts)

    $z = [System.IO.Compression.ZipFile]::Open($zipPlus.FullName, [System.IO.Compression.ZipArchiveMode]::Update)

    # remove existing entry with same name (if rerun)
    $old = $z.Entries | Where-Object { $_.FullName -ieq $entryName } | Select -First 1
    if($old){ $old.Delete() }

    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $invPath, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    $z.Dispose()

    ("ZIPPLUS_INVENTORY_ADDED=1 zip=" + $zipPlus.FullName + " entry=" + $entryName) | Add-Content -Encoding UTF8 -Path $out
  } else {
    ("ZIPPLUS_INVENTORY_ADDED=0 reason=NO_RUNROOT_PLUS_ZIP_FOUND") | Add-Content -Encoding UTF8 -Path $out
  }
}catch{
  ("ZIPPLUS_INVENTORY_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

  "OK=POSTFREEZE_INVENTORY_DONE" | Add-Content -Encoding UTF8 -Path $out
}catch{
  ("POSTFREEZE_INVENTORY_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

"OUT=$out" | Out-Host
"ERR=$err" | Out-Host

