#!/usr/bin/env bash
# group-add.sh — put Skírnir in a Telegram group, in one word.
#
#   group-add.sh                  # every group he has seen, and whether he answers there
#   group-add.sh allow <name|id>  # allow it: he answers there WHEN NAMED (never every message)
#   group-add.sh close <name|id>  # stop answering there at all (he is removed from the allowlist)
#
# THE LAW (the Allfather's word, 2026-10-23): "only my private chat should be answering on all.
# groups never." `allow` therefore grants the ROOM, never the loudness — there is no switch that makes
# him answer every message in a group, and this door no longer writes one.
#
# WHY: adding him used to mean reading a chat id out of a journal and editing YAML. A bot cannot join a
# group from an invite link — Telegram has no such API — so the human adds the bot once, he RECORDS the
# group (that is what `seen-groups.json` is for), and this door is the one word that follows.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root H 2>/dev/null || true
SEEN="$H/hodd/state/assistant/seen-groups.json"
GROUPFILE="$H/hodd/identity/assistant/groups.yaml"   # NOT `GROUPS`: that is a bash BUILT-IN array
                                                     # (the user's unix groups) and the assignment
                                                     # silently becomes `1000` — measured 2026-10-23
ACTION="${1:-list}"; WANT="${2:-}"
python3 - "$SEEN" "$GROUPFILE" "$ACTION" "$WANT" <<'PY'
import json, os, sys, yaml
seen_path, groups_path, action, want = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

seen = {}
try:
    seen = json.load(open(seen_path))
except Exception:
    pass
path = groups_path
try:
    doc = yaml.safe_load(open(path)) or {}
except Exception:
    doc = {}
groups = doc.setdefault("groups", [])
allowed = {str(g.get("id")): g for g in groups}

def find(want):
    if not want:
        return None
    for cid, row in seen.items():
        title = row.get("title") or ""
        if want == cid or want.lower() in title.lower():
            return cid, title          # the RECORDED title, not the query's casing
    for cid, g in allowed.items():
        if want.lower() in str(g.get("name", "")).lower():
            return cid, g.get("name")
    return None

if action == "list":
    print("groups[{n}]{id,title,answers,owner_trusted}:")
    print(f"groups{len(seen)}")
    for cid, row in seen.items():
        g = allowed.get(cid) or {}
        answers = "when named" if g else "NO — he is not allowed here"
        print(f'  "{cid}","{row.get("title","")}","{answers}","{bool(g.get("owner_trusted")) if g else False}"')
    sys.exit(0)

hit = find(want)
if not hit:
    print(f"group-add: no group matches {want!r} — run group-add.sh to see them", file=sys.stderr)
    sys.exit(3)
cid, title = hit
if action == "allow":
    row = allowed.get(cid) or {"id": cid, "name": title}
    row.update({"name": title or row.get("name", ""), "tier": row.get("tier", "collaborator"),
                "owner_trusted": True,
                "added_by": "the Allfather", "added_at": "2026-10-23"})
    row.pop("addressed_only", None)          # the law: a room never answers every message
    if cid not in allowed:
        groups.append(row)
    else:
        for i, g in enumerate(groups):
            if str(g.get("id")) == cid:
                groups[i] = row
    yaml.safe_dump(doc, open(path, "w"), sort_keys=False, allow_unicode=True)
    print(f'group_add[1]{{id,title,answers}}: "{cid}","{title}","only when named"')
elif action == "close":
    # a closed room is a room he is not allowed in: the row goes, so nothing answers there at all
    keep = [g for g in groups if str(g.get("id")) != cid]
    if len(keep) != len(groups):
        doc["groups"] = keep
        yaml.safe_dump(doc, open(path, "w"), sort_keys=False, allow_unicode=True)
        print(f'group_add[1]{{id,title,answers}}: "{cid}","{title}","not allowed — silent"')
    else:
        print(f'group_add[1]{{id,title,answers}}: "{cid}","{title}","was not allowed"')
else:
    print("usage: group-add.sh [list|allow <name|id>|close <name|id>]", file=sys.stderr); sys.exit(2)
PY
