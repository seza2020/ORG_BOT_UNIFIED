$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$out = Join-Path $ROOT "ROOT_DRIFT_SCAN.txt"

$oldRoots=@(
  "C:\alpaca-bot\org_bot",
  "C:\alpaca-bot\org_bot_runtime"
)

$files = Get-ChildItem -LiteralPath $ROOT -Recurse -File -ErrorAction SilentlyContinue

$hits = New-Object System.Collections.Generic.List[object]

foreach($r in $oldRoots){
  $pat = [regex]::Escape($r)
  foreach($f in $files){
    $m = Select-String -LiteralPath $f.FullName -Pattern $pat -ErrorAction SilentlyContinue
    if($m){
      foreach($one in $m){
        $hits.Add([pscustomobject]@{
          OldRoot    = $r
          Path       = $one.Path
          LineNumber = $one.LineNumber
          Line       = $one.Line.Trim()
        })
      }
    }
  }
}

if($hits.Count -eq 0){
  "NO_DRIFT_FOUND" | Set-Content -LiteralPath $out -Encoding UTF8
} else {
  $hits |
    Sort-Object OldRoot,Path,LineNumber |
    Format-Table -AutoSize |
    Out-String |
    Set-Content -LiteralPath $out -Encoding UTF8
}

Write-Host $out
