from __future__ import annotations
import json

from tbot.policy.alpha_mode import decide_alpha_mode


_warmup_profile_cache = None

def _get_warmup_profile():
    global _warmup_profile_cache
    try:
        if _warmup_profile_cache is None:
            runroot = os.getenv('TBOT_RUNROOT') or os.getcwd()
            candidate = os.path.join(os.path.dirname(os.path.dirname(runroot)), 'ops', 'validation', 'warmup_profile_v1.json')
            if os.path.exists(candidate):
                with open(candidate, 'r', encoding='utf-8') as f:
                    _warmup_profile_cache = json.load(f)
            else:
                _warmup_profile_cache = {}
        return _warmup_profile_cache or {}
    except Exception:
        return {}

def _get_effective_thresholds(default_on_th, default_cap_th):
    try:
        p = _get_warmup_profile()
        if str(p.get('mode') or '').upper() == 'PAPER_WARMUP':
            return 0.30, 0.15
        return default_on_th, default_cap_th
    except Exception:
        return default_on_th, default_cap_th

def compute_alpha_mode(core_ctx, regime):
    try:
        reg = str((regime or {}).get("regime") or "CHOP").upper()
        bias = str((core_ctx or {}).get("bias") or "FLAT").upper()
        ts = float((core_ctx or {}).get("trend_strength") or 0.0)

        if bias == "FLAT":
            return {"mode": "OFF", "cap_ratio": 0.0, "reason": "alpha_off_flat_bias"}

        d = decide_alpha_mode(regime=reg, bias=bias, trend_strength=ts)
        import os
        return {
            "mode": getattr(d, "mode", "OFF"),
            "cap_ratio": float(getattr(d, "cap_ratio", 0.0) or 0.0),
            "reason": getattr(d, "reason", "alpha_mode_unknown"),
            "regime": reg,
            "bias": bias,
            "trend_strength": ts,
        }
    except Exception as e:
        return {"mode": "OFF", "cap_ratio": 0.0, "reason": f"alpha_mode_exception:{type(e).__name__}"}
