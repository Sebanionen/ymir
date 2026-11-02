#!/usr/bin/env bash
# report.sh — what Skírnir was asked, what he could not answer, and who is still waiting.
#
#   bin/assistant/report.sh              # TOON, for a terminal or a cron log
#   bin/assistant/report.sh --notify     # the same, sent to the Allfather through Hófvarpnir
#
# WHY: the tower shows a NUMBER (turnsToday, refusalsToday). The Allfather asked for the LIST — which
# questions he could not answer, who asked them, and what is still open — because that is the only
# way he can decide what Skírnir should be taught next.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'report: the hoard is unresolved\n' >&2; exit 2; }
STATE="$HOME_R/hodd/state/assistant"
NOTIFY=0
[ "${1:-}" = "--notify" ] && NOTIFY=1

OUT="$(STATE_Q="$STATE" python3 - <<'PY'
import json, os, sqlite3, time, glob

state = os.environ["STATE_Q"]
today = time.strftime("%Y-%m-%d")
lines = []

# what he holds
try:
    digest = [json.loads(l) for l in open(os.path.join(state, "digest.jsonl")) if l.strip()]
except Exception:
    digest = []
classes = {}
for row in digest:
    classes[str(row.get("class", "public"))] = classes.get(str(row.get("class", "public")), 0) + 1
lines.append(f'held[{len(classes)}]{{class,count}}:')
lines.append(f'held{len(classes)}')
for k in sorted(classes):
    lines.append(f'  "{k}","{classes[k]}"')

# today's traffic
turns = refused = research = 0
unknowns = []
try:
    con = sqlite3.connect(os.path.join(state, "assistant.db"))
    turns = con.execute("select count(*) from conversations where ts like ?", (today + "%",)).fetchone()[0]
    refused = con.execute("select count(*) from conversations where ts like ? and refused=1",
                          (today + "%",)).fetchone()[0]
    research = con.execute("select count(*) from conversations where ts like ? and intent like 'research%'",
                           (today + "%",)).fetchone()[0]
    seen = set()
    for q, intent in con.execute("select question, intent from conversations where ts like ? and refused=1 "
                                 "order by rowid desc limit 40", (today + "%",)):
        key = (q or "").strip().lower()[:80]
        if key and key not in seen:
            seen.add(key)
            unknowns.append((q or "", intent or ""))
except Exception:
    pass
lines.append('traffic[1]{turns,refused,research}:')
lines.append("traffic1")
lines.append(f'  "{turns}","{refused}","{research}"')

# who is waiting
try:
    asks = json.load(open(os.path.join(state, "asks.json"))).get("asks", [])
except Exception:
    asks = []
open_asks = [a for a in asks if a.get("status") == "open"]
open_asks.sort(key=lambda a: a.get("at", 0))
lines.append(f'waiting[{len(open_asks)}]{{who,age_h,question}}:')
lines.append(f"waiting{len(open_asks)}")
for a in open_asks[:12]:
    age = round((time.time() - float(a.get("at", 0))) / 3600, 1)
    lines.append(f'  "{a.get("who","")}","{age}","{a.get("question","")[:100]}"')

lines.append(f'unanswered[{len(unknowns[:12])}]{{question}}:')
lines.append(f"unanswered{len(unknowns[:12])}")
for q, _intent in unknowns[:12]:
    lines.append(f'  "{q[:110]}"')

beat = os.path.join(state, "telegram.heartbeat")
age = -1
try:
    age = round(time.time() - os.path.getmtime(beat))
except Exception:
    pass
lines.append('service[1]{heartbeat_age_s,up}:')
lines.append(f'  "{age}","{"yes" if 0 <= age < 600 else "no"}"')
print("\n".join(lines))
PY
)"

printf '%s\n' "$OUT"
if [ "$NOTIFY" -eq 1 ] && [ -x "$ROOT/bin/notify/send.sh" ]; then
  bash "$ROOT/bin/notify/send.sh" --source assistant --severity MEDIUM \
    --message "Skírnir's day: $(printf '%s' "$OUT" | grep -A1 '^traffic1' | tail -1 | tr -d '"') — open questions: $(printf '%s' "$OUT" | grep '^waiting[0-9]' | sed 's/waiting//')" \
    --key "assistant-report:$(date +%Y-%m-%d)" >/dev/null 2>&1 || true
fi
