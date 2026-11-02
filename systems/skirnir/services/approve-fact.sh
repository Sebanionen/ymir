#!/usr/bin/env bash
# approve-fact.sh — promote a pending fact into the approved digest. Run by the approval click.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
S="$HOME_R/hodd/identity/assistant"
SLUG="${1:-}"; [ -n "$SLUG" ] || { printf 'usage: approve-fact.sh <slug>\n' >&2; exit 2; }
P="$S/pending/$SLUG.md"; [ -r "$P" ] || { printf 'approve-fact: no pending fact %s\n' "$SLUG" >&2; exit 2; }
python3 - "$P" "$S/approved/$SLUG.md" <<'PY'
import sys, pathlib, datetime
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
text = src.read_text()
text = text.replace("approved_by: (pending)", "approved_by: the Allfather")
text = text.replace('approved_at: ""', f"approved_at: {datetime.date.today().isoformat()}")
dst.write_text(text)
src.unlink()
print("approved", dst.name)
PY
bash "$SCRIPT_DIR/kb-export.sh" >/dev/null 2>&1 || true
bash "$ROOT/bin/records/runes-append.sh" brokk assistant \
  --message "approved a learned fact: $SLUG" >/dev/null 2>&1 || true
printf 'approved %s\n' "$SLUG"
