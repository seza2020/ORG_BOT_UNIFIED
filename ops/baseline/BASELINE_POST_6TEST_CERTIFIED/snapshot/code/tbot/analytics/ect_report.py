import json
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

from .ect_parse_meta import load_meta_events, kcount, by_sid_none, alpha_off_reasons

def write_json(p: Path, obj: Dict[str, Any]) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")

def write_md(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")

def build_report(runroot: Path) -> Dict[str, Any]:
    events = load_meta_events(runroot)
    kc = kcount(events)
    sid = by_sid_none(events)
    aoff = alpha_off_reasons(events)

    report = {
        "ts_utc": datetime.utcnow().isoformat() + "Z",
        "runroot": str(runroot),
        "meta_events_count": len(events),
        "event_kind_counts": kc,
        "strategy_none_by_sid": sid,
        "alpha_off_reasons": aoff,
    }
    return report

def render_md(r: Dict[str, Any]) -> str:
    lines=[]
    lines.append("# EDGE CONTROL TOWER — V1 Report")
    lines.append("")
    lines.append(f"- ts_utc: `{r.get('ts_utc')}`")
    lines.append(f"- runroot: `{r.get('runroot')}`")
    lines.append(f"- meta_events_count: `{r.get('meta_events_count')}`")
    lines.append("")
    lines.append("## Event kind counts")
    for k,v in sorted((r.get("event_kind_counts") or {}).items(), key=lambda x: (-x[1], x[0])):
        lines.append(f"- **{k}**: {v}")
    lines.append("")
    lines.append("## Alpha OFF reasons")
    aoff = r.get("alpha_off_reasons") or {}
    if not aoff:
        lines.append("- (none)")
    else:
        for k,v in sorted(aoff.items(), key=lambda x: (-x[1], x[0])):
            lines.append(f"- {k}: {v}")
    lines.append("")
    lines.append("## Strategy NONE by SID")
    sid = r.get("strategy_none_by_sid") or {}
    if not sid:
        lines.append("- (none)")
    else:
        for s, d in sid.items():
            total = d.get("TOTAL",0)
            none  = d.get("NONE",0)
            rate = (none/total*100.0) if total else 0.0
            lines.append(f"- **{s}**: NONE {none}/{total} ({rate:.1f}%)")
    lines.append("")
    lines.append("## Notes")
    lines.append("- V1 is read-only: no runtime patches.")
    lines.append("- If NONE dominates, next step is V2: richer reject reasons.")
    return "\n".join(lines)

def run(runroot: Path) -> Path:
    r = build_report(runroot)
    outdir = runroot / "reports" / "ect_v1"
    jsonp = outdir / "ect_report.json"
    mdp   = outdir / "ect_report.md"
    write_json(jsonp, r)
    write_md(mdp, render_md(r))
    return outdir
