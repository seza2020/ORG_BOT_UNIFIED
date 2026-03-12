$ErrorActionPreference="Stop"

$ROOT = 'C:\alpaca-bot\ORG_BOT_UNIFIED'
$EXEC = 'C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1'
$POLL = 'C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1'

$force = @()
$force += "# === PAPER_RUNROOT_FORCE_UNIFIED BEGIN ==="
$force += '$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"'
$force += '$env:TBOT_CODE = "C:\alpaca-bot\ORG_BOT_UNIFIED\code"'
$force += '$env:RUNROOT   = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"'
$force += '$env:TBOT_RUNROOT = $env:RUNROOT'
$force += '$env:TBOT_LOG_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs"'
$force += '$env:TBOT_OPS_LOG  = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops"'
$force += "# === PAPER_RUNROOT_FORCE_UNIFIED END ==="
$forceText = ($force -join "`r`n") + "`r`n"

function Repair-One([string]$Path){
  if(!(Test-Path -LiteralPath $Path)){ throw ("FILE_NOT_FOUND=" + $Path) }
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw ("FILE_EMPTY=" + $Path) }

  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $PDIR  = Join-Path $ROOT ("ops\patches\PARAMTOP_REPAIR_" + $stamp)
  $ADIR  = Join-Path $ROOT ("ops\audit\PARAMTOP_REPAIR_" + $stamp)
  New-Item -ItemType Directory -Force -Path $PDIR | Out-Null
  New-Item -ItemType Directory -Force -Path $ADIR | Out-Null
  Copy-Item $Path (Join-Path $PDIR (([IO.Path]::GetFileName($Path)) + ".bak")) -Force

  # 1) Remove any existing injected block (wherever it sits)
  $raw2 = [regex]::Replace($raw, "(?s)#\s*===\s*PAPER_RUNROOT_FORCE_UNIFIED\s*BEGIN\s*===.*?#\s*===\s*PAPER_RUNROOT_FORCE_UNIFIED\s*END\s*===\s*\r?\n?", "", 1)

  # 2) Replace legacy runroot literals (best-effort)
  $raw2 = $raw2 -replace "C:\\alpaca-bot\\org_bot_runtime\\paper","C:\\alpaca-bot\\ORG_BOT_UNIFIED\\runtime\\paper"

  # 3) Insert AFTER param() if it exists near top; else prepend
  $lines = $raw2 -split "`r?`n"
  $inserted = $false

  # Find first non-empty non-comment line
  $firstIdx = -1
  for($i=0;$i -lt $lines.Count;$i++){
    $t = $lines[$i].Trim()
    if($t -eq ""){ continue }
    if($t.StartsWith("#")){ continue }
    $firstIdx = $i; break
  }

  if($firstIdx -ge 0 -and $lines[$firstIdx].TrimStart().ToLower().StartsWith("param(")){
    # locate closing ")" of param block
    $close = -1
    for($j=$firstIdx;$j -lt $lines.Count;$j++){
      if($lines[$j].Trim() -eq ")"){ $close=$j; break }
    }
    if($close -ge 0){
      $out=@()
      for($k=0;$k -lt $lines.Count;$k++){
        $out += $lines[$k]
        if($k -eq $close){
          $out += ""
          $out += ($forceText -split "`r`n")
          $inserted = $true
        }
      }
      $raw2 = ($out -join "`r`n")
    }
  }

  if(-not $inserted){
    # keep param() first rule: only prepend if there is no param() at top
    $raw2 = $forceText + $raw2
  }

  Set-Content -LiteralPath $Path -Value $raw2 -Encoding utf8
  Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue

  # Evidence head
  ($raw2 -split "`r?`n" | Select-Object -First 80) | Set-Content (Join-Path $ADIR (([IO.Path]::GetFileName($Path)) + ".head80.txt")) -Encoding utf8

  Write-Host ("REPAIRED=" + $Path)
  Write-Host ("PATCH_DIR=" + $PDIR)
  Write-Host ("AUDIT_DIR=" + $ADIR)
}

Repair-One $EXEC
Repair-One $POLL

Write-Host "REPAIR_DONE=OK"
Write-Host "NEXT=RERUN_EXECUTOR_AND_POLL_ONCE"
