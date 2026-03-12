import os, sys, json, time, argparse, datetime
if os.name == "nt":
    import msvcrt

def _now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

def _rt_root(root, profile):
    return os.path.join(root, "runtime", profile.lower())

def _paths(root, profile):
    rt = _rt_root(root, profile)
    state = os.path.join(rt, "state")
    locks = os.path.join(state, "locks")
    os.makedirs(locks, exist_ok=True)
    ledger = os.path.join(state, "risk_ledger.atomic.json")
    lockf  = os.path.join(locks, "risk_ledger.lock")
    return rt, state, locks, ledger, lockf

def _lock_open(lock_path):
    f = open(lock_path, "a+b")
    if os.name == "nt":
        msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)
    return f

def _lock_close(f):
    try:
        if os.name == "nt":
            f.seek(0)
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
    finally:
        f.close()

def _atomic_write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as w:
        json.dump(data, w, ensure_ascii=False, indent=2)
        w.flush()
        os.fsync(w.fileno())
    os.replace(tmp, path)

def load_or_init(root, profile):
    rt, state, locks, ledger, lockf = _paths(root, profile)
    base = {
        "schema": "atomic_risk_ledger_v1",
        "profile": profile.upper(),
        "root": root,
        "created_at": _now(),
        "updated_at": _now(),
        "run_id": os.environ.get("TBOT_RUN_ID") or "",
        "limits": {
            "daily_max_r": float(os.environ.get("TBOT_DAILY_KILL_R") or "-2.0"),
            "weekly_max_r": float(os.environ.get("TBOT_WEEKLY_KILL_R") or "-5.0"),
            "max_risk_usd": float(os.environ.get("TBOT_GATE_MAX_RISK_USD") or "500")
        },
        "state": {
            "daily_r": 0.0,
            "weekly_r": 0.0,
            "open_risk_usd": 0.0
        },
        "events": []
    }
    if os.path.exists(ledger):
        try:
            with open(ledger, "r", encoding="utf-8") as r:
                return json.load(r), ledger, lockf
        except Exception:
            # fail-safe: refuse corrupted ledger
            raise RuntimeError("RISK_LEDGER_CORRUPT")
    return base, ledger, lockf

def cmd_init(args):
    data, ledger, lockf = load_or_init(args.root, args.profile)
    lf = _lock_open(lockf)
    try:
        data["updated_at"] = _now()
        data["events"].append({"ts": _now(), "kind": "init", "msg": "ledger_init"})
        _atomic_write_json(ledger, data)
    finally:
        _lock_close(lf)
    print("OK INIT", ledger)

def cmd_snapshot(args):
    data, ledger, lockf = load_or_init(args.root, args.profile)
    print(json.dumps(data, ensure_ascii=False, indent=2))

def cmd_add_event(args):
    data, ledger, lockf = load_or_init(args.root, args.profile)
    lf = _lock_open(lockf)
    try:
        data["updated_at"] = _now()
        data["events"].append({"ts": _now(), "kind": args.kind, "msg": args.msg})
        _atomic_write_json(ledger, data)
    finally:
        _lock_close(lf)
    print("OK EVENT", args.kind)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=r"C:\alpaca-bot\ORG_BOT_UNIFIED")
    ap.add_argument("--profile", default="PAPER", choices=["PAPER","SHADOW","LIVE"])
    sp = ap.add_subparsers(dest="cmd", required=True)

    p0 = sp.add_parser("init")
    p0.set_defaults(func=cmd_init)

    p1 = sp.add_parser("snapshot")
    p1.set_defaults(func=cmd_snapshot)

    p2 = sp.add_parser("event")
    p2.add_argument("--kind", required=True)
    p2.add_argument("--msg", required=True)
    p2.set_defaults(func=cmd_add_event)

    args = ap.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()
