#!/usr/bin/env bash
# escalation-timer.sh — the fifth part of a stop rule: what happens if nobody answers.
#
#   bin/assistant/escalation-timer.sh
#
# An approval or an escalation older than four hours gets ONE reminder; older than a day it joins the
# morning digest instead of being quietly forgotten. Run every thirty minutes by a user timer.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
DIR="$HOME_R/hodd/state/notify/approvals"
DOOR="$ROOT/bin/notify/send.sh"
[ -d "$DIR" ] || { printf 'escalation-timer[1]{state}: "nothing pending"\n'; exit 0; }

# ── and the ASKS: a question handed to him that nobody has answered ────────────────────────────
# The approvals pass below covers `notify/approvals` only. An ask from a PERSON sat silently forever
# (measured 2026-10-22), so it gets the same treatment: one reminder after four hours.
ASKS="$HOME_R/hodd/state/assistant/asks.json"
if [ -f "$ASKS" ]; then
  ROOT_DIR="$ROOT" ASKS_Q="$ASKS" DOOR_Q="$DOOR" python3 - <<'PY'
import json, os, subprocess, time
path = os.environ["ASKS_Q"]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
changed = 0
for ask in data.get("asks", []):
    if ask.get("status") != "open" or ask.get("reminded"):
        continue
    age_h = (time.time() - float(ask.get("at", 0))) / 3600
    if age_h < 4:
        continue
    msg = (f"Still waiting on you: {ask.get('who','someone')} asked “{ask.get('question','')[:140]}” "
           f"{age_h:.0f} h ago. Answer with: tell {ask.get('who','them')}: …")
    subprocess.run(["bash", os.environ["DOOR_Q"], "--source", "assistant", "--severity", "HIGH",
                    "--message", msg, "--key", f"ask-reminder:{ask.get('id')}"],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ask["reminded"] = 1
    changed += 1
if changed:
    json.dump(data, open(path, "w"), indent=1)
    print(f'escalation-timer: reminded {changed} open ask(s)')
PY
fi

ROOT_DIR="$ROOT" DIR_Q="$DIR" DOOR_Q="$DOOR" python3 - <<'PY'
import glob, json, os, subprocess, time
reminded = 0; digest = []
for path in glob.glob(os.path.join(os.environ["DIR_Q"], "*.json")):
    try:
        rec = json.load(open(path))
    except Exception:
        continue
    if rec.get("decision"):
        continue
    asked = rec.get("asked_at", "")
    try:
        age_h = (time.time() - time.mktime(time.strptime(asked[:19], "%Y-%m-%dT%H:%M:%S"))) / 3600
    except Exception:
        continue
    if age_h >= 24:
        digest.append(rec.get("question", "")[:100])
    elif age_h >= 4 and not rec.get("reminded"):
        subprocess.run(["bash", os.environ["DOOR_Q"], "--source", "assistant", "--severity", "MEDIUM",
                        "--message", f"still waiting on you ({int(age_h)}h): {rec.get('question','')[:120]}",
                        "--key", f"remind:{rec.get('id','')}"],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        rec["reminded"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        json.dump(rec, open(path, "w"))
        reminded += 1
print(f'escalation-timer[1]{{reminded,digest}}:"{reminded}","{len(digest)}"')
for line in digest:
    print(f'  "unanswered for a day: {line}"')
PY
