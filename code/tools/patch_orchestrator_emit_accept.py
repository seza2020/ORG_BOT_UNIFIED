import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")

# We ensure that after gate.evaluate(), if ok then we emit shadow_accept (and shadow_plan if writer exists)
# Pattern: ok, reasons = gate.evaluate(...)

pat = re.compile(r"(ok,\s*reasons\s*=\s*gate\.evaluate\([\s\S]*?\)\s*)", re.M)

m = pat.search(s)
if not m:
    raise SystemExit("orchestrator.py: could not find gate.evaluate() assignment")

# Find the subsequent 'if not ok:' block to insert an 'else:' accept emitter before it.
# We locate 'if not ok:' after the match.
start = m.end()
idx = s.find("if not ok:", start)
if idx == -1:
    raise SystemExit("orchestrator.py: could not find 'if not ok:' after gate.evaluate()")

# Determine indentation of 'if not ok:'
line_start = s.rfind("\n", 0, idx) + 1
indent = re.match(r"[ \t]*", s[line_start:idx]).group(0)

# If an 'else:' already exists for accept, do nothing.
after_block = s[idx: idx+3000]
if re.search(r"(?m)^\s*else\s*:\s*$", after_block):
    print("SKIP: accept else already present")
    raise SystemExit(0)

insert = (
    f"{indent}else:\n"
    f"{indent}    # accepted by gate\n"
    f"{indent}    ev = make_event(level=\"INFO\", kind=\"shadow_accept\", payload={{\n"
    f"{indent}        \"sid\": plan.sid,\n"
    f"{indent}        \"symbol\": plan.symbol,\n"
    f"{indent}        \"side\": plan.side,\n"
    f"{indent}        \"qty\": int(plan.qty),\n"
    f"{indent}        \"entry\": float(plan.entry),\n"
    f"{indent}        \"stop\": float(plan.stop),\n"
    f"{indent}        \"tp\": float(plan.tp),\n"
    f"{indent}        \"risk_usd\": float(plan.risk_usd),\n"
    f"{indent}        \"per_share_risk\": float(getattr(plan, 'per_share_risk', 0.0)),\n"
    f"{indent}        \"rr\": float(getattr(plan, 'rr', 0.0)),\n"
    f"{indent}        \"confidence\": float(getattr(plan, 'confidence', 0.0)),\n"
    f"{indent}        \"reason\": str(getattr(plan, 'reason', \"\")),\n"
    f"{indent}    }})\n"
    f"{indent}    meta.emit(ev); announce.emit(ev)\n"
    f"{indent}    if shadow_writer is not None:\n"
    f"{indent}        shadow_writer.write(plan)\n"
    f"{indent}        ev = make_event(level=\"INFO\", kind=\"shadow_plan\", payload={{\n"
    f"{indent}            \"sid\": plan.sid,\n"
    f"{indent}            \"symbol\": plan.symbol,\n"
    f"{indent}            \"side\": plan.side,\n"
    f"{indent}            \"qty\": int(plan.qty),\n"
    f"{indent}            \"entry\": float(plan.entry),\n"
    f"{indent}            \"stop\": float(plan.stop),\n"
    f"{indent}            \"tp\": float(plan.tp),\n"
    f"{indent}            \"risk_usd\": float(plan.risk_usd),\n"
    f"{indent}            \"per_share_risk\": float(getattr(plan, 'per_share_risk', 0.0)),\n"
    f"{indent}            \"rr\": float(getattr(plan, 'rr', 0.0)),\n"
    f"{indent}            \"confidence\": float(getattr(plan, 'confidence', 0.0)),\n"
    f"{indent}            \"reason\": str(getattr(plan, 'reason', \"\")),\n"
    f"{indent}            \"path\": str(getattr(shadow_writer, 'path', \"\")),\n"
    f"{indent}        }})\n"
    f"{indent}        meta.emit(ev); announce.emit(ev)\n"
)

# Insert the else block right before 'if not ok:'
s = s[:idx] + insert + s[idx:]

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
