# tools\WEEK2_POLICY_LOCKS_ONECLICK_V2.ps1
# One-click patch + tests for Week2 policy locks (project-only)
# - Boot guard (>=3) => refuse to start (non-auditable)
# - Cooldown guard (min 20; cooldown=0 forbidden unless TBOT_ALLOW_COOLDOWN_0=1)
# - Cap breach guard (meta valid_accepts > orig cap) => hard stop
# - Entry deviation guard (entry vs market.last > pct) => hard stop
# - QA meta summary (strategy + side)
[CmdletBinding()]
param()

$ErrorActionPreference="Stop"
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }

$PY  = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Missing venv python: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_POLICY_LOCKS_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

function Backup([string]$p){
  if(Test-Path $p){
    Copy-Item -Force $p (Join-Path $BAK ([IO.Path]::GetFileName($p) + ".bak"))
  }
}

function Insert-AfterLine([string]$txt, [int]$lineStartIdx, [string]$block){
  $nl = $txt.IndexOf("`n", $lineStartIdx)
  if($nl -lt 0){ return $txt + "`r`n" + $block + "`r`n" }
  $ins = $nl + 1
  return $txt.Insert($ins, $block + "`r`n")
}

# -----------------------------
# (A) gate_state.py policy locks
# -----------------------------
$gatePath = Join-Path $ROOT "tbot\runtime\gate_state.py"
if(-not (Test-Path $gatePath)){ throw "Missing: $gatePath" }
Backup $gatePath

$markerA = "TBOT_POLICY_LOCKS_V1"
$gateTxt = Get-Content -Raw -Encoding UTF8 $gatePath

if($gateTxt -notmatch $markerA){

  # 1) insert boot/cooldown guard right after st = meta_stats(...)
  $m = [regex]::Match($gateTxt, "(?m)^(?<ind>\s*)st\s*=\s*meta_stats\(")
  if(-not $m.Success){ throw "gate_state.py: cannot find 'st = meta_stats(' line" }
  $ind = $m.Groups["ind"].Value
  $ind2 = $ind + "    "

  $block1 = @"
${ind}# --- ${markerA} BEGIN ---
${ind}import os as _os
${ind}_max_boots = int((_os.getenv("TBOT_MAX_BOOTS_PER_DAY","3") or "3").strip())
${ind}if st.boot >= _max_boots and _os.getenv("TBOT_ALLOW_BOOT_OVERRUN","0") != "1":
${ind2}raise SystemExit(f"[BOOT_GUARD] HARD_STOP: boots_today={st.boot} >= max_boots={_max_boots}. Day non-auditable; refusing to start.")

${ind}_min_cd = int((_os.getenv("TBOT_MIN_COOLDOWN_SEC","20") or "20").strip())
${ind}_allow_cd0 = (_os.getenv("TBOT_ALLOW_COOLDOWN_0","0") == "1")
${ind}if hasattr(args, "gate_cooldown_sec"):
${ind2}_cd = int(getattr(args, "gate_cooldown_sec"))
${ind2}if _cd == 0 and not _allow_cd0:
${ind2}    raise SystemExit("[COOLDOWN] HARD_STOP: gate_cooldown_sec=0 is not allowed for tuning (set TBOT_ALLOW_COOLDOWN_0=1 only for research).")
${ind2}if _cd < _min_cd and _os.getenv("TBOT_ALLOW_LOW_COOLDOWN","0") != "1":
${ind2}    raise SystemExit(f"[COOLDOWN] HARD_STOP: gate_cooldown_sec={_cd} < min={_min_cd}.")
${ind}# --- ${markerA} END ---
"@

  $gateTxt = Insert-AfterLine $gateTxt $m.Index ($block1)

  # 2) cap breach guard after orig cap line
  $m2 = [regex]::Match($gateTxt, "(?m)^(?<ind>\s*)orig\s*=\s*int\(\s*getattr\(\s*args\s*,\s*['""]gate_max_plans_per_day['""]\s*\)\s*\)\s*$")
  if(-not $m2.Success){
    throw "gate_state.py: cannot find orig cap line (gate_max_plans_per_day)"
  }
  $indCap = $m2.Groups["ind"].Value
  $block2 = @"
${indCap}if st.valid_accepts > orig:
${indCap}    raise SystemExit(f"[PERSIST_CAP] HARD_STOP: meta valid_accepts={st.valid_accepts} > orig_cap={orig}. Cap integrity broken.")
"@
  $gateTxt = Insert-AfterLine $gateTxt $m2.Index ($block2)

  Set-Content -Encoding UTF8 -Path $gatePath -Value $gateTxt
  Write-Host "OK: patched => $gatePath"
} else {
  Write-Host "SKIP: gate_state.py already has $markerA"
}

# -----------------------------
# (B) orchestrator.py entry deviation guard
# -----------------------------
$orcPath = Join-Path $ROOT "tbot\runtime\orchestrator.py"
if(-not (Test-Path $orcPath)){ throw "Missing: $orcPath" }
Backup $orcPath

$markerB = "TBOT_ENTRY_DEVIATION_GUARD_V1"
$orcTxt = Get-Content -Raw -Encoding UTF8 $orcPath

if($orcTxt -notmatch $markerB){
  $mEnd = [regex]::Match($orcTxt, "(?m)^(?<ind>\s*)# --- TBOT_HARD_BLOCK_FAKE_PRICE_V1 END ---\s*$")
  if(-not $mEnd.Success){
    throw "orchestrator.py: cannot locate '# --- TBOT_HARD_BLOCK_FAKE_PRICE_V1 END ---' marker"
  }
  $ind = $mEnd.Groups["ind"].Value
  $ind2 = $ind + "    "

  $guard = @"
${ind}# --- ${markerB} BEGIN ---
${ind}try:
${ind2}import os as _tbot_os
${ind2}_pct = float(_tbot_os.getenv('TBOT_MAX_ENTRY_DEVIATION_PCT','0.02'))
${ind2}_hard = (_tbot_os.getenv('TBOT_HARD_STOP_ON_ENTRY_DEVIATION','1') == '1')
${ind2}_sym = getattr(plan,'symbol',None)
${ind2}_entry = getattr(plan,'entry',None)
${ind2}_last = None
${ind2}if _sym:
${ind2}    try:
${ind2}        _snap = getattr(market, _sym, None)
${ind2}        _last = getattr(_snap, 'last', None)
${ind2}    except Exception:
${ind2}        _last = None
${ind2}if _last is not None and _entry is not None:
${ind2}    _lf = float(_last); _ef = float(_entry)
${ind2}    if _lf > 0 and abs(_ef - _lf)/_lf > _pct:
${ind2}        try:
${ind2}            ev = make_event(level='ERROR', kind='shadow_reject', payload={
${ind2}                'sid': getattr(plan,'sid',None),
${ind2}                'symbol': _sym,
${ind2}                'side': getattr(plan,'side',None),
${ind2}                'qty': getattr(plan,'qty',None),
${ind2}                'entry': _ef,
${ind2}                'stop': getattr(plan,'stop',None),
${ind2}                'tp': getattr(plan,'tp',None),
${ind2}                'risk_usd': getattr(plan,'risk_usd',None),
${ind2}                'rr': getattr(plan,'rr',None),
${ind2}                'confidence': getattr(plan,'confidence',None),
${ind2}                'reason': getattr(plan,'reason',None),
${ind2}                'reasons': ['entry_off_market'],
${ind2}                'last': _lf,
${ind2}                'max_entry_dev_pct': _pct,
${ind2}            })
${ind2}            meta.emit(ev); announce.emit(ev)
${ind2}        except Exception:
${ind2}            pass
${ind2}        if _hard:
${ind2}            raise SystemExit(f"[ENTRY_OFF_MARKET] hard-stop: entry={_ef} last={_lf} dev_pct={abs(_ef-_lf)/_lf:.4f} > {_pct}")
${ind}except SystemExit:
${ind2}raise
${ind}except Exception:
${ind2}pass
${ind}# --- ${markerB} END ---
"@

  $orcTxt = Insert-AfterLine $orcTxt $mEnd.Index ($guard)
  Set-Content -Encoding UTF8 -Path $orcPath -Value $orcTxt
  Write-Host "OK: patched => $orcPath"
} else {
  Write-Host "SKIP: orchestrator.py already has $markerB"
}

# -----------------------------
# (C) QA meta summary (python + ps wrapper)
# -----------------------------
$qaPy = Join-Path $ROOT "tools\qa_meta_summary.py"
$qaPs = Join-Path $ROOT "tools\QA_META_SUMMARY_V1.ps1"

$pyCode = @"
import os, json
from datetime import datetime, date
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

TZ = ZoneInfo("America/Los_Angeles") if ZoneInfo else None

def to_pt(ts: str):
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    dt = datetime.fromisoformat(ts)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=TZ) if TZ else dt
    return dt.astimezone(TZ) if TZ else dt

def today_pt():
    if TZ:
        return datetime.utcnow().replace(tzinfo=ZoneInfo("UTC")).astimezone(TZ).date()
    return datetime.now().date()

def is_fake(p):
    if not p: return False
    r = str(p.get("reason","") or "")
    if "forced_signal_test" in r: return True
    try:
        e=float(p.get("entry")); s=float(p.get("stop")); t=float(p.get("tp"))
        return abs(e-100.0)<1e-6 and abs(s-99.0)<1e-6 and abs(t-102.0)<1e-6
    except Exception:
        return False

day = os.environ.get("TBOT_QA_DAY","").strip()
day_pt = date.fromisoformat(day) if day else today_pt()

meta_path = os.path.join(os.getcwd(),"logs","meta.jsonl")
counts = dict(boot=0, shadow_plan=0, shadow_accept=0, shadow_reject=0, fake_plans=0, valid_accepts=0)
by_sid = {}
by_side = {}
reject_reasons = {}

with open(meta_path,"r",encoding="utf-8") as f:
    for line in f:
        line=line.strip()
        if not line: continue
        try: j=json.loads(line)
        except Exception: continue
        kind=j.get("kind"); ts=j.get("ts")
        if not kind or not ts: continue
        try: tpt=to_pt(str(ts))
        except Exception: continue
        if tpt.date() != day_pt: continue

        if kind in counts: counts[kind]+=1
        p=j.get("payload") or {}

        if kind=="shadow_plan" and is_fake(p):
            counts["fake_plans"] += 1

        if kind=="shadow_accept":
            if is_fake(p): 
                continue
            counts["valid_accepts"] += 1
            sid = p.get("sid") or p.get("strategy") or p.get("signal_id") or p.get("name") or "UNKNOWN"
            side = p.get("side") or "UNKNOWN"
            by_sid[sid] = by_sid.get(sid,0)+1
            by_side[side] = by_side.get(side,0)+1

        if kind=="shadow_reject":
            rs = p.get("reasons") or []
            if isinstance(rs,str): rs=[rs]
            for r in rs:
                reject_reasons[r]=reject_reasons.get(r,0)+1

max_boots = int(os.environ.get("TBOT_QA_MAX_BOOTS","3"))
cap = int(os.environ.get("TBOT_QA_CAP","150"))
audit_ok = True
notes=[]
if counts["boot"] > max_boots:
    audit_ok=False; notes.append(f"boots_gt_{max_boots}")
if counts["fake_plans"] > 0:
    audit_ok=False; notes.append("fake_plans_present")
if counts["valid_accepts"] > cap:
    audit_ok=False; notes.append("valid_accepts_gt_cap")

print(f"QA_DAY={day_pt} AUDIT_OK={audit_ok} NOTES={';'.join(notes) if notes else '(none)'}")
print("META_COUNTS", counts)
print("BY_STRATEGY", dict(sorted(by_sid.items(), key=lambda kv: -kv[1])))
print("BY_SIDE", dict(sorted(by_side.items(), key=lambda kv: -kv[1])))
print("REJECT_REASONS", dict(sorted(reject_reasons.items(), key=lambda kv: -kv[1])))
"@

Set-Content -Encoding UTF8 -Path $qaPy -Value $pyCode

$psCode = @"
# tools\QA_META_SUMMARY_V1.ps1
[CmdletBinding()]
param(
  [string]\$Day = "",   # YYYY-MM-DD PT (optional)
  [int]\$MaxBoots = 3,
  [int]\$Cap = 150
)
\$ErrorActionPreference="Stop"
\$ROOT = (Get-Location).Path
if(\$ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot" }
\$PY = Join-Path \$ROOT ".venv\Scripts\python.exe"
\$OPS = Join-Path \$ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path \$OPS | Out-Null

if(\$Day){ \$env:TBOT_QA_DAY = \$Day } else { Remove-Item Env:TBOT_QA_DAY -ErrorAction SilentlyContinue }
\$env:TBOT_QA_MAX_BOOTS = "\$MaxBoots"
\$env:TBOT_QA_CAP = "\$Cap"

\$out = & \$PY (Join-Path \$ROOT "tools\qa_meta_summary.py")
\$stamp = if(\$Day){ \$Day.Replace("-","") } else { (Get-Date).ToString("yyyyMMdd") }
\$path = Join-Path \$OPS ("QA_META_SUMMARY_{0}.txt" -f \$stamp)
\$out | Out-File -Encoding UTF8 -FilePath \$path
\$out
Write-Host ("WROTE => " + \$path)
"@

Set-Content -Encoding UTF8 -Path $qaPs -Value $psCode
Write-Host "OK: wrote => $qaPs"

# -----------------------------
# Tests (real failures)
# -----------------------------
Write-Host ""
Write-Host "TEST 1: py_compile touched modules"
& $PY -m py_compile `
  "tbot\runtime\gate_state.py" `
  "tbot\runtime\orchestrator.py" `
  "tbot\runtime\shadow_pricing.py" `
  "tbot\runtime\shadow_gate.py" `
  "tbot\main.py"
if($LASTEXITCODE -ne 0){ throw "py_compile failed" }

Write-Host ""
Write-Host "TEST 2: synthetic policy locks (boot>=3, cooldown=0, cap breach)"
$testPy = Join-Path $BAK "_policy_test.py"
@"
import os, json, tempfile
from argparse import Namespace
from datetime import date
from tbot.runtime.gate_state import apply_persistent_gate_limits

def write_meta(path, lines):
    with open(path,'w',encoding='utf-8') as f:
        f.write("\n".join(lines) + "\n")

day = date(2031,1,1)
tmp = tempfile.mkdtemp()
os.makedirs(os.path.join(tmp,'logs'), exist_ok=True)
mp = os.path.join(tmp,'logs','meta.jsonl')

# --- boot guard: 3 boots => stop ---
boot_lines = [json.dumps({'ts':'2031-01-01T06:31:00-08:00','kind':'boot','run_id':str(i)}) for i in range(3)]
write_meta(mp, boot_lines)
os.environ.pop("TBOT_ALLOW_BOOT_OVERRUN", None)
args = Namespace(gate_max_plans_per_day=150, gate_max_risk_usd=500.0, gate_cooldown_sec=30, shadow=True)
try:
    apply_persistent_gate_limits(args, root_dir=tmp, allow_fake_start=True, day_pt=day)
    raise SystemExit("FAIL boot-guard did not stop")
except SystemExit as e:
    if "[BOOT_GUARD]" not in str(e):
        raise

# --- cooldown=0 => stop ---
write_meta(mp, [])  # no boots now
os.environ.pop("TBOT_ALLOW_COOLDOWN_0", None)
args = Namespace(gate_max_plans_per_day=150, gate_max_risk_usd=500.0, gate_cooldown_sec=0, shadow=True)
try:
    apply_persistent_gate_limits(args, root_dir=tmp, allow_fake_start=True, day_pt=day)
    raise SystemExit("FAIL cooldown=0 did not stop")
except SystemExit as e:
    if "[COOLDOWN]" not in str(e):
        raise

# --- cap breach: 6 accepts vs cap 5 => stop ---
acc_lines = [json.dumps({'ts':'2031-01-01T07:00:00-08:00','kind':'shadow_accept','payload':{
    'entry':10,'stop':9,'tp':12,'reason':'ok','risk_usd':25,'symbol':'SPY','sid':'S11','side':'LONG'
}}) for _ in range(6)]
write_meta(mp, acc_lines)
args = Namespace(gate_max_plans_per_day=5, gate_max_risk_usd=200.0, gate_cooldown_sec=30, shadow=True)
try:
    apply_persistent_gate_limits(args, root_dir=tmp, allow_fake_start=True, day_pt=day)
    raise SystemExit("FAIL cap-breach did not stop")
except SystemExit as e:
    if "[PERSIST_CAP]" not in str(e):
        raise

print("ALL_POLICY_TESTS_PASS")
"@ | Set-Content -Encoding UTF8 -Path $testPy

& $PY $testPy
if($LASTEXITCODE -ne 0){ throw "TEST 2 failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK
Write-Host ""
Write-Host "Next:"
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\QA_META_SUMMARY_V1.ps1 -Cap 150 -MaxBoots 3"
