import ast, sys, os

F = r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py"

with open(F, "r", encoding="utf-8", errors="replace") as f:
    src = f.read()

if "SIG_PAYLOAD_MISSING_AST_V1" in src:
    print("ALREADY_PATCHED")
    sys.exit(0)

tree = ast.parse(src)

# parent pointers
for n in ast.walk(tree):
    for ch in ast.iter_child_nodes(n):
        ch._parent = n

# find the string "strategy_result" in code by locating meta.emit({... "kind":"strategy_result" ...})
target_stmt = None
for n in ast.walk(tree):
    if isinstance(n, ast.Expr) and isinstance(n.value, ast.Call):
        c = n.value
        fn = c.func
        if isinstance(fn, ast.Attribute) and fn.attr == "emit":
            # look for dict literal with "kind": "strategy_result"
            for arg in c.args:
                if isinstance(arg, ast.Dict):
                    keys = arg.keys
                    vals = arg.values
                    for k,v in zip(keys, vals):
                        if isinstance(k, ast.Constant) and k.value == "kind" and isinstance(v, ast.Constant) and v.value == "strategy_result":
                            target_stmt = n
                            break
                if target_stmt is not None:
                    break
    if target_stmt is not None:
        break

# fallback: just find first occurrence of the literal string strategy_result anywhere
if target_stmt is None:
    for n in ast.walk(tree):
        if isinstance(n, ast.Constant) and n.value == "strategy_result":
            # climb to statement
            cur = getattr(n, "_parent", None)
            while cur is not None and not isinstance(cur, ast.stmt):
                cur = getattr(cur, "_parent", None)
            target_stmt = cur
            break

if target_stmt is None or not hasattr(target_stmt, "lineno"):
    print("ERROR: could not locate strategy_result emission in AST")
    sys.exit(2)

insert_after_line = int(getattr(target_stmt, "end_lineno", target_stmt.lineno))

lines = src.splitlines(True)
if insert_after_line < 1 or insert_after_line > len(lines):
    print("ERROR: bad insert_after_line=%d" % insert_after_line)
    sys.exit(3)

# infer indentation from the target statement line
stmt_text = lines[insert_after_line-1]
indent = stmt_text[:len(stmt_text) - len(stmt_text.lstrip(" \t"))]

snippet = [
    indent + "# === SIG_PAYLOAD_MISSING_AST_V1 (observability-only)\n",
    indent + "try:\n",
    indent + "    if sig_payload is None:\n",
    indent + "        meta.emit({\"kind\":\"sig_payload_missing\",\"sid\":sid if 'sid' in locals() else None,"
             "\"alpha_mode\":getattr(ctx,'alpha_mode',None) if 'ctx' in locals() else None,"
             "\"confidence\":float(confidence or 0.0) if 'confidence' in locals() else 0.0,"
             "\"rr\":float(rr or 0.0) if 'rr' in locals() else 0.0,"
             "\"reason\":\"strategy_did_not_emit_payload\"})\n",
    indent + "except Exception:\n",
    indent + "    pass\n",
    indent + "# === END_SIG_PAYLOAD_MISSING_AST_V1\n",
]

out = []
out.extend(lines[:insert_after_line])
out.extend(snippet)
out.extend(lines[insert_after_line:])

new_src = "".join(out)
with open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(new_src)

print("PATCH_OK_SIGPAYLOAD_MISSING insert_after_line=%d" % insert_after_line)
