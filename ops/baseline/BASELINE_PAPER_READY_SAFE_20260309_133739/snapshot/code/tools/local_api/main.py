# === LOCAL_DECISION_GATEWAY_V1 ===
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Any, Dict, Optional
import uuid
import time

app = FastAPI(title="Local Decision Gateway", version="1.0")

class DecisionReq(BaseModel):
    features: dict = {}
    meta: dict = {}

    # Optional fields (backward compatible)
    trace_id: Optional[str] = None

    def get_symbol(self) -> str:
        try:
            sym = self.meta.get("symbol", None)
            if sym is None:
                return "UNKNOWN"
            s = str(sym).strip().upper()
            return s if s else "UNKNOWN"
        except Exception:
            return "UNKNOWN"

    def get_trace_id(self) -> str:
        # Order: explicit field -> meta.trace_id -> generated
        if self.trace_id and str(self.trace_id).strip():
            return str(self.trace_id).strip()
        try:
            t = self.meta.get("trace_id", None)
            if t and str(t).strip():
                return str(t).strip()
        except Exception:
            pass
        return str(uuid.uuid4())

    def get_phase(self) -> str:
        try:
            p = self.meta.get("phase", "PHASE_1_ADVISORY_ONLY")
            return str(p)
        except Exception:
            return "PHASE_1_ADVISORY_ONLY"
class DecisionResp(BaseModel):
    decision: str
    reason: str

    # Added fields (backward compatible for consumers that ignore unknown fields)
    trace_id: str
    symbol: str
    ttl_sec: int = 30
    model_confidence: float = 0.5

    latency_ms: float = 0.0
    raw: Optional[dict] = None
@app.get("/health")
def health():
    return {"ok": True, "service": "local_decision_gateway", "version": "1.0"}

@app.post("/decision")
def decision(req: DecisionReq):
    t0 = time.time()

    # ---- Phase 1: advisory-only baseline decision (keep your existing policy logic if any) ----
    decision = "ALLOW"
    reason = "baseline_allow"
    model_conf = 0.5
    ttl = 30

    trace_id = req.get_trace_id()
    symbol = req.get_symbol()

    latency_ms = (time.time() - t0) * 1000.0

    return DecisionResp(
        decision=decision,
        reason=reason,
        trace_id=trace_id,
        symbol=symbol,
        ttl_sec=ttl,
        model_confidence=model_conf,
        latency_ms=latency_ms,
        raw={"policy": "baseline_allow"},
    )


