# File: tbot/policy/scorecard_policy.py
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AlphaScore:
    fires: int
    accepts: int
    avg_r: float
    pf: float
    dd: float


@dataclass(frozen=True)
class ScorecardDecision:
    allow: bool
    cap_ratio: float
    reason: str


def decide_alpha(score: AlphaScore) -> ScorecardDecision:
    """
    Enterprise Alpha Admission Rule (v2).
    - Warmup: allow with CAP50 until we have enough accepts.
    - After warmup: enforce expectancy/PF rules.
    """
    # ALPHA_WARMUP_UNIFY_V1: warmup handled by unified gate below (removed early warmup_cap)
    # Hard blocks
    if score.avg_r <= 0.0:
        # ALPHA_WARMUP_AUTO_V2: warmup gate with cap ramp; exits to normal policy after sample is sufficient
        try:
            import os
            _min_fires = int((os.getenv('TBOT_ALPHA_MIN_FIRES','200') or '200').strip())
            _min_accs  = int((os.getenv('TBOT_ALPHA_MIN_ACCEPTS','80') or '80').strip())
        except Exception:
            _min_fires = 200
            _min_accs  = 80
        
        try:
            _fires = int(getattr(score, 'fires', 0))
            _accs  = int(getattr(score, 'accepts', 0))
        except Exception:
            _fires = 0
            _accs  = 0
        
        if (_fires < _min_fires) or (_accs < _min_accs):
            # Ramp cap while warming up; do NOT override normal policy after thresholds are met
            if _fires < max(1, int(_min_fires * 0.5)):
                _cap_ratio = 0.10
                _mode = 'CAP10'
            else:
                _cap_ratio = 0.25
                _mode = 'CAP25'
            return ScorecardDecision(True, _cap_ratio, 'warmup_insufficient_sample')
        
        return ScorecardDecision(False, 0.0, "negative_expectancy")

    if score.pf < 1.2:
        return ScorecardDecision(False, 0.0, "low_pf")

    # Soft caps
    if score.dd < -5.0:
        return ScorecardDecision(True, 0.5, "drawdown_cap")

    return ScorecardDecision(True, 1.0, "alpha_ok")

# PATCH_SC_TO_SCORE_V1
