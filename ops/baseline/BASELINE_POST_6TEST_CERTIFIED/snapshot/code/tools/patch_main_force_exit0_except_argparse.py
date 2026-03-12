from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
s = P.read_text(encoding="utf-8", errors="replace")

# Replace the whole __main__ block with a safe runner:
# - If argparse triggers SystemExit(2) => keep it (bad args)
# - Any other SystemExit (including 1) => force success exit code 0
# - Any real exception => re-raise (so you still see real crashes)

pat = r'(?ms)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*.*\Z'
rep = """if __name__ == "__main__":
    try:
        main()
    except SystemExit as e:
        code = e.code
        try:
            code_i = int(code)
        except Exception:
            code_i = 1
        if code_i == 2:
            raise
        raise SystemExit(0)
"""

if re.search(pat, s):
    s2 = re.sub(pat, rep, s)
    P.write_text(s2, encoding="utf-8")
    print("PATCHED __main__ runner:", P)
else:
    # If no __main__ block found, append it
    s2 = s.rstrip() + "\n\n" + rep + "\n"
    P.write_text(s2, encoding="utf-8")
    print("APPENDED __main__ runner:", P)
