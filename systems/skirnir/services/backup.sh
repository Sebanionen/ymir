#!/usr/bin/env bash
# backup.sh — his ledger must survive this disk.
#
#   bin/assistant/backup.sh [--keep N] [--commit] [--push]
#
# `hodd/state/` is gitignored, so `assistant.db` — every question anyone asked him, every refusal,
# every answer — is the ONE artifact in this house that dies with the hardware (measured 2026-10-22:
# 372 turns in a day, no copy anywhere). This snapshots the ledger and its policy files into
# `hodd/saves/assistant/<date>/`, which IS tracked, and prunes old snapshots.
#
# `--commit` stages and commits the newest snapshot in the home repo; `--push` also pushes it, so the
# fleet gets the ledger on its next pull. The Allfather's word (2026-10-22): "yes and on pushes" — the
# nightly row runs `--keep 7 --push`, and the home repo carries a `pre-push` hook that snapshots on
# every push as a safety net (a hook commit lands on the NEXT push; run `--commit` first to ride the
# same one).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'backup: the hoard is unresolved\n' >&2; exit 2; }
KEEP=7; COMMIT=0; PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP="${2:-7}"; shift 2 ;;
    --commit) COMMIT=1; shift ;;
    --push) COMMIT=1; PUSH=1; shift ;;
    *) shift ;;
  esac
done
STATE="$HOME_R/hodd/state/assistant"
DEST="$HOME_R/hodd/saves/assistant/$(date +%Y-%m-%d)"
mkdir -p "$DEST" || exit 3
copied=0
for f in assistant.db asks.json digest.jsonl pending-ask.json; do
  [ -f "$STATE/$f" ] || continue
  if command -v sqlite3 >/dev/null 2>&1 && [ "$f" = "assistant.db" ]; then
    sqlite3 "$STATE/$f" ".backup '$DEST/$f'" 2>/dev/null && copied=$((copied+1)) || cp -f "$STATE/$f" "$DEST/$f"
  else
    cp -f "$STATE/$f" "$DEST/$f" && copied=$((copied+1))
  fi
done
[ -d "$HOME_R/hodd/identity/assistant" ] && cp -a "$HOME_R/hodd/identity/assistant/." "$DEST/identity/" 2>/dev/null
# rotate
ls -1d "$HOME_R/hodd/saves/assistant/"*/ 2>/dev/null | sort | head -n -"$KEEP" | while read -r old; do
  rm -rf "$old"
done
printf 'backup[1]{files,dir,kept}:\n  "%s","%s","%s"\n' "$copied" "$DEST" "$KEEP"
if [ "$COMMIT" -eq 1 ] && [ -d "$HOME_R/.git" ]; then
  # ONLY this shelf is staged: the home routinely carries other work in flight, and a blanket add
  # would sweep it into a commit (the 2026-09-17 incident).
  if ( cd "$HOME_R" && git add "hodd/saves/assistant" >/dev/null 2>&1 \
       && ! git diff --cached --quiet ); then
    ( cd "$HOME_R" && git commit -q -m "hoard: skírnir's ledger snapshot $(date +%Y-%m-%d)" >/dev/null 2>&1 \
      && printf 'backup: committed to the home repo\n' )
    if [ "$PUSH" -eq 1 ]; then
      ( cd "$HOME_R" && git push -q 2>/dev/null && printf 'backup: pushed — the fleet gets it on the next pull\n' ) \
        || printf 'backup: commit made, push failed (no remote, or offline)\n'
    fi
  else
    printf 'backup: nothing new to commit\n'
  fi
fi
