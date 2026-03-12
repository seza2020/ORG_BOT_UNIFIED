param()

$ErrorActionPreference="Stop"
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$mp   = Join-Path $ROOT "tbot\market\market_provider.py"
if(!(Test-Path $mp)){ throw "market_provider.py not found: $mp" }

# Backup
$bakDir = Join-Path $ROOT "_quarantine\patches"
New-Item -ItemType Directory -Force $bakDir | Out-Null
$bak = Join-Path $bakDir ("market_provider_{0}.py" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Copy-Item $mp $bak -Force

$src = Get-Content $mp -Raw

function Replace-TopLevelFunc {
  param([string]$Text,[string]$FuncName,[string]$NewBlock)

  $defs = [regex]::Matches($Text,'(?m)^def\s+\w+\s*\(')
  if($defs.Count -lt 1){ throw "No top-level defs found (unexpected)" }

  $startMatch = [regex]::Match($Text, "(?m)^def\s+$FuncName\s*\(")
  if(!$startMatch.Success){ throw "Patch failed: cannot find def $FuncName(" }

  $start = $startMatch.Index

  # find next top-level def after this one
  $next = $null
  foreach($d in $defs){
    if($d.Index -gt $start){
      if($null -eq $next -or $d.Index -lt $next.Index){ $next = $d }
    }
  }
  $end = if($null -ne $next){ $next.Index } else { $Text.Length }

  $prefix = $Text.Substring(0,$start)
  $suffix = $Text.Substring($end)

  # Ensure newline separation
  $nb = $NewBlock.TrimEnd() + "`r`n`r`n"
  return ($prefix + $nb + $suffix)
}

$newJsonRetry = @"
def _http_json_retry(url: str, headers: dict, tries: int = 5, base_sleep: float = 0.5):
    import urllib.error
    for i in range(tries):
        try:
            return _http_json(url, headers)
        except urllib.error.HTTPError as e:
            code = getattr(e, "code", None)
            # Retry on rate-limit + transient server errors
            if code == 429 or (code is not None and 500 <= code < 600):
                if i < tries - 1:
                    ra = None
                    try:
                        ra = e.headers.get("Retry-After")
                    except Exception:
                        ra = None
                    if ra:
                        try:
                            _sleep(float(ra))
                        except Exception:
                            _sleep(base_sleep * (i + 1) * 2.0)
                    else:
                        _sleep(base_sleep * (i + 1) * 2.0)
                    continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise
"@

$newGetRetry = @"
def _http_get_retry(url: str, headers: dict, timeout_sec: float = 10.0, tries: int = 5, base_sleep: float = 0.5) -> str:
    import urllib.error
    for i in range(tries):
        try:
            return _http_get(url, headers=headers, timeout_sec=timeout_sec)
        except urllib.error.HTTPError as e:
            code = getattr(e, "code", None)
            if code == 429 or (code is not None and 500 <= code < 600):
                if i < tries - 1:
                    ra = None
                    try:
                        ra = e.headers.get("Retry-After")
                    except Exception:
                        ra = None
                    if ra:
                        try:
                            _sleep(float(ra))
                        except Exception:
                            _sleep(base_sleep * (i + 1) * 2.0)
                    else:
                        _sleep(base_sleep * (i + 1) * 2.0)
                    continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise
"@

$src2 = Replace-TopLevelFunc -Text $src  -FuncName "_http_json_retry" -NewBlock $newJsonRetry
$src3 = Replace-TopLevelFunc -Text $src2 -FuncName "_http_get_retry"  -NewBlock $newGetRetry

# Insert: last fallback BEFORE MarketSnap creation (prevents 100/99/102 if bars yielded vwap/ema)
if($src3 -notmatch "TBOT_REALPRICE_FALLBACK"){
  $m = [regex]::Match($src3,'(?m)^(?<i>\s*)out\[sym\]\s*=\s*MarketSnap\s*\(')
  if(!$m.Success){ throw "Patch failed: cannot find 'out[sym] = MarketSnap(' anchor" }
  $indent = $m.Groups['i'].Value
  $inject = @"
${indent}# TBOT_REALPRICE_FALLBACK: avoid fake 100/99/102 when latest trade fails but bars produced values
${indent}if last is None:
${indent}    try:
${indent}        if vwap is not None:
${indent}            last = float(vwap)
${indent}        elif ef is not None:
${indent}            last = float(ef)
${indent}        elif es is not None:
${indent}            last = float(es)
${indent}    except Exception:
${indent}        pass

"@
  $src3 = $src3.Substring(0,$m.Index) + $inject + $src3.Substring($m.Index)
}

Set-Content -Path $mp -Value $src3 -Encoding UTF8
Write-Host ("PATCH_OK V2 applied. Backup=" + $bak) -ForegroundColor Green
