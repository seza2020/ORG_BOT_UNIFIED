import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"orchestrator.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")
if "OBS_REASON_NONE_V2" in txt:
    print("SKIP: already patched")
    raise SystemExit(0)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"OBS_REASON_NONE_V2_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

# Anchor: the strategy_result payload creation contains this exact pattern (you showed line 1649)
anchor_pat = r'"returned":\s*\("NONE"\s*if\s*_sig\s*is\s*None\s*else\s*"SIGNAL"\)\s*,'
m = re.search(anchor_pat, txt)
if not m:
    print("FAIL: anchor not found for returned/NONE payload builder")
    raise SystemExit(2)

# We need to locate the payload dict variable name used in logger call.
# Common pattern: logger.info("strategy_result", payload={...}) OR payload=payload
# We'll patch both cases:
# 1) If payload dict literal is used directly in logger.info(... payload={...}), inject normalization inside that dict.
# 2) If a variable like `payload = {...}` exists, inject normalization after payload is built.

# First try: find the surrounding dict literal block "strategy_result", payload={ ... }
# We'll insert a small normalization block *after* payload dict is created in variable form.
inserted = False

# Case: logger.info("strategy_result", payload=payload) with a `payload = {...}` nearby
# Find nearest "payload=" after anchor
after = txt[m.start():]
m_log = re.search(r'logger\.info\(\s*["\']strategy_result["\']\s*,\s*payload\s*=\s*([a-zA-Z_]\w*)', after)
if m_log:
    varname = m_log.group(1)
    # insert normalization right before the logger call (at the start of 'logger.info("strategy_result"...')
    log_pos = m.start() + m_log.start()
    block = f"""
                    # --- OBS_REASON_NONE_V2 (observability-only) ---
                    try:
                        if isinstance({varname}, dict) and {varname}.get("returned") == "NONE" and not {varname}.get("reason"):
                            _in_session = locals().get("in_session", None)
                            _alpha_mode = locals().get("alpha_mode", None)
                            if _in_session is False:
                                {varname}["reason"] = "out_of_session"
                            else:
                                try:
                                    if isinstance(_alpha_mode, dict) and (_alpha_mode.get("mode") == "OFF"):
                                        {varname}["reason"] = "alpha_off"
                                    else:
                                        {varname}["reason"] = "no_setup"
                                except Exception:
                                    {varname}["reason"] = "no_setup"
                    except Exception:
                        pass
                    # --- /OBS_REASON_NONE_V2 ---
"""
    txt = txt[:log_pos] + block + txt[log_pos:]
    inserted = True

if not inserted:
    # Fallback Case: inline dict literal in logger call: payload={ ... "returned": ("NONE" if _sig is None else "SIGNAL"), ... }
    # We'll inject a "reason" expression that never yields None when returned==NONE.
    # Find the "reason": line near the anchor and replace it with a guarded expression.
    # If no explicit "reason" key, we add one.
    window_start = max(0, m.start() - 800)
    window_end = min(len(txt), m.start() + 1200)
    win = txt[window_start:window_end]

    # Ensure we are inside a payload dict literal; look for 'payload={' before and a closing '}' after
    idx_payload = win.rfind("payload={")
    if idx_payload == -1:
        print("FAIL: could not locate payload={ near anchor")
        raise SystemExit(3)

    # Replace existing "reason": (...) if present inside the dict literal window
    # We set reason to one of alpha_off / no_setup / out_of_session when _sig is None
    reason_rx = re.compile(r'"reason"\s*:\s*([^,\n]+)\s*,')
    reason_m = reason_rx.search(win)
    if reason_m:
        new_reason = '"reason": (("out_of_session" if (locals().get("in_session", True) is False) else ("alpha_off" if (isinstance(locals().get("alpha_mode", None), dict) and locals().get("alpha_mode", {}).get("mode")=="OFF") else "no_setup")) if _sig is None else _sig.get("reason")),'  # noqa
        win2 = win[:reason_m.start()] + new_reason + win[reason_m.end():]
        txt = txt[:window_start] + win2 + txt[window_end:]
        inserted = True
    else:
        # Add a reason line right after returned line
        # Insert after the anchor matched line end (just after the comma)
        rel = win.find('("NONE" if _sig is None else "SIGNAL")')
        if rel == -1:
            print("FAIL: could not find returned expression inside window")
            raise SystemExit(4)
        # Insert after the returned line comma (best-effort)
        insert_rel = win.find("\n", win.find('"returned"', rel-200))
        if insert_rel == -1:
            insert_rel = rel
        add_line = '\n                        "reason": (("out_of_session" if (locals().get("in_session", True) is False) else ("alpha_off" if (isinstance(locals().get("alpha_mode", None), dict) and locals().get("alpha_mode", {}).get("mode")=="OFF") else "no_setup")) if _sig is None else _sig.get("reason")),'  # noqa
        win2 = win[:insert_rel+1] + add_line + win[insert_rel+1:]
        txt = txt[:window_start] + win2 + txt[window_end:]
        inserted = True

if not inserted:
    print("FAIL: could not insert OBS_REASON_NONE_V2")
    raise SystemExit(5)

path.write_text(txt, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
