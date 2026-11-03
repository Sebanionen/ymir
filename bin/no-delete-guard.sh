#!/usr/bin/env bash
# no-delete-guard.sh — Rule 11, ENFORCED. A tracked file is never deleted.
#
# WHY (2026-10-01): the Allfather — *"we can not never ever delete a file … if we need to delete it,
# we move it into ymir home to a reference folder so we can always learn from it … if we are porting
# anything … it's always getting features lost in the porting."* RULES/11 states the law; nothing
# enforced it, which made it an intention.
#
# What this does, and does NOT do:
#   · REFUSES any commit or push that deletes a tracked file.
#   · has ONE escape — YMIR_ALLOW_DELETE="<reason>" — which is **logged** with the reason, so a
#     deletion is always deliberate, always attributable, and NEVER silent.
#   · does NOT decide what should be deleted. To retire a file, MOVE it:
#       git mv <old> $YMIR_HOME/hodd/reference/<path>   (Rule 11, and the migration path)
#
#   Wired into .git/hooks/{pre-commit,pre-push} AFTER its refusal was observed to refuse
#   (scratch repo: staged deletion -> rc=1; with a reason -> rc=0 and a log line naming the
#   files). A guard not yet seen to refuse is worse than no guard, so that came first.
#
#   bin/no-delete-guard.sh --staged        # what a pre-commit hook would ask
#   bin/no-delete-guard.sh --base main    # what CI asks: what does this range delete?
#   YMIR_ALLOW_DELETE="superseded by src/…" bin/no-delete-guard.sh --staged
set -uo pipefail

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="$(_root)"
cd "$ROOT" || exit 2

MODE="${1:---staged}"
BASE="${2:-}"
case "$MODE" in
  # --name-only for the DELETED set, not a `--name-status | awk $2`: a path with a space was
  # logged as its first word (`Wed` for a file named `Wed 2026-09-30 …`), and a truncated path
  # in the deleted-on-purpose log is a record that cannot be read back (measured 2026-11-03).
  --staged)      deleted=$(git diff --cached --diff-filter=D --name-only 2>/dev/null) ;;
  --base)        [ -n "$BASE" ] || { echo "no-delete-guard: --base needs a ref" >&2; exit 2; }
                 deleted=$(git diff --diff-filter=D --name-only "$BASE"...HEAD 2>/dev/null) ;;
  -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)             echo "usage: no-delete-guard.sh [--staged | --base <ref>]" >&2; exit 2 ;;
esac
[ -n "$deleted" ] || { printf 'no-delete-guard[1]{deleted,verdict}:\n  "0","clear"\n'; exit 0; }

count=$(printf '%s\n' "$deleted" | grep -c . || true)
reason="${YMIR_ALLOW_DELETE:-}"

# ── the one escape: explicit, attributed, and written down ─────────────────────
if [ -n "$reason" ]; then
  # The vault, resolved by THE resolver (ymir_home_root). The literal path this line
  # started with was one machine's layout — defaults-guard refused the file for it, rightly.
  # shellcheck source=bin/vault/hoard-lib.sh
  . "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
  _h=""
  if command -v ymir_home_root >/dev/null 2>&1; then ymir_home_root _h; fi
  LOG="${YMIR_LOG:-${_h:-${YMIR_HOME:-}}/hodd/memory/deleted-on-purpose.log}"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  {
    printf '\n--- %s — DELETED ON PURPOSE (Rule 11 escape used)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'reason: %s\n' "$reason"
    printf 'files:\n'
    printf '%s\n' "$deleted" | sed 's/^/  - /'
  } >> "$LOG" 2>/dev/null
  printf 'no-delete-guard[2]{deleted,verdict}:\n  "%s","ALLOWED — on purpose, and LOGGED"\n' "$count"
  printf '  reason: %s\n' "$reason"
  printf '  logged: %s\n' "$LOG" >&2
  printf '  Rule 11 prefers a MOVE to hodd/reference/ — the law is that nothing is lost.\n' >&2
  exit 0
fi

# ── the refusal ──────────────────────────────────────────────────────────────
printf 'no-delete-guard[2]{deleted,verdict}:\n  "%s","REFUSED — Rule 11: files are MOVED, never deleted"\n' "$count"
printf '%s\n' "$deleted" | sed 's/^/  - /' >&2
cat >&2 <<'MSG'

  To retire a file, MOVE it — it stays in the record and in the history:

      git mv <old> $YMIR_HOME/hodd/reference/<same-shape/path>

  If a deletion is genuinely correct (a secret that leaked, a file that must never exist),
  say so out loud and it is logged, never silent:

      YMIR_ALLOW_DELETE="why, in one line" git commit …
MSG
exit 1