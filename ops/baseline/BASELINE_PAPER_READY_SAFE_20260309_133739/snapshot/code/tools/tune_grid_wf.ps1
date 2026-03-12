# File: tools/tune_grid_wf.ps1
param(
  [int]$Iters = 240,
  [double]$Sleep = 0.01,
  [string]$Symbols = "SPY,QQQ,IWM,NVDA,AAPL"
)

$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outCsv = Join-Path (Resolve-Path ".\logs").Path ("wf_grid_raw_" + $ts + ".csv")
$outAgg = Join-Path (Resolve-Path ".\logs").Path ("wf_grid_rank_" + $ts + ".csv")

# Grid knobs
$barsList = @(5,10,15,20,25,30)
$confList = @(0.0,0.2,0.4,0.6,0.8)
$riskList = @(100.0,150.0,200.0,250.0,300.0,350.0,400.0)

# v2 ranking knobs
$p_win = 0.45
$A_min = 3
$A_max = 12
$over_w = 1.0
$under_w = 0.5

$replays = @(
  ".\replay\replay_suite_01_trend.csv",
  ".\replay\replay_suite_02_chop.csv",
  ".\replay\replay_suite_03_spike.csv"
)

# Header raw
"suite,iters,sleep,symbols,min_bars,gate_min_conf,risk_usd,fires,accepts,avg_rr,risk_sum,E_R_proxy,E_usd_proxy,score_v2,run_dir" | Set-Content -LiteralPath $outCsv -Encoding UTF8

function ParseS01($lines) {
  $s01 = $lines | Where-Object { # File: tools/tune_grid_wf.ps1
param(
  [int]$Iters = 240,
  [double]$Sleep = 0.01,
  [string]$Symbols = "SPY,QQQ,IWM,NVDA,AAPL"
)

$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outCsv = Join-Path (Resolve-Path ".\logs").Path ("wf_grid_raw_" + $ts + ".csv")
$outAgg = Join-Path (Resolve-Path ".\logs").Path ("wf_grid_rank_" + $ts + ".csv")

# Grid knobs
$barsList = @(5,10,15,20,25,30)
$confList = @(0.0,0.2,0.4,0.6,0.8)
$riskList = @(100.0,150.0,200.0,250.0,300.0,350.0,400.0)

# v2 ranking knobs
$p_win = 0.45
$A_min = 3
$A_max = 12
$over_w = 1.0
$under_w = 0.5

$replays = @(
  ".\replay\replay_suite_01_trend.csv",
  ".\replay\replay_suite_02_chop.csv",
  ".\replay\replay_suite_03_spike.csv"
)

# Header raw
"suite,iters,sleep,symbols,min_bars,gate_min_conf,risk_usd,fires,accepts,avg_rr,risk_sum,E_R_proxy,E_usd_proxy,score_v2,run_dir" | Set-Content -LiteralPath $outCsv -Encoding UTF8

function ParseS01($lines) {
  $s01 = $lines | Where-Object { $_ -match "^\s*S01\s*\|" } | Select-Object -First 1
  if (-not $s01) { return @{fires=0; accepts=0; avg_rr=0.0; risk_sum=0.0; avg_conf=0.0} }

  $p = $s01 -split "\|"
  return @{
    fires = [int]($p[2].Trim())
    accepts = [int]($p[4].Trim())
    avg_conf = 0.0
    avg_rr = [double]($p[9].Trim())
    risk_sum = [double]($p[10].Trim())
  }
}

function ScoreV2($accepts, $avg_rr, $risk_sum, $risk_usd) {
  $A = [double]$accepts
  $RR = [double]$avg_rr
  $riskSum = [double]$risk_sum
  $riskUsd = [double]$risk_usd

  $E_R = ($p_win * $RR) - ((1.0 - $p_win) * 1.0)
  $E_usd = $A * $riskUsd * $E_R

  $risk_pen = $riskSum / 1000.0
  $over_pen = [math]::Max(0.0, ($A - $A_max)) * $over_w
  $under_pen = [math]::Max(0.0, ($A_min - $A)) * $under_w

  $score = ($E_usd / 100.0) - $risk_pen - $over_pen - $under_pen

  return @{
    E_R = [math]::Round($E_R, 4)
    E_usd = [math]::Round($E_usd, 2)
    score = [math]::Round($score, 4)
  }
}

Write-Host "RAW_CSV=$outCsv"
Write-Host "RANK_CSV=$outAgg"
Write-Host "WF_GRID iters=$Iters sleep=$Sleep symbols=$Symbols"

foreach ($replay in $replays) {

  Write-Host "SUITE=$replay"

  foreach ($minBars in $barsList) {
    foreach ($gateMinConf in $confList) {
      foreach ($riskUsd in $riskList) {

        $env:TBOT_MARKET_MODE="replay"
        $env:TBOT_REPLAY_CSV=$replay
        $env:TBOT_ENABLE_S01_LOGIC="1"
        $env:TBOT_S01_MIN_BARS_BETWEEN_FIRES=("$minBars")

        $runOut = & powershell -ExecutionPolicy Bypass -File .\tools\shadow_run.ps1 `
          -Iters $Iters -Sleep $Sleep -Symbols $Symbols `
          -RiskUsd $riskUsd -GateMinConf $gateMinConf

        if ($LASTEXITCODE -ne 0) {
          Write-Host "RUN_FAIL suite=$replay minBars=$minBars conf=$gateMinConf risk=$riskUsd"
          continue
        }

        $metaLine = ($runOut | Select-String -Pattern "^META=" | Select-Object -First 1)
        $runDirLine = ($runOut | Select-String -Pattern "^OUTDIR=" | Select-Object -First 1)
        if (-not $metaLine -or -not $runDirLine) { continue }
        $metaPath = ($metaLine.ToString().Split("=",2)[1]).Trim()
        $runDir = ($runDirLine.ToString().Split("=",2)[1]).Trim()

                $j = & python .\tools\extract_s01_from_meta.py --meta $metaPath --sid "S01"
        if ($LASTEXITCODE -ne 0) { continue }
        $o = $j | ConvertFrom-Json
        $s01 = @{
          fires = [int]$o.fires_real
          accepts = [int]$o.accepts
          avg_rr = [double]$o.avg_rr
          risk_sum = [double]$o.risk_sum
        }
        $v2 = ScoreV2 $s01.accepts $s01.avg_rr $s01.risk_sum $riskUsd

                $vals = @(
          $replay.Replace(",",";"),
          $Iters,
          $Sleep,
          $Symbols.Replace(",",";"),
          $minBars,
          $gateMinConf,
          $riskUsd,
          $s01.fires,
          $s01.accepts,
          $s01.avg_rr,
          $s01.risk_sum,
          $v2.E_R,
          $v2.E_usd,
          $v2.score,
          $runDir.Replace(",",";")
        )
        $row = ($vals -join ",")
        Add-Content -LiteralPath $outCsv -Value $row -Encoding UTF8

        Write-Host ("DONE suite={0} bars={1} conf={2} risk={3} acc={4} score={5}" -f `
          (Split-Path $replay -Leaf), $minBars, $gateMinConf, $riskUsd, $s01.accepts, $v2.score)
      }
    }
  }
}

# Aggregate stability across suites
$raw = Import-Csv $outCsv

# group key
$groups = $raw | Group-Object -Property min_bars,gate_min_conf,risk_usd

"min_bars,gate_min_conf,risk_usd,mean_score,std_score,worst_score,mean_accepts,notes" | Set-Content -LiteralPath $outAgg -Encoding UTF8

foreach ($g in $groups) {
  $items = $g.Group
  $scores = $items | ForEach-Object { [double]$_.score_v2 }
  $accepts = $items | ForEach-Object { [double]$_.accepts }

  $mean = ($scores | Measure-Object -Average).Average
  $min = ($scores | Measure-Object -Minimum).Minimum
  $avgA = ($accepts | Measure-Object -Average).Average

  # std (manual)
  $var = 0.0
  foreach ($s in $scores) { $var += ($s - $mean) * ($s - $mean) }
  $std = [math]::Sqrt($var / [math]::Max(1, $scores.Count))

  $note = ""
  if ($min -lt 0) { $note = "unstable_worst_lt0" }

  $line = "{0},{1},{2},{3},{4},{5},{6},{7}" -f `
    $items[0].min_bars, $items[0].gate_min_conf, $items[0].risk_usd, `
    ([math]::Round($mean,4)), ([math]::Round($std,4)), ([math]::Round($min,4)), ([math]::Round($avgA,2)), $note

  Add-Content -LiteralPath $outAgg -Value $line -Encoding UTF8
}

# Rank: highest mean_score, then lowest std, then highest worst_score
$ranked = Import-Csv $outAgg | Sort-Object `
  @{Expression={[double]$_.mean_score}; Descending=$true}, `
  @{Expression={[double]$_.std_score}; Descending=$false}, `
  @{Expression={[double]$_.worst_score}; Descending=$true}

$ranked | Select-Object -First 20 | Format-Table

Write-Host "DONE_WF RAW_CSV=$outCsv"
Write-Host "DONE_WF RANK_CSV=$outAgg"

# Clean env
Remove-Item Env:\TBOT_MARKET_MODE -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_REPLAY_CSV -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_ENABLE_S01_LOGIC -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_S01_MIN_BARS_BETWEEN_FIRES -ErrorAction SilentlyContinue

 -match "^\s*S01\s*\|" } | Select-Object -First 1
  if (-not $s01) { return @{fires=0; accepts=0; avg_rr=0.0; risk_sum=0.0} }

  $p = $s01 -split "\|"

  function _toInt($x) {
    try { return [int]($x.Trim()) } catch { return 0 }
  }
  function _toDbl($x) {
    $t = $x.Trim()
    if ($t -eq "-" -or $t -eq "") { return 0.0 }
    try { return [double]$t } catch { return 0.0 }
  }

  return @{
    fires = _toInt $p[2]
    accepts = _toInt $p[4]
    avg_rr = _toDbl $p[9]
    risk_sum = _toDbl $p[10]
  }
}

function ScoreV2($accepts, $avg_rr, $risk_sum, $risk_usd) {
  $A = [double]$accepts
  $RR = [double]$avg_rr
  $riskSum = [double]$risk_sum
  $riskUsd = [double]$risk_usd

  $E_R = ($p_win * $RR) - ((1.0 - $p_win) * 1.0)
  $E_usd = $A * $riskUsd * $E_R

  $risk_pen = $riskSum / 1000.0
  $over_pen = [math]::Max(0.0, ($A - $A_max)) * $over_w
  $under_pen = [math]::Max(0.0, ($A_min - $A)) * $under_w

  $score = ($E_usd / 100.0) - $risk_pen - $over_pen - $under_pen

  return @{
    E_R = [math]::Round($E_R, 4)
    E_usd = [math]::Round($E_usd, 2)
    score = [math]::Round($score, 4)
  }
}

Write-Host "RAW_CSV=$outCsv"
Write-Host "RANK_CSV=$outAgg"
Write-Host "WF_GRID iters=$Iters sleep=$Sleep symbols=$Symbols"

foreach ($replay in $replays) {

  Write-Host "SUITE=$replay"

  foreach ($minBars in $barsList) {
    foreach ($gateMinConf in $confList) {
      foreach ($riskUsd in $riskList) {

        $env:TBOT_MARKET_MODE="replay"
        $env:TBOT_REPLAY_CSV=$replay
        $env:TBOT_ENABLE_S01_LOGIC="1"
        $env:TBOT_S01_MIN_BARS_BETWEEN_FIRES=("$minBars")

        $runOut = & powershell -ExecutionPolicy Bypass -File .\tools\shadow_run.ps1 `
          -Iters $Iters -Sleep $Sleep -Symbols $Symbols `
          -RiskUsd $riskUsd -GateMinConf $gateMinConf

        if ($LASTEXITCODE -ne 0) {
          Write-Host "RUN_FAIL suite=$replay minBars=$minBars conf=$gateMinConf risk=$riskUsd"
          continue
        }

        $metaLine = ($runOut | Select-String -Pattern "^META=" | Select-Object -First 1)
        $runDirLine = ($runOut | Select-String -Pattern "^OUTDIR=" | Select-Object -First 1)
        if (-not $metaLine -or -not $runDirLine) { continue }
        $metaPath = ($metaLine.ToString().Split("=",2)[1]).Trim()
        $runDir = ($runDirLine.ToString().Split("=",2)[1]).Trim()

                $j = & python .\tools\extract_s01_from_meta.py --meta $metaPath --sid "S01"
        if ($LASTEXITCODE -ne 0) { continue }
        $o = $j | ConvertFrom-Json
        $s01 = @{
          fires = [int]$o.fires_real
          accepts = [int]$o.accepts
          avg_rr = [double]$o.avg_rr
          risk_sum = [double]$o.risk_sum
        }
        $v2 = ScoreV2 $s01.accepts $s01.avg_rr $s01.risk_sum $riskUsd

                $vals = @(
          $replay.Replace(",",";"),
          $Iters,
          $Sleep,
          $Symbols.Replace(",",";"),
          $minBars,
          $gateMinConf,
          $riskUsd,
          $s01.fires,
          $s01.accepts,
          $s01.avg_rr,
          $s01.risk_sum,
          $v2.E_R,
          $v2.E_usd,
          $v2.score,
          $runDir.Replace(",",";")
        )
        $row = ($vals -join ",")
        Add-Content -LiteralPath $outCsv -Value $row -Encoding UTF8

        Write-Host ("DONE suite={0} bars={1} conf={2} risk={3} acc={4} score={5}" -f `
          (Split-Path $replay -Leaf), $minBars, $gateMinConf, $riskUsd, $s01.accepts, $v2.score)
      }
    }
  }
}

# Aggregate stability across suites
$raw = Import-Csv $outCsv

# group key
$groups = $raw | Group-Object -Property min_bars,gate_min_conf,risk_usd

"min_bars,gate_min_conf,risk_usd,mean_score,std_score,worst_score,mean_accepts,notes" | Set-Content -LiteralPath $outAgg -Encoding UTF8

foreach ($g in $groups) {
  $items = $g.Group
  $scores = $items | ForEach-Object { [double]$_.score_v2 }
  $accepts = $items | ForEach-Object { [double]$_.accepts }

  $mean = ($scores | Measure-Object -Average).Average
  $min = ($scores | Measure-Object -Minimum).Minimum
  $avgA = ($accepts | Measure-Object -Average).Average

  # std (manual)
  $var = 0.0
  foreach ($s in $scores) { $var += ($s - $mean) * ($s - $mean) }
  $std = [math]::Sqrt($var / [math]::Max(1, $scores.Count))

  $note = ""
  if ($min -lt 0) { $note = "unstable_worst_lt0" }

  $line = "{0},{1},{2},{3},{4},{5},{6},{7}" -f `
    $items[0].min_bars, $items[0].gate_min_conf, $items[0].risk_usd, `
    ([math]::Round($mean,4)), ([math]::Round($std,4)), ([math]::Round($min,4)), ([math]::Round($avgA,2)), $note

  Add-Content -LiteralPath $outAgg -Value $line -Encoding UTF8
}

# Rank: highest mean_score, then lowest std, then highest worst_score
$ranked = Import-Csv $outAgg | Sort-Object `
  @{Expression={[double]$_.mean_score}; Descending=$true}, `
  @{Expression={[double]$_.std_score}; Descending=$false}, `
  @{Expression={[double]$_.worst_score}; Descending=$true}

$ranked | Select-Object -First 20 | Format-Table

Write-Host "DONE_WF RAW_CSV=$outCsv"
Write-Host "DONE_WF RANK_CSV=$outAgg"

# Clean env
Remove-Item Env:\TBOT_MARKET_MODE -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_REPLAY_CSV -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_ENABLE_S01_LOGIC -ErrorAction SilentlyContinue
Remove-Item Env:\TBOT_S01_MIN_BARS_BETWEEN_FIRES -ErrorAction SilentlyContinue



