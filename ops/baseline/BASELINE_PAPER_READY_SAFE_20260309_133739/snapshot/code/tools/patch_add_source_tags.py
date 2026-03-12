from __future__ import annotations

from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

def main() -> int:
    s = P.read_text(encoding="utf-8")

    # Forced payload: insert "source": "forced" after forced_signal_test reason line
    if '"source": "forced"' not in s:
        s = s.replace(
            '"reason": "forced_signal_test",\n                    }',
            '"reason": "forced_signal_test",\n                        "source": "forced",\n                    }'
        )

    # Real payload: insert "source": "strategy" after sig.reason line
    if '"source": "strategy"' not in s:
        s = s.replace(
            '"reason": sig.reason,\n                    }',
            '"reason": sig.reason,\n                        "source": "strategy",\n                    }'
        )

    P.write_text(s, encoding="utf-8")
    print("DONE: patched source tags")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
