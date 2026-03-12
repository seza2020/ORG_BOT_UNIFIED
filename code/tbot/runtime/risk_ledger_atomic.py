import os, json, time, uuid

def _today():
    return time.strftime("%Y-%m-%d")

def _lock_acquire(lock_path, timeout_sec=5.0, poll=0.05):
    t0 = time.time()
    while True:
        try:
            fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
            os.write(fd, str(os.getpid()).encode("utf-8", "ignore"))
            return fd
        except FileExistsError:
            if time.time() - t0 >= timeout_sec:
                raise TimeoutError(f"LOCK_TIMEOUT:{lock_path}")
            time.sleep(poll)

def _lock_release(fd, lock_path):
    try:
        os.close(fd)
    finally:
        try:
            os.remove(lock_path)
        except Exception:
            pass

def _atomic_write_json(path, obj):
    tmp = path + ".tmp." + uuid.uuid4().hex
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)

def _load_or_init(ledger_path, max_day_risk_default=500.0):
    if not os.path.exists(ledger_path):
        obj = {
            "date": _today(),
            "max_day_risk": float(max_day_risk_default),
            "used_risk": 0.0,
            "reserved_risk": 0.0,
            "reservations": {},  # id -> {ts,risk,sid,symbol}
            "commits": []        # list of {ts,id,risk,sid,symbol}
        }
        _atomic_write_json(ledger_path, obj)
        return obj
    with open(ledger_path, "r", encoding="utf-8") as f:
        obj = json.load(f)
    # backfill for older ledgers
    obj.setdefault("reserved_risk", 0.0)
    obj.setdefault("reservations", {})
    obj.setdefault("commits", [])
    obj.setdefault("used_risk", float(obj.get("used_risk", 0.0)))
    return obj

def _resolve_ledger_path(runroot):
    return os.path.join(runroot, "state", "risk", "risk_ledger.json")

def _roll_day_if_needed(led):
    if str(led.get("date")) != _today():
        led["date"] = _today()
        led["used_risk"] = 0.0
        led["reserved_risk"] = 0.0
        led["reservations"] = {}
        led["commits"] = []

def reserve_preaccept(runroot, risk_usd, reservation_id, sid=None, symbol=None):
    if runroot is None:
        return (False, "RISK_LEDGER_NO_RUNROOT", None)
    try:
        r = float(risk_usd)
    except Exception:
        return (False, "RISK_MISSING_OR_INVALID", None)
    if r <= 0:
        return (False, "RISK_NONPOSITIVE", None)
    if not reservation_id:
        return (False, "RESERVATION_ID_MISSING", None)

    ledger_path = _resolve_ledger_path(runroot)
    lock_path = ledger_path + ".lock"
    fd = _lock_acquire(lock_path, timeout_sec=5.0)
    try:
        led = _load_or_init(ledger_path)
        _roll_day_if_needed(led)

        max_day = float(led.get("max_day_risk", 0.0))
        used = float(led.get("used_risk", 0.0))
        reserved = float(led.get("reserved_risk", 0.0))

        # idempotent reserve
        if reservation_id in led["reservations"]:
            snap = {"date": led["date"], "max_day_risk": max_day, "used_risk": used, "reserved_risk": reserved}
            return (True, None, snap)

        if used + reserved + r > max_day + 1e-9:
            snap = {"date": led["date"], "max_day_risk": max_day, "used_risk": used, "reserved_risk": reserved}
            return (False, "DAILY_RISK_CAP_REJECT", snap)

        led["reservations"][reservation_id] = {"ts": time.time(), "risk_usd": r, "sid": sid, "symbol": symbol}
        led["reserved_risk"] = reserved + r
        _atomic_write_json(ledger_path, led)
        snap = {"date": led["date"], "max_day_risk": max_day, "used_risk": used, "reserved_risk": float(led["reserved_risk"])}
        return (True, None, snap)
    finally:
        _lock_release(fd, lock_path)

def commit_after_accept(runroot, reservation_id):
    if runroot is None:
        return (False, "RISK_LEDGER_NO_RUNROOT", None)
    if not reservation_id:
        return (False, "RESERVATION_ID_MISSING", None)

    ledger_path = _resolve_ledger_path(runroot)
    lock_path = ledger_path + ".lock"
    fd = _lock_acquire(lock_path, timeout_sec=5.0)
    try:
        led = _load_or_init(ledger_path)
        _roll_day_if_needed(led)

        used = float(led.get("used_risk", 0.0))
        reserved = float(led.get("reserved_risk", 0.0))

        rec = led["reservations"].get(reservation_id)
        if rec is None:
            return (False, "RESERVATION_NOT_FOUND", {"used_risk": used, "reserved_risk": reserved})

        r = float(rec.get("risk_usd", 0.0))
        # idempotent commit: if already committed, treat ok
        for c in led["commits"]:
            if c.get("id") == reservation_id:
                snap = {"used_risk": used, "reserved_risk": reserved}
                return (True, None, snap)

        led["commits"].append({"ts": time.time(), "id": reservation_id, "risk_usd": r, "sid": rec.get("sid"), "symbol": rec.get("symbol")})
        led["used_risk"] = used + r
        led["reserved_risk"] = max(0.0, reserved - r)
        led["reservations"].pop(reservation_id, None)
        _atomic_write_json(ledger_path, led)
        snap = {"used_risk": float(led["used_risk"]), "reserved_risk": float(led["reserved_risk"])}
        return (True, None, snap)
    finally:
        _lock_release(fd, lock_path)

def release_reservation(runroot, reservation_id):
    if runroot is None:
        return (False, "RISK_LEDGER_NO_RUNROOT", None)
    if not reservation_id:
        return (False, "RESERVATION_ID_MISSING", None)

    ledger_path = _resolve_ledger_path(runroot)
    lock_path = ledger_path + ".lock"
    fd = _lock_acquire(lock_path, timeout_sec=5.0)
    try:
        led = _load_or_init(ledger_path)
        _roll_day_if_needed(led)

        reserved = float(led.get("reserved_risk", 0.0))
        rec = led["reservations"].pop(reservation_id, None)
        if rec is None:
            return (True, None, {"reserved_risk": reserved})
        r = float(rec.get("risk_usd", 0.0))
        led["reserved_risk"] = max(0.0, reserved - r)
        _atomic_write_json(ledger_path, led)
        return (True, None, {"reserved_risk": float(led["reserved_risk"])})
    finally:
        _lock_release(fd, lock_path)

def reconcile_ttl(runroot, ttl_sec=900.0):
    """Release stale reservations older than ttl_sec."""
    if runroot is None:
        return (False, "RISK_LEDGER_NO_RUNROOT", None)
    ledger_path = _resolve_ledger_path(runroot)
    lock_path = ledger_path + ".lock"
    fd = _lock_acquire(lock_path, timeout_sec=5.0)
    try:
        led = _load_or_init(ledger_path)
        _roll_day_if_needed(led)
        now = time.time()
        reserved = float(led.get("reserved_risk", 0.0))
        released = []
        for rid, rec in list(led["reservations"].items()):
            if now - float(rec.get("ts", now)) >= ttl_sec:
                r = float(rec.get("risk_usd", 0.0))
                led["reservations"].pop(rid, None)
                reserved = max(0.0, reserved - r)
                released.append(rid)
        led["reserved_risk"] = reserved
        _atomic_write_json(ledger_path, led)
        return (True, None, {"released": released, "reserved_risk": float(reserved)})
    finally:
        _lock_release(fd, lock_path)
