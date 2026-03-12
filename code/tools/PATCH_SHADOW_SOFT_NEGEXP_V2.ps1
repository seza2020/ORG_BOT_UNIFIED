# tools/PATCH_SHADOW_SOFT_NEGEXP_V2.ps1
$ErrorActionPreference = "Stop"

function New-BackupDir {
  param([string]$Root)
  $ops = Join-Path $Root "logs\ops"
  New-Item -ItemType Directory -Force -Path $ops | Out-Null
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $bdir = Join-Path $ops ("PATCH_SHADOW_SOFT_NEGEXP_" + $stamp)
  New-Item -ItemType Directory -Force -Path $bdir | Out-Null
  return $bdir
}

function Replace-MarkedBlock {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [string]$BeginMarker,
    [Parameter(Mandatory)] [string]$EndMarker,
    [Parameter(Mandatory)] [string]$NewInnerText
  )

  if (!(Test-Path $Path)) { throw "Missing file: $Path" }

  $raw = Get-Content -Raw -Encoding UTF8 $Path
  $useCRLF = $raw.Contains("`r`n")
  $txt = $raw -replace "`r`n","`n"

  $bi = $txt.IndexOf($BeginMarker)
  $ei = $txt.IndexOf($EndMarker)
  if ($bi -lt 0 -or $ei -lt 0 -or $ei -le $bi) {
    throw "Markers not found or invalid order in $Path`nBEGIN=$BeginMarker`nEND=$EndMarker"
  }

  # start-of-line for begin marker
  $lineStart = $txt.LastIndexOf("`n", $bi)
  if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart = $lineStart + 1 }

  # indent from lineStart to marker start
  $indent = $txt.Substring($lineStart, $bi - $lineStart)

  # end-of-line for end marker
  $endLineEnd = $txt.IndexOf("`n", $ei)
  if ($endLineEnd -lt 0) { $endLineEnd = $txt.Length } else { $endLineEnd = $endLineEnd + 1 }

  $innerLines = ($NewInnerText -replace "`r`n","`n") -split "`n"
  $innerIndented = ($innerLines | ForEach-Object { if ($_ -eq "") { "" } else { $indent + $_ } }) -join "`n"

  $replacement =
    $indent + $BeginMarker + "`n" +
    $innerIndented + "`n" +
    $indent + $EndMarker + "`n"

  $newTxt = $txt.Substring(0, $lineStart) + $replacement + $txt.Substring($endLineEnd)
  if ($useCRLF) { $newTxt = $newTxt -replace "`n","`r`n" }

  Set-Content -Encoding UTF8 -Path $Path -Value $newTxt
}

# ---- main ----
# IMPORTANT: root is resolved from this script location => run from anywhere safely.
$root = Split-Path $PSScriptRoot -Parent

$orch  = Join-Path $root "tbot\runtime\orchestrator.py"
$canon = Join-Path $root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"

Write-Host "ROOT  => $root"
Write-Host "ORCH  => $orch"
Write-Host "CANON => $canon"

$backup = New-BackupDir -Root $root
Copy-Item -Force $orch  (Join-Path $backup "orchestrator.py.bak")
Copy-Item -Force $canon (Join-Path $backup "RUN_LIVE_SHADOW_CANON_V2.ps1.bak")

# 1) Canon env block (shadow-only knobs)
$canonBegin = "# --- TBOT_SHADOW_SOFT_NEGEXP_ENV_V1 BEGIN ---"
$canonEnd   = "# --- TBOT_SHADOW_SOFT_NEGEXP_ENV_V1 END ---"

$canonInner = @'
# Shadow-only: prevent "negative_expectancy" from hard-killing the day.
# Goal: keep the day representative for tuning, while keeping risk low + auditable.
$env:TBOT_SHADOW_SOFT_NEGEXP = "1"
$env:TBOT_SHADOW_SOFT_NEGEXP_MIN_ACCEPTS = "120"
$env:TBOT_SHADOW_SOFT_NEGEXP_CAP_RATIO = "0.10"
$env:TBOT_SHADOW_SOFT_NEGEXP_COOLDOWN_SEC = "180"
# PT local time (24h). Until this time, hard-off is forbidden => soft mode instead.
$env:TBOT_SHADOW_SOFT_NEGEXP_SOFT_UNTIL_PT = "13:00"
'@

Replace-MarkedBlock -Path $canon -BeginMarker $canonBegin -EndMarker $canonEnd -NewInnerText $canonInner.TrimEnd()

# 2) Orchestrator policy block
$orchBegin = "# --- TBOT_SHADOW_SOFT_NEGEXP_V1 BEGIN ---"
$orchEnd   = "# --- TBOT_SHADOW_SOFT_NEGEXP_V1 END ---"

$orchInner = @'
try:
    import os as _tbot_os
    import datetime as _tbot_dt

    if bool(shadow_enabled) and str(_tbot_os.getenv("TBOT_SHADOW_SOFT_NEGEXP","0")).strip() == "1":
        _soft_cap = float(str(_tbot_os.getenv("TBOT_SHADOW_SOFT_NEGEXP_CAP_RATIO","0.10")).strip() or "0.10")
        _min_acc  = int(str(_tbot_os.getenv("TBOT_SHADOW_SOFT_NEGEXP_MIN_ACCEPTS","120")).strip() or "120")
        _soft_cd  = int(str(_tbot_os.getenv("TBOT_SHADOW_SOFT_NEGEXP_COOLDOWN_SEC","180")).strip() or "180")
        _until_s  = str(_tbot_os.getenv("TBOT_SHADOW_SOFT_NEGEXP_SOFT_UNTIL_PT","13:00")).strip()

        # local machine time (PT on your box)
        _now = _tbot_dt.datetime.now()
        _now_min = int(_now.hour) * 60 + int(_now.minute)

        _until_min = None
        try:
            _hh, _mm = [int(x) for x in _until_s.split(":")[:2]]
            _until_min = _hh * 60 + _mm
        except Exception:
            _until_min = None

        _acc_today = 0
        try:
            _acc_today = int(getattr(stats, "shadow_accept", 0) or 0)
        except Exception:
            _acc_today = 0

        # If alpha admission wants to hard-block due to negative_expectancy,
        # shadow should switch to "soft mode" (allow but tiny risk + slower).
        if (not bool(getattr(dec, "allow", True))) and str(getattr(dec, "reason", "")).strip() == "negative_expectancy":
            _forbid_hard_off = False
            if _acc_today < _min_acc:
                _forbid_hard_off = True
            if (_until_min is not None) and (_now_min < _until_min):
                _forbid_hard_off = True

            if _forbid_hard_off:
                # 1) allow with small cap_ratio (reduces shadow risk)
                try:
                    dec = type(dec)(allow=True, cap_ratio=float(_soft_cap), reason="negative_expectancy_soft")
                except Exception:
                    dec = type(dec)(True, float(_soft_cap), "negative_expectancy_soft")

                # 2) optional: slow down via gate cooldown if possible
                try:
                    if "gate" in locals() and hasattr(gate, "cooldown_sec"):
                        gate.cooldown_sec = max(int(getattr(gate, "cooldown_sec", 0) or 0), int(_soft_cd))
                except Exception:
                    pass
except Exception:
    pass
'@

Replace-MarkedBlock -Path $orch -BeginMarker $orchBegin -EndMarker $orchEnd -NewInnerText $orchInner.TrimEnd()

Write-Host "OK: patch applied safely."
Write-Host "Backup dir => $backup"

Write-Host "`nVERIFY (canon env vars):"
Select-String -Path $canon -Pattern "TBOT_SHADOW_SOFT_NEGEXP" | Select-Object -First 50 | ForEach-Object { $_.Line }

Write-Host "`nVERIFY (orchestrator soft override):"
Select-String -Path $orch -Pattern "negative_expectancy_soft|TBOT_SHADOW_SOFT_NEGEXP" | Select-Object -First 80 | ForEach-Object { $_.Line }

Write-Host "`nROLLBACK:"
Write-Host "Copy back these two files from backup dir:"
Write-Host "  $backup\orchestrator.py.bak  -> $orch"
Write-Host "  $backup\RUN_LIVE_SHADOW_CANON_V2.ps1.bak -> $canon"