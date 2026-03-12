# File: tbot/regime/enforce.py
from __future__ import annotations

import os
from typing import Any

from tbot.regime.overlay import RegimeOverlay


def regime_enabled() -> bool:
    v = os.getenv("TBOT_REGIME_ENABLE", "0").strip().lower()
    return v in ("1", "true", "yes", "on")


def apply_alpha_overlay(*, is_alpha: bool, sig_payload: dict[str, Any], overlay: RegimeOverlay) -> tuple[dict[str, Any] | None, str | None]:
    """
    Returns:
      (new_payload, reason) where reason is non-None when dropped.
    """
    if not is_alpha:
        return sig_payload, None

    mode = str(overlay.alpha_mode).upper()

    if mode == "OFF":
        return None, "regime_alpha_off"

    if mode == "CAP50":
        try:
            conf = float(sig_payload.get("confidence", 0.0))
        except Exception:
            conf = 0.0
        sig_payload = dict(sig_payload)
        sig_payload["confidence"] = max(0.0, min(1.0, conf * 0.5))
        return sig_payload, None

    # ON or unknown
    return sig_payload, None
