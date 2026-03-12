from __future__ import annotations
from pathlib import Path
import datetime as dt

def main():
    path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
    s0 = path.read_text(encoding="utf-8")
    lines = s0.splitlines()

    # backup
    bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / ("MAIN_ENTRYPOINT_TRACE_EXCEPTIONS_V2_" + dt.datetime.now().strftime("%Y%m%d_%H%M%S"))
    bakdir.mkdir(parents=True, exist_ok=True)
    (bakdir / "main.py").write_text(s0, encoding="utf-8")

    # locate def entrypoint():
    def_i = None
    for i, ln in enumerate(lines):
        if ln.startswith("def entrypoint"):
            def_i = i
            break
    if def_i is None:
        raise SystemExit("ANCHOR_NOT_FOUND: def entrypoint() not found")

    # find the try: inside entrypoint
    try_i = None
    for i in range(def_i+1, min(def_i+120, len(lines))):
        if lines[i].lstrip().startswith("try:"):
            # must be indented (inside function)
            if len(lines[i]) - len(lines[i].lstrip()) > 0:
                try_i = i
                break
    if try_i is None:
        raise SystemExit("ANCHOR_NOT_FOUND: try: inside entrypoint() not found")

    # scan for except blocks aligned with try (same indent as try)
    base_indent = lines[try_i][:len(lines[try_i]) - len(lines[try_i].lstrip())]  # e.g. "    "
    except_indices = []
    for i in range(try_i+1, min(try_i+260, len(lines))):
        ln = lines[i]
        if ln.startswith(base_indent + "except "):
            except_indices.append(i)

    if not except_indices:
        raise SystemExit("ANCHOR_NOT_FOUND: no except blocks found under entrypoint try")

    # pick the generic except that returns 1 (silent)
    # We will replace from that 'except ...' line up to (but not including) the next 'except' at same level,
    # or until we leave the function block.
    target_start = None
    target_end = None

    for ex_i in except_indices:
        # find block end
        j = ex_i + 1
        while j < len(lines):
            if lines[j].startswith(base_indent + "except "):
                break
            # if we reach a new top-level def/class (indent 0), stop
            if lines[j] and (len(lines[j]) - len(lines[j].lstrip()) == 0) and (lines[j].startswith("def ") or lines[j].startswith("class ")):
                break
            j += 1

        block = "\n".join(lines[ex_i:j])

        # heuristic: silent block is generic Exception and contains a "return 1"
        if ("except Exception" in lines[ex_i]) and ("return 1" in block):
            target_start = ex_i
            target_end = j
            break

    if target_start is None:
        raise SystemExit("TARGET_NOT_FOUND: could not find a generic except Exception block with return 1 inside entrypoint()")

    # build replacement with proper indentation
    ex_indent = base_indent  # except aligned with try
    in_indent = base_indent + "    "  # inside except

    new_block = [
        ex_indent + "except Exception as e:",
        in_indent + "try:",
        in_indent + "    import os as _os, traceback as _tb, sys as _sys",
        in_indent + "    if (_os.getenv('TBOT_TRACE_EXCEPTIONS','0') == '1'):",
        in_indent + "        print('[ENTRYPOINT_EXCEPTION] ' + repr(e), file=_sys.stderr)",
        in_indent + "        _tb.print_exc()",
        in_indent + "except Exception:",
        in_indent + "    pass",
        in_indent + "return 1",
    ]

    out = []
    out.extend(lines[:target_start])
    out.extend(new_block)
    out.extend(lines[target_end:])

    s1 = "\n".join(out) + ("\n" if s0.endswith("\n") else "")
    path.write_text(s1, encoding="utf-8")

    print("PATCH_OK:", str(path))
    print("BACKUP_DIR:", str(bakdir))
    print("REPLACED_LINES:", target_start+1, "to", target_end)

if __name__ == "__main__":
    main()
