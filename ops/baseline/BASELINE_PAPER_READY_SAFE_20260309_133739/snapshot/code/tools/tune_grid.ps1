# File: tools/tune_grid.ps1
param(
  [int]$Iters = 240,
  [double]$Sleep = 0.01,
  [string]$Symbols = "SPY,QQQ"
)

$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outCsv = Join-Path (Resolve-Path ".\logs").Path ("grid_results_" + $ts + ".csv")

# Grid values
$barsList = @(5,10,15,20)
$confList = @(0.0,0.2,0.4)
$riskList = @(150.0,250.0,350.0)

# Ensure replay sample exists
python .\tools\make_replay_sample.py | Out-Null

# Write CSV header
"ts,run_dir,iters,sleep,symbols,min_bars,gate_min_conf,risk_usd,fires,accepts,avg_rr,risk_sum" | Set-Content -LiteralPath $outCsv -Encoding UTF8

function Parse-ScorecardLine {
  param([string]$text)

  # Example line:
  # S01 |     0 |     6 |    0 |    6 |       0 |     0 |        - |    0.600 | 2.000 | 1500.00
  if ($text -notmatch "^\s*S01\s*\|") { return $null }

  $parts = $text -split "\|"
  if ($parts.Count -lt 11) { return $null }

  $fireR = ($parts[2]).Trim()
  $accR  = ($parts[4]).Trim()
  $avgRR = ($parts[9]).Trim()
  $riskSum = ($parts[10]).Trim()

  return @{
    fires = [int]$fireR
    accepts = [int]$accR
    avg_rr = [double]$avgRR
    risk_sum = [double]$riskSum
  }
}

Write-Host "OUTCSV=$outCsv"
Write-Host "GRID iters=$Iters sleep=$Sleep symbols=$Symbols"

foreach ($minBars in $barsList) {
  foreach ($gateMinConf in $confList) {
    foreach ($riskUsd in $riskList) {

      # Env for replay + core logic + cooldown
      $env:TBOT_MARKET_MODE="replay"
      $env:TBOT_REPLAY_CSV=".\replay\replay.csv"
      $env:TBOT_ENABLE_S01_LOGIC="1"
      $env:TBOT_S01_MIN_BARS_BETWEEN_FIRES=("$minBars")

      # Run shadow
      $runOut = & powershell -ExecutionPolicy Bypass -File .\tools\shadow_run.ps1 `
        -Iters $Iters -Sleep $Sleep -Symbols $Symbols `
        -RiskUsd $riskUsd -GateMinConf $gateMinConf

      $rc = $LASTEXITCODE
      if ($rc -ne 0) {
        Write-Host "RUN_FAIL minBars=$minBars gateMinConf=$gateMinConf riskUsd=$riskUsd rc=$rc"
        continue
      }

      # Extract OUTDIR from shadow_run output
      $outdirLine = ($runOut | Select-String -Pattern "^OUTDIR=" | Select-Object -First 1)
      if (-not $outdirLine) { continue }
      $runDir = ($outdirLine.ToString().Split("=",2)[1]).Trim()

      # Extract meta path from output
      $metaLine = ($runOut | Select-String -Pattern "^META=" | Select-Object -First 1)
      if (-not $metaLine) { continue }
      $metaPath = ($metaLine.ToString().Split("=",2)[1]).Trim()

      # Run scorecard on the meta (capture output)
      $scOut = & python .\tools\scorecard_daily.py --meta $metaPath
      if ($LASTEXITCODE -ne 0) { continue }

      # Find S01 line
      $s01Line = ($scOut | Where-Object { $_ -match "^\s*S01\s*\|" } | Select-Object -First 1)
      $parsed = Parse-ScorecardLine -text $s01Line
      if (-not $parsed) {
        $parsed = @{fires=0; accepts=0; avg_rr=0.0; risk_sum=0.0}
      }

      # Append to CSV
      $row = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}" -f `
        $ts, $runDir.Replace(",",";"), $Iters, $Sleep, $Symbols.Replace(",",";"), `
        $minBars, $gateMinConf, $riskUsd, `
        $parsed.fires, $parsed.accepts, $parsed.avg_rr, $parsed.risk_sum

      Add-Content -LiteralPath $outCsv -Value $row -Encoding UTF8

      Write-Host ("DONE minBars={0} gateMinConf={1} riskUsd={2} fires={3} acc={4}" -f `
        $minBars, $gateMinConf, $riskUsd, $parsed.fires, $parsed.accepts)
    }
  }
}

# Clean env
Remove-Item Env:\TBOT_MARKET_MODE -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_REPLAY_CSV -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_ENABLE_S01_LOGIC -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_S01_MIN_BARS_BETWEEN_FIRES -ErrorAction SilentlyContinue

Write-Host "DONE_GRID OUTCSV=$outCsv"
