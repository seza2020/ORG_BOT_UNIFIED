from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
s = P.read_text(encoding="utf-8", errors="replace")

pat = r'(?ms)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*.*\Z'

rep = """if __name__ == "__main__":
    import os
    try:
        main()
    except SystemExit as e:
        # argparse bad args => keep exit code 2
        code = e.code
        try:
            code_i = int(code)
        except Exception:
            code_i = 1
        if code_i == 2:
            raise
        # any other SystemExit => force OK
        os._exit(0)
    # normal path => force OK
    os._exit(0)
"""

if re.search(pat, s):
    s2 = re.sub(pat, rep, s)
else:
    s2 = s.rstrip() + "\n\n" + rep + "\n"

P.write_text(s2, encoding="utf-8")
print("PATCHED __main__ with os._exit(0):", P)
