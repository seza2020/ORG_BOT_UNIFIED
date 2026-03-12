from __future__ import annotations
from pathlib import Path
from datetime import datetime

path = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
lines = path.read_text(encoding="utf-8").splitlines(True)

# Backup
bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / ("MAIN_ENTRYPOINT_TRACE_V2_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
bakdir.mkdir(parents=True, exist_ok=True)
(bakdir / "main.py").write_text("".join(lines), encoding="utf-8")

# Locate the entrypoint() except Exception: ... return 1
idx_except = -1
idx_return = -1
for i, ln in enumerate(lines):
    if ln.lstrip().startswith("def entrypoint"):
        # search forward within entrypoint
        for j in range(i, min(i + 200, len(lines))):
            if lines[j].strip() == "except Exception:":
                # find the immediate "return 1" inside that except block
                ex_indent = lines[j].split("except Exception:")[0]
                for k in range(j+1, min(j + 40, len(lines))):
                    if lines[k].strip() == "return 1":
                        ret_indent = lines[k].split("return 1")[0]
                        # must be deeper indentation than except line
                        if len(ret_indent) > len(ex_indent):
                            idx_except = j
                            idx_return = k
                            break
                if idx_except >= 0:
                    break
        break

if idx_except < 0 or idx_return < 0:
    raise SystemExit("PATCH_FAIL: could not locate entrypoint except Exception: ... return 1 block")

ex_indent = lines[idx_except].split("except Exception:")[0]
blk = ex_indent + "    "  # indent inside except block

injected = [
    blk + "try:\n",
    blk + "    import traceback as _tb\n",
    blk + "    print('[ENTRYPOINT] UNHANDLED_EXCEPTION', file=sys.stderr)\n",
    blk + "    _tb.print_exc()\n",
    blk + "except Exception:\n",
    blk + "    pass\n",
]

# Insert injected block right after the except line, before existing return 1
lines = lines[:idx_except+1] + injected + lines[idx_except+1:]

path.write_text("".join(lines), encoding="utf-8")

print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
print("ANCHOR_LINES:", "except@", idx_except+1, "return@", idx_return+1)
