from __future__ import annotations
from pathlib import Path
import re

MAIN = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")

def fix_future_import(text: str) -> str:
    lines = text.splitlines(True)

    # find the future import line
    idx = None
    for i, ln in enumerate(lines):
        if ln.strip() == "from __future__ import annotations":
            idx = i
            break
    if idx is None:
        return text  # nothing to do

    future_line = lines.pop(idx)

    # detect shebang / encoding at very top
    out = []
    i = 0
    if i < len(lines) and lines[i].startswith("#!"):
        out.append(lines[i]); i += 1
    if i < len(lines) and re.match(r"^#.*coding[:=]\s*[-\w.]+", lines[i]):
        out.append(lines[i]); i += 1

    # detect module docstring (must be first statement)
    # allow blank lines between header and docstring
    while i < len(lines) and lines[i].strip() == "":
        out.append(lines[i]); i += 1

    if i < len(lines) and re.match(r'^[ \t]*([ruRU]{0,2}("""|\'\'\'))', lines[i]):
        quote = '"""' if '"""' in lines[i] else "'''"
        out.append(lines[i]); i += 1
        # consume until closing quote appears
        while i < len(lines):
            out.append(lines[i])
            if quote in lines[i]:
                i += 1
                break
            i += 1
        # keep any blank line after docstring
        while i < len(lines) and lines[i].strip() == "":
            out.append(lines[i]); i += 1

    # now insert future import here
    # ensure exactly one blank line after it
    out.append(future_line if future_line.endswith("\n") else future_line + "\n")
    if len(out) == 0 or out[-1].strip() != "":
        pass
    # if next line isn't blank, add one blank line
    if i < len(lines):
        if not (len(out) > 0 and out[-1].endswith("\n")):
            out[-1] = out[-1] + "\n"
        if (i < len(lines)) and (lines[i].strip() != ""):
            out.append("\n")

    # append rest
    out.extend(lines[i:])
    return "".join(out)

def main():
    if not MAIN.exists():
        raise SystemExit("[FIX] missing main.py")

    orig = MAIN.read_text(encoding="utf-8")
    fixed = fix_future_import(orig)

    if fixed == orig:
        print("[FIX] no change needed")
        return

    bak = MAIN.with_suffix(MAIN.suffix + ".bak_future")
    bak.write_text(orig, encoding="utf-8")
    MAIN.write_text(fixed, encoding="utf-8")
    print("[FIX] patched:", str(MAIN))
    print("[FIX] backup :", str(bak))

if __name__ == "__main__":
    main()
