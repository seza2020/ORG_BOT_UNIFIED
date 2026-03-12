from __future__ import annotations
import ast
from pathlib import Path

F = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")
src = F.read_text(encoding="utf-8", errors="replace")
tree = ast.parse(src)

def is_true(node):
    return isinstance(node, ast.Constant) and node.value is True

def expr_name(node):
    if isinstance(node, ast.Name): return node.id
    return None

accept_returns = []
all_returns = []

class V(ast.NodeVisitor):
    def visit_ClassDef(self, node: ast.ClassDef):
        if node.name == "ShadowGate":
            for n in node.body:
                if isinstance(n, ast.FunctionDef) and n.name == "evaluate":
                    self.visit(n)
        # don't recurse into other classes by default

    def visit_FunctionDef(self, node: ast.FunctionDef):
        if node.name != "evaluate":
            return
        for n in ast.walk(node):
            if isinstance(n, ast.Return):
                all_returns.append((n.lineno, ast.unparse(n.value) if n.value else "None"))
                v = n.value
                # Cases we consider ACCEPT:
                # 1) return (True, reasons) or return True, reasons  -> Tuple with first element True
                if isinstance(v, ast.Tuple) and v.elts and is_true(v.elts[0]):
                    accept_returns.append((n.lineno, "tuple_first_true", ast.unparse(v)))
                # 2) return ok, reasons where ok variable set True earlier (can't prove statically here)
                # We'll report it separately by listing returns.

V().visit(tree)

print("FILE=", str(F))
print("TOTAL_RETURNS=", len(all_returns))
print("ACCEPT_RETURNS_DETECTED=", len(accept_returns))
print("")
print("=== ACCEPT_RETURNS ===")
for ln, kind, expr in accept_returns:
    print(f"L{ln}: {kind}: {expr}")

print("")
print("=== ALL_RETURNS (for manual confirmation) ===")
for ln, expr in sorted(all_returns):
    print(f"L{ln}: return {expr}")
