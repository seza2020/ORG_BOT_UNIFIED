from __future__ import annotations

import json
import os
import time

class AtomicRiskGuard:
    """
    Atomic daily risk budget reservation per profile/runroot.

    Files in state_dir:
      - risk_guard_state.json
      - risk_guard_state.lock  (O_EXCL)
      - risk_guard_journal.jsonl (append best-effort)

    Fail-closed: reserve() returns (False, reason) on lock/IO failure.
    """

    def __init__(self, state_dir: str, budget_usd: float, lock_timeout_sec: float = 2.0):
        self.state_dir = os.path.abspath(state_dir)
        self.budget_usd = float(budget_usd)
        self.lock_timeout_sec = float(lock_timeout_sec)

        os.makedirs(self.state_dir, exist_ok=True)
        self.state_path = os.path.join(self.state_dir, "risk_guard_state.json")
        self.lock_path  = os.path.join(self.state_dir, "risk_guard_state.lock")
        self.journal_path = os.path.join(self.state_dir, "risk_guard_journal.jsonl")

    def _now(self) -> float:
        return time.time()

    def _day_key(self) -> str:
        return time.strftime("%Y-%m-%d", time.localtime())

    def _journal(self, obj: dict) -> None:
        try:
            with open(self.journal_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
        except Exception:
            pass

    def _load(self) -> dict:
        if not os.path.exists(self.state_path):
            return {"day": self._day_key(), "reserved_total": 0.0, "reservations": {}}
        with open(self.state_path, "r", encoding="utf-8") as f:
            s = json.load(f)
        if not isinstance(s, dict):
            raise ValueError("state_not_dict")
        if s.get("day") != self._day_key():
            return {"day": self._day_key(), "reserved_total": 0.0, "reservations": {}}
        s.setdefault("reserved_total", 0.0)
        s.setdefault("reservations", {})
        return s

    def _save(self, s: dict) -> None:
        tmp = self.state_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(s, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.state_path)

    def _acq(self) -> bool:
        t0 = self._now()
        while (self._now() - t0) < self.lock_timeout_sec:
            try:
                fd = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, str(os.getpid()).encode("utf-8"))
                os.close(fd)
                return True
            except FileExistsError:
                time.sleep(0.05)
            except Exception:
                return False
        return False

    def _rel(self) -> None:
        try:
            os.remove(self.lock_path)
        except Exception:
            pass

    def reserve(self, plan_id: str, risk_usd: float) -> tuple[bool, str]:
        risk = float(risk_usd)
        if risk <= 0:
            return (False, "RISK_NONPOSITIVE")
        if not plan_id:
            return (False, "PLAN_ID_EMPTY")

        if not self._acq():
            self._journal({"ts": self._now(), "ev": "reserve", "ok": False, "reason": "LOCK_TIMEOUT", "plan_id": plan_id, "risk": risk})
            return (False, "LOCK_TIMEOUT")

        try:
            s = self._load()
            if plan_id in s["reservations"]:
                return (True, "ALREADY_RESERVED")
            reserved = float(s.get("reserved_total", 0.0))
            if reserved + risk > self.budget_usd + 1e-9:
                self._journal({"ts": self._now(), "ev": "reserve", "ok": False, "reason": "BUDGET_EXCEEDED", "plan_id": plan_id, "risk": risk, "reserved": reserved, "budget": self.budget_usd})
                return (False, "BUDGET_EXCEEDED")

            s["reservations"][plan_id] = {"risk": risk, "ts": self._now()}
            s["reserved_total"] = reserved + risk
            self._save(s)

            self._journal({"ts": self._now(), "ev": "reserve", "ok": True, "plan_id": plan_id, "risk": risk, "reserved_total": s["reserved_total"], "budget": self.budget_usd})
            return (True, "OK")
        except Exception as e:
            self._journal({"ts": self._now(), "ev": "reserve", "ok": False, "reason": "IO_FAIL", "plan_id": plan_id, "risk": risk, "err": repr(e)})
            return (False, "IO_FAIL")
        finally:
            self._rel()

    def release(self, plan_id: str) -> tuple[bool, str]:
        if not plan_id:
            return (False, "PLAN_ID_EMPTY")
        if not self._acq():
            self._journal({"ts": self._now(), "ev": "release", "ok": False, "reason": "LOCK_TIMEOUT", "plan_id": plan_id})
            return (False, "LOCK_TIMEOUT")

        try:
            s = self._load()
            if plan_id not in s["reservations"]:
                return (True, "NOT_FOUND")
            risk = float(s["reservations"][plan_id].get("risk", 0.0))
            del s["reservations"][plan_id]
            s["reserved_total"] = max(0.0, float(s.get("reserved_total", 0.0)) - risk)
            self._save(s)

            self._journal({"ts": self._now(), "ev": "release", "ok": True, "plan_id": plan_id, "risk": risk, "reserved_total": s["reserved_total"]})
            return (True, "OK")
        except Exception as e:
            self._journal({"ts": self._now(), "ev": "release", "ok": False, "reason": "IO_FAIL", "plan_id": plan_id, "err": repr(e)})
            return (False, "IO_FAIL")
        finally:
            self._rel()

def make_guard(runroot: str, budget_usd: float) -> AtomicRiskGuard:
    state_dir = os.path.join(os.path.abspath(runroot), "state", "risk")
    return AtomicRiskGuard(state_dir=state_dir, budget_usd=float(budget_usd))
