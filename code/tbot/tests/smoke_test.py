# File: tbot/tests/smoke_test.py
from __future__ import annotations

# Allow running this test as a direct script (python tbot/tests/smoke_test.py)
# by ensuring project root is on sys.path.
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from tbot.main import smoke


def run() -> None:
    rc = smoke()
    assert rc == 0


if __name__ == "__main__":
    run()
    print("OK")
