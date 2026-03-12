$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$PAPER=Join-Path $ROOT "code\tools\paper"

$targets=@(
  (Join-Path $PAPER "RUN_PAPER_ORDER_POLL_TASK_V1.ps1"),
  (Join-Path $PAPER "RUN_PAPER_EXECUTOR_TASK_V1.ps1")
)

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$PDIR=Join-Path $ROOT ("ops\patches\LOG_APPEND_SIMPLE_" + $stamp)
New-Item -ItemType Directory -Force -Path $PDIR | Out-Null

function Patch-One([string]$T){
  if(!(Test-Path -LiteralPath $T)){ throw "TARGET_NOT_FOUND=$T" }

  Copy-Item $T (Join-Path $PDIR ([IO.Path]::GetFileName($T)+".bak")) -Force
  $raw = Get-Content -LiteralPath $T -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "TARGET_EMPTY=$T" }

  if($raw.Contains("LOG_APPEND_MODE_V1")){
    Write-Host ("SKIP_ALREADY_PATCHED=" + $T)
    return
  }

  $name = [IO.Path]::GetFileName($T)
  if($name -like "*ORDER_POLL*"){
    $outName="ORDER_POLL_OUT_APPEND.txt"
    $errName="ORDER_POLL_ERR_APPEND.txt"
  } else {
    $outName="PAPER_EXEC_OUT_APPEND.txt"
    $errName="PAPER_EXEC_ERR_APPEND.txt"
  }

  $inject = @"
# === LOG_APPEND_MODE_V1 BEGIN ===
`$__APPEND_DIR = Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" ("runtime\paper\logs\ops\_APPEND_" + (Get-Date -Format "yyyyMMdd"))
New-Item -ItemType Directory -Force -Path `$__APPEND_DIR | Out-Null
`$__OUT = Join-Path `$__APPEND_DIR "$outName"
`$__ERR = Join-Path `$__APPEND_DIR "$errName"
# === LOG_APPEND_MODE_V1 END ===
"@

  # Prepend inject (safe, no regex)
  $raw = $inject + "`r`n" + $raw

  # Simple replacements (no regex)
  # 1) If script assigns $out/$err, override them to $__OUT/__ERR
  $raw = $raw.Replace("`$out =", "`$out = `$__OUT # patched`r`n# original: `$out =")
  $raw = $raw.Replace("`$err =", "`$err = `$__ERR # patched`r`n# original: `$err =")

  # 2) If it writes via Out-File with $out/$err, route to $__OUT/__ERR with -Append
  $raw = $raw.Replace("Out-File `$out", "Out-File `$__OUT -Append")
  $raw = $raw.Replace("Out-File `$err", "Out-File `$__ERR -Append")

  # 3) If it uses Set-Content for out/err variables, convert to Add-Content (append)
  $raw = $raw.Replace("Set-Content -LiteralPath `$out -Value", "Add-Content -LiteralPath `$__OUT -Value")
  $raw = $raw.Replace("Set-Content -LiteralPath `$err -Value", "Add-Content -LiteralPath `$__ERR -Value")

  Set-Content -LiteralPath $T -Value $raw -Encoding utf8
  Unblock-File -LiteralPath $T -ErrorAction SilentlyContinue

  Write-Host ("PATCHED=" + $T)
}

foreach($t in $targets){ Patch-One $t }

Write-Host "LOG_APPEND_SIMPLE=OK"
Write-Host ("PATCH_DIR=" + $PDIR)
Write-Host "NEXT=RUN_EXECUTOR_ONCE_AND_POLL_TWICE"
