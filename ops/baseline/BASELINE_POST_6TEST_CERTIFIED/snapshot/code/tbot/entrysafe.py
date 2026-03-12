from __future__ import annotations

import argparse
import os
import sys
import traceback

def build_argparser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="tbot.entrysafe")
    p.add_argument("--profile", default=os.environ.get("TBOT_PROFILE", "PAPER"))
    p.add_argument("--run", action="store_true")
    p.add_argument("--iters", type=int, default=999999)
    p.add_argument("--sleep", type=float, default=0.5)
    return p

def entrypoint(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    args = build_argparser().parse_args(argv)

    if not args.run:
        print("ENTRYSAFE_HELP_EXIT", flush=True)
        return 0

    from tbot.runtime.orchestrator_entrysafe import run_loop
    try:
        return int(run_loop(profile=str(args.profile).upper(), iters=int(args.iters), sleep=float(args.sleep)))
    except SystemExit:
        raise
    except Exception:
        print("ENTRYSAFE_FATAL", flush=True)
        traceback.print_exc()
        return 1

def main() -> None:
    raise SystemExit(entrypoint())

if __name__ == "__main__":
    main()
