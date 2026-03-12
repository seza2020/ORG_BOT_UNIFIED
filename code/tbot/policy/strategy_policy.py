# File: tbot/policy/strategy_policy.py
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Dict


def _clamp01(x: float) -> float:
    if x < 0.0:
        return 0.0
    if x > 1.0:
        return 1.0
    return x


@dataclass(frozen=True)
class StrategyPolicy:
    enabled: bool = True
    weight: float = 1.0
    min_conf: float = 0.0
    max_fires_per_day: int = 10_000
    max_accepts_per_day: int = 10_000
    cooldown_sec: int = 0


def _default_policy() -> Dict[str, StrategyPolicy]:
    # Defaults must preserve current behavior.
    # - S01 enabled (core)
    # - S11 enabled (primary alpha)
    # - S12 disabled by default (secondary alpha with hard caps)
    return {
        "S01": StrategyPolicy(enabled=True, weight=1.0, min_conf=0.0),
        "S11": StrategyPolicy(enabled=True, weight=1.0, min_conf=0.0),
        "S12": StrategyPolicy(
            enabled=False,
            weight=0.5,
            min_conf=0.8,
            max_fires_per_day=1,
            max_accepts_per_day=1,
            cooldown_sec=999999,
        ),
        "S08": StrategyPolicy(
            enabled=False,
            weight=0.5,
            min_conf=0.8,
            max_fires_per_day=1,
            max_accepts_per_day=1,
            cooldown_sec=999999,
        ),
    }


def load_policy() -> Dict[str, StrategyPolicy]:
    """
    Env:
      TBOT_STRATEGY_POLICY_JSON = JSON mapping SID -> policy fields.
    """
    raw = os.getenv("TBOT_STRATEGY_POLICY_JSON", "").strip()
    if not raw:
        return _default_policy()

    try:
        obj = json.loads(raw)
        out: Dict[str, StrategyPolicy] = {}
        for sid, cfg in obj.items():
            if not isinstance(cfg, dict):
                continue

            enabled = bool(cfg.get("enabled", True))
            weight = float(cfg.get("weight", 1.0))
            min_conf = float(cfg.get("min_conf", 0.0))
            max_fires = int(cfg.get("max_fires_per_day", 10_000))
            max_accepts = int(cfg.get("max_accepts_per_day", 10_000))
            cooldown = int(cfg.get("cooldown_sec", 0))

            out[str(sid)] = StrategyPolicy(
                enabled=enabled,
                weight=weight,
                min_conf=_clamp01(min_conf),
                max_fires_per_day=max(0, max_fires),
                max_accepts_per_day=max(0, max_accepts),
                cooldown_sec=max(0, cooldown),
            )

        base = _default_policy()
        for sid, pol in base.items():
            out.setdefault(sid, pol)

        return out
    except Exception:
        return _default_policy()

