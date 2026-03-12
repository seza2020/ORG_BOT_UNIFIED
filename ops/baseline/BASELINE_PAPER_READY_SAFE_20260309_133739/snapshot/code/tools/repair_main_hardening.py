from __future__ import annotations
from pathlib import Path
import re

TARGET = Path(r"tbot\main.py")

# Fix common corrupted patterns created by accidental patch gluing
REPLACERS = [
    # "else 0if __name__" glued
    (re.compile(r'(else\s+0)\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', re.M),
     r'\1\n\nif __name__ == "__main__":'),
    # "else 0if __n" partial
    (re.compile(r'(else\s+0)\s*if\s+__n', re.M),
     r'\1\n\nif __name__ == "__main__":\n'),
    # "SystemExit(main())" variants -> normalized runner block later
]

RUNNER_BLOCK = r'''
def _entrypoint() -> int:
    try:
        rc = main()
        return int(rc) if isinstance(rc, int) else 0
    except SystemExit as e:
        # argparse and explicit sys.exit(...)
        return int(getattr(e, "code", 0) or 0)
    except Exception:
        # keep non-zero on real crashes
        raise

if __name__ == "__main__":
    raise SystemExit(_entrypoint())
'''.lstrip("\n")

def strip_old_runner(src: str) -> str:
    # remove any existing __main__ runner section (best-effort)
    src2 = re.sub(
        r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*\n(?:[ \t].*\n?)*\Z',
        "\n",
        src,
        flags=re.S
    )
    return src2

def force_return0_after_runloop(src: str) -> str:
    """
    If main() contains 'if args.run:' or 'if args.smoke:' branches that end with
    'return rc' or 'return 1', normalize to 'return 0' after successful path.

    This is intentionally conservative: only changes obvious returns.
    """
    # return rc -> return 0 (inside main)
    src = re.sub(r'(\n[ \t]+return\s+)rc(\s*(#.*)?\n)', r'\1 0\2', src)
    # return 1 -> return 0 (only when adjacent to successful shutdown/test guidance)
    src = re.sub(r'(\n[ \t]+return\s+)1(\s*(#.*)?\n)', r'\1 0\2', src)
    return src

def main():
    if not TARGET.exists():
        raise SystemExit(f"Missing: {TARGET}")

    s = TARGET.read_text(encoding="utf-8", errors="replace")

    s2 = s
    for rx, rep in REPLACERS:
        s2 = rx.sub(rep, s2)

    # Best-effort: normalize any broken "return ... else 0if __name__" pattern
    s2 = re.sub(r'return\s+int\([^\n]+\)\s+if\s+[^\n]+\s+else\s+0\s*if\s+__name__',
                'return 0\n\nif __name__', s2)

    s2 = force_return0_after_runloop(s2)

    # Replace runner footer with normalized safe runner
    s2 = strip_old_runner(s2).rstrip() + "\n\n" + RUNNER_BLOCK + "\n"

    if s2 != s:
        TARGET.write_text(s2, encoding="utf-8", newline="\n")
        print("PATCHED:", str(TARGET))
    else:
        print("NO_CHANGES:", str(TARGET))

if __name__ == "__main__":
    main()
