#!/usr/bin/env bash
# group-allow.sh — let Skírnir speak in ONE Telegram group, after the Allfather approves it.
#
#   bin/assistant/group-allow.sh <chat-id> "<title>"      # appends to groups.yaml (collaborator tier)
#
# Never called by the adapter directly: the adapter ASKS (through the approval door), and this runs
# when the Allfather approves. A bot can be added to a group by anyone; a bot that starts talking
# there without a word from him is a bot that can be pointed at strangers.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'error: the home is unresolved\n' >&2; exit 1; }
ID="${1:-}"; TITLE="${2:-}"
[ -n "$TITLE" ] || TITLE="$(python3 - "$HOME_R/hodd/state/assistant/seen-groups.json" "$ID" 2>/dev/null <<'PY'
import json, sys
try:
    seen = json.load(open(sys.argv[1]))
    print(seen.get(sys.argv[2], {}).get("title", "unnamed"))
except Exception:
    print("unnamed")
PY
)"; TITLE="${TITLE:-unnamed}"
[ -n "$ID" ] || { printf 'usage: group-allow.sh <chat-id> "<title>"\n' >&2; exit 2; }
G="$HOME_R/hodd/identity/assistant/groups.yaml"

python3 - "$G" "$ID" "$TITLE" <<'PY'
import sys, yaml, pathlib, datetime
path, cid, title = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
data = yaml.safe_load(p.read_text()) if p.exists() else {}
data = data or {}
rows = data.get("groups") or []
if not any(str(r.get("id")) == str(cid) for r in rows):
    rows.append({"id": str(cid), "name": title, "tier": "collaborator",
                 "added_by": "the Allfather (approved)",
                 "added_at": datetime.date.today().isoformat()})
data["groups"] = rows
p.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
print(f'group-allow: {cid} "{title}" — collaborator tier')
PY
bash "$ROOT/bin/records/runes-append.sh" brokk assistant \
  --message "Skírnir allowed in group $ID ($TITLE) at collaborator tier" >/dev/null 2>&1 || true
