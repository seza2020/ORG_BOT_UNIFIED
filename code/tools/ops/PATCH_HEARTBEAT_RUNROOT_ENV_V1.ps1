param(
  [string]$Root="C:\alpaca-bot\org_bot"
)
$ErrorActionPreference="Stop"
$orch = Join-Path $Root "tbot\runtime\orchestrator.py"
if(!(Test-Path -LiteralPath $orch)){ throw "ORCH_NOT_FOUND=$orch" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$bkpDir = Join-Path $Root ("logs\ops\patches\HB_ENV_PATCH_" + $stamp)
New-Item -ItemType Directory -Force -Path $bkpDir | Out-Null
Copy-Item -Force -LiteralPath $orch -Destination (Join-Path $bkpDir "orchestrator.py")

$txt = Get-Content -LiteralPath $orch -Raw

# 1) Inject env-first runroot
$needle = @"
            runroot = None
            try:
                mp = getattr(self, "meta_path", None) or getattr(self, "meta", None)
"@

if($txt -notmatch [regex]::Escape($needle)){
  throw "ANCHOR_NOT_FOUND (HEARTBEAT_FILE_V1 runroot block)."
}

$inject = @"
            runroot = None
            try:
                # ENV-first runroot (stable + auditable)
                _rr = (os.getenv("TBOT_RUNROOT") or os.getenv("TBOT_RUNTIME") or "").strip()
                if _rr:
                    runroot = _P(_rr).resolve()
                else:
                    mp = getattr(self, "meta_path", None) or getattr(self, "meta", None)
"@

$txt = $txt -replace [regex]::Escape($needle), $inject

# 2) Add heartbeat_err.txt logging instead of silent pass
# Replace the outer-most except Exception: pass for HEARTBEAT_FILE_V1 block.
# We'll do a conservative replace: the last "except Exception:\n            pass" right after the heartbeat try.
$pattern = [regex]'(?s)# HEARTBEAT_FILE_V1.*?except Exception:\s*\n\s*pass\s*\n'
$m = $pattern.Match($txt)
if(-not $m.Success){ throw "HB_BLOCK_NOT_FOUND" }

$block = $m.Value
if($block -match "heartbeat_err\.txt"){
  "PATCH_ALREADY_HAS_HB_ERR"
} else {
  $block2 = $block -replace 'except Exception:\s*\n\s*pass\s*\n\Z', @"
except Exception as _e:
            try:
                # Best-effort: persist error for ops
                _rr = (os.getenv("TBOT_RUNROOT") or os.getenv("TBOT_RUNTIME") or "").strip()
                if _rr:
                    _sd = _P(_rr) / "state"
                    _sd.mkdir(parents=True, exist_ok=True)
                    (_sd / "heartbeat_err.txt").write_text(repr(_e), encoding="utf-8")
            except Exception:
                pass
"@
  $txt = $txt.Substring(0, $m.Index) + $block2 + $txt.Substring($m.Index + $m.Length)
}

Set-Content -Encoding UTF8 -LiteralPath $orch -Value $txt
"OK: PATCHED orchestrator.py"
"BKP_DIR=$bkpDir"
