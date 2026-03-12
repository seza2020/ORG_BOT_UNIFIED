param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day  = "",
  [int]$TopLive = 5,
  [int]$TopFreeze = 3,
  [switch]$Zip
)

$ErrorActionPreference="Stop"

function Add-Row($list, $group, $path){
  $exists = Test-Path -LiteralPath $path
  $it = $null
  if($exists){ $it = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue }
  $list.Add([pscustomobject]@{
    Group=$group
    Path=$path
    Exists=$exists
    Length=if($it){$it.Length}else{0}
    LastWriteTime=if($it){$it.LastWriteTime}else{$null}
  }) | Out-Null
}

function Copy-Into($destDir, $path){
  if(!(Test-Path -LiteralPath $path)){ return }
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  Copy-Item -LiteralPath $path -Destination (Join-Path $destDir (Split-Path $path -Leaf)) -Force
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$Ops = Join-Path $Root "logs\ops"
$Logs = Join-Path $Root "logs"
$OutDir = Join-Path $Ops ("UPLOAD_BUNDLE_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if([string]::IsNullOrWhiteSpace($Day)){
  $Day = (Get-Date).ToString("yyyyMMdd")
}

$list = New-Object System.Collections.Generic.List[object]

Add-Row $list "core_logs" (Join-Path $Logs "meta.jsonl")
Add-Row $list "core_logs" (Join-Path $Logs "announce.log")
Add-Row $list "core_logs" (Join-Path $Logs "shadow_plans.jsonl")

Add-Row $list "shadow_daily" (Join-Path $Logs ("shadow_daily\shadow_plans_{0}_FROM_META.jsonl" -f $Day))

Get-ChildItem -LiteralPath $Ops -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First $TopLive |
  ForEach-Object { Add-Row $list "ops_live_out" $_.FullName }

Get-ChildItem -LiteralPath $Ops -Filter "LIVE_ERR_*.txt" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First $TopLive |
  ForEach-Object { Add-Row $list "ops_live_err" $_.FullName }

$FreezeDir = Join-Path $Logs "freeze"
Get-ChildItem -LiteralPath $FreezeDir -Filter "FREEZE_TODAY_*.zip" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First $TopFreeze |
  ForEach-Object { Add-Row $list "freeze_zip" $_.FullName }

$Tools = Join-Path $Root "tools"
Add-Row $list "tools" (Join-Path $Tools "RUN_LIVE_SHADOW_CANON_V2.ps1")
Add-Row $list "tools" (Join-Path $Tools "OPS_END_OF_DAY_V2.ps1")
Add-Row $list "tools" (Join-Path $Tools "recover_shadow_plans_from_meta.ps1")
Add-Row $list "tools" (Join-Path $Tools "freeze_today_enterprise_SAFE.ps1")
Add-Row $list "tools" (Join-Path $Tools "run_shadow.ps1")
Add-Row $list "tools" (Join-Path $Tools "RUN_SHADOW_UI.ps1")
Add-Row $list "tools_ops" (Join-Path $Tools "ops\TBOT_Freeze.ps1")

$manifest = Join-Path $OutDir ("UPLOAD_FILE_LIST_{0}.txt" -f $ts)

$sorted = $list | Sort-Object `
  @{Expression="Group"; Descending=$false}, `
  @{Expression="Exists"; Descending=$true}, `
  @{Expression="LastWriteTime"; Descending=$true}

$sorted | ForEach-Object {
  "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.Group, $_.Exists, $_.LastWriteTime, $_.Length, $_.Path
} | Set-Content -Encoding UTF8 -Path $manifest

foreach($r in $sorted){
  if(-not $r.Exists){ continue }
  $dest = Join-Path $OutDir $r.Group
  Copy-Into $dest $r.Path
}

if($Zip){
  $zipPath = Join-Path $Ops ("UPLOAD_BUNDLE_{0}.zip" -f $ts)
  if(Test-Path $zipPath){ Remove-Item $zipPath -Force }
  Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zipPath -Force
  "ZIP_READY=$zipPath"
}

"FOLDER_READY=$OutDir"
"MANIFEST_READY=$manifest"

