import json
from pathlib import Path

# ما فقط state file رو می‌خونیم، نه API بازار
from tbot.runtime.shadow_gate import ShadowGate, ShadowGateCfg

# cfg: هر پلن 250 OK، ولی بودجه روزانه 500 => سومی باید Reject شود
cfg = ShadowGateCfg()
cfg.max_risk_usd = 999999.0
cfg.max_risk_per_trade_usd = 250.0
cfg.max_risk_per_day_usd = 500.0

g = ShadowGate(cfg)

class P:
    def __init__(self, risk):
        self.risk_usd = risk

# شبیه‌سازی اینکه امروز 2 پلن قبول شده و ریسک استفاده شده 500 شده
g._risk_today = 500.0

plan = P(250.0)

allow, reasons = g.allow(plan)
print("ALLOW=", allow)
print("REASONS=", reasons)

# انتظار: allow=False و daily_risk_budget_reached داخل reasons باشد
