# analytics_pipeline

ترتیب اجرایی مؤسساتی:

1. build_runtime_summary
2. build_strategy_counts
3. build_gate_rejections
4. build_risk_status
5. rejection_analyzer
6. throughput_analyzer
7. expectancy_calculator
8. strategy_health
9. promotion_rules

قانون:
- analytics فقط read-only است
- هیچ تغییری روی runtime state نمی‌دهد
