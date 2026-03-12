from __future__ import annotations

import json
import os
import time
from urllib.request import Request, urlopen
from typing import Any, Dict, Optional, Tuple

def _now() -> float:
    return time.time()

def _trade_base(profile: str) -> str:
    b = (os.environ.get("TBOT_ALPACA_TRADE_BASE") or "").strip()
    if b:
        return b.rstrip("/")
    b = (os.environ.get("APCA_API_BASE_URL") or "").strip()
    if b:
        return b.rstrip("/")
    p = (profile or "").strip().lower()
    if p in ("paper", "shadow"):
        return "https://paper-api.alpaca.markets"
    return "https://api.alpaca.markets"

def _headers() -> Optional[Dict[str, str]]:
    kid = (os.environ.get("APCA_API_KEY_ID") or os.environ.get("ALPACA_API_KEY") or "").strip()
    sec = (os.environ.get("APCA_API_SECRET_KEY") or os.environ.get("ALPACA_API_SECRET_KEY") or "").strip()
    if not kid or not sec:
        return None
    return {
        "APCA-API-KEY-ID": kid,
        "APCA-API-SECRET-KEY": sec,
        "Accept": "application/json",
        "User-Agent": "tbot-portfolio-governor/1.0",
    }

def _get_json(url: str, headers: Dict[str, str], timeout: float = 3.0) -> Any:
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=timeout) as r:
        raw = r.read().decode("utf-8", errors="replace")
    return json.loads(raw)

def _safe_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None

def _runroot() -> str:
    rr = (os.environ.get("TBOT_RUNROOT") or "").strip()
    if rr:
        return rr
    root = (os.environ.get("TBOT_UNIFIED_ROOT") or "").strip()
    prof = (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()
    if root:
        return os.path.join(root, "runtime", prof)
    return os.path.join(r"C:\alpaca-bot\ORG_BOT_UNIFIED", "runtime", prof)

def _read_json(path: str) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            o = json.load(f)
        return o if isinstance(o, dict) else None
    except Exception:
        return None

def _write_json(path: str, obj: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)

def _append_jsonl(path: str, obj: Dict[str, Any]) -> None:
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _default_cfg() -> Dict[str, Any]:
    return {
        "max_positions": 8,
        "max_symbol_concentration_pct": 0.35,  # max(|mv_symbol|)/equity
        "max_gross_exposure_pct": 1.20,         # sum(|mv|)/equity
        "max_net_exposure_pct": 0.80,           # |sum(mv)|/equity
        "max_leverage": 1.25,                   # gross exposure proxy
        "fail_closed_if_no_keys": False,        # if True and keys missing => kill
        "profile": (os.environ.get("TBOT_PROFILE") or "paper").strip().lower(),
    }

def assess_portfolio(profile: str, cfg: Dict[str, Any]) -> Dict[str, Any]:
    h = _headers()
    if h is None:
        ok = not bool(cfg.get("fail_closed_if_no_keys", False))
        return {
            "ts": _now(),
            "ok": ok,
            "reason": "NO_API_KEYS",
            "limits": cfg,
            "account": None,
            "positions": None,
            "metrics": None,
        }

    base = _trade_base(profile)
    acct = _get_json(f"{base}/v2/account", h, timeout=3.0)
    pos  = _get_json(f"{base}/v2/positions", h, timeout=3.0)

    equity = _safe_float(acct.get("equity")) or _safe_float(acct.get("portfolio_value")) or 0.0
    if equity <= 0:
        equity = 0.0

    positions = []
    gross = 0.0
    net = 0.0
    max_sym_abs = 0.0
    max_sym = None

    if isinstance(pos, list):
        for p in pos:
            if not isinstance(p, dict):
                continue
            sym = (p.get("symbol") or "UNKNOWN").strip().upper()
            mv  = _safe_float(p.get("market_value"))
            if mv is None:
                # fallback: qty * current_price
                q = _safe_float(p.get("qty"))
                cp = _safe_float(p.get("current_price"))
                if q is not None and cp is not None:
                    mv = q * cp
            if mv is None:
                continue
            gross += abs(mv)
            net += mv
            if abs(mv) > max_sym_abs:
                max_sym_abs = abs(mv)
                max_sym = sym
            positions.append({
                "symbol": sym,
                "qty": p.get("qty"),
                "side": p.get("side"),
                "market_value": mv,
                "avg_entry_price": p.get("avg_entry_price"),
                "current_price": p.get("current_price"),
                "unrealized_pl": p.get("unrealized_pl"),
                "unrealized_plpc": p.get("unrealized_plpc"),
            })

    npos = len(positions)
    if equity > 0:
        gross_pct = gross / equity
        net_pct = abs(net) / equity
        sym_pct = max_sym_abs / equity
    else:
        gross_pct = None
        net_pct = None
        sym_pct = None

    limits = cfg
    max_positions = int(limits.get("max_positions", 0) or 0)
    max_sym_pct = float(limits.get("max_symbol_concentration_pct", 0.0) or 0.0)
    max_gross_pct = float(limits.get("max_gross_exposure_pct", 0.0) or 0.0)
    max_net_pct = float(limits.get("max_net_exposure_pct", 0.0) or 0.0)
    max_lev = float(limits.get("max_leverage", 0.0) or 0.0)

    breaches = []
    if max_positions > 0 and npos > max_positions:
        breaches.append("MAX_POSITIONS")
    if equity > 0:
        if max_sym_pct > 0 and sym_pct is not None and sym_pct > max_sym_pct + 1e-9:
            breaches.append("MAX_SYMBOL_CONCENTRATION")
        if max_gross_pct > 0 and gross_pct is not None and gross_pct > max_gross_pct + 1e-9:
            breaches.append("MAX_GROSS_EXPOSURE")
        if max_net_pct > 0 and net_pct is not None and net_pct > max_net_pct + 1e-9:
            breaches.append("MAX_NET_EXPOSURE")
        if max_lev > 0 and gross_pct is not None and gross_pct > max_lev + 1e-9:
            breaches.append("MAX_LEVERAGE_PROXY")

    ok = (len(breaches) == 0)

    return {
        "ts": _now(),
        "ok": ok,
        "reason": "OK" if ok else "BREACH",
        "breaches": breaches,
        "limits": limits,
        "account": {
            "equity": acct.get("equity"),
            "portfolio_value": acct.get("portfolio_value"),
            "cash": acct.get("cash"),
            "buying_power": acct.get("buying_power"),
        },
        "metrics": {
            "equity": equity,
            "n_positions": npos,
            "gross_exposure": gross,
            "net_exposure": net,
            "gross_exposure_pct": gross_pct,
            "net_exposure_pct": net_pct,
            "max_symbol": max_sym,
            "max_symbol_abs_mv": max_sym_abs,
            "max_symbol_pct": sym_pct,
        },
        "positions": positions,
        "base": base,
        "profile": profile,
    }

def apply(meta=None) -> Dict[str, Any]:
    rr = _runroot()
    ana = os.path.join(rr, "analytics")
    logs = os.path.join(rr, "logs")
    os.makedirs(ana, exist_ok=True)
    os.makedirs(logs, exist_ok=True)

    cfg_path = os.path.join(ana, "portfolio_risk_config.json")
    cfg = _read_json(cfg_path) or _default_cfg()
    # persist cfg if missing
    if not os.path.exists(cfg_path):
        try:
            _write_json(cfg_path, cfg)
        except Exception:
            pass

    prof = (cfg.get("profile") or os.environ.get("TBOT_PROFILE") or "paper").strip().lower()
    rep = assess_portfolio(prof, cfg)

    rep_path = os.path.join(ana, "portfolio_risk_report.json")
    _write_json(rep_path, rep)

    hist = os.path.join(ana, "portfolio_risk_history.jsonl")
    _append_jsonl(hist, rep)

    # kill file (fail-safe for gates)
    kill_path = os.path.join(ana, "portfolio_kill.json")
    if not rep.get("ok", False):
        kill = {
            "ts": rep.get("ts"),
            "kill": True,
            "reason": "PORTFOLIO_RISK_BREACH",
            "breaches": rep.get("breaches", []),
            "metrics": rep.get("metrics", {}),
        }
        _write_json(kill_path, kill)
    else:
        # clear kill if exists
        try:
            if os.path.exists(kill_path):
                os.remove(kill_path)
        except Exception:
            pass

    # meta event best-effort
    try:
        if meta is not None:
            meta.write("portfolio_risk", rep)
    except Exception:
        pass

    return {
        "ok": True,
        "runroot": rr,
        "cfg": cfg_path,
        "report": rep_path,
        "history": hist,
        "kill_file": kill_path,
    }

def main():
    out = apply(meta=None)
    print("OK")
    for k,v in out.items():
        print(f"{k}={v}")

if __name__ == "__main__":
    main()
