#!/usr/bin/env bash
# pending.sh — everything that is waiting on the operator, in ONE list.
#
#   bin/seat/pending.sh [--json]
#
# Near-the-loop only works if the operator can see, in one place, what is blocked on him.
# Today that knowledge is scattered across four truthful-but-separate shelves. This door
# reads them and prints one list; it never decides anything, and it never writes.
set -u
JSON=0
[ "${1-}" = "--json" ] && JSON=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_DIR 2>/dev/null || HOME_DIR="${YMIR_HOME:-$HOME/Documents/ymirhome}"
hoard_state_dir STATE 2>/dev/null || STATE="$HOME_DIR/state"

python3 - "$ROOT" "$HOME_DIR" "$STATE" "$JSON" <<'PY'
import json, os, re, subprocess, sys, glob

root, home, state, as_json = sys.argv[1:5]
as_json = as_json == "1"
items = []

def add(kind, what, where, age=""):
    items.append({"kind": kind, "what": what, "where": where, "since": age})

# 1 · open pull requests — a merge is the operator's seal, so an open PR is waiting on him
try:
    out = subprocess.run(["gh", "pr", "list", "--repo", "zerwiz/ymir", "--state", "open",
                          "--json", "number,title,createdAt"],
                         capture_output=True, text=True, timeout=25).stdout
    for p in json.loads(out or "[]"):
        add("pull request", f'#{p["number"]} {p["title"][:70]}', "github", p.get("createdAt", "")[:10])
except Exception:
    pass

# 2 · the wake queue — a line in it is a message the seat has not answered yet
q = os.path.join(state, ".wake-queue")
if os.path.exists(q):
    for line in open(q, errors="ignore"):
        if line.strip():
            add("wake", line.strip()[:90], ".wake-queue")

# 3 · mail drafts — a drafted letter waits for a word before it leaves
try:
    out = subprocess.run(["bash", os.path.join(root, "systems/snotra/services/letters/mail-send.sh"), "status"],
                         capture_output=True, text=True, timeout=25).stdout
    for line in out.splitlines():
        if "draft" in line.lower() and ("r-" in line or "waiting" in line.lower()):
            add("mail draft", line.strip()[:90], "mail-send status")
except Exception:
    pass

# 4 · the status shelf — lines the record itself marks as the operator's
for p in glob.glob(os.path.join(home, "hodd/docs/status/*.md")):
    for line in open(p, errors="ignore"):
        if "needs the operator" in line.lower() or "needs his word" in line.lower():
            add("decision", line.strip(' "\n')[:100], os.path.relpath(p, home))

if as_json:
    print(json.dumps({"count": len(items), "items": items}))
else:
    print(f'pending[{len(items)}]{{kind,what,where,since}}:')
    for i in items:
        print(f'  "{i["kind"]}","{i["what"]}","{i["where"]}","{i["since"]}"')
    if not items:
        print('  "nothing","nothing is waiting on the operator","-","-"')
PY
