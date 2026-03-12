$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$PAPER=Join-Path $ROOT "code\tools\paper"

$files=@(
  (Join-Path $PAPER "RUN_PAPER_EXECUTOR_TASK_V1.ps1"),
  (Join-Path $PAPER "RUN_PAPER_ORDER_POLL_TASK_V1.ps1")
)

# Latest append patch dir you reported
$LAST_PATCH_DIR="C:\alpaca-bot\ORG_BOT_UNIFIED\ops\patches\LOG_APPEND_SIMPLE_20260303_064323"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $ROOT ("ops\audit\REPAIR_PAPER_RUNSCRIPTS_" + $stamp)
$PDIR=Join-Path $ROOT ("ops\patches\REPAIR_PAPER_RUNSCRIPTS_" + $stamp)
New-Item -ItemType Directory -Force -Path $ADIR,$PDIR | Out-Null

function ReadText([string]$p){
  return (Get-Content -LiteralPath $p -Raw -Encoding utf8)
}

function WriteText([string]$p,[string]$txt){
  Set-Content -LiteralPath $p -Value $txt -Encoding utf8
  Unblock-File -LiteralPath $p -ErrorAction SilentlyContinue
}

function RestoreFromBackup([string]$target,[string]$bakDir){
  $name=[IO.Path]::GetFileName($target)
  $bak=Join-Path $bakDir ($name + ".bak")
  if(!(Test-Path -LiteralPath $bak)){ throw "BACKUP_NOT_FOUND=$bak" }
  Copy-Item $target (Join-Path $PDIR ($name + ".pre_restore.bak")) -Force
  Copy-Item $bak $target -Force
  Write-Host ("RESTORED=" + $target)
}

function ParamInsertIndex([string]$raw){
  $lines=$raw -split "`r?`n"
  if($lines.Count -eq 0){ return 0 }

  $start=-1
  for($i=0;$i -lt $lines.Count;$i++){
    $t=$lines[$i].Trim()
    if($t -eq "" -or $t.StartsWith("#")){ continue }
    if($t.ToLower().StartsWith("param(")){ $start=$i; break }
    else { return 0 }
  }
  if($start -lt 0){ return 0 }

  $close=-1
  for($j=$start;$j -lt $lines.Count;$j++){
    if($lines[$j].Trim() -eq ")"){ $close=$j; break }
  }
  if($close -lt 0){ throw "PARAM_BLOCK_NO_CLOSING_PAREN" }

  $prefix = ($lines[0..$close] -join "`r`n") + "`r`n"
  return $prefix.Length
}

function ApplySafeAppendPatch([string]$target){
  Copy-Item $target (Join-Path $PDIR ([IO.Path]::GetFileName($target)+".pre_patch.bak")) -Force
  $raw=ReadText $target
  if([string]::IsNullOrWhiteSpace($raw)){ throw "TARGET_EMPTY=$target" }

  if($raw.Contains("LOG_APPEND_MODE_V2_SAFE")){
    Write-Host ("SKIP_ALREADY_PATCHED=" + $target)
    return
  }

  $name=[IO.Path]::GetFileName($target)
  if($name -like "*ORDER_POLL*"){
    $outName="ORDER_POLL_OUT_APPEND.txt"
    $errName="ORDER_POLL_ERR_APPEND.txt"
  } else {
    $outName="PAPER_EXEC_OUT_APPEND.txt"
    $errName="PAPER_EXEC_ERR_APPEND.txt"
  }

  $inject=@"
# === LOG_APPEND_MODE_V2_SAFE BEGIN ===
`$__APPEND_DIR = Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" ("runtime\paper\logs\ops\_APPEND_" + (Get-Date -Format "yyyyMMdd"))
New-Item -ItemType Directory -Force -Path `$__APPEND_DIR | Out-Null
`$__OUT = Join-Path `$__APPEND_DIR "$outName"
`$__ERR = Join-Path `$__APPEND_DIR "$errName"
# === LOG_APPEND_MODE_V2_SAFE END ===
"@

  $idx=ParamInsertIndex $raw
  $raw2 = $raw.Substring(0,$idx) + $inject + "`r`n" + $raw.Substring($idx)

  # Only route known patterns; never touch param assignments.
  $raw2 = $raw2.Replace("Out-File `$out", "Out-File `$__OUT -Append")
  $raw2 = $raw2.Replace("Out-File `$err", "Out-File `$__ERR -Append")
  $raw2 = $raw2.Replace("Set-Content -LiteralPath `$out -Value", "Add-Content -LiteralPath `$__OUT -Value")
  $raw2 = $raw2.Replace("Set-Content -LiteralPath `$err -Value", "Add-Content -LiteralPath `$__ERR -Value")

  WriteText $target $raw2
  Write-Host ("PATCHED_SAFE_APPEND=" + $target)
}

function SmokeParse([string]$target){
  $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $target 2>&1 | Out-String
  $out | Set-Content (Join-Path $ADIR ([IO.Path]::GetFileName($target)+".smoke.txt")) -Encoding utf8
  if($LASTEXITCODE -ne 0){ throw ("SMOKE_FAIL=" + $target) }
}

foreach($t in $files){
  RestoreFromBackup $t $LAST_PATCH_DIR
}

foreach($t in $files){
  ApplySafeAppendPatch $t
}

foreach($t in $files){
  SmokeParse $t
}

Write-Host "REPAIR_AND_SAFE_APPEND=OK"
Write-Host ("PATCH_DIR=" + $PDIR)
Write-Host ("AUDIT_DIR=" + $ADIR)
Write-Host "NEXT=RUN_EXECUTOR_ONCE_AND_POLL_TWICE"
