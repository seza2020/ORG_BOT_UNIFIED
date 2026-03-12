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
  if($defs.Count -lt 1){ throw "No top-level defs found" }

  $startMatch = [regex]::Match($Text, "(?m)^def\s+$FuncName\s*\(")
  if(!$startMatch.Success){ throw "Patch failed: cannot find def $FuncName(" }

  $start = $startMatch.Index
  $next = $null
  foreach($d in $defs){
    if($d.Index -gt $start){
      if($null -eq $next -or $d.Index -lt $next.Index){ $next = $d }
    }
  }
  $end = if($null -ne $next){ $next.Index } else { $Text.Length }

  $prefix = $Text.Substring(0,$start)
  $suffix = $Text.Substring($end)
  $nb = $NewBlock.TrimEnd() + "`r`n`r`n"
  return ($prefix + $nb + $suffix)
}

# Ensure globals exist once (right before def _http_get)
if($src -notmatch "_HTTP_CACHE" -or $src -notmatch "_LAST_HTTP_TS"){
  $m = [regex]::Match($src,'(?m)^def\s+_http_get\s*\(')
  if(!$m.Success){ throw "Patch failed: cannot find def _http_get(" }

  $inject = @"
# TBOT_HTTP_CACHE_THROTTLE (V4)
_HTTP_CACHE = {}     # url -> (ts, body)
_LAST_HTTP_TS = 0.0

"@
  $src = $src.Substring(0,$m.Index) + $inject + $src.Substring($m.Index)
}

$newHttpGet = @"
def _http_get(url: str, headers: Dict[str, str], timeout_sec: float = 10.0) -> str:
    import time, os
    import urllib.request
    import urllib.error
    global _LAST_HTTP_TS, _HTTP_CACHE

    # Throttle: minimum interval between ANY HTTP calls (ms)
    try:
        min_ms = float(os.getenv("TBOT_HTTP_MIN_INTERVAL_MS", "300") or 0.0)
    except Exception:
        min_ms = 300.0

    if min_ms and min_ms > 0:
        now = time.time()
        wait = (min_ms / 1000.0) - (now - float(_LAST_HTTP_TS or 0.0))
        if wait > 0:
            time.sleep(wait)
        _LAST_HTTP_TS = time.time()

    def _fenv(name: str, d: str) -> float:
        try:
            return float(os.getenv(name, d))
        except Exception:
            return float(d)

    # Cache TTLs (seconds)
    ttl_trade = _fenv("TBOT_HTTP_CACHE_TRADE_SEC", "15")
    ttl_bars  = _fenv("TBOT_HTTP_CACHE_BARS_SEC",  "60")

    ttl = 0.0
    if "/trades/latest" in url or "/quotes/latest" in url:
        ttl = ttl_trade
    elif "/bars?" in url:
        ttl = ttl_bars

    # Fresh cache hit
    if ttl and ttl > 0:
        v = _HTTP_CACHE.get(url)
        if v:
            ts, body = v
            if (time.time() - float(ts)) < ttl:
                return body

    # Retry/backoff on 429/5xx, fallback to cached body if exists
    try:
        retries = int(os.getenv("TBOT_HTTP_RETRIES", "4"))
    except Exception:
        retries = 4
    base = _fenv("TBOT_HTTP_RETRY_BASE_SEC", "1.0")

    last_err = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=timeout_sec) as r:
                body = r.read().decode("utf-8", "replace")
            if ttl and ttl > 0:
                _HTTP_CACHE[url] = (time.time(), body)
            return body

        except urllib.error.HTTPError as e:
            last_err = e
            code = getattr(e, "code", None)

            # If we have any cached body (even stale), prefer returning it over triggering fallback pricing
            v = _HTTP_CACHE.get(url)
            if v and code in (429,) or (isinstance(code, int) and code >= 500):
                return v[1]

            if code == 429 or (isinstance(code, int) and code >= 500):
                ra = None
                try:
                    ra = e.headers.get("Retry-After")
                except Exception:
                    ra = None
                try:
                    sleep_s = float(ra) if ra else (base * (2 ** attempt))
                except Exception:
                    sleep_s = base * (2 ** attempt)
                time.sleep(min(30.0, sleep_s))
                continue
            raise

        except Exception as e:
            last_err = e
            v = _HTTP_CACHE.get(url)
            if v:
                return v[1]
            time.sleep(min(10.0, base * (2 ** attempt)))
            continue

    raise last_err
"@

$src2 = Replace-TopLevelFunc -Text $src -FuncName "_http_get" -NewBlock $newHttpGet
Set-Content -Path $mp -Value $src2 -Encoding UTF8

Write-Host ("PATCH_OK V4 applied (retry+cache-on-429). Backup=" + $bak) -ForegroundColor Green
