from pathlib import Path

P = Path(r"C:\alpaca-bot\org_bot\tbot\strategies\base.py")
txt = P.read_text(encoding="utf-8", errors="replace")

if "class MarketSnapshot" in txt:
    print("NO_CHANGES: MarketSnapshot already exists")
    raise SystemExit(0)

needle = "class Strategy(Protocol):"
idx = txt.find(needle)
if idx < 0:
    print("NO_CHANGES: could not find Strategy(Protocol) block to insert before")
    raise SystemExit(0)

insert = """
class MarketSnapshot:
    \"""
    Lightweight snapshot container used by market_provider.

    Intentionally permissive: accepts arbitrary fields via kwargs so that
    market_provider can evolve without breaking imports/tests.
    \"""
    def __init__(self, *args, **kwargs):
        if args:
            self.args = args
        for k, v in kwargs.items():
            setattr(self, k, v)

    def __repr__(self) -> str:
        keys = sorted([k for k in self.__dict__.keys() if k != "args"])
        return f"MarketSnapshot(keys={keys}, has_args={'args' in self.__dict__})"

"""

txt2 = txt[:idx] + insert + txt[idx:]
P.write_text(txt2, encoding="utf-8")
print("PATCHED:", P)
