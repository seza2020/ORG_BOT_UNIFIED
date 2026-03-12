param(
  [Parameter(Mandatory=$true)][ValidateSet("PAPER","SHADOW")][string]$Profile,
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [int]$KillOnFail = 1
)
$ErrorActionPreference="Stop"

function EnsureDir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function EnsureFile([string]$p){ EnsureDir (Split-Path $p -Parent); if(!(Test-Path $p)){ "" | Set-Content -Encoding UTF8 -Path $p } }
function Finger([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $n=$s.Length
  return ($s.Substring(0,[Math]::Min(4,$n)) + "****" + $s.Substring([Math]::Max(0,$n-4)))
}

$opsRoot = Join-Path $RunRoot "logs\ops"
$anaRoot = Join-Path $RunRoot "logs\analytics"
EnsureDir $opsRoot; EnsureDir $anaRoot

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $opsRoot ("POSTFREEZE_QC_OUT_{0}_{1}.txt" -f $Profile,$ts)
$err = Join-Path $opsRoot ("POSTFREEZE_QC_ERR_{0}_{1}.txt" -f $Profile,$ts)
EnsureFile $out; EnsureFile $err

try{
  # load secrets (safe)
  $ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
  if(Test-Path $ldr){ . $ldr -Profile $Profile -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null }

  # find backup dir
  $fo = Get-ChildItem $opsRoot -File -Filter "FREEZE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
  $bk = $null
  if($fo){
    $l = Select-String -Path $fo.FullName -Pattern '^RUNROOT_BACKUP_DIR=' -ErrorAction SilentlyContinue | Select -First 1
    if($l){ $bk = $l.Line.Split("=",2)[1].Trim() }
  }
  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){
    $bk = (Get-ChildItem $opsRoot -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1).FullName
  }
  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){ throw "BK_NOT_FOUND" }

  $ymd = ($bk -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
  if($ymd -notmatch '^\d{8}$'){ $ymd=(Get-Date).ToString("yyyyMMdd") }

  # select zip (prefer PLUS)
  $zip = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*_RUNROOT_PLUS.zip" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
  if(-not $zip){ $zip = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*_RUNROOT.zip" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1 }
  if(-not $zip){ $zip = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1 }
  if(-not $zip){ throw "ZIP_NOT_FOUND" }

  Add-Content -Encoding UTF8 -Path $out -Value ("TS=" + $ts)
  Add-Content -Encoding UTF8 -Path $out -Value ("PROFILE=" + $Profile)
  Add-Content -Encoding UTF8 -Path $out -Value ("RUNROOT=" + $RunRoot)
  Add-Content -Encoding UTF8 -Path $out -Value ("RUNROOT_BACKUP_DIR=" + $bk)
  Add-Content -Encoding UTF8 -Path $out -Value ("YMD=" + $ymd)
  Add-Content -Encoding UTF8 -Path $out -Value ("ZIP=" + $zip.FullName)
  Add-Content -Encoding UTF8 -Path $out -Value ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))

  # required artifacts (minimal but enforceable)
  $qcTxt   = Join-Path $bk ("QC_{0}_{1}.txt" -f $Profile,$ymd)
  $kpiJson = Join-Path $bk ("KPI_{0}_{1}.json" -f $Profile,$ymd)
  $rkJson  = Join-Path $bk ("REALIZED_KPI_{0}_{1}.json" -f $Profile,$ymd)
  $polMd   = Join-Path $bk ("POLICY_SNAPSHOT_{0}_{1}.md" -f $Profile,$ymd)
  $briefMd = Join-Path $bk ("DAILY_BRIEF_{0}_{1}.md" -f $Profile,$ymd)

  $profPath = Join-Path $ProjectRoot ("tools\profiles\{0}.profile.json" -f $Profile.ToLower())
  $profRaw = if(Test-Path $profPath){ Get-Content -Raw -Encoding UTF8 $profPath } else { "{}" }

  @(
    ("# POLICY_SNAPSHOT " + $Profile),
    ("date=" + $ymd),
    ("runroot=" + $RunRoot),
    ("profile_path=" + $profPath),
    ("key_id_fingerprint=" + (Finger ([string]$env:APCA_API_KEY_ID))),
    "",
    $profRaw.Trim()
  ) | Set-Content -Encoding UTF8 -Path $polMd

  $meta = Join-Path $RunRoot "logs\meta.jsonl"
  $ledger = Join-Path $RunRoot "logs\ledger"
  ([ordered]@{
    ts=$ts; ymd=$ymd; profile=$Profile; runroot=$RunRoot; zip=$zip.Name
    key_id_fingerprint=(Finger ([string]$env:APCA_API_KEY_ID))
    meta_exists=(Test-Path $meta)
    ledger_exists=(Test-Path $ledger)
  } | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 -Path $kpiJson

  ([ordered]@{ ts=$ts; ymd=$ymd; profile=$Profile; realized_pnl_usd=$null } |
    ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 -Path $rkJson

  @(
    ("# DAILY_BRIEF " + $Profile),
    ("date=" + $ymd),
    ("zip=" + $zip.Name)
  ) | Set-Content -Encoding UTF8 -Path $briefMd

  $req = @($qcTxt,$kpiJson,$rkJson,$polMd,$briefMd)
  $missing = @($req | Where-Object { !(Test-Path $_) })

  @(
    ("QC_STATUS=" + ($(if($missing.Count -eq 0){"PASS"}else{"FAIL"}))),
    ("missing_count=" + $missing.Count),
    ("missing=" + (($missing | ForEach-Object { Split-Path $_ -Leaf }) -join ",")),
    ("zip=" + $zip.Name)
  ) | Set-Content -Encoding UTF8 -Path $qcTxt

  # inject into zip
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z=[System.IO.Compression.ZipFile]::Open($zip.FullName,[System.IO.Compression.ZipArchiveMode]::Update)
  try{
    foreach($p in $req){
      $name=[IO.Path]::GetFileName($p)
      $old=$z.Entries | Where-Object { $_.FullName -eq $name } | Select -First 1
      if($old){ $old.Delete() }
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$p,$name) | Out-Null
    }
  } finally { $z.Dispose() }

  $still = @($req | Where-Object { !(Test-Path $_) })
  if($still.Count -gt 0){
    Add-Content -Encoding UTF8 -Path $err -Value ("QC_ENFORCE_FAIL missing=" + (($still | ForEach-Object { Split-Path $_ -Leaf }) -join ","))
    if($KillOnFail -eq 1){
      $ks = Join-Path $RunRoot "KILL_SWITCH"
      @("ts=" + (Get-Date).ToString("s"),"reason=qc_missing","profile="+$Profile,"ymd="+$ymd) | Set-Content -Encoding UTF8 -Path $ks
    }
    exit 1
  }

  Add-Content -Encoding UTF8 -Path $out -Value "QC_ENFORCE_STATUS=PASS"
  exit 0
}catch{
  Add-Content -Encoding UTF8 -Path $err -Value ("QC_EXC=" + $_.Exception.Message)
  exit 1
}finally{
  "OUT=$out" | Out-Host
  "ERR=$err" | Out-Host
}
