#!/usr/bin/env bash
# prune.sh — the retention window, as a tool rather than a promise.
#
#   bin/assistant/prune.sh [--days 90] [--apply]
#
# The audit's open compliance item: `assistant.db` holds third-party conversations with no window and
# no deletion path (372 turns in the first day). Dry-run by DEFAULT — it prints what would go and
# changes nothing. `--apply` is the Allfather's decision, and it is written to the ledger first.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'prune: the hoard is unresolved\n' >&2; exit 2; }
DAYS=90; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="${2:-90}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    *) shift ;;
  esac
done
DB="$HOME_R/hodd/state/assistant/assistant.db"
[ -f "$DB" ] || { printf 'prune: no ledger\n'; exit 0; }
python3 - "$DB" "$DAYS" "$APPLY" <<'PY'
import sqlite3, sys, time
db, days, apply = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1"
cut = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - days * 86400))
con = sqlite3.connect(db)
old = con.execute("select count(*) from conversations where ts < ?", (cut,)).fetchone()[0]
old_turns = con.execute("select count(*) from turns where ts < ?", (cut,)).fetchone()[0]
total = con.execute("select count(*) from conversations").fetchone()[0]
print(f'retention[1]{{window_days,would_delete,of_total,turns,applied}}:')
print(f'  "{days}","{old}","{total}","{old_turns}","{"yes" if apply else "no"}"')
if apply and old:
    con.execute("delete from conversations where ts < ?", (cut,))
    con.execute("delete from turns where ts < ?", (cut,))
    con.commit()
    con.execute("vacuum")
    print(f'prune: removed {old} conversation(s) and {old_turns} turn(s) older than {days} days')
con.close()
PY
