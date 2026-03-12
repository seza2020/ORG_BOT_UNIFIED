import json, collections, sys
p=r"C:\alpaca-bot\org_bot_runtime\paper\logs\meta.jsonl"
cnt=collections.Counter()
bad=0
n=0
with open(p,"r",encoding="utf-8",errors="replace") as f:
    for ln in f:
        ln=ln.strip()
        if not ln: 
            continue
        n+=1
        try:
            obj=json.loads(ln)
        except Exception:
            bad+=1
            continue
        k=obj.get("kind","<none>")
        cnt[k]+=1
        if n>=5000:
            break
print("FILE", p)
print("sample_lines", n, "bad_json", bad)
print("top_kinds", cnt.most_common(20))
