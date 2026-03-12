from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8", errors="replace")
orig = txt

def force_info_for_kind(kind: str) -> None:
    global txt
    pat = r'(make_event\(\s*)(?P<head>.*?kind\s*=\s*["\']' + re.escape(kind) + r'["\'].*?\))'
    def repl(m):
        block = m.group(0)
        if re.search(r'\blevel\s*=', block):
            block2 = re.sub(r'\blevel\s*=\s*[^,)\n]+', 'level="INFO"', block, count=1)
            return block2
        return re.sub(r'make_event\(\s*', 'make_event(level="INFO", ', block, count=1)

    txt2 = re.sub(pat, repl, txt, flags=re.DOTALL)
    txt = txt2

force_info_for_kind("alpha_kill_change")
force_info_for_kind("portfolio_kill_change")

if txt == orig:
    raise SystemExit("NO_CHANGES: could not match make_event blocks; paste the Select-String output for those kinds.")

P.write_text(txt, encoding="utf-8")
print("PATCHED:", str(P))
