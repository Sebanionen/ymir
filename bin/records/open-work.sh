#!/usr/bin/env bash
# open-work.sh — the open work, rendered for a HUMAN, from the record the doors read.
#
#   bin/records/open-work.sh [--file PATH] [--md] [--json] [--write]
#
# The status shelf writes its list as a TOON block (`open_work[17]{…}`) because that is
# what a door reads. A human does not read TOON on a phone — so this door renders the
# SAME record as a plain list: one line per item, its state in words, its owner, and
# the proof that closes it. `--write` refreshes the companion `.md` beside the source.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_DIR 2>/dev/null || HOME_DIR="${YMIR_HOME:-$HOME/Documents/ymirhome}"

FILE=""; MODE=text
while [ $# -gt 0 ]; do case "$1" in
  --file) FILE="${2-}"; shift 2 ;;
  --md) MODE=md; shift ;;
  --json) MODE=json; shift ;;
  --write) MODE=write; shift ;;
  *) shift ;;
esac; done
if [ -z "$FILE" ]; then
  # the newest SOURCE, never a rendered companion (`*-readable.md` carries no TOON block)
  FILE="$(ls -t "$HOME_DIR"/hodd/docs/status/*.md 2>/dev/null | grep -v -- '-readable\.md$' | head -1)"
fi
[ -n "$FILE" ] && [ -r "$FILE" ] || { printf 'open-work: no status document found under hodd/docs/status/\n' >&2; exit 2; }

python3 - "$FILE" "$MODE" <<'PY'
import json, os, re, sys
path, mode = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8", errors="ignore").read()
m = re.search(r"open_work\[(\d+)\]\{([^}]*)\}:", text)
if not m:
    print("open-work: no open_work block in this document", file=sys.stderr); raise SystemExit(1)
keys = [k.strip() for k in m.group(2).split(",")]
rows, got, count = [], 0, int(m.group(1))
for line in text[m.end():].splitlines():
    s = line.strip()
    if s.startswith('"'):
        cells = re.findall(r'"((?:[^"\\]|\\.)*)"', s)
        if cells:
            rows.append(dict(zip(keys, cells))); got += 1
        if got >= count: break
    elif s and not s.startswith(("#", "`", "-", "*")):
        break

STATE_ORDER = {"doing": 0, "open": 1, "needs the operator": 2, "needs another machine": 3}
rows.sort(key=lambda r: (STATE_ORDER.get(r.get("state", ""), 9), int(r.get("#", r.get("num", "99")))))

if mode == "json":
    print(json.dumps({"count": len(rows), "items": rows}, indent=1)); raise SystemExit(0)

title = re.search(r"^# (.+)$", text, re.M)
lines = [f"# {title.group(1) if title else os.path.basename(path)}", ""]
lines.append(f"*{len(rows)} items, from `{os.path.basename(path)}`. Rendered for reading; the source stays TOON for the doors.*")
lines.append("")
by_state = {}
for r in rows:
    by_state.setdefault(r.get("state", "open"), []).append(r)
for state, items in by_state.items():
    lines.append(f"## {state.capitalize()}")
    lines.append("")
    for r in items:
        n = r.get("#") or r.get("num")
        lines.append(f"- **{r.get('item','')}** — owner {r.get('owner','?')}")
        if r.get("proof_when_done"):
            lines.append(f"  - done when: {r['proof_when_done']}")
    lines.append("")
out = "\n".join(lines)

if mode == "write":
    dest = os.path.splitext(path)[0] + "-readable.md"
    open(dest, "w").write(out)
    print(dest)
else:
    print(out)
PY
