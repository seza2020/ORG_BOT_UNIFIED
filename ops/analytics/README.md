# ops/analytics

این لایه برای تحلیل مؤسساتی سیستم معامله‌گری ساخته شده است.

هدف:
- تبدیل runtime logs به summaryهای قابل‌تحلیل
- اندازه‌گیری throughput, expectancy, rejection map
- پشتیبانی از promotion / hold / throttle / kill decision

قواعد:
- این لایه read-only نسبت به runtime است
- هیچ state اجرایی را تغییر نمی‌دهد
- فقط از روی logs و summaries تحلیل می‌کند

ورودی‌های اصلی:
- runtime/paper/logs/meta_events.jsonl
- runtime/paper/logs/meta_engine.jsonl
- runtime/paper/logs/strategy_perf_events.jsonl
- runtime/paper/logs/shadow_plans.jsonl
- runtime/paper/logs/risk_ledger_v1.json
