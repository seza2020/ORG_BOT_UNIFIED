#!/usr/bin/env python3
"""
P0-2.2 Gate Selftest (from scratch, signature-aware)

Fixes the exact failure you hit:
- ShadowGate.evaluate expects (now, plan, *, alpha_kill, portfolio_kill, in_session, pre_close, ...)
- We detect positional params and supply now correctly.

Run:
  python .\tools\p0_2_2_gate_selftest.py
"""

from __future__ import annotations

import sys
import inspect
import datetime as dt
from types import SimpleNamespace
from dataclasses import is_dataclass, fields as dc_fields


def die(msg: str) -> None:
    print("[P0-2.2] FAIL:", msg, file=sys.stderr)
    sys.exit(1)


def ok(msg: str) -> None:
    print("[P0-2.2] OK:", msg)


def mk_plan(risk_usd: float):
    return SimpleNamespace(
        sid="SELFTEST",
        symbol="TEST",
        side="LONG",
        qty=1,
        entry=1.0,
        stop=0.9,
        tp=1.2,
        risk_usd=float(risk_usd),
    )


def find_cfg_class(mod):
    # Prefer dataclass configs first
    candidates = []
    for name, obj in vars(mod).items():
        if inspect.isclass(obj) and obj.__module__ == mod.__name__:
            lname = name.lower()
            if lname.endswith("cfg") or "config" in lname:
                candidates.append((name, obj))
    for name, cls in candidates:
        if is_dataclass(cls):
            return name, cls
    return candidates[0] if candidates else (None, None)


def make_cfg(mod, max_trade: float, max_day, max_plans: int = 999999, cooldown: int = 0):
    cfg_name, cfg_cls = find_cfg_class(mod)

    desired = {
        "max_risk_per_trade_usd": max_trade,
        "max_risk_per_day_usd": max_day,
        "max_plans_per_day": max_plans,
        "gate_cooldown_sec": cooldown,
    }
    aliases = {
        "max_risk_usd": max_trade,
        "cooldown_sec": cooldown,
        "max_plans": max_plans,
        "daily_cap": max_plans,
        "daily_plan_cap": max_plans,
    }

    if cfg_cls is None:
        return "SimpleNamespace", SimpleNamespace(**desired)

    if is_dataclass(cfg_cls):
        fnames = {f.name for f in dc_fields(cfg_cls)}
        kw = {}
        for k, v in desired.items():
            if k in fnames:
                kw[k] = v
        for k, v in aliases.items():
            if k in fnames and k not in kw:
                kw[k] = v
        try:
            return cfg_name, cfg_cls(**kw)  # type: ignore
        except TypeError as e:
            die(f"Could not instantiate dataclass cfg '{cfg_name}' with kwargs={kw}. Error: {e}")

    # Non-dataclass config
    try:
        sig = inspect.signature(cfg_cls)
        kw = {}
        for k, v in desired.items():
            if k in sig.parameters:
                kw[k] = v
        for k, v in aliases.items():
            if k in sig.parameters and k not in kw:
                kw[k] = v
        return cfg_name, cfg_cls(**kw)  # type: ignore
    except Exception:
        obj = cfg_cls()  # type: ignore
        for k, v in desired.items():
            try:
                setattr(obj, k, v)
            except Exception:
                pass
        for k, v in aliases.items():
            try:
                setattr(obj, k, v)
            except Exception:
                pass
        return cfg_name, obj


def pick_gate_method_name(g):
    for name in ("evaluate", "check", "admit", "allow", "decide", "should_allow", "can_accept"):
        fn = getattr(g, name, None)
        if callable(fn):
            return name
    # fallback: first public callable
    for name in dir(g):
        if name.startswith("_"):
            continue
        fn = getattr(g, name, None)
        if callable(fn):
            return name
    return None


def call_gate(g, method_name: str, plan):
    """
    Signature-aware caller:
    - Supplies `now` for positional param names: now/ts/time/dt/when
    - Supplies `plan` for positional param names: plan/shadow_plan
    - Supplies required kw-only context booleans if present
    """
    fn = getattr(g, method_name)
    sig = inspect.signature(fn)
    now = dt.datetime.now(dt.timezone.utc)

    ctx_defaults = {
        "alpha_kill": False,
        "portfolio_kill": False,
        "in_session": True,
        "pre_close": False,
    }

    # Build args in positional order, and kwargs for keyword-only
    args = []
    kwargs = {}

    for p in sig.parameters.values():
        if p.kind in (inspect.Parameter.POSITIONAL_ONLY, inspect.Parameter.POSITIONAL_OR_KEYWORD):
            nm = p.name.lower()
            if nm in ("plan", "shadow_plan"):
                args.append(plan)
            elif nm in ("now", "ts", "time", "dt", "when", "timestamp"):
                args.append(now)
            elif p.name in ctx_defaults:
                args.append(ctx_defaults[p.name])
            else:
                # If it has a default, let it default by not passing (only possible for pos-or-kw).
                # But since we are building args, we must keep ordering; so:
                if p.default is not inspect._empty:
                    args.append(p.default)
                else:
                    # unknown required positional -> safest None
                    args.append(None)

        elif p.kind == inspect.Parameter.KEYWORD_ONLY:
            if p.name in ctx_defaults:
                kwargs[p.name] = ctx_defaults[p.name]
            elif p.default is not inspect._empty:
                # has default, omit
                pass
            else:
                # unknown required keyword-only -> safest False
                kwargs[p.name] = False

    out = fn(*args, **kwargs)

    # normalize output
    allow = None
    reasons = []

    if isinstance(out, bool):
        allow = out
    elif isinstance(out, tuple) and len(out) >= 1:
        allow = bool(out[0])
        if len(out) >= 2:
            r = out[1]
            if isinstance(r, (list, tuple)):
                reasons = list(r)
            elif isinstance(r, str):
                reasons = [r]
    elif isinstance(out, dict):
        if "allow" in out:
            allow = bool(out.get("allow"))
        elif "ok" in out:
            allow = bool(out.get("ok"))
        rv = out.get("reasons") or out.get("reason") or []
        if isinstance(rv, (list, tuple)):
            reasons = list(rv)
        elif isinstance(rv, str):
            reasons = [rv]
    else:
        allow = bool(out)

    return allow, reasons


def main():
    import tbot.runtime.shadow_gate as sg

    if not hasattr(sg, "ShadowGate"):
        die("shadow_gate module has no ShadowGate. Check tbot/runtime/shadow_gate.py")

    ShadowGate = getattr(sg, "ShadowGate")

    cfg_kind, cfg = make_cfg(sg, max_trade=200.0, max_day=300.0, max_plans=999999, cooldown=0)
    print("[P0-2.2] cfg_kind =", cfg_kind)

    try:
        g = ShadowGate(cfg)
    except TypeError as e:
        die(f"ShadowGate(cfg) failed: {e}")

    mname = pick_gate_method_name(g)
    if not mname:
        die("Could not find a callable decision method on ShadowGate instance.")
    print("[P0-2.2] Using gate method:", mname)

    # ---- Test 1: per-trade cap ----
    allow1, reasons1 = call_gate(g, mname, mk_plan(250.0))  # > 200
    if allow1 is True:
        die(f"Per-trade cap expected REJECT, got allow=True (reasons={reasons1})")
    if "risk_above_max_trade" not in reasons1 and "risk_above_max" not in reasons1:
        die(f"Per-trade cap expected risk_above_max_trade (or legacy risk_above_max), got {reasons1}")
    ok("Per-trade cap => risk_above_max_trade (or legacy risk_above_max)")

    # ---- Test 2: daily budget ----
    g2 = ShadowGate(cfg)
    _ = call_gate(g2, mname, mk_plan(150.0))
    _ = call_gate(g2, mname, mk_plan(150.0))
    allow3, reasons3 = call_gate(g2, mname, mk_plan(1.0))

    if allow3 is False and ("daily_risk_budget_reached" in reasons3 or "risk_budget_reached" in reasons3):
        ok("Daily budget => daily_risk_budget_reached")
    else:
        die(
            "Daily budget test did NOT produce expected rejection. "
            f"Got allow={allow3}, reasons={reasons3}. "
            "This likely means daily budget is incremented outside gate (commit stage in orchestrator). "
            "If so, we must do P0-2.3 selftest through orchestrator commit path."
        )

    # ---- Test 3: day-budget None fallback should not crash ----
    cfg_kind3, cfg3 = make_cfg(sg, max_trade=200.0, max_day=None, max_plans=999999, cooldown=0)
    print("[P0-2.2] cfg_kind3 =", cfg_kind3)
    try:
        g3 = ShadowGate(cfg3)
        _ = call_gate(g3, mname, mk_plan(150.0))
    except Exception as e:
        die(f"Fallback test crashed when max_risk_per_day_usd=None: {e}")
    ok("Fallback max_risk_per_day_usd=None does not crash")

    print("[P0-2.2] PASS ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
