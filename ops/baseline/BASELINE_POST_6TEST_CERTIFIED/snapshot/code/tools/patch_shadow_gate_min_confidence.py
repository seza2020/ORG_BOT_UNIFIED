import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")
s = P.read_text(encoding="utf-8")

# 1) GateConfig field: min_conf -> min_confidence
s = re.sub(r"(^\s*min_conf\s*:\s*float\s*=\s*)([0-9.]+)\s*$",
           r"\1\2\n    # backward-compatible name used by orchestrator\n    min_confidence: float = \2",
           s, flags=re.M)

# If the file already has min_confidence, avoid duplicate insertion:
# (cleanup: if both exist, remove the old min_conf line)
if re.search(r"^\s*min_confidence\s*:\s*float\s*=\s*", s, flags=re.M):
    # remove original min_conf line if present (keep min_confidence)
    s = re.sub(r"^\s*min_conf\s*:\s*float\s*=\s*[0-9.]+\s*\n", "", s, flags=re.M)

# 2) Replace cfg.min_conf with cfg.min_confidence in logic
s = s.replace("self.cfg.min_conf", "self.cfg.min_confidence")
s = s.replace("float(self.cfg.min_conf)", "float(self.cfg.min_confidence)")

# 3) Optional: provide a read-only alias property min_conf for older code paths (safe)
if "def min_conf(" not in s:
    insert_pat = r"(class\s+ShadowGate\s*:\s*\n)"
    m = re.search(insert_pat, s)
    if m:
        idx = m.end(1)
        alias = "\n    @property\n    def min_conf(self):\n        return float(self.cfg.min_confidence)\n\n"
        s = s[:idx] + alias + s[idx:]

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
