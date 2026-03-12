import os, sys, json, argparse, datetime

def _now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

def _rt(root, profile):
    return os.path.join(root, "runtime", profile.lower())

def _read_jsonl(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8", errors="replace") as r:
        for line in r:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out

def _atomic_write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as w:
        json.dump(data, w, ensure_ascii=False, indent=2)
        w.flush()
        os.fsync(w.fileno())
    os.replace(tmp, path)

def compute_report(root, profile):
    rt = _rt(root, profile)
    logs = os.path.join(rt, "logs")
    reports = os.path.join(rt, "reports")
    trades_path = os.path.join(logs, "trades.jsonl")

    trades = _read_jsonl(trades_path)

    # Expected schema per trade (future integration):
    # { "ts": "...", "r": 1.2 }  or  { "r_mult": 1.2 } or { "R": 1.2 }
    rs = []
    for t in trades:
        r = None
        for k in ("r","r_mult","R","R_mult"):
            if k in t and isinstance(t[k], (int,float)):
                r = float(t[k])
                break
        if r is not None:
            rs.append(r)

    report = {
        "schema": "expectancy_report_v1",
        "profile": profile.upper(),
        "root": root,
        "generated_at": _now(),
        "input": {
            "trades_jsonl": trades_path,
            "trades_found": len(trades),
            "r_values_found": len(rs)
        },
        "metrics": {},
        "status": "OK"
    }

    if len(rs) < 10:
        report["status"] = "NO_DATA"
        report["metrics"] = {
            "note": "Need >=10 trades with R to compute stable expectancy.",
            "expectancy_r": None,
            "win_rate": None,
            "profit_factor": None,
            "avg_win_r": None,
            "avg_loss_r": None
        }
        out = os.path.join(reports, "expectancy_report.json")
        _atomic_write(out, report)
        return out

    wins = [x for x in rs if x > 0]
    losses = [x for x in rs if x < 0]
    win_rate = len(wins) / len(rs)

    avg_win = sum(wins)/len(wins) if wins else 0.0
    avg_loss = sum(losses)/len(losses) if losses else 0.0  # negative
    expectancy = (win_rate * avg_win) + ((1-win_rate) * avg_loss)

    gross_profit = sum(wins)
    gross_loss = abs(sum(losses)) if losses else 0.0
    pf = (gross_profit / gross_loss) if gross_loss > 1e-9 else None

    report["metrics"] = {
        "n": len(rs),
        "expectancy_r": expectancy,
        "win_rate": win_rate,
        "profit_factor": pf,
        "avg_win_r": avg_win,
        "avg_loss_r": avg_loss,
        "sum_r": sum(rs),
        "max_drawdown_r": _max_drawdown(rs)
    }

    out = os.path.join(reports, "expectancy_report.json")
    _atomic_write(out, report)
    return out

def _max_drawdown(rs):
    peak = 0.0
    eq = 0.0
    mdd = 0.0
    for r in rs:
        eq += r
        if eq > peak:
            peak = eq
        dd = eq - peak
        if dd < mdd:
            mdd = dd
    return mdd

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\alpaca-bot\ORG_BOT_UNIFIED")
    ap.add_argument("--profile", default="PAPER", choices=["PAPER","SHADOW","LIVE"])
    ap.add_argument("cmd", choices=["report"])
    args = ap.parse_args()

    if args.cmd == "report":
        out = compute_report(args.root, args.profile)
        print("OK REPORT", out)

if __name__ == "__main__":
    main()
