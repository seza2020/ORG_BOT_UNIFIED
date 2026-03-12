$ErrorActionPreference = "Stop"

# --- Config ---
$ORG = "C:\alpaca-bot\org_bot"
$LOGDIR = Join-Path $ORG "logs"
$PY = "C:\Python313\python.exe"

# --- Ensure paths ---
if (!(Test-Path $ORG)) { throw "ORG path not found: $ORG" }
if (!(Test-Path $LOGDIR)) { New-Item -ItemType Directory -Path $LOGDIR | Out-Null }
if (!(Test-Path $PY)) { throw "Python not found: $PY" }

# --- Move to project root (fixes 'tbot' import in most cases) ---
Set-Location $ORG

# --- Hard fallback: ensure module import works from anywhere ---
$env:PYTHONPATH = $ORG

# --- SPY-only diagnostic run ---
$env:TBOT_SYMBOLS = "SPY"

$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$ann_spy  = Join-Path $LOGDIR ("ann_shadow_spy_only_{0}.log" -f $ts)
$meta_spy = Join-Path $LOGDIR ("meta_shadow_spy_only_{0}.jsonl" -f $ts)

Write-Host "`n[RUN] SPY-only shadow run"
Write-Host ("ORG={0}" -f $ORG)
Write-Host ("ANN={0}" -f $ann_spy)
Write-Host ("META={0}" -f $meta_spy)

# --- Quick import sanity check ---
Write-Host "`n[CHK] python import tbot"
& $PY -c "import sys; import tbot; print('OK: tbot import | sys.path[0]=', sys.path[0])"

# --- Run ---
Write-Host "`n[RUN] python -m tbot.main ..."
& $PY -u -m tbot.main --run --iters 30 --sleep 15 --shadow --announce $ann_spy --meta $meta_spy

if (!(Test-Path $meta_spy)) { throw "META not created: $meta_spy" }

# --- Diagnostics on meta ---
Write-Host "`n[CHK] core_context no_data rate"
$all = 0
$nod = 0

Get-Content -LiteralPath $meta_spy |
  ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
  Where-Object { $_ -and $_.kind -eq "core_context" } |
  ForEach-Object {
    $all++
    $r = ($_.payload.reason -as [string])
    if ($r -like "no_data*") { $nod++ }
  } | Out-Null

$nodPct = [math]::Round(100.0 * $nod / [math]::Max(1,$all), 2)
Write-Host ("CORE_CONTEXT_TOTAL={0}  NO_DATA={1}  NO_DATA_PCT={2}%" -f $all,$nod,$nodPct)

Write-Host "`n[CHK] reason histogram (top 20)"
$hist = Get-Content -LiteralPath $meta_spy |
  ForEach-Object { try { ($_ | ConvertFrom-Json).payload.reason } catch { "__BADJSON__" } } |
  Where-Object { $_ } |
  Group-Object |
  Sort-Object Count -Descending |
  Select-Object -First 20 Name,Count

$hist | Format-Table -AutoSize

Write-Host "`n[CHK] longest consecutive no_data streak"
$streak=0; $max=0
Get-Content -LiteralPath $meta_spy |
  ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
  Where-Object { $_ -and $_.kind -eq "core_context" } |
  ForEach-Object {
    $isNo = (($_.payload.reason -as [string]) -like "no_data*")
    if($isNo){ $streak++ } else { if($streak -gt $max){ $max=$streak }; $streak=0 }
  } | Out-Null
if($streak -gt $max){ $max=$streak }
Write-Host ("MAX_NO_DATA_STREAK={0}" -f $max)

Write-Host "`n[CHK] sample core_context rows (first 12)"
Get-Content -LiteralPath $meta_spy |
  ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
  Where-Object { $_ -and $_.kind -eq "core_context" } |
  Select-Object -First 12 |
  ForEach-Object {
    $ts2 = $_.ts
    $rid = $_.run_id
    $bias = $_.payload.bias
    $vw = $_.payload.vwap_state
    $es = $_.payload.ema_sep
    $tr = $_.payload.trend_strength
    $rs = $_.payload.reason
    "{0} | {1} | bias={2} vwap={3} ema_sep={4} ts={5} reason={6}" -f $ts2,$rid,$bias,$vw,$es,$tr,$rs
  }

# --- Save a compact report text file for easy sharing ---
$report = Join-Path $LOGDIR ("report_spy_diag_{0}.txt" -f $ts)
@(
  "[FILES]"
  ("ANN={0}" -f $ann_spy)
  ("META={0}" -f $meta_spy)
  ""
  "[SUMMARY]"
  ("CORE_CONTEXT_TOTAL={0}" -f $all)
  ("NO_DATA={0}" -f $nod)
  ("NO_DATA_PCT={0}%" -f $nodPct)
  ("MAX_NO_DATA_STREAK={0}" -f $max)
  ""
  "[HIST_TOP20]"
  ($hist | Out-String)
) | Set-Content -LiteralPath $report -Encoding UTF8

Write-Host "`n[DONE]"
Write-Host ("REPORT={0}" -f $report)
Write-Host ("Send me: REPORT + META jsonl (and ANN if possible)")
