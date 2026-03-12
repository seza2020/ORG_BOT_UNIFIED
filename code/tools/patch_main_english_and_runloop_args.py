from __future__ import annotations

import re
from pathlib import Path

TARGET = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")

def main() -> int:
    if not TARGET.exists():
        print("ERROR: main.py not found:", str(TARGET))
        return 2

    s = TARGET.read_text(encoding="utf-8", errors="ignore")

    # 1) Remove/replace the known Persian print that causes UnicodeEncodeError on Windows cp1252 consoles.
    #    Replace any print("...Persian...") line with an English-only message.
    s2 = re.sub(
        r'^\s*print\(\s*["\'].*?[\u0600-\u06FF].*?["\']\s*\)\s*$',
        '    print("For testing use --smoke or --run or --emit_test_trade.")',
        s,
        flags=re.MULTILINE
    )

    # 2) Ensure stdout is UTF-8 (best-effort). Insert right after imports if not present.
    if "reconfigure(encoding=" not in s2:
        # Insert near the top after the first import block; safe idempotent approach.
        marker = "import argparse"
        if marker in s2:
            s2 = s2.replace(
                marker,
                marker + "\n\n# Ensure predictable encoding on Windows terminals.\nimport sys\ntry:\n    if hasattr(sys.stdout, 'reconfigure'):\n        sys.stdout.reconfigure(encoding='utf-8', errors='replace')\nexcept Exception:\n    pass\n",
                1
            )

    # 3) Fix common typo that appeared in patched snippets: args.force_signal_sidor -> args.force_signal_sid
    s2 = s2.replace("args.force_signal_sidor", "args.force_signal_sid")

    # 4) Patch the run_loop call block so required keyword-only args are satisfied.
    #    We locate the pattern:
    #       sig = inspect.signature(run_loop)
    #       filtered = ...
    #       rc = run_loop(**filtered)
    #    and replace it with a safer block that injects required args.
    pat = re.compile(
        r"(?P<indent>^[ \t]*)sig\s*=\s*inspect\.signature\(run_loop\)\s*\n"
        r"(?P=indent)filtered\s*=\s*\{.*?\}\s*\n"
        r"(?P=indent)#?\s*Run\s*\n"
        r"(?P=indent)rc\s*=\s*run_loop\(\*\*filtered\)\s*\n"
        r"(?P=indent)return\s+int\(rc\)\s+if\s+isinstance\(rc,\s*int\)\s+else\s+0\s*",
        flags=re.DOTALL | re.MULTILINE
    )

    def repl(m: re.Match) -> str:
        ind = m.group("indent")
        return (
f"{ind}sig = inspect.signature(run_loop)\n"
f"{ind}\n"
f"{ind}def _maybe_build(name: str):\n"
f"{ind}    # Best-effort builders. These are intentionally conservative.\n"
f"{ind}    if name == 'symbols':\n"
f"{ind}        try:\n"
f"{ind}            from tbot.config import SYMBOLS  # type: ignore\n"
f"{ind}            return list(SYMBOLS)\n"
f"{ind}        except Exception:\n"
f"{ind}            import os\n"
f"{ind}            raw = os.getenv('TBOT_SYMBOLS', os.getenv('SYMBOLS', 'SPY,QQQ'))\n"
f"{ind}            return [x.strip() for x in raw.split(',') if x.strip()]\n"
f"{ind}\n"
f"{ind}    if name == 'session':\n"
f"{ind}        try:\n"
f"{ind}            from tbot.runtime.session import DEFAULT_SESSION  # type: ignore\n"
f"{ind}            return DEFAULT_SESSION\n"
f"{ind}        except Exception:\n"
f"{ind}            return None\n"
f"{ind}\n"
f"{ind}    if name == 'env':\n"
f"{ind}        try:\n"
f"{ind}            from tbot.runtime.env import build_env  # type: ignore\n"
f"{ind}            return build_env()\n"
f"{ind}        except Exception:\n"
f"{ind}            return {{}}\n"
f"{ind}\n"
f"{ind}    if name == 'ledger':\n"
f"{ind}        try:\n"
f"{ind}            from tbot.runtime.ledger import build_ledger  # type: ignore\n"
f"{ind}            return build_ledger()\n"
f"{ind}        except Exception:\n"
f"{ind}            try:\n"
f"{ind}                from tbot.runtime.ledger import Ledger  # type: ignore\n"
f"{ind}                return Ledger()\n"
f"{ind}            except Exception:\n"
f"{ind}                return None\n"
f"{ind}\n"
f"{ind}    return None\n"
f"{ind}\n"
f"{ind}# Inject required keyword-only args if run_loop expects them.\n"
f"{ind}required = []\n"
f"{ind}for k, p in sig.parameters.items():\n"
f"{ind}    if p.default is inspect._empty and p.kind == inspect.Parameter.KEYWORD_ONLY:\n"
f"{ind}        required.append(k)\n"
f"{ind}\n"
f"{ind}for k in ('ledger','env','symbols','session'):\n"
f"{ind}    if k in sig.parameters and k not in kwargs:\n"
f"{ind}        kwargs[k] = _maybe_build(k)\n"
f"{ind}\n"
f"{ind}filtered = {{k: v for k, v in kwargs.items() if k in sig.parameters}}\n"
f"{ind}rc = run_loop(**filtered)\n"
f"{ind}return int(rc) if isinstance(rc, int) else 0"
        )

    if pat.search(s2):
        s2 = pat.sub(repl, s2, count=1)
    else:
        # If pattern didn't match, we still try a simpler insertion just before run_loop(**filtered) if present.
        # This keeps the patch resilient across minor edits.
        s2 = re.sub(
            r"sig\s*=\s*inspect\.signature\(run_loop\)\s*\n\s*filtered\s*=\s*\{[^\n]*\}\s*\n",
            "sig = inspect.signature(run_loop)\n\n"
            "def _maybe_build(name: str):\n"
            "    if name == 'symbols':\n"
            "        try:\n"
            "            from tbot.config import SYMBOLS\n"
            "            return list(SYMBOLS)\n"
            "        except Exception:\n"
            "            import os\n"
            "            raw = os.getenv('TBOT_SYMBOLS', os.getenv('SYMBOLS', 'SPY,QQQ'))\n"
            "            return [x.strip() for x in raw.split(',') if x.strip()]\n"
            "    if name == 'session':\n"
            "        try:\n"
            "            from tbot.runtime.session import DEFAULT_SESSION\n"
            "            return DEFAULT_SESSION\n"
            "        except Exception:\n"
            "            return None\n"
            "    if name == 'env':\n"
            "        try:\n"
            "            from tbot.runtime.env import build_env\n"
            "            return build_env()\n"
            "        except Exception:\n"
            "            return {}\n"
            "    if name == 'ledger':\n"
            "        try:\n"
            "            from tbot.runtime.ledger import build_ledger\n"
            "            return build_ledger()\n"
            "        except Exception:\n"
            "            return None\n"
            "    return None\n\n"
            "for k in ('ledger','env','symbols','session'):\n"
            "    if k in sig.parameters and k not in kwargs:\n"
            "        kwargs[k] = _maybe_build(k)\n\n"
            "filtered = {k: v for k, v in kwargs.items() if k in sig.parameters}\n",
            s2,
            count=1,
            flags=re.MULTILINE
        )

    if s2 == s:
        print("NO_CHANGES: main.py already looks patched or patterns not found.")
        return 0

    TARGET.write_text(s2, encoding="utf-8", newline="\n")
    print("PATCHED:", str(TARGET))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
