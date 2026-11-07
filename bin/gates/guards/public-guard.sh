#!/usr/bin/env bash
# public-guard.sh — every PUBLIC, user-facing file must be free of operator
# private content (tenant names, personal handles, domains, /home paths, secret
# shapes). Supersedes agents-guard (root AGENTS.md is just one public file).
#
#   bin/gates/guards/public-guard.sh          # inspect the staged change (pre-commit)
#   bin/gates/guards/public-guard.sh --all    # inspect every tracked public file
#
# Two lessons are baked in here (2026-09-12):
#   1. The scan used to cover only root docs, so `apps/`, `bin/`, `scripts/` and
#      `.agents/` shipped unchecked — and a personal domain, a personal bundle id
#      and a live tunnel credential path sat in them for months.
#   2. Append-only records are HISTORY. Rewriting one to hide a name would
#      falsify the ledger, so they are exempt from the sweep by design and named
#      here rather than quietly skipped.
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yh="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for _i in 1 2 3 4 5; do
    [ -n "$_yh" ] || break
    if [ -r "$_yh/bin/vault/hoard-lib.sh" ]; then . "$_yh/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    if [ -r "$_yh/hoard-lib.sh" ]; then . "$_yh/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    _yh="$(cd "$_yh/.." 2>/dev/null && pwd)"
  done
  unset _yh _i
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# The public tree scanned for private markers: shipped code, agent surfaces, docs.
PUBLIC='^(apps/|bin/|scripts/|config/|midgard/|\.agents/|\.pi/|\.opencode/|AGENTS\.md|README\.md|TODO\.md|Structure\.md|CONTRIBUTING\.md|SECURITY\.md|NOTICE|docs/)'
# Append-only records and archived reference material: history, never rewritten.
APPEND_ONLY='(^docs/fixes/|^docs/append-only-log\.md$|^docs/plans/|^assets/reference/|^.agents/state/)'
# Operator-private markers that must never appear in a public file.
#
# THE OPERATOR'S OWN WORDS ARE NOT NAMED HERE. RULES/04 (2026-10-01) is explicit: a guard
# "deliberately contains NO operator name, domain or hostname: naming them in the guard would
# re-create the very leak the guard exists to stop." Measured 2026-11-03 at the Allfather's word:
# this file named his personal name as two literal alternatives in a PUBLIC repository — the ward
# against personal data was itself the copy of it, and the `$HOME` inside a single-quoted string
# never expanded, so that third alternative matched nothing at all.
#
# So the personal words are read AT RUN TIME from the home, and the repo ships only this door:
#     $YMIR_HOME/hodd/security/operator-words.txt      (one token per line)
# A machine with no such list still scans for secret shapes, and SAYS it had no token list rather
# than reporting a clean scan that checked less than it claims (RULES/25: a clean skip is a pass,
# a false green is not).
# The public owner identity — the repo holder's login, its public domains, and the project's own
# repo forms — is intentionally NOT private; what stays guarded is the operator's own name, real
# /home paths, tenants, and secret shapes.
_SECRET_SHAPES='(ghp|gho|ghs|ghr)_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
_private_tokens() {  # one alternation of the home's tokens, or nothing
  local home list
  if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
    for _c in "$ROOT/bin/vault/hoard-lib.sh" "$(dirname "$0")/../vault/hoard-lib.sh"; do
      [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
    done
  fi
  if declare -f ymir_home_root >/dev/null 2>&1; then ymir_home_root home; else home="${YMIR_HOME:-}"; fi
  list="${home:-}/hodd/security/operator-words.txt"
  [ -r "$list" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$list" | sed 's/[[:space:]]*$//' | paste -sd'|' -
}
TOKENS="$(_private_tokens 2>/dev/null || true)"
if [ -n "$TOKENS" ]; then
  PATTERNS="($TOKENS|$_SECRET_SHAPES)"
else
  PATTERNS="($_SECRET_SHAPES)"
  TOKEN_LIST_ABSENT=1
fi
# Legitimate exceptions, named explicitly rather than by widening the pattern:
#   - the public owner identity (the repo's full URL, the short owner/repo form,
#     and the owner's public homepage — the copyright holder on every licence);
#   - AWS's documented dummy key, which is a fixture, not a credential.
ALLOW='github\.com/zerwiz/|zerwiz/ymir|zerwiz\.org|akka://|AKIAIOSFODNN7EXAMPLE|AKIA[A-Z0-9]*EXAMPLE'

# ── TOPOLOGY, BY SHAPE ──────────────────────────────────────────────────────────────────────
# RULES/04's 2026-10-01 append: "username, home path, tailnet domain, hostnames, machine names
# and the fleet's hardware inventory are never committed to this repo" — whether or not they are
# a secret, and whether or not they are in a fixture. So these are judged by SHAPE, and the
# house's own placeholders are the only allowed values:
#   · a PRIVATE address may appear only as a RANGE (192.168.0.0/16, 100.64.0.0/10, 10.0.0.0/8)
#     or in RFC 5737 documentation space (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24);
#   · a tailnet name may appear only as the generic `<host>.<host>.tailnet.ts.net`;
#   · a mailbox may appear only as an RFC 2606 example domain, or a noreply account form.
LAN_HOST='(^|[^0-9./])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})(/[0-9]{1,2})?'
CGNAT_HOST='(^|[^0-9./])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'
TAILNET='\b[a-z0-9-]+\.(tailefab[0-9a-z]+\.)?ts\.net\b'
MAILBOX='\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
TOPOLOGY="$LAN_HOST|$CGNAT_HOST|$TAILNET"
# Allowed forms, named explicitly (never by widening the shape):
TOPOLOGY_ALLOW='/8|/10|/12|/16|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|<host>|<tailnet|\btailnet\.ts\.net|192\.168\.0\.0/16|100\.64\.0\.0/10|10\.0\.0\.0/8'
MAILBOX_ALLOW='@users\.noreply\.github\.com|@(example\.(com|org|net)|example|test|invalid|ymir|ymir\.local|zerwiz\.org)$'

# A GUARD MUST NOT ECHO THE LEAK. Printing the offending line in the clear writes the operator's
# own name into CI logs and a terminal scrollback - the same publication, one door over. tk_sed
# masks each declared token as `j***`.
tk_sed() {
  local expr=""
  [ -n "${TOKENS:-}" ] || { cat; return 0; }
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    expr="$expr -e s/${t}/${t:0:1}***/gI"
  done < <(printf '%s' "$TOKENS" | tr '|' '\n')
  # shellcheck disable=SC2086
  sed $expr
}

leaks() {  # stdin → prints masked hits, returns 1 on any
  local out=0
  # secrets and the operator's own words
  if grep -En "$PATTERNS" | grep -Ev "$ALLOW" \
       | sed -E 's/(sk-|ghp_|AKIA|xox[a-z]*-)[A-Za-z0-9-]+/\1…/g; s#$HOME#/home/<user>#g' \
       | tk_sed | head -3 | grep -q .; then
    grep -En "$PATTERNS" | grep -Ev "$ALLOW" \
      | sed -E 's/(sk-|ghp_|AKIA|xox[a-z]*-)[A-Za-z0-9-]+/\1…/g; s#$HOME#/home/<user>#g' \
      | tk_sed | head -3
    out=1
  fi
  # topology: a place this house stands. Named as such, never echoed in the clear.
  if grep -EnE "$TOPOLOGY" | grep -EvE "$TOPOLOGY_ALLOW" | grep -q .; then
    printf 'topology: this line names a private address, a tailnet host or a machine\n'
    out=1
  fi
  # a personal mailbox, unless it is an example domain, a noreply account or the house's own
  if grep -EnE "$MAILBOX" | grep -EvE "$MAILBOX_ALLOW" | grep -q .; then
    printf 'mailbox: a personal address would be published\n'
    out=1
  fi
  return "$out"
}

scan_one() {  # $1 = path in the index; prints a finding, returns 1 when clean
  local f="$1" out
  # This file necessarily contains the patterns it looks for; scanning it would
  # always fail. The same is true of every guard whose job is to name a secret
  # shape, so all three are exempt by name — and the patterns in them stay honest.
  case "$f" in
    bin/gates/guards/public-guard.sh|bin/gates/guards/secret-guard.sh|bin/gates/guards/hoard-guard.sh|\
    bin/gates/guards/identity-guard.sh) return 0 ;; esac
  printf '%s\n' "$f" | grep -Eq "$PUBLIC" || return 0
  printf '%s\n' "$f" | grep -Eq "$APPEND_ONLY" && return 0
  out="$(git -C "$ROOT" show ":$f" 2>/dev/null | leaks)" || true
  if [ -n "$out" ]; then
    printf 'public-guard: %s\n%s\n' "$f" "$out" >&2
    return 1
  fi
  return 0
}

hit=0
# `--tree` is what CI runs: every tracked file, not only what is staged. A commit is a snapshot;
# a tree is what a stranger clones, and RULES/04 is about the clone.
if [ "${1:-}" = "--tree" ]; then
  # ONE GREP PER CLASS over the whole tree. The per-file loop took minutes on 4,082 files, and a
  # gate that is too slow to run is a gate that is skipped (RULES/25: a ward must be able to fail,
  # and CI must be willing to run it). `git grep` already knows the index, so the tree is judged
  # in three passes instead of four thousand.
  tree_hits() {  # <label> <ERE> <ALLOW-ERE>
    local label="$1" ere="$2" allow="$3" files
    files="$(git -C "$ROOT" grep -IlE "$ere" -- . 2>/dev/null || true)"
    [ -n "$files" ] || return 0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in bin/gates/guards/public-guard.sh|bin/gates/guards/secret-guard.sh|bin/gates/guards/hoard-guard.sh|bin/gates/guards/identity-guard.sh) continue ;; esac
      git -C "$ROOT" grep -nE "$ere" -- "$f" 2>/dev/null | grep -EvE "$allow" | head -1 | grep -q . || continue
      printf 'public-guard: %s — %s\n' "$f" "$label" >&2
      hit=1
    done <<EOF2
$files
EOF2
  }
  tree_hits "names the operator's own words" "$TOKENS" "$ALLOW" 2>/dev/null || true
  [ -n "${TOKENS:-}" ] && {
    files="$(git -C "$ROOT" grep -Il -E "$TOKENS" -- . 2>/dev/null || true)"
    [ -n "$files" ] && while IFS= read -r f; do
      case "$f" in bin/gates/guards/*) continue ;; esac
      printf 'public-guard: %s — names the operator (RULES/04)\n' "$f" >&2; hit=1
    done <<EOF3
$files
EOF3
  }
  tree_hits "carries a secret shape" "$_SECRET_SHAPES" "$ALLOW" || true
  tree_hits "names a private address, a tailnet host or a machine" "$TOPOLOGY" "$TOPOLOGY_ALLOW" || true
  tree_hits "publishes a personal mailbox" "$MAILBOX" "$MAILBOX_ALLOW" || true
elif [ "${1:-}" = "--all" ]; then
  while IFS= read -r f; do
    scan_one "$f" || hit=1
  done < <(git -C "$ROOT" ls-files)
else
  while IFS= read -r f; do
    scan_one "$f" || hit=1
  done < <(git -C "$ROOT" diff --cached --name-only --diff-filter=ACM)
fi

[ "$hit" = 0 ] || { printf 'public-guard: blocked — that is private; move it to $YMIR_HOME (Rule 04)\n' >&2; exit 1; }
exit 0
