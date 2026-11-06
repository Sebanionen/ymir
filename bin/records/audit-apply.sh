#!/usr/bin/env bash
# audit-apply.sh — turn an audit into work, in one door.
#
#   bin/records/audit-apply.sh <audit.md> [--json] [--tickets]
#
# An audit that nobody acts on is a document, not a decision. This door reads the TOON
# blocks an audit already carries (`owed[…]`, `gaps[…]`, `fixes[…]`, `build[…]`, `last_mile[…]`)
# and emits ONE work list: what is owed, who owns it, and the proof that closes it.
#
#   --tickets   print ready-to-file ticket titles (namespace ymir) — it never files them;
#               filing is a write, and a write is the operator's word or an agent's task.
#
# Exit: 0 rows found · 1 no actionable block · 2 usage.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FILE="${1-}"; shift || true
JSON=0; TICKETS=0
while [ $# -gt 0 ]; do case "$1" in
  --json) JSON=1; shift ;;
  --tickets) TICKETS=1; shift ;;
  *) shift ;;
esac; done
[ -n "$FILE" ] || { printf 'usage: audit-apply.sh <audit.md> [--json] [--tickets]\n' >&2; exit 2; }
[ -r "$FILE" ] || { printf 'audit-apply: cannot read %s\n' "$FILE" >&2; exit 2; }

python3 - "$FILE" "$JSON" "$TICKETS" <<'PY'
import json, re, sys

path, as_json, as_tickets = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
text = open(path, encoding="utf-8", errors="ignore").read()

# A TOON block: `name[N]{k1,k2,…}:` then N rows of `"…","…",…`
BLOCK = re.compile(r"^([a-z_]+)\[(\d+)\]\{([^}]*)\}:\s*$", re.M)
ACTIONABLE = ("owed", "gaps", "fixes", "build", "last_mile", "changes", "moves", "next")

rows = []
for m in BLOCK.finditer(text):
    name, count, keys = m.group(1), int(m.group(2)), [k.strip() for k in m.group(3).split(",")]
    if name not in ACTIONABLE:
        continue
    rest = text[m.end():].split("\n")
    got = 0
    for line in rest:
        s = line.strip()
        if not s.startswith('"'):
            if s and not s.startswith(("#", "---", "`")):
                break
            continue
        cells = re.findall(r'"((?:[^"\\]|\\.)*)"', s)
        if not cells:
            continue
        row = dict(zip(keys, [c.replace('\\"', '"') for c in cells]))
        rows.append({"block": name, **row})
        got += 1
        if got >= count:
            break

if not rows:
    print("audit-apply: no actionable block (owed · gaps · fixes · build) found — nothing to file", file=sys.stderr)
    sys.exit(1)

def what(r):
    for k in ("item", "gap", "fix", "what", "move", "change", "step", "#", "id"):
        if r.get(k):
            return str(r[k])
    return next((v for v in r.values() if v), "")

def owner(r):
    for k in ("owner", "who", "by"):
        if r.get(k):
            return str(r[k])
    return "unowned"

def proof(r):
    for k in ("proof", "proof_when_done", "proved", "evidence", "fix", "why"):
        if r.get(k):
            return str(r[k])
    return ""

items = [{"source": path.split("/")[-1], "block": r["block"], "what": what(r), "owner": owner(r), "proof": proof(r)}
         for r in rows]

if as_json:
    print(json.dumps({"count": len(items), "items": items}))
elif as_tickets:
    for i in items:
        title = f"audit: {i['what'][:70]}"
        print(f"{title} | namespace=ymir | proof={i['proof'][:80] or '-'}")
else:
    print(f'audit_work[{len(items)}]{{block,what,owner,proof}}:')
    for i in items:
        esc = lambda s: s.replace('"', "'")[:110]
        print(f'  "{i["block"]}","{esc(i["what"])}","{esc(i["owner"])}","{esc(i["proof"])}"')
PY
