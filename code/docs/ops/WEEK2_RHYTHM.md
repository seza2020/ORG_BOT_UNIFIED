WEEK2 OPERATING RHYTHM (PT / America/Los_Angeles)

SCHEDULED TASK TRIGGERS (Task Scheduler = single source of truth):
- RUN_START_PT:        06:30:00  (TBOT_RUN_SHADOW_DAILY_0630)
- PRE_CLOSE_STOP_PT:   12:58:30  (TBOT_PRE_CLOSE_STOP_125830)
- EOD_FREEZE_PT:       13:05:00  (TBOT_END_OF_DAY_1305)
- POSTFIX_AUDIT_PT:    13:06:00  (TBOT_POSTFIX_DAILY_EVIDENCE_1306)

EXECUTION COMMANDS:
- TBOT_RUN_SHADOW_DAILY_0630 -> tools/RUN_LIVE_SHADOW_CANON_V2.ps1
- TBOT_END_OF_DAY_1305       -> tools/OPS_END_OF_DAY_V2.ps1 -StopBot 1
- TBOT_POSTFIX_DAILY_EVIDENCE_1306 -> tools/ops/POSTFIX_DAILY_EVIDENCE.ps1

RULES:
- Do NOT claim any other "session window" time unless proven by exact file path + line.
- Operational stop is PRE_CLOSE_STOP_PT; anything after is freeze/pack/audit hardening.
