import re
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")
shadow_py = ROOT / "tbot" / "runtime" / "shadow.py"
orch_py   = ROOT / "tbot" / "runtime" / "orchestrator.py"

def die(msg: str):
    raise SystemExit("[PATCH] " + msg)

def backup(p: Path):
    b = p.with_suffix(p.suffix + ".bak")
    b.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    return b

def patch_shadow_writer(p: Path) -> bool:
    t = p.read_text(encoding="utf-8")

    # Replace ANY append(...) body under ShadowWriter with a known-good implementation
    # Works even if previous replace attempts failed.
    pat = re.compile(
        r"(?ms)^(?P<indent>[ \t]*)def append\(\s*self\s*,\s*plan\s*:\s*ShadowPlan\s*\)\s*->\s*None\s*:\s*\n"
        r"(?P<body>(?:(?!^[ \t]*def |^[ \t]*class ).*\n)*)"
    )

    m = pat.search(t)
    if not m:
        return False

    indent = m.group("indent")
    new_fn = (
        f"{indent}def append(self, plan: ShadowPlan) -> None:\n"
        f"{indent}    # AUTO-PATCH: apply shadow pricing right before writing jsonl\n"
        f"{indent}    from tbot.runtime.shadow_pricing import price_shadow_plan\n"
        f"{indent}    plan = price_shadow_plan(plan)\n"
        f"{indent}    line = plan.to_json()\n"
        f"{indent}    with open(self.path, 'a', encoding='utf-8') as f:\n"
        f"{indent}        f.write(line + '\\n')\n"
    )

    t2 = t[:m.start()] + new_fn + t[m.end():]
    if t2 == t:
        return False

    p.write_text(t2, encoding="utf-8")
    return True

def patch_orchestrator(p: Path) -> bool:
    t = p.read_text(encoding="utf-8")

    # If orchestrator already imports/uses price_shadow_plan elsewhere, keep it.
    # Insert right before shadow_writer.append(plan) when present.
    # This is extra safety; main fix is in shadow.py writer.
    pat = re.compile(r"(?m)^(?P<indent>[ \t]*)shadow_writer\.append\(\s*plan\s*\)\s*$")
    m = pat.search(t)
    if not m:
        return False

    indent = m.group("indent")
    inject = (
        f"{indent}from tbot.runtime.shadow_pricing import price_shadow_plan\n"
        f"{indent}plan = price_shadow_plan(plan)\n"
        f"{indent}shadow_writer.append(plan)\n"
    )

    t2 = pat.sub(inject, t, count=1)
    if t2 == t:
        return False

    p.write_text(t2, encoding="utf-8")
    return True

def main():
    if not shadow_py.exists():
        die(f"missing {shadow_py}")
    if not orch_py.exists():
        die(f"missing {orch_py}")

    backup(shadow_py)
    backup(orch_py)

    ok1 = patch_shadow_writer(shadow_py)
    ok2 = patch_orchestrator(orch_py)

    print(f"[PATCH] shadow.py patched={ok1}")
    print(f"[PATCH] orchestrator.py patched={ok2}")

    if not ok1 and not ok2:
        die("no changes made (patterns not found)")

if __name__ == "__main__":
    main()
