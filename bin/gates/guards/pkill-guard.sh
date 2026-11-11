#!/usr/bin/env bash
# pkill-guard.sh — no blanket kill in the tree, and the audit that finds one.
#
# WHY THIS EXISTS (measured 2026-10-20): `pkill -f "<pattern>"` matched the very
# shell that ran it — twice in one session — because `pkill -f` matches the whole
# command LINE, and the command line of the caller contains the pattern. A blanket
# kill does not know what it is killing: it takes an agent's own process tree, a
# sibling's pane, or the next unrelated process that happens to carry the name.
#
# The law: kill the PID THAT OWNS THE THING — the pid holding the port, the pane id
# herdr reports, the process a unit started. `systemctl --user stop`, `herdr`, and
# `kill "$pid"` all name a target; `pkill -f` names a guess.
#
#   pkill-guard.sh --check     # judge the current branch range against its base
#   pkill-guard.sh --scan      # audit the WHOLE tree: every pkill/killall, classified
#   git push                   # the pre-push hook feeds refs on stdin
#
# An escape exists, and it must be written down in the same line:
#   pkill -f x   # pkill-allowed: <why this cannot be a pid>
# or per-push, loudly: YMIR_ALLOW_PKILL=1
#
# Exempt by path (they QUOTE the pattern as data, never run it): `.compliance/` and
# every vendored `nsr-compliance` asset.
#
# Exit: 0 clean, 1 a blanket kill is present, 2 usage.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
cd "$ROOT" || exit 1

EXEMPT_RE='^(\./)?(\.compliance/|\.agents/skills/nsr-compliance/|node_modules/|bin/gates/guards/pkill-guard\.sh$|\.agents/tests/pkill-guard\.test\.sh$)'
CODE_RE='\.(sh|bash|zsh|ts|tsx|js|mjs|cjs|py|rb|go|rs)$'
# An INVOCATION, not a mention: pkill/killall as a command word — so `pkill-guard`
# and `pkill-scan` (the tool's own names) never match.
PATTERN='(^|[[:space:];&|(`"'"'"'])(sudo[[:space:]]+)?(pkill|killall)([[:space:]]|$)'

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --check|check|--scan|scan|"") ;;
  *) printf 'error: unknown flag %s\nhelp: bin/gates/guards/pkill-guard.sh [--check|--scan]\n' "$1" >&2; exit 2 ;;
esac
MODE="${1:---check}"; case "$MODE" in check) MODE=--check ;; scan) MODE=--scan ;; esac

[ "${YMIR_ALLOW_PKILL:-0}" = 1 ] && {
  printf 'pkill-guard[1]{gate,result}:\n  "%s","allowed (YMIR_ALLOW_PKILL=1 — recorded)"\n' "$MODE"
  exit 0
}

# A line is a VIOLATION when it invokes pkill/killall outside a comment, outside an
# explicit `pkill-allowed:` escape, and in a code file. A mention in prose is not.
judge_line() {  # <path> <line-text> → exit 0 when it violates
  local path=$1 text=$2
  printf '%s' "$path" | grep -Eq "$EXEMPT_RE" && return 1
  printf '%s' "$path" | grep -Eq "$CODE_RE" || return 1
  # The guard's own name is not a kill: strip it before matching, so a message that
  # says "pkill-guard" never counts as an invocation.
  local probe; probe="$(printf '%s' "$text" | sed 's/pkill-guard//g')"
  printf '%s' "$probe" | grep -Eq "$PATTERN" || return 1
  printf '%s' "$text" | grep -q 'pkill-allowed:' && return 1
  printf '%s' "$text" | grep -Eq '^[[:space:]]*#' && return 1
  return 0
}

block() {  # <path> <line> <text>
  cat >&2 <<EOF
⛔ A blanket kill was added: $1:$2
   $3

   pkill -f matches the whole command LINE — including the shell that runs it, so it
   can take your own process tree (measured twice on 2026-10-20).

   Kill the PID THAT OWNS the thing instead:
     · a service      systemctl --user stop <unit>
     · a pane         herdr pane close <pane-id>   (bin/seat/herdr-run.sh)
     · a port         the pid holding it: ss -ltnp | grep :PORT  → kill "\$pid"
     · a listener     the launcher records its pid; read it, do not guess it

   If a blanket kill is genuinely the only door, say so on the same line:
     pkill -f x   # pkill-allowed: <why this cannot be a pid>
EOF
  printf 'error: pkill-guard blocked a blanket kill (%s:%s)\n' "$1" "$2" >&2
  printf 'help: bin/gates/guards/pkill-guard.sh --scan · RULES/24 (the ward)\n' >&2
}

findings=0
report() { findings=$((findings + 1)); }

case "$MODE" in
  --scan)
    # Audit the tree: every real invocation, and the mentions told apart from them.
    printf 'pkill-scan[?]{path,line,kind,text}:\n'
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      path="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; text="${rest#*:}"
      if judge_line "$path" "$text"; then
        printf '  "%s",%s,"INVOCATION","%s"\n' "$path" "$line" "$(printf '%s' "$text" | sed 's/"/'"'"'/g' | cut -c1-140)"
        report
      else
        printf '  "%s",%s,"mention","%s"\n' "$path" "$line" "$(printf '%s' "$text" | sed 's/"/'"'"'/g' | cut -c1-140)"
      fi
    done < <(grep -rnI -E "$PATTERN" --include='*.sh' --include='*.bash' --include='*.ts' --include='*.tsx' \
               --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.py' \
               --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.yggdrasil . 2>/dev/null)
    printf 'invocations: %s\n' "$findings"
    [ "$findings" = 0 ] || exit 1
    exit 0
    ;;
esac

# ── --check: the push range ──────────────────────────────────────────────────
# Read the refs ONLY when something is actually there to read. A ward runs inside
# `$( ... )` from bin/gates/guards.sh, where stdin is whatever the caller happened
# to hold open — a git hook pipe, a pane, a terminal. A bare `cat` then waits for an
# EOF that never comes, and the push hangs with no output at all. Measured
# 2026-11-11: three worktrees wedged on this line at once, each at three minutes and
# climbing, and nothing on screen to say why. The bound is not a truncation: git
# writes the refs and closes the pipe, so a real pre-push returns at once.
refs=""
if [ ! -t 0 ]; then refs="$(timeout 3 cat 2>/dev/null || true)"; fi
base=""
if [ -n "$refs" ]; then
  while read -r _local local_sha _remote remote_sha; do
    [ -n "${local_sha:-}" ] || continue
    case "$local_sha" in 000000*) continue ;; esac   # a deletion delivers no content
    if [ -n "${remote_sha:-}" ] && ! printf '%s' "$remote_sha" | grep -q '^0*$'; then
      base="$remote_sha"
    fi
    head_sha="$local_sha"
  done <<<"$refs"
fi
head_sha="${head_sha:-$(git rev-parse HEAD 2>/dev/null || true)}"
[ -n "$head_sha" ] || exit 0
if [ -z "$base" ]; then
  base="$(git merge-base "$head_sha" origin/main 2>/dev/null || git rev-parse "$head_sha^\~1" 2>/dev/null || true)"
fi
[ -n "$base" ] || exit 0

added="$(git diff -U0 "$base" "$head_sha" -- 2>/dev/null | awk '
  /^\+\+\+ / { file = substr($0, 7); sub(/^b\//, "", file); next }
  /^@@/     { match($0, /\+[0-9]+/); line = substr($0, RSTART + 1, RLENGTH - 1); next }
  /^\+/     { print file ":" line ":" substr($0, 2); line++ }
')"

[ -n "$added" ] || exit 0

# Only a line that NAMES a blanket kill can be one, so find those first with a single
# pass. Judging every changed line was O(lines) processes: measured 2026-11-11, a
# 600-line range spent 25 seconds spawning printf/grep/sed triplets for lines that
# contained nothing — and three concurrent worktrees made the delivery gate look hung,
# with no output on screen to say otherwise. One grep, then judge only what it found.
candidates="$(printf '%s\n' "$added" | grep -E "$PATTERN" || true)"
[ -n "$candidates" ] || {
  printf 'pkill-guard[1]{gate,result}:\n  "push","clean — no blanket kill in the range"\n'
  exit 0
}

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  path="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"; text="${rest#*:}"
  judge_line "$path" "$text" || continue
  block "$path" "$line" "$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-160)"
  report
done <<<"$candidates"

if [ "$findings" -gt 0 ]; then
  printf 'pkill-guard[1]{gate,finding}:\n  "push","BLOCKED — %s blanket kill(s) in the range"\n' "$findings"
  exit 1
fi
printf 'pkill-guard[1]{gate,result}:\n  "push","clean — no blanket kill in the range"\n'
exit 0
