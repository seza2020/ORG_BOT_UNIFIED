# tbot/runtime/local_decision_client.py
# Local Decision API client (LLM loop)
# Observability + risk-safe defaults

from __future__ import annotations

import json
import os
import time
import urllib.request
import urllib.error
from typing import Any, Dict, Optional


def _env(name: str, default: str) -> str:
    v = os.getenv(name)
    return v if (v is not None and str(v).strip() != "") else default


def request_decision(
    *,
    features: Dict[str, Any],
    meta: Any = None,
    url: Optional[str] = None,
    timeout_sec: float = 1.0,
) -> Dict[str, Any]:
    """
    Calls local decision API.
    Returns dict with at minimum:
      {"decision": "ALLOW"|"BLOCK", "reason": "...", "latency_ms": float}
    Fail-safe behavior controlled by TBOT_LLM_FAILSAFE = "BLOCK"|"ALLOW".
    """
    t0 = time.perf_counter()

    endpoint = url or _env("TBOT_LOCAL_DECISION_URL", "http://127.0.0.1:8899/decision")
    failsafe = _env("TBOT_LLM_FAILSAFE", "BLOCK").upper().strip()
    if failsafe not in ("BLOCK", "ALLOW"):
        failsafe = "BLOCK"

    payload = {
        "ts": time.time(),
        "features": features,
    }

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=float(timeout_sec)) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            obj = json.loads(raw) if raw else {}
            decision = str(obj.get("decision", "")).upper().strip()
            reason = str(obj.get("reason", ""))
            latency_ms = (time.perf_counter() - t0) * 1000.0

            if decision not in ("ALLOW", "BLOCK"):
                # Unknown response -> failsafe
                return {"decision": failsafe, "reason": f"bad_response:{decision}", "latency_ms": latency_ms}

            obj.setdefault("latency_ms", latency_ms)
            obj.setdefault("reason", reason)
            obj["decision"] = decision
            return obj

    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, Exception) as e:
        latency_ms = (time.perf_counter() - t0) * 1000.0
        return {"decision": failsafe, "reason": f"exception:{type(e).__name__}", "latency_ms": latency_ms}


def ping(url: Optional[str] = None, timeout_sec: float = 0.5) -> bool:
    """Cheap health check (GET /health)."""
    endpoint = url or _env("TBOT_LOCAL_DECISION_URL", "http://127.0.0.1:8899/decision")
    health = endpoint.rsplit("/", 1)[0] + "/health"
    req = urllib.request.Request(health, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=float(timeout_sec)) as resp:
            return 200 <= int(getattr(resp, "status", 200)) < 300
    except Exception:
        return False


