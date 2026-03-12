import argparse
from pathlib import Path
from .ect_report import run as run_report

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runroot", required=True, help="TBOT runroot, e.g. ...\\runtime\\paper")
    args = ap.parse_args()
    outdir = run_report(Path(args.runroot))
    print("ECT_V1_OK")
    print("OUTDIR=", str(outdir))

if __name__ == "__main__":
    main()
