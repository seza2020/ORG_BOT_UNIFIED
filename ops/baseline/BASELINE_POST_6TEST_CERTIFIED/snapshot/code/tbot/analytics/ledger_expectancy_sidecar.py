from __future__ import annotations

import json
import os
import time
from urllib.request import Request, urlopen

def _now() -> float:
    return time.time()

def _profile() -> str:
    return (os.environ.get("TBOT_PROFILE") or "paper").strip().lower()

def _runroot() -> str:
    rr = (os.environ.get("TBOT_RUNROOT") or "").strip()
    if rr:
        return rr
    root = (os.environ.get("TBOT_UNIFIED_ROOT") or "").strip()
    if root:
        return os.path.join(root, "runtime", _profile())
    # last resort (matches your known layout)
    return os.path.join(r"C:\alpaca-bot\ORG_BOT_UNIFIED", "runtime", _profile())

def _trade_base() -> str:
    b = (os.environ.get("TBOT_ALPACA_TRADE_BASE") or "").strip()
    if b:
        return b.rstrip("/")
    b = (os.environ.get("APCA_API_BASE_URL") or "").strip()
    if b:
        return b.rstrip("/")
    # paper/shadow both use paper endpoint
    if _profile() in ("paper","shadow"):
        return "https://paper-api.alpaca.markets"
    return "https://api.alpaca.markets"

def _headers():
    kid = (os.environ.get("APCA_API_KEY_ID") or os.environ.get("ALPACA_API_KEY") or "").strip()
    sec = (os.environ.get("APCA_API_SECRET_KEY") or os.environ.get("ALPACA_API_SECRET_KEY") or "").strip()
    if not kid or not sec:
        return None
    return {
        "APCA-API-KEY-ID": kid,
        "APCA-API-SECRET-KEY": sec,
        "Accept": "application/json",
        "User-Agent": "tbot-ledger-sidecar/1.0",
    }

def _get_json(url: str, headers: dict, timeout: float = 5.0):
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=timeout) as r:
        raw = r.read().decode("utf-8", errors="replace")
    return json.loads(raw)

def _append_jsonl(path: str, obj: dict):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        pass

def _write_json(path: str, obj: dict):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        pass

def _tail_jsonl(path: str, max_lines: int = 5000):
    # simple tail: read whole if small; good enough for sidecar
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        return [json.loads(x) for x in lines[-max_lines:] if x.strip()]
    except Exception:
        return []

def _compute_metrics(trades: list[dict]) -> dict:
    # trades expected to have realized_pl (float-ish)
    pl = []
    for t in trades:
        try:
            v = t.get("realized_pl")
            if v is None:
                continue
            pl.append(float(v))
        except Exception:
            continue

    n = len(pl)
    if n == 0:
        return {
            "n_trades": 0,
            "win_rate": None,
            "avg_win": None,
            "avg_loss": None,
            "profit_factor": None,
            "expectancy": None,
            "sum_pl": None,
        }

    wins = [x for x in pl if x > 0]
    losses = [x for x in pl if x < 0]

    win_rate = (len(wins) / n) if n else None
    avg_win = (sum(wins) / len(wins)) if wins else 0.0
    avg_loss = (sum(losses) / len(losses)) if losses else 0.0  # negative or 0
    gross_profit = sum(wins) if wins else 0.0
    gross_loss = -sum(losses) if losses else 0.0
    pf = (gross_profit / gross_loss) if gross_loss > 0 else None
    expectancy = (sum(pl) / n) if n else None

    return {
        "n_trades": n,
        "win_rate": win_rate,
        "avg_win": avg_win,
        "avg_loss": avg_loss,
        "profit_factor": pf,
        "expectancy": expectancy,
        "sum_pl": sum(pl),
    }

def run(loop_sec: float = 10.0, duration_sec: float | None = None):
    h = _headers()
    if h is None:
        print("NO_API_KEYS_IN_ENV")
        return 2

    base = _trade_base()
    rr = _runroot()
    out_dir = os.path.join(rr, "analytics")
    fills_path = os.path.join(out_dir, "fills.jsonl")
    trades_path = os.path.join(out_dir, "trades.jsonl")
    expect_path = os.path.join(out_dir, "expectancy.json")
    hist_path = os.path.join(out_dir, "expectancy_history.jsonl")

    # watermark to avoid duplicate appends on restart
    wm_path = os.path.join(out_dir, "ledger_watermark.json")
    wm = {"last_activity_id": None, "ts": _now()}
    try:
        if os.path.exists(wm_path):
            with open(wm_path, "r", encoding="utf-8") as f:
                wm = json.load(f) or wm
    except Exception:
        pass

    t0 = _now()
    while True:
        t = _now()
        if duration_sec is not None and (t - t0) >= float(duration_sec):
            break

        try:
            # activities: pulls fills + trades info (best-effort)
            # Alpaca activities endpoint (v2): /v2/account/activities?activity_types=FILL
            url = f"{base}/v2/account/activities?activity_types=FILL&direction=desc&page_size=100"
            acts = _get_json(url, h, timeout=5.0)

            if isinstance(acts, list) and acts:
                # acts newest->oldest; append until watermark hit
                new = []
                last_id = wm.get("last_activity_id")
                for a in acts:
                    if not isinstance(a, dict):
                        continue
                    if last_id is not None and a.get("id") == last_id:
                        break
                    new.append(a)

                if new:
                    # append oldest->newest for readability
                    for a in reversed(new):
                        _append_jsonl(fills_path, {"ts": t, "base": base, "profile": _profile(), "fill": a})
                    wm["last_activity_id"] = new[0].get("id")  # newest id
                    wm["ts"] = t
                    _write_json(wm_path, wm)

                    # naive realized trade aggregation:
                    # Use 'net_amount' if present; otherwise 0 (still logs)
                    for a in reversed(new):
                        try:
                            realized = None
                            if "net_amount" in a:
                                realized = float(a.get("net_amount"))
                            trade = {
                                "ts": t,
                                "profile": _profile(),
                                "activity_id": a.get("id"),
                                "symbol": a.get("symbol"),
                                "side": a.get("side"),
                                "qty": a.get("qty"),
                                "price": a.get("price"),
                                "realized_pl": realized,
                            }
                            _append_jsonl(trades_path, trade)
                        except Exception:
                            pass

            # compute expectancy snapshot
            trades = _tail_jsonl(trades_path, max_lines=5000)
            metrics = _compute_metrics(trades)
            snap = {"ts": t, "profile": _profile(), "metrics": metrics}
            _write_json(expect_path, snap)
            _append_jsonl(hist_path, snap)

        except Exception:
            pass

        time.sleep(float(loop_sec))

    print("DONE")
    print("RUNROOT=", rr)
    print("OUTDIR=", out_dir)
    return 0

if __name__ == "__main__":
    loop = float((os.environ.get("TBOT_LEDGER_TICK_SEC") or "10").strip() or "10")
    dur  = os.environ.get("TBOT_LEDGER_DURATION_SEC")
    duration = float(dur) if dur else None
    raise SystemExit(run(loop_sec=loop, duration_sec=duration))
