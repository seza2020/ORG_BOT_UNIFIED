from __future__ import annotations
import os
import uuid
from tbot.runtime.llm_gate import LlmGate

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Iterable, List, Tuple
import datetime as dt  # P0_2_3_V2_4_DAILY_BUDGET_ENFORCE

# --- Gate reason taxonomy (enterprise-grade) ---
# These are the only allowed reasons to appear in logs.
_ALLOWED_REASONS = {
    "rr_below_min",
    "confidence_below_min",
    "risk_above_max",
    "risk_above_max_trade",
    "daily_risk_budget_reached",
    "daily_plan_cap_reached",
    "cooldown_active",
    "alpha_kill_active",
    "portfolio_kill_active",
    "out_of_session",
    "pre_close",
    "unknown_reason",
    "fake_price_blocked",    "llm_gate_deny",
}

def _normalize_reasons(reasons: Iterable[str] | None) -> List[str]:
    """
    Deterministic, unique, sorted reasons list.
    Enforces taxonomy: any unknown reason -> "unknown_reason".
    """
    if not reasons:
        return []
    out = []
    seen = set()
    for r in reasons:
        if r is None:
            continue
        s = str(r).strip()
        if not s:
            continue
        if s not in _ALLOWED_REASONS:
            s = "unknown_reason"
        if s not in seen:
            out.append(s)
            seen.add(s)
    out.sort()
    return out

def _safe_float(x: Any, default: float | None = None) -> float | None:
    try:
        if x is None:
            return default
        return float(x)
    except Exception:
        return default

def _calc_rr(plan: Any) -> float | None:
    """
    Prefer plan.rr if present; else compute from entry/stop/tp if possible.
    rr = |tp-entry| / |entry-stop|
    """
    rr = _safe_float(getattr(plan, "rr", None), None)
    if rr is not None:
        return rr

    entry = _safe_float(getattr(plan, "entry", None), None)
    stop  = _safe_float(getattr(plan, "stop", None), None)
    tp    = _safe_float(getattr(plan, "tp", None), None)
    if entry is None or stop is None or tp is None:
        return None
    denom = abs(entry - stop)
    if denom <= 0:
        return None
    return abs(tp - entry) / denom

@dataclass(frozen=True)
class GateConfig:
    min_rr: float = 1.0
    # backward-compatible name used by orchestrator
    min_confidence: float = 0.90
    cooldown_sec: int = 0
    max_plans_per_day: int = 999
    max_risk_usd: float = 999999.0

    # P0_2_RISK_BUDGET_SPLIT_V1
    max_risk_per_trade_usd: float = 999999.0
    max_risk_per_day_usd: float | None = None
    # backward-compatible (some callers pass it; gate may ignore)
    max_qty: int = 0
class ShadowGate:

    @property
    def min_conf(self):
        return float(self.cfg.min_confidence)

    """
    Stateless API, stateful behavior (cooldown + daily cap) in-memory.
    This is only used in runtime loop, not for backtest.
    """

    def __init__(self, cfg: GateConfig):
        # P0_2_3_V2_4_DAILY_BUDGET_ENFORCE
        self._risk_today = 0.0
        self._risk_day_key = None
        self.cfg = cfg
        self._day_key: str | None = None
        self._plans_today: int = 0
        self._last_accept_ts: float | None = None

    def _roll_day(self, now: datetime) -> None:
        key = now.strftime("%Y%m%d")
        if self._day_key != key:
            self._day_key = key
            self._plans_today = 0
            self._last_accept_ts = None


    def _ensure_day(self, now: datetime) -> None:
        """Reset daily counters when the date changes (compat helper)."""
        try:
            day_key = now.strftime("%Y%m%d")
        except Exception:
            try:
                day_key = str(now.date()).replace("-", "")
            except Exception:
                day_key = None

        cur = getattr(self, "_day_key", None)
        if day_key is not None and cur != day_key:
            self._day_key = day_key
            self._plans_today = 0
            self._last_accept_ts = None
            # Best-effort mirrors (do not affect runtime gate logic)
            setattr(self, "_accepted_today", 0)
            setattr(self, "_risk_today", 0.0)

    def commit_accept(self, now, plan):
        """Record an accepted plan for cooldown/daily-cap enforcement (back-compat API)."""
        if hasattr(self, "_ensure_day"):
            self._ensure_day(now)

        # Runtime gate counters used by evaluate() for daily cap
        try:
            self._plans_today = int(getattr(self, "_plans_today", 0)) + 1
        except Exception:
            pass

        # Counters (best-effort, non-breaking)
        setattr(self, "_accepted_today", int(getattr(self, "_accepted_today", 0)) + 1)
        try:
            setattr(
                self,
                "_risk_today",
                float(getattr(self, "_risk_today", 0.0)) + float(getattr(plan, "risk_usd", 0.0)),
            )
        except Exception:
            pass

        # FIX: keep _last_accept_ts as float timestamp seconds (cooldown relies on this)
        try:
            ts = float(now.timestamp())  # datetime -> float seconds
        except Exception:
            try:
                ts = float(now)  # if caller passed a float already
            except Exception:
                ts = None

        if ts is not None:
            setattr(self, "_last_accept_ts", ts)
            
            # Per-key cooldown timestamp (sid+symbol+side) to avoid cross-symbol starvation
            try:
                d = getattr(self, "_last_accept_ts_by_key", None)
                if not isinstance(d, dict):
                    d = {}
                sid = getattr(plan, "sid", None) or getattr(plan, "strategy_id", None) or getattr(plan, "signal_id", None) or "?"
                sym = getattr(plan, "symbol", None) or "?"
                side = getattr(plan, "side", None) or "?"
                d[(str(sid), str(sym), str(side))] = float(ts)
                setattr(self, "_last_accept_ts_by_key", d)
            except Exception:
                pass

        # Optional human-friendly mirrors (do not affect cooldown math)
        setattr(self, "_last_plan_ts", now)
        setattr(self, "last_accept_ts", now)
        setattr(self, "last_plan_ts", now)


    def commit_reject(self, now, plan, reasons=None):
        """Record a rejected plan (optional; mainly for debugging/metrics)."""
        if hasattr(self, "_ensure_day"):
            self._ensure_day(now)
        setattr(self, "_last_reject_ts", now)
        setattr(self, "last_reject_ts", now)
    def evaluate(
        self,
        now: datetime,
        plan: Any,
        *,
        alpha_kill: bool,
        portfolio_kill: bool,
        in_session: bool,
        pre_close: bool,
    ) -> Tuple[bool, List[str]]:
        # P0_2_3_V2_4_DAILY_BUDGET_ENFORCE
        # Day roll + daily budget enforce (inside gate, multiline-signature safe)
        try:
            _now = None
            if 'now' in locals() and hasattr(locals().get('now'), 'strftime'):
                _now = locals().get('now')
            else:
                _now = dt.datetime.now(dt.timezone.utc)
            _k = _now.strftime('%Y%m%d')
            if getattr(self, '_risk_day_key', None) != _k:
                self._risk_day_key = _k
                self._risk_today = 0.0
        except Exception:
            pass
        try:
            _day_cap = getattr(self.cfg, 'max_risk_per_day_usd', None)
            _risk_plan = float(getattr(plan, 'risk_usd', 0.0))
            if _day_cap is not None:
                if float(getattr(self, '_risk_today', 0.0)) + _risk_plan > float(_day_cap):
                    reasons.append('daily_risk_budget_reached')
        except Exception:
            pass
        """
        Returns (ok, reasons)
        - ok=True => accept
        - ok=False => reject with normalized reasons list
        """
        self._roll_day(now)

        reasons: List[str] = []

                # --- TBOT_HARD_BLOCK_FAKE_PRICE_V1 BEGIN ---
        try:
            from tbot.runtime.gate_state import is_fake_payload as _tbot_is_fake
            _p = {
                'reason': getattr(plan, 'reason', None),
                'entry':  getattr(plan, 'entry',  None),
                'stop':   getattr(plan, 'stop',   None),
                'tp':     getattr(plan, 'tp',     None),
            }
            if plan is not None and _tbot_is_fake(_p):
                if _os.getenv('TBOT_HARD_STOP_ON_FAKE_PRICE','1') == '1':
                    _r = str(getattr(plan, 'reason', '') or '')
                    if (_r == 'forced_signal_test') and (_os.getenv('TBOT_ALLOW_FORCE_SIGNAL_TEST','0') == '1'):
                        pass
                    else:
                        reasons.append('fake_price_blocked')
        except Exception:
            pass
        # --- TBOT_HARD_BLOCK_FAKE_PRICE_V1 END ---


        # Hard blocks
        if portfolio_kill:
            reasons.append("portfolio_kill_active")
        if not in_session:
            reasons.append("out_of_session")
        if pre_close:
            reasons.append("pre_close")
        if alpha_kill:
            reasons.append("alpha_kill_active")

        # Numeric gates
        rr = _calc_rr(plan)
        conf = _safe_float(getattr(plan, "confidence", None), None)
        risk = _safe_float(getattr(plan, "risk_usd", None), None)

        if rr is not None and rr < float(self.cfg.min_rr):
            reasons.append("rr_below_min")
        if conf is not None and conf < float(self.cfg.min_confidence):
            reasons.append("confidence_below_min")        # P0_2_RISK_BUDGET_SPLIT_V1
        # Per-trade cap (legacy max_risk_usd still supported, but prefer max_risk_per_trade_usd)
        max_trade = float(getattr(self.cfg, "max_risk_per_trade_usd", None) or getattr(self.cfg, "max_risk_usd", 0.0))
        if risk is not None and risk > max_trade:
            reasons.append("risk_above_max_trade")
            # Keep legacy reason too for compatibility with existing dashboards
            reasons.append("risk_above_max")
        # Daily budget (cumulative)
        max_day = getattr(self.cfg, "max_risk_per_day_usd", None)
        if (risk is not None) and (max_day is not None):
            try:
                used = float(getattr(self, "_risk_today", 0.0))
                if used + float(risk) > float(max_day):
                    reasons.append("daily_risk_budget_reached")
            except Exception:
                pass
        # Daily cap
        if self._plans_today >= int(self.cfg.max_plans_per_day):
            reasons.append("daily_plan_cap_reached")

        # Cooldown (per sid+symbol+side; prevents cross-symbol starvation)
        cd = int(self.cfg.cooldown_sec)
        if cd > 0:
            try:
                d = getattr(self, "_last_accept_ts_by_key", None)
                if not isinstance(d, dict):
                    d = {}
                sid = getattr(plan, "sid", None) or getattr(plan, "strategy_id", None) or getattr(plan, "signal_id", None) or "?"
                sym = getattr(plan, "symbol", None) or "?"
                side = getattr(plan, "side", None) or "?"
                last = d.get((str(sid), str(sym), str(side)))
                if last is not None:
                    dt = now.timestamp() - float(last)
                    if dt < cd:
                        reasons.append("cooldown_active")
            except Exception:
                # Fallback to legacy global cooldown if something is odd
                if getattr(self, "_last_accept_ts", None) is not None:
                    try:
                        dt = now.timestamp() - float(getattr(self, "_last_accept_ts"))
                        if dt < cd:
                            reasons.append("cooldown_active")
                    except Exception:
                        pass
        

        reasons = _normalize_reasons(reasons)

        ok = (len(reasons) == 0)
        # P0_2_3_V2_4_DAILY_BUDGET_ENFORCE
        try:
            _day_cap2 = getattr(self.cfg, 'max_risk_per_day_usd', None)
            if _day_cap2 is not None:
                if ('allow' in locals()) and bool(locals().get('allow')) and (len(reasons) == 0):
                    # --- LLM Advisory Gate (Injected) ---
                    if ok:
                        try:
                            _gate = LlmGate(runroot=os.environ.get('TBOT_RUNROOT',''))
                            _sym = getattr(plan, 'symbol', 'UNKNOWN') if 'plan' in locals() else 'UNKNOWN'
                            _features = getattr(plan, 'features', {}) if 'plan' in locals() else {}
                            if not isinstance(_features, dict):
                                _features = {}
                            _meta = {
                                'phase': os.environ.get('TBOT_PHASE','PHASE_1_ADVISORY_ONLY'),
                                'trace_id': str(uuid.uuid4()),
                                'symbol': str(_sym),
                            }
                            _res = _gate.evaluate(str(_sym), _features, _meta)
                            if _res.decision != 'ALLOW':
                                ok = False
                                reasons.append('llm_gate_deny')
                        except Exception:
                            ok = False
                            reasons.append('llm_gate_deny')

                    self._risk_today = float(getattr(self, '_risk_today', 0.0)) + float(getattr(plan, 'risk_usd', 0.0))
        except Exception:
            pass
        return ok, reasons




