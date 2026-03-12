import csv
from pathlib import Path

SRC = Path(r".\replay\replay_suite_01_trend.csv")   # می‌تونی این رو به suite_02_chop هم تغییر بدی
DST = Path(r".\replay\replay_suite_03_highvol.csv")

# HighVol settings
VOL_MULT = 6.0    # شدت نوسان (۶ برابر)
EMA_JITTER = 0.6  # میزان جدا شدن ema ها

rows = []
with SRC.open("r", newline="", encoding="utf-8") as f:
    r = csv.DictReader(f)
    for row in r:
        last = float(row["last"])
        vwap = float(row["vwap"])
        ef = float(row["ema_fast"])
        es = float(row["ema_slow"])

        # amplify last-vwap distance and ema separation
        dv = (last - vwap) * VOL_MULT
        de = (ef - es) * max(1.0, VOL_MULT * EMA_JITTER)

        row["last"] = f"{(vwap + dv):.4f}"
        mid = (ef + es) / 2.0
        row["ema_fast"] = f"{(mid + de/2.0):.4f}"
        row["ema_slow"] = f"{(mid - de/2.0):.4f}"
        rows.append(row)

DST.parent.mkdir(parents=True, exist_ok=True)
with DST.open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["symbol","last","vwap","ema_fast","ema_slow"])
    w.writeheader()
    w.writerows(rows)

print("WROTE:", str(DST), "rows=", len(rows))
