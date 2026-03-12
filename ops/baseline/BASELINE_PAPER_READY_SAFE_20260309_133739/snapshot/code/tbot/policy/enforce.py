# File: tbot/policy/enforce.py
from __future__ import annotations

from tbot.policy.strategy_policy import load_policy
from tbot.strategies.base import Signal


def _clamp01(x: float) -> float:
    if x < 0.0:
        return 0.0
    if x > 1.0:
        return 1.0
    return x


def apply_policy(signal: Signal) -> Signal | None:
    """
    Applies managerial policy to a strategy signal:
    - enabled: if False => drop signal
    - weight: scales confidence
    - min_conf: drops signal if below threshold

    Defaults preserve behavior (weight=1, min_conf=0).
    """
    pol = load_policy()
    p = pol.get(signal.sid, None)
    if p is None:
        return signal

    if not p.enabled:
        return None

    new_conf = _clamp01(float(signal.confidence) * float(p.weight))
    if new_conf < float(p.min_conf):
        return None

    if new_conf == signal.confidence:
        return signal

    return Signal(
        sid=signal.sid,
        symbol=signal.symbol,
        side=signal.side,
        confidence=new_conf,
        reason=signal.reason,
    )
