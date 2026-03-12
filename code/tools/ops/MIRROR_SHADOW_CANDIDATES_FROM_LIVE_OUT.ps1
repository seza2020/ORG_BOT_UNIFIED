param([string]$Root="C:\alpaca-bot\org_bot")

$Logs = Join-Path $Root "logs"
$Ops  = Join-Path $Logs "ops"
$cand = Join-Path $Logs "shadow_candidates.jsonl"
$state = Join-Path $Ops  "shadow_candidates_mirror.state"

if (-not (Test-Path $cand)) { New-Item -ItemType File -Force $cand | Out-Null }

$live = Get-ChildItem (Join-Path $Ops "LIVE_OUT_*.txt") | Sort-Object LastWriteTime -Desc | Select-Object -First 1
if (-not $live) { return }

$last = 0
if (Test-Path $state) { $last = [int](Get-Content $state -Raw) }

$lines = Get-Content $live.FullName
$n = $lines.Count
if ($n -le $last) { return }

$emit = New-Object System.Collections.Generic.List[string]
for ($i=$last; $i -lt $n; $i++) {
  $ln = $lines[$i]
  if ($ln -match "\|\s+shadow_(accept|reject)\s+") {
    $kind = $Matches[1]
    $ts = (Get-Date).ToString("o")
    if ($ln -match "\|\s+([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:\.]+)\s+\|") { $ts = $Matches[1] }

    $emit.Add( ('{"ts":"'+$ts+'","kind":"shadow_'+$kind+'","src":"'+$live.Name+'","line":'+(ConvertTo-Json $ln -Compress)+'}') )
  }
}

if ($emit.Count -gt 0) { $emit | Add-Content -Encoding UTF8 $cand }
Set-Content -Encoding ASCII $state $n
