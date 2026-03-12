# OPS_RUNBOOK_DAILY

## Daily sequence
1) Run Shadow session (no orders).
2) Collect outputs into latest_daily/ and logs/.
3) Build upload artifacts (5 files).
4) Upload:
   - Always replace: MYGPT_ROLLING_LAST10.zip, MYGPT_DAILY_LATEST.zip
   - Replace static only if changed.

## Minimum checks
- No SECRET_HIT in packaging
- QC summary present (or explain missing)
- Rolling and Daily ZIP sizes within cap
