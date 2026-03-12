$ErrorActionPreference = "Stop"

$root = "C:\alpaca-bot\org_bot"

function Backup-File($p) {
  $bak = "$p.bak_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
  Copy-Item -LiteralPath $p -Destination $bak -Force
  return $bak
}

# 1) Find orchestrator.py (call-site)
$orch = Join-Path $root "tbot\runtime\orchestrator.py"
if (!(Test-Path -LiteralPath $orch)) { throw "Missing: $orch" }

# 2) Find Stats class file by scanning python files (best-effort)
$statsFile = Get-ChildItem -Path (Join-Path $root "tbot") -Recurse -Filter "*.py" |
  Where-Object {
    Select-String -LiteralPath $_.FullName -Pattern "^\s*class\s+Stats\b" -Quiet
  } |
  Select-Object -First 1 -ExpandProperty FullName

if (!$statsFile) { throw "Could not locate class Stats in tbot/*.py" }

Write-Host "ORCH_FILE=$orch"
Write-Host "STATS_FILE=$statsFile"

# 3) Patch Stats: add bump_reason if missing
$statsText = Get-Content -LiteralPath $statsFile -Raw
$hasBump = $statsText -match "def\s+bump_reason\s*\("
if (-not $hasBump) {

  # Try to insert method inside class Stats block.
  # We insert right after the class Stats line or after __init__ if present.
  $lines = Get-Content -LiteralPath $statsFile

  $classIdx = ($lines | Select-String -Pattern "^\s*class\s+Stats\b").LineNumber
  if (-not $classIdx) { throw "Stats class line not found (unexpected)" }
  $classIdx0 = $classIdx - 1

  # Determine indent level for methods (assume 4 spaces inside class)
  $indent = "    "

  $method = @(
    ""
    "$indent" + "def bump_reason(self, reason: str) -> None:"
    "$indent$indent" + '"""Increment a counter for a drop/skip reason (optional telemetry)."""'
    "$indent$indent" + "try:"
    "$indent$indent$indent" + "# Lazy-init reasons dict"
    "$indent$indent$indent" + "d = getattr(self, 'reasons', None)"
    "$indent$indent$indent" + "if d is None:"
    "$indent$indent$indent$indent" + "d = {}"
    "$indent$indent$indent$indent" + "setattr(self, 'reasons', d)"
    "$indent$indent$indent" + "d[reason] = int(d.get(reason, 0)) + 1"
    "$indent$indent" + "except Exception:"
    "$indent$indent$indent" + "# Never let telemetry crash the bot"
    "$indent$indent$indent" + "return"
    ""
  )

  # Insert after __init__ if exists within next ~80 lines, else right after class line
  $insertAt = $classIdx0 + 1
  for ($i = $classIdx0 + 1; $i -lt [Math]::Min($lines.Count, $classIdx0 + 80); $i++) {
    if ($lines[$i] -match "^\s*def\s+__init__\s*\(") {
      # find end of __init__ block: next line that starts with 4 spaces + "def " or dedent to class level
      for ($j = $i + 1; $j -lt [Math]::Min($lines.Count, $i + 400); $j++) {
        if ($lines[$j] -match "^\s{4}def\s+" -and $j -gt $i) { $insertAt = $j; break }
        if ($lines[$j] -match "^\S") { $insertAt = $j; break }
      }
      break
    }
  }

  $bak1 = Backup-File $statsFile
  Write-Host "BACKUP_STATS=$bak1"

  $newLines = @()
  $newLines += $lines[0..($insertAt-1)]
  $newLines += $method
  $newLines += $lines[$insertAt..($lines.Count-1)]

  $newLines | Set-Content -LiteralPath $statsFile -Encoding UTF8
  Write-Host "PATCHED: added bump_reason() to Stats"
} else {
  Write-Host "OK: Stats already has bump_reason()"
}

# 4) Patch call-site defensively (optional but safe): replace stats.bump_reason(x) with getattr guard
$orchText = Get-Content -LiteralPath $orch -Raw
if ($orchText -match "stats\.bump_reason\(") {
  $bak2 = Backup-File $orch
  Write-Host "BACKUP_ORCH=$bak2"

  # Very targeted replace: stats.bump_reason(_rsn) -> (getattr(stats,'bump_reason',None) or (lambda *_:None))(_rsn)
  $orchText2 = $orchText -replace "stats\.bump_reason\(([^)]+)\)", "(getattr(stats,'bump_reason',None) or (lambda *_: None))($1)"
  Set-Content -LiteralPath $orch -Value $orchText2 -Encoding UTF8
  Write-Host "PATCHED: orchestrator call-site guarded"
} else {
  Write-Host "OK: orchestrator has no bump_reason call (unexpected given traceback)"
}

# 5) Compile check
python -m py_compile $statsFile
if ($LASTEXITCODE -ne 0) { throw "py_compile failed for Stats file" }

python -m py_compile $orch
if ($LASTEXITCODE -ne 0) { throw "py_compile failed for orchestrator.py" }

Write-Host "COMPILE_OK=YES"

# 6) Quick smoke run
$env:TBOT_SYMBOLS = "SPY"
python -m tbot.main --run --iters 5 --sleep 1 --shadow
Write-Host ("EXITCODE=" + $LASTEXITCODE)
