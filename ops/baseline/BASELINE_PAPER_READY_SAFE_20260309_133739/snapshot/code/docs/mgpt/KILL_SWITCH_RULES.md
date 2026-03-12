# KILL_SWITCH_RULES

Trigger immediate stand-down if any occurs:
- Any suspected secret exposure risk
- Repeated runtime crashes or reconnect loops
- Order-routing behavior observed in SHADOW (should be none)
- Data integrity failure (missing core fields, corrupted JSONL)

Stand-down actions:
- Stop bot
- Preserve logs
- Produce a DAILY artifact bundle for audit
- Diagnose before resuming
