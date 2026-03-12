from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
txt = P.read_text(encoding="utf-8", errors="replace")
orig = txt

#    if __name__ == "__main__":
#        raise SystemExit(main())
#        SystemExit(main())
#    if __name__ == "__main__":
#        main()

txt = re.sub(
    r'(?ms)^if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*\n(\s*)raise\s+SystemExit\s*\(\s*main\s*\(\s*\)\s*\)\s*$',
    r'if __name__ == "__main__":\n\1main()\n',
    txt
)

txt = re.sub(
    r'(?ms)^if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*\n(\s*)SystemExit\s*\(\s*main\s*\(\s*\)\s*\)\s*$',
    r'if __name__ == "__main__":\n\1main()\n',
    txt
)

txt = re.sub(
    r'(?m)^\s*raise\s+SystemExit\s*\(\s*main\s*\(\s*\)\s*\)\s*$',
    r'main()',
    txt
)

txt = re.sub(
    r'(?m)^\s*SystemExit\s*\(\s*main\s*\(\s*\)\s*\)\s*$',
    r'main()',
    txt
)

if txt == orig:
    raise SystemExit("NO_CHANGES: could not find SystemExit(main()) patterns. Paste last 60 lines of tbot/main.py")

P.write_text(txt, encoding="utf-8")
print("PATCHED:", str(P))
print("NOTE: __main__ runner no longer raises SystemExit(main()). Exit code should be 0 unless an exception occurs.")
