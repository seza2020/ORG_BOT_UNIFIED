import re
from pathlib import Path

SG = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")

txt = SG.read_text(encoding="utf-8")

# If already patched, no-op
if re.search(r"^\s{4}def\s+commit_accept\s*\(", txt, flags=re.M):
    print("NOOP: commit_accept already exists:", SG)
    raise SystemExit(0)

m_class = re.search(r"^class\s+ShadowGate\b.*?:\s*$", txt, flags=re.M)
if not m_class:
    raise SystemExit("ERROR: ShadowGate class not found")

m_eval = re.search(r"^\s{4}def\s+evaluate\s*\(", txt, flags=re.M)
if not m_eval:
    raise SystemExit("ERROR: ShadowGate.evaluate not found")

need_ensure = not re.search(r"^\s{4}def\s+_ensure_day\s*\(", txt, flags=re.M)

ensure_block = ""
if need_ensure:
    ensure_block = r'''
    def _ensure_day(self, now):
        """Reset daily counters when the date changes."""
        try:
            day_key = now.date().isoformat()
        except Exception:
            day_key = str(getattr(now, "date", lambda: None)())

        cur = getattr(self, "_day_key", None)
        if cur != day_key:
            setattr(self, "_day_key", day_key)
            setattr(self, "_accepted_today", 0)
            setattr(self, "_risk_today", 0.0)
'''

commit_block = r'''
    def commit_accept(self, now, plan):
        """Record an accepted plan for cooldown/daily-cap enforcement (back-compat API)."""
        if hasattr(self, "_ensure_day"):
            self._ensure_day(now)

        # Counters (best-effort, non-breaking)
        setattr(self, "_accepted_today", int(getattr(self, "_accepted_today", 0)) + 1)
        try:
            setattr(self, "_risk_today", float(getattr(self, "_risk_today", 0.0)) + float(getattr(plan, "risk_usd", 0.0)))
        except Exception:
            pass

        # Timestamps (aliases included for compatibility)
        setattr(self, "_last_accept_ts", now)
        setattr(self, "_last_plan_ts", now)
        setattr(self, "last_accept_ts", now)
        setattr(self, "last_plan_ts", now)

    def commit_reject(self, now, plan, reasons=None):
        """Record a rejected plan (optional; mainly for debugging/metrics)."""
        if hasattr(self, "_ensure_day"):
            self._ensure_day(now)
        setattr(self, "_last_reject_ts", now)
        setattr(self, "last_reject_ts", now)
'''

insert = ensure_block + commit_block

# Insert right before evaluate()
patched = txt[:m_eval.start()] + insert + txt[m_eval.start():]
SG.write_text(patched, encoding="utf-8")
print("PATCHED:", SG)
