import pathlib

path = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
txt = path.read_text(encoding="utf-8")

# 1) Add argparse options (only if not present)
if "--sim_in_session" not in txt:
    needle = '    ap.add_argument("--sim_week_r", type=float, default=None, help="simulate week_r (R units)")\n'
    if needle not in txt:
        raise SystemExit("Could not find sim_week_r line to patch argparse.")
    txt = txt.replace(
        needle,
        needle
        + '\n'
        + '    ap.add_argument("--sim_in_session", type=int, default=-1, help="override in_session for testing: 1=in, 0=out, -1=normal")\n'
        + '    ap.add_argument("--sim_pre_close", type=int, default=-1, help="override pre_close for testing: 1=pre_close, 0=not, -1=normal")\n'
    )

# 2) Wrap SessionWindow in args.run (only if not present)
marker = """        sw = SessionWindow(
            start_hhmm=cfg.session_start,
            end_hhmm=cfg.session_end,
            pre_close_minutes=cfg.pre_close_minutes,
        )
"""

if "_SimSessionWindow" not in txt:
    if marker not in txt:
        raise SystemExit("Could not find SessionWindow block marker to patch run section.")
    insert = marker + """
        # Simulate session/pre-close flags (test-only; defaults keep real behavior)
        in_raw = int(getattr(args, "sim_in_session", -1))
        pre_raw = int(getattr(args, "sim_pre_close", -1))
        in_ov = None if in_raw < 0 else bool(in_raw)
        pre_ov = None if pre_raw < 0 else bool(pre_raw)

        if (in_ov is not None) or (pre_ov is not None):
            class _SimSessionWindow:
                def __init__(self, base, in_override, pre_override):
                    self._base = base
                    self._in_override = in_override
                    self._pre_override = pre_override
                    self.start_hhmm = base.start_hhmm
                    self.end_hhmm = base.end_hhmm
                    self.pre_close_minutes = base.pre_close_minutes

                def in_session(self, now):
                    if self._in_override is None:
                        return self._base.in_session(now)
                    return bool(self._in_override)

                def is_pre_close(self, now):
                    # keep original semantics: pre_close only meaningful if we're in session
                    if not self.in_session(now):
                        return False
                    if self._pre_override is None:
                        return self._base.is_pre_close(now)
                    return bool(self._pre_override)

            sw = _SimSessionWindow(sw, in_ov, pre_ov)
"""
    txt = txt.replace(marker, insert)

path.write_text(txt, encoding="utf-8")
print("PATCHED:", path)
