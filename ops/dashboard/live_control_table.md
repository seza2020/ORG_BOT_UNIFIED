# Enterprise Project Control Table

Generated: 2026-03-11 15:13:17

| Section | Metric | Value | Notes |
|---|---|---:|---|
| Runtime | family_count | 0 |  |
| Runtime | family_root_pids |  |  |
| Runtime | lock_pid_present | False |  |
| Runtime | last_heartbeat_ts | 2026-03-11 13:00:56 |  |
| Runtime | meta_line_count | 217445 |  |
| Runtime | perf_line_count | 21805 |  |
| Market | regime | CHOP |  |
| Market | confidence | 0.3393 |  |
| Market | regime_reason | chop_spread(0.0002) |  |
| Market | alpha_mode | OFF |  |
| Market | alpha_reason | alpha_off_chop(ts=0.026) |  |
| Market | bias | LONG |  |
| Market | trend_strength | 0.0257 |  |
| Market | vwap_state | ABOVE |  |
| Market | ema_sep | 0.000214 |  |
| Strategy | last_gate_decision | REJECT |  |
| Strategy | last_gate_reason | alpha_mode_off |  |
| Strategy | last_plan_sid | A_VALIDATION_PIPELINE_V1 |  |
| Strategy | last_skipped_sid |  |  |
| Strategy | last_skipped_reason | alpha_mode_off |  |
| Strategy | plan_created_count_tail | 0 |  |
| Strategy | plan_skipped_count_tail | 154 |  |
| Strategy | gate_accept_count_tail | 71 |  |
| Strategy | chop_v1_eval_count_tail | 103 |  |
| Strategy | chop_v1_plan_created_count_tail | 0 |  |
| Strategy | chop_v1_rejected_count_tail | 103 |  |
| PnL | realized_r_total | 0 |  |
| PnL | realized_r_count | 0 |  |
| PnL | risk_per_trade_usd | 250 |  |
| PnL | realized_usd_total | 0 | Computed as realized_r_total * risk_per_trade_usd |
| Risk | ledger_day_key | 2026-03-11 |  |
| Risk | ledger_week_key | 2026-W11 |  |
| Risk | daily_budget_used_r | 1.25 |  |
| Risk | weekly_budget_used_r | 1.25 |  |
| Risk | open_risk_r | 0.5 |  |
| Risk | open_positions_count | 0 |  |
| Risk | ledger_last_reason | smoke_release |  |
| Stability | regime_exception_count_tail | 0 |  |
| Reasons | top_reason_1 | gate_rejected_upstream | count=415 |
| Reasons | top_reason_2 | alpha_mode_off | count=248 |
| Reasons | top_reason_3 | validation_runtime_active_v1 | count=153 |
| Reasons | top_reason_4 | signal_eval_runtime_v1 | count=153 |
| Reasons | top_reason_5 | core_context_from_snapshot_v1 | count=153 |
