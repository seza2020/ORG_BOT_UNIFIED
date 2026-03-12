import ast, io, os, sys

F = r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py"

with open(F, "r", encoding="utf-8", errors="replace") as f:
    src = f.read()

if "LLM_GATE_PRECHECK_AST_V1" in src:
    print("ALREADY_PATCHED")
    sys.exit(0)

tree = ast.parse(src)

# attach parent pointers
for node in ast.walk(tree):
    for ch in ast.iter_child_nodes(node):
        ch._parent = node

# find first call to llm_gate(...)
target_call = None
for node in ast.walk(tree):
    if isinstance(node, ast.Call):
        fn = node.func
        if isinstance(fn, ast.Name) and fn.id == "llm_gate":
            target_call = node
            break
        if isinstance(fn, ast.Attribute) and fn.attr == "llm_gate":
            target_call = node
            break

if target_call is None or not hasattr(target_call, "lineno"):
    print("ERROR: llm_gate call not found in AST")
    sys.exit(2)

call_line = int(target_call.lineno)

# climb parents to find nearest block container that has a 'body' list containing a statement that spans call_line
def spans(node, line):
    a = getattr(node, "lineno", None)
    b = getattr(node, "end_lineno", None)
    if a is None:
        return False
    if b is None:
        b = a
    return a <= line <= b

block = None
stmt_in_block = None

cur = getattr(target_call, "_parent", None)
while cur is not None:
    # candidate blocks that own 'body'
    if hasattr(cur, "body") and isinstance(cur.body, list) and cur.body:
        # find statement in this body that spans call_line
        for st in cur.body:
            if spans(st, call_line):
                block = cur
                stmt_in_block = st
                break
        if block is not None:
            break
    cur = getattr(cur, "_parent", None)

if block is None:
    print("ERROR: could not locate enclosing block body for llm_gate call (line=%d)" % call_line)
    sys.exit(3)

# decide insertion line: insert immediately BEFORE the statement that contains the call, at same indent as that statement
insert_before_line = int(getattr(stmt_in_block, "lineno", call_line))

lines = src.splitlines(True)  # keep newlines
if insert_before_line < 1 or insert_before_line > len(lines):
    print("ERROR: bad insert_before_line=%d" % insert_before_line)
    sys.exit(4)

# infer indentation from the statement line
stmt_text = lines[insert_before_line-1]
indent = stmt_text[:len(stmt_text) - len(stmt_text.lstrip(" \t"))]

snippet = [
    indent + "# === LLM_GATE_PRECHECK_AST_V1 (observability-only)\n",
    indent + "try:\n",
    indent + "    meta.emit({\"kind\":\"llm_gate_precheck\",\"shadow_enabled\":bool(shadow_enabled),\"has_shadow_writer\":bool(shadow_writer is not None),\"has_gate\":bool(gate is not None),\"has_sig_payload\":bool(sig_payload is not None)})\n",
    indent + "except Exception:\n",
    indent + "    pass\n",
    indent + "# === END_LLM_GATE_PRECHECK_AST_V1\n",
]

out = []
out.extend(lines[:insert_before_line-1])
out.extend(snippet)
out.extend(lines[insert_before_line-1:])

new_src = "".join(out)

# sanity: ensure marker is present exactly once
if new_src.count("LLM_GATE_PRECHECK_AST_V1") != 2:
    print("ERROR: marker count unexpected")
    sys.exit(5)

with open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(new_src)

print("PATCH_OK_AST insert_before_line=%d llm_gate_call_line=%d" % (insert_before_line, call_line))
