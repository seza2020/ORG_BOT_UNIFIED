# File: tbot/policy/alpha_contract.py
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class AlphaContract:
    primary_sid: str = "S11"
    secondary_sid: str = "S12"


def load_contract() -> AlphaContract:
    """
    Env:
      TBOT_ALPHA_PRIMARY_SID: default S11
      TBOT_ALPHA_SECONDARY_SID: default S12 (can set to S08)
    """
    p = os.getenv("TBOT_ALPHA_PRIMARY_SID", "S11").strip() or "S11"
    s = os.getenv("TBOT_ALPHA_SECONDARY_SID", "S12").strip() or "S12"
    return AlphaContract(primary_sid=p, secondary_sid=s)


def classify_alpha(sid: str) -> str:
    """
    Returns:
      - "primary" for primary alpha SID
      - "secondary" for secondary alpha SID
      - "other" otherwise
    """
    c = load_contract()
    u = str(sid).upper()
    if u == c.primary_sid.upper():
        return "primary"
    if u == c.secondary_sid.upper():
        return "secondary"
    return "other"
