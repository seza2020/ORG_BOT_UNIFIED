from __future__ import annotations

from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

MARK = "# Regime overlay enforcement (alpha only)"

INJECT = """\
                    # Regime overlay enforcement (alpha only)
                    if regime_enabled() and bool(is_alpha):
                        sig2, rsn2 = apply_alpha_overlay(is_alpha=True, sig_payload=sig_payload, overlay=regime_overlay)
                        if sig2 is None:
                            ev = make_event(level="INFO", kind="signal_skip", payload={"sid": str(sig_payload["sid"]), "reason": rsn2})
                            meta.emit(ev); announce.emit(ev)
                            continue
                        sig_payload = sig2

"""

def main() -> int:
    s = P.read_text(encoding="utf-8")

    if MARK in s:
        print("SKIP: regime enforce block already present")
        return 0

    needle = "if shadow_enabled and (shadow_writer is not None) and (gate is not None) and (sig_payload is not None):"
    idx = s.find(needle)
    if idx < 0:
        print("FAIL: could not find shadow_enabled block anchor")
        return 2

    # insert right after that line (end-of-line)
    eol = s.find("\n", idx)
    if eol < 0:
        print("FAIL: anchor line has no newline")
        return 3

    s2 = s[: eol + 1] + INJECT + s[eol + 1 :]
    P.write_text(s2, encoding="utf-8")
    print("DONE: inserted regime enforce block")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
