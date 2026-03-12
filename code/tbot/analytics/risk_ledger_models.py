from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict


@dataclass(slots=True)
class RiskLedgerState:
    ledger_version: int
    run_id: str
    last_update_ts: str
    day_key: str
    week_key: str
    daily_budget_used_r: float
    weekly_budget_used_r: float
    open_risk_r: float
    open_positions_count: int
    last_reason: str
    load_error: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
