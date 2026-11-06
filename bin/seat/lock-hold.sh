#!/usr/bin/env bash
# lock-hold.sh — a PRIMARY THAT DOES NOT EXIT: hold this machine's session lock, for the seat's life.
#
# WHY (plan 206 §11.3 #1): the review loop does not decide — it ASKS the lock owner, by design
# ("a read-only agent waits for a primary rather than deciding for one"). On a headless heart no
# interactive session exists to hold that lock: `hodd/state/.lock-path` named a `brokk.lock` that
# did not exist, so `review-watch` saw five open PRs every ten minutes and raised none —
#   "there is NO lock on this machine — nobody holds it, so there is nobody to ask".
# A lock taken by a shell that then exits is not a lock. This is the process that stays.
#
#   bin/seat/lock-hold.sh            # acquire and hold in the foreground (systemd runs this)
#   bin/seat/lock-hold.sh --status   # who holds it now, and is that owner alive
#
# It never steals: if a live session already owns the lock, the holder waits and re-checks. When
# that session ends, the reaper clears the stale record and the holder takes it over — so the seat
# always has a primary, whether or not a human is in a pane.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/gleipnir-lock-lib.sh" 2>/dev/null || { echo "lock-hold: no gleipnir-lock-lib" >&2; exit 1; }

if [ "${1-}" = "--status" ]; then
  gleipnir_lock_path lockf; gleipnir_lock_owner owner; gleipnir_lock_reap
  live=no; [ -n "$owner" ] && gleipnir_pid_alive "$owner" && live=yes
  printf 'lock-hold[3]{lock,owner,live}:\n  "%s","%s","%s"\n' "${lockf:-?}" "${owner:-none}" "$live"
  exit 0
fi

WANT="${BROKK_LOCK_HOLD_NAME:-seat-lock}"
gleipnir_lock_reap

_release() {
  gleipnir_lock_release >/dev/null 2>&1 || true
  printf 'lock-hold: released by %s\n' "$WANT" >&2
  exit 0
}
trap _release TERM INT HUP

printf 'lock-hold: %s holding the seat lock (pid %s)\n' "$WANT" "$$" >&2
while :; do
  if gleipnir_lock_owned; then
    : # already ours — nothing to do but stay alive
  elif gleipnir_lock_acquire; then
    gleipnir_lock_owner o; printf 'lock-hold: acquired · owner=%s\n' "${o:-?}" >&2
  else
    # A live session holds it: that IS a primary. Wait, and take over when it ends.
    gleipnir_lock_owner o; gleipnir_lock_reap
    printf 'lock-hold: yielding to live owner %s\n' "${o:-?}" >&2
  fi
  sleep 20
done
