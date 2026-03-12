from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
SHADOW = ROOT / r"tbot\runtime\shadow.py"
PRICING = ROOT / r"tbot\runtime\shadow_pricing.py"

def backup(p: Path) -> None:
    bak = p.with_suffix(p.suffix + ".bak_autopatch")
    bak.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    print("[PATCH] backup:", str(bak))

def ensure_price_shadow_plan() -> None:
    txt = PRICING.read_text(encoding="utf-8")
    if "def price_shadow_plan(" in txt:
        print("[PATCH] shadow_pricing.py: price_shadow_plan already exists")
        return

    backup(PRICING)

    addon = r'''
def price_shadow_plan(plan):
    """
    Apply shadow pricing to a ShadowPlan-like object.

    Works with dataclasses (frozen or not) and plain objects/dicts.
    Uses TBOT_SHADOW_PRICE_MODE, TBOT_SHADOW_RR, TBOT_SHADOW_STOP_PCT.
    """
    try:
        import dataclasses
        from tbot.market.market_provider import build_market_snapshot
        from tbot.runtime.shadow_pricing import compute_shadow_prices  # self module, safe
    except Exception:
        return plan

    try:
        symbol = getattr(plan, "symbol", None) or (plan.get("symbol") if isinstance(plan, dict) else None)
        side = getattr(plan, "side", None) or (plan.get("side") if isinstance(plan, dict) else None)
        entry0 = getattr(plan, "entry", None) if not isinstance(plan, dict) else plan.get("entry")
        stop0  = getattr(plan, "stop", None)  if not isinstance(plan, dict) else plan.get("stop")
        tp0    = getattr(plan, "tp", None)    if not isinstance(plan, dict) else plan.get("tp")
        if not symbol or not side:
            return plan
        # build market snapshot for this symbol
        m = build_market_snapshot(symbols=(symbol,))
        p = compute_shadow_prices(
            sig_payload={"symbol": symbol, "side": side},
            market=m,
            default_entry=float(entry0) if entry0 is not None else 100.0,
            default_stop=float(stop0) if stop0 is not None else 101.0,
            default_tp=float(tp0) if tp0 is not None else 98.0,
        )
        # Update plan (dataclass or object or dict)
        if isinstance(plan, dict):
            plan["entry"], plan["stop"], plan["tp"] = float(p.entry), float(p.stop), float(p.tp)
            return plan

        if dataclasses.is_dataclass(plan):
            try:
                return dataclasses.replace(plan, entry=float(p.entry), stop=float(p.stop), tp=float(p.tp))
            except Exception:
                pass

        try:
            setattr(plan, "entry", float(p.entry))
            setattr(plan, "stop",  float(p.stop))
            setattr(plan, "tp",    float(p.tp))
        except Exception:
            pass
        return plan
    except Exception:
        return plan
'''
    # append at end with a separating newline
    if not txt.endswith("\n"):
        txt += "\n"
    txt += "\n" + addon.lstrip("\n")
    PRICING.write_text(txt, encoding="utf-8")
    print("[PATCH] shadow_pricing.py: added price_shadow_plan")

def patch_shadow_append() -> None:
    txt = SHADOW.read_text(encoding="utf-8")

    # Remove any top-level import of price_shadow_plan (safer to import inside method)
    txt2 = re.sub(r"(?m)^\s*from\s+tbot\.runtime\.shadow_pricing\s+import\s+price_shadow_plan\s*\r?\n", "", txt)
    changed = (txt2 != txt)
    txt = txt2

    # Replace append() method body inside ShadowPlanWriter class
    needle = "def append(self, plan: ShadowPlan) -> None:"
    i = txt.find(needle)
    if i == -1:
        raise SystemExit("[PATCH] shadow.py: append() not found")

    # find end of this def block by next "\n    def " (method) or "\nclass " at col0
    start = i
    j = txt.find("\n    def ", i + len(needle))
    k = txt.find("\nclass ", i + len(needle))
    end = None
    if j != -1 and k != -1:
        end = min(j, k)
    elif j != -1:
        end = j
    elif k != -1:
        end = k
    else:
        end = len(txt)

    old_block = txt[start:end]

    new_block = (
        "def append(self, plan: ShadowPlan) -> None:\n"
        "        # Apply pricing at write-time (defensive) so we never emit placeholder entry=100.\n"
        "        from tbot.runtime.shadow_pricing import price_shadow_plan\n"
        "        plan = price_shadow_plan(plan)\n"
        "        line = plan.to_json()\n"
        "        with open(self.path, \"a\", encoding=\"utf-8\") as f:\n"
        "            f.write(line + \"\\n\")\n"
    )

    if old_block.strip() == new_block.strip():
        print("[PATCH] shadow.py: append() already in desired form")
        return

    backup(SHADOW)
    txt = txt[:start] + new_block + txt[end:]
    SHADOW.write_text(txt, encoding="utf-8")
    print("[PATCH] shadow.py: append() patched" + (" (also removed top import)" if changed else ""))

def main() -> int:
    if not PRICING.exists():
        raise SystemExit("[PATCH] missing: " + str(PRICING))
    if not SHADOW.exists():
        raise SystemExit("[PATCH] missing: " + str(SHADOW))

    ensure_price_shadow_plan()
    patch_shadow_append()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
