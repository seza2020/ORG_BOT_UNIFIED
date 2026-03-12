import pathlib
import re

MAIN = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
ORCH = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")

txt = MAIN.read_text(encoding="utf-8")

# ---- 1) argparse: add force_signal_ignore_pre_close if missing
if "--force_signal_ignore_pre_close" not in txt:
    needle = '    ap.add_argument("--force_signal_ignore_session", type=int, default=0, help="allow --force_signal to run even when out of session")\n'
    if needle not in txt:
        raise SystemExit("Could not find force_signal_ignore_session line in main.py to patch argparse.")
    txt = txt.replace(
        needle,
        needle + '    ap.add_argument("--force_signal_ignore_pre_close", type=int, default=0, help="allow --force_signal to run even when pre_close is true (test-only)")\n'
    )

# ---- 2) main.py: pass arg into run_loop call
if "force_signal_ignore_pre_close" not in txt:
    needle = '            force_signal_ignore_session=bool(int(getattr(args,\'force_signal_ignore_session\',0))),\n'
    if needle not in txt:
        raise SystemExit("Could not find force_signal_ignore_session kwarg in run_loop call to patch.")
    txt = txt.replace(
        needle,
        needle + '            force_signal_ignore_pre_close=bool(int(getattr(args,\'force_signal_ignore_pre_close\',0))),\n'
    )

MAIN.write_text(txt, encoding="utf-8")

# ---- 3) orchestrator.py: add parameter + log block reasons
orch = ORCH.read_text(encoding="utf-8")

if "force_signal_ignore_pre_close" not in orch:
    # add parameter in run_loop signature
    m = re.search(r"def\s+run_loop\((.*?)\)\s*->", orch, flags=re.S)
    if not m:
        raise SystemExit("Could not find run_loop signature in orchestrator.py")
    sig = m.group(1)
    if "force_signal_ignore_session" not in sig:
        raise SystemExit("run_loop signature does not contain force_signal_ignore_session; patch needs a different marker.")

    # insert after force_signal_ignore_session argument (works for most layouts)
    orch = orch.replace(
        "force_signal_ignore_session",
        "force_signal_ignore_session, force_signal_ignore_pre_close"
    )

    # add a small block-reason announce/meta when forced signal is skipped
    # We patch by finding the first occurrence of force_signal_ignore_session usage.
    anchor = "force_signal_ignore_session"
    idx = orch.find(anchor)
    if idx < 0:
        raise SystemExit("Could not find force_signal_ignore_session usage in orchestrator.py")

    # Heuristic insertion: look for a line that checks session/pre_close near the top of loop
    # We'll add a helper function that can be used where force_signal is handled.
    if "_emit_force_block" not in orch:
        insert_helper = """

def _emit_force_block(meta, announce, sid: str, reasons: list[str]) -> None:
    payload = {"sid": sid, "reasons": reasons}
    try:
        announce.info("force_signal_blocked", payload)
    except Exception:
        pass
    try:
        meta.info("force_signal_blocked", payload)
    except Exception:
        pass
"""
        # Put helper near top (after imports). We insert after the first blank line following imports.
        imp_end = orch.find("\n\n")
        if imp_end > 0:
            orch = orch[:imp_end] + insert_helper + orch[imp_end:]

ORCH.write_text(orch, encoding="utf-8")
print("PATCHED main.py + orchestrator.py OK")
