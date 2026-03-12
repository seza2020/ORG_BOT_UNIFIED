param()

$ErrorActionPreference="Stop"
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$mp = Join-Path $ROOT "tbot\market\market_provider.py"
if(!(Test-Path $mp)){ throw "market_provider.py not found: $mp" }

# Backup
$bakDir = Join-Path $ROOT "_quarantine\patches"
New-Item -ItemType Directory -Force $bakDir | Out-Null
$bak = Join-Path $bakDir ("market_provider_{0}.py" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Copy-Item $mp $bak -Force

$src = Get-Content $mp -Raw

# Replace _http_json_retry block
$newJsonRetry = @"
def _http_json_retry(url: str, headers: dict, tries: int = 5, base_sleep: float = 0.5):
    import urllib.error
    for i in range(tries):
        try:
            return _http_json(url, headers)
        except urllib.error.HTTPError as e:
            code = getattr(e, "code", None)
            # Retry only on rate-limit + transient server errors
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
        except (urllib.error.URLError, TimeoutError) as e:
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise
"@

$src2 = [regex]::Replace(
  $src,
  '(?ms)^def _http_json_retry\([^\n]*\):.*?(?=^def _http_get_retry\()',
  $newJsonRetry
)
if($src2 -eq $src){ throw "Patch failed: could not replace _http_json_retry" }

# Replace _http_get_retry block
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
        except (urllib.error.URLError, TimeoutError) as e:
            if i < tries - 1:
                _sleep(base_sleep * (i + 1))
                continue
            raise
"@

$src3 = [regex]::Replace(
  $src2,
  '(?ms)^def _http_get_retry\([^\n]*\):.*?(?=^def build_market_snapshot\()',
  $newGetRetry
)
if($src3 -eq $src2){ throw "Patch failed: could not replace _http_get_retry" }

# Insert: if last is None and closes -> use last close (prevents fake when trade.latest fails but bars succeeded)
if($src3 -notmatch 'if last is None and closes:'){
  $m = [regex]::Match($src3, '(?m)^(?<i>\s*)bar_index\s*=\s*.+$')
  if(!$m.Success){ throw "Patch failed: could not find bar_index assignment to inject fallback" }
  $indent = $m.Groups['i'].Value
  $inject = $m.Value + "`n" + $indent + "if last is None and closes:" + "`n" + $indent + "    last = float(closes[-1])"
  $src3 = $src3.Substring(0,$m.Index) + $inject + $src3.Substring($m.Index + $m.Length)
}

Set-Content -Path $mp -Value $src3 -Encoding UTF8
Write-Host ("PATCH_OK market_provider.py patched. Backup=" + $bak) -ForegroundColor Green
