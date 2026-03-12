import io, os, re

ROOT = r"C:\alpaca-bot\org_bot"
F = os.path.join(ROOT, r"tbot\runtime\orchestrator.py")

with io.open(F, "r", encoding="utf-8") as f:
    s = f.read()

orig = s

def force_info_for_kind(text: str, kind_name: str) -> str:
    # make_event(level='X', kind='kind_name' ...)
    pattern = re.compile(
        r"make_event\((?P<body>[^)]*?\bkind\s*=\s*['\"]" + re.escape(kind_name) + r"['\"][^)]*?)\)",
        re.DOTALL,
    )

    def repl(m):
        body = m.group("body")

        if re.search(r"\blevel\s*=\s*['\"]", body):
            body2 = re.sub(
                r"(\blevel\s*=\s*['\"])(ERROR|WARN)(['\"])",
                r"\1INFO\3",
                body,
            )
        else:
            body2 = "level='INFO', " + body

        return "make_event(" + body2 + ")"

    return pattern.sub(repl, text)

s = force_info_for_kind(s, "portfolio_kill_change")
s = force_info_for_kind(s, "alpha_kill_change")

if s == orig:
    raise SystemExit("PATCH FAILED: no kill_change make_event(...) call matched")

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(s)

print("PATCHED:", F)
