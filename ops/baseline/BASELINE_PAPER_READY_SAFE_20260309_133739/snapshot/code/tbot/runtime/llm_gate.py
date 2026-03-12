# tbot/runtime/llm_gate.py
# LLM advisory gate (PHASE 1): fail-closed, rate-limited, evidence-first.

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, Optional

import urllib.request


@dataclass
class LlmGateResult:
    ok: bool
    decision: str              # "ALLOW" | "DENY"
    reason: str
    trace_id: str
    symbol: str
    ttl_sec: int
    model_confidence: float
    latency_ms: float
    raw: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class LlmGate:
    """
    Advisory-only decision gate.
    - Fail-closed on any error (DENY)
    - Per-symbol rate-limit
    - Writes JSONL evidence to runroot/logs/ops/local_api_decisions.jsonl
    """

    def __init__(
        self,
        api_url: Optional[str] = None,
        runroot: Optional[str] = None,
        min_gap_sec: Optional[float] = None,
        timeout_sec: Optional[float] = None,
        enabled: bool = True,
    ) -> None:
        self.api_url = api_url or os.environ.get("TBOT_LOCAL_API_URL", "http://127.0.0.1:8008/decision")
        self.runroot = runroot or os.environ.get("TBOT_RUNROOT", "")
        self.min_gap_sec = float(min_gap_sec if min_gap_sec is not None else os.environ.get("TBOT_LLM_GATE_MIN_GAP_SEC", "10"))
        self.timeout_sec = float(timeout_sec if timeout_sec is not None else os.environ.get("TBOT_LLM_GATE_TIMEOUT_SEC", "2"))
        self.enabled = enabled and (os.environ.get("TBOT_LLM_GATE_ENABLED", "1") == "1")

        self._last_call_ts: Dict[str, float] = {}
        self._consecutive_errors = 0
        self._max_consecutive_errors = int(os.environ.get("TBOT_LLM_GATE_MAX_CONSEC_ERRORS", "10"))

        self._log_path = self._resolve_log_path()

    def _resolve_log_path(self) -> Optional[Path]:
        if not self.runroot:
            return None
        p = Path(self.runroot) / "logs" / "ops"
        p.mkdir(parents=True, exist_ok=True)
        return p / "local_api_decisions.jsonl"

    def _write_jsonl(self, obj: Dict[str, Any]) -> None:
        if not self._log_path:
            return
        line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
        with self._log_path.open("a", encoding="utf-8") as f:
            f.write(line + "\n")

    def evaluate(self, symbol: str, features: Dict[str, Any], meta: Optional[Dict[str, Any]] = None) -> LlmGateResult:
        symbol_u = (symbol or "UNKNOWN").strip().upper() or "UNKNOWN"
        meta = dict(meta or {})
        phase = meta.get("phase", "PHASE_1_ADVISORY_ONLY")

        trace_id = str(meta.get("trace_id") or uuid.uuid4())
        meta["trace_id"] = trace_id
        meta["symbol"] = symbol_u
        meta["phase"] = phase
        if "ts" not in meta:
            meta["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")

        if not self.enabled:
            res = LlmGateResult(
                ok=True, decision="DENY", reason="llm_gate_disabled",
                trace_id=trace_id, symbol=symbol_u, ttl_sec=0, model_confidence=0.0,
                latency_ms=0.0, raw=None
            )
            self._write_jsonl({"ts": meta["ts"], "trace_id": trace_id, "symbol": symbol_u, "phase": phase,
                               "request": {"features": features, "meta": meta}, "response": asdict(res), "ok": True})
            return res

        now = time.time()
        last = self._last_call_ts.get(symbol_u)
        if last is not None and (now - last) < self.min_gap_sec:
            res = LlmGateResult(
                ok=True, decision="DENY", reason="rate_limited",
                trace_id=trace_id, symbol=symbol_u, ttl_sec=0, model_confidence=0.0,
                latency_ms=0.0, raw=None
            )
            self._write_jsonl({"ts": meta["ts"], "trace_id": trace_id, "symbol": symbol_u, "phase": phase,
                               "request": {"features": features, "meta": meta}, "response": asdict(res), "ok": True})
            return res

        payload = {"features": features, "meta": meta}
        t0 = time.time()
        try:
            req = urllib.request.Request(
                self.api_url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=self.timeout_sec) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                data = json.loads(body) if body else {}
            self._last_call_ts[symbol_u] = now

            latency_ms = (time.time() - t0) * 1000.0
            decision = str(data.get("decision", "DENY")).upper()
            reason = str(data.get("reason", "missing_reason"))
            ttl_sec = int(data.get("ttl_sec", 0) or 0)
            model_conf = float(data.get("model_confidence", 0.0) or 0.0)
            raw = data.get("raw", None)

            if decision not in ("ALLOW", "DENY"):
                decision = "DENY"
                reason = "invalid_decision"

            res = LlmGateResult(
                ok=True, decision=decision, reason=reason,
                trace_id=str(data.get("trace_id") or trace_id),
                symbol=str(data.get("symbol") or symbol_u),
                ttl_sec=ttl_sec, model_confidence=model_conf,
                latency_ms=latency_ms, raw=raw
            )
            self._consecutive_errors = 0
            self._write_jsonl({"ts": meta["ts"], "trace_id": trace_id, "symbol": symbol_u, "phase": phase,
                               "request": payload, "response": data, "ok": True})
            return res

        except Exception as e:
            latency_ms = (time.time() - t0) * 1000.0
            self._consecutive_errors += 1
            if self._consecutive_errors >= self._max_consecutive_errors:
                self.enabled = False

            res = LlmGateResult(
                ok=False, decision="DENY", reason="api_error",
                trace_id=trace_id, symbol=symbol_u, ttl_sec=0, model_confidence=0.0,
                latency_ms=latency_ms, raw=None, error=str(e)
            )
            self._write_jsonl({"ts": meta["ts"], "trace_id": trace_id, "symbol": symbol_u, "phase": phase,
                               "request": payload, "response": None, "ok": False, "error": str(e)})
            return res
