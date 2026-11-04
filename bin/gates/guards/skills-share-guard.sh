#!/usr/bin/env bash
# skills-share-guard.sh — nothing private crosses the skills door.
#
# WHY THIS EXISTS (plan 184 §3, §5, the Allfather's word: *"we also need to make sure we're not
# putting our data out in the MCP — like in the model testing skill we have a lot of personal
# testings and info"*). The share build redacts what the house can NAME — our paths, our hosts,
# our people, our catalog. **What it cannot name, it cannot rewrite**, and a redaction pass that
# is trusted to be complete is exactly how a hostname leaves in a footnote. So the last word is
# a refusal, not a review: this ward reads the built tree and refuses ANY of the shapes below,
# including the ones no redactor would have guessed.
#
# The classes, and why each is private (RULES/04, RULES/39 — never give out the address):
#   machine path      /home/<user>, /Users/<user>, C:\Users\<user>   — who and where
#   address           any IPv4 literal, LAN or public                 — an address is an address
#   host              *.local · *.lan · *.internal · *.ts.net · tailnet
#   port              a port hung off a host, or "port 8080"
#   name              a person from the house's registries, or an explicitly seeded name
#   mailbox / phone   an email address or a telephone number
#   bench table       a markdown row of runs, benches, trials, throughput or latency
#   model id          our catalog's ids (the catalog is the truth, never a table in a doc)
#
# Usage:
#   skills-share-guard.sh [check] [--root DIR] [--names FILE] [--models FILE] [--quiet]
#
#   --root    the tree to judge (default $SKILLS_SHARE_ROOT, else <home>/hodd/skills-share/published)
#   --names   one name per line (default: <root>/../deny-names.txt when present, plus
#             $SKILLS_SHARE_NAMES). A seed is how a test proves a name is caught.
#   --models  model ids (default: <root>/../deny-models.txt when present)
#
# A missing published tree is a CLEAN SKIP and says why: this ward judges a build that exists,
# and a build that does not exist cannot leak (Rule 25 — a clean skip names its reason).
#
# Exit: 0 clean (or nothing to judge) · 1 findings · 2 usage.
set -uo pipefail
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"
# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
HOME_ROOT=""
if command -v ymir_home_root >/dev/null 2>&1; then ymir_home_root HOME_ROOT; fi

TARGET=""; NAMES=""; MODELS=""; QUIET=0
case "${1:-}" in
  -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check) shift ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --root) TARGET="${2:-}"; shift 2 ;;
    --root=*) TARGET="${1#*=}"; shift ;;
    --names) NAMES="${2:-}"; shift 2 ;;
    --names=*) NAMES="${1#*=}"; shift ;;
    --models) MODELS="${2:-}"; shift 2 ;;
    --models=*) MODELS="${1#*=}"; shift ;;
    --quiet) QUIET=1; shift ;;
    *) printf 'error: unknown argument %s\nhelp: skills-share-guard.sh [check] [--root DIR]\n' "$1" >&2; exit 2 ;;
  esac
done

TARGET="${TARGET:-${SKILLS_SHARE_ROOT:-${HOME_ROOT:+$HOME_ROOT/hodd/skills-share/published}}}"
if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  [ "$QUIET" = 1 ] || printf 'skills_share_guard[1]{state,reason}:\n  "clean skip","no published tree at %s — nothing is shared from this machine yet"\n' "${TARGET:-<unresolved>}"
  exit 0
fi
TARGET="$(cd "$TARGET" && pwd)"

SHARE_BASE="$(dirname "$TARGET")"
[ -n "$NAMES" ] || { [ -r "$SHARE_BASE/deny-names.txt" ] && NAMES="$SHARE_BASE/deny-names.txt"; }
[ -n "$MODELS" ] || { [ -r "$SHARE_BASE/deny-models.txt" ] && MODELS="$SHARE_BASE/deny-models.txt"; }

# One alternation for the names, so the ward costs one grep per file rather than one per person.
ensure_pat() {
  local names_pat=""
  if [ -n "$NAMES" ] && [ -r "$NAMES" ]; then
    names_pat="$(grep -vE '^[[:space:]]*(#|$)' "$NAMES" | awk 'length($0) >= 3' \
      | sed -E 's/[][\\.*^$(){}+?|]/\\&/g' | paste -sd '|' -)"
  fi
  if [ -n "${SKILLS_SHARE_NAMES:-}" ]; then
    local seed
    seed="$(printf '%s' "$SKILLS_SHARE_NAMES" | tr ',' '\n' | awk 'length($0) >= 3' \
      | sed -E 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed -E 's/[][\\.*^$(){}+?|]/\\&/g' | paste -sd '|' -)"
    names_pat="${names_pat:+$names_pat|}$seed"
  fi
  printf '%s' "$names_pat"
}
NAMES_PAT="$(ensure_pat)"

models_pat() {
  local p=""
  if [ -n "$MODELS" ] && [ -r "$MODELS" ]; then
    p="$(grep -vE '^[[:space:]]*(#|$)' "$MODELS" | awk 'length($0) >= 6' \
      | sed -E 's/[][\\.*^$(){}+?|]/\\&/g' | paste -sd '|' -)"
  fi
  # the generic shape as well, so an id we do not hold is still refused
  printf '(openrouter|opencode-go|llamacpp-[a-z0-9-]+|llama-swap)/[A-Za-z0-9._-]+%s' "${p:+|$p}"
}
MODELS_PAT="$(models_pat)"

# Three parallel arrays, never one packed string: a regex may contain `|`, and a packed
# separator silently made every class match every line (measured while building this ward).
C_CLASS=()
C_PAT=()
C_ICASE=()

add_class() { C_CLASS+=("$1"); C_PAT+=("$2"); C_ICASE+=("${3:-0}"); }

add_class "machine path" '/(home|Users)/[A-Za-z0-9._-]+' 0
add_class "machine path" '[A-Za-z]:\\\\Users\\\\[A-Za-z0-9._ -]+' 0
add_class "address"      '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' 0
add_class "host"         '\b[a-zA-Z0-9][a-zA-Z0-9.-]*\.(local|lan|internal|ts\.net|home\.arpa|tailnet)\b' 1
add_class "port"         '(^|[^a-zA-Z0-9/:])([a-zA-Z0-9][a-zA-Z0-9-]*(\.[a-zA-Z0-9-]+)+|localhost|127\.0\.0\.1):[0-9]{2,5}' 0
add_class "port"         '(localhost|127\.0\.0\.1|\[::1\]):[0-9]{2,5}' 0
add_class "port"         '\bports?[[:space:]]+(is[[:space:]]+|of[[:space:]]+|at[[:space:]]+)?[0-9]{3,5}\b' 1
add_class "mailbox"      '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 0
add_class "phone"        '\+[0-9][0-9 .()-]{6,}[0-9]' 0
add_class "phone"        '\b0[1-9][0-9]{0,2}[ -][0-9]{2,4}[ -][0-9]{2,4}([ -][0-9]{2,4})?\b' 0
add_class "bench table"  '^\|[^|]*(run|bench|trial|measurement|throughput|latency|tok/s)[^|]*\|' 1
add_class "bench table"  '\|[[:space:]]*(tok/s|tokens/s|latency|throughput|qps)[[:space:]]*\|' 1
add_class "model id"     "$MODELS_PAT" 0
[ -n "$NAMES_PAT" ] && add_class "name" "$NAMES_PAT" 1

count=0; findings=0
printf 'skills_share_guard[3]{root,names,models}:\n  "%s","%s","%s"\n' \
  "$TARGET" "${NAMES:-none}" "${MODELS:-none}"
printf 'skills_share_findings[4]{class,file,line,finding}:\n'

declare -A SEEN=()
while IFS= read -r f; do
  count=$((count + 1))
  i=0
  while [ "$i" -lt "${#C_PAT[@]}" ]; do
    args=(-nE -e "${C_PAT[$i]}")
    [ "${C_ICASE[$i]}" = 1 ] && args+=(-i)
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      # one finding per class per line: two patterns may name the same row
      key="${C_CLASS[$i]}|${f}|${hit%%:*}"
      [ -n "${SEEN[$key]:-}" ] && continue
      SEEN[$key]=1
      findings=$((findings + 1))
      printf '  "%s","%s","%s","%s"\n' "${C_CLASS[$i]}" "${f#"$TARGET"/}" "${hit%%:*}" \
        "$(printf '%s' "${hit#*:}" | cut -c1-120 | sed 's/"/\x27/g')"
    done < <(grep -I "${args[@]}" -- "$f" 2>/dev/null | head -3)
    i=$((i + 1))
  done
done < <(find "$TARGET" -type f | sort)

printf 'skills_share_guard: %s file(s) judged · %s finding(s)\n' "$count" "$findings"
if [ "$findings" -ne 0 ]; then
  printf 'help: a finding means the copy is NOT fit to leave. Reword the skill, or — when the shape\n' >&2
  printf '      is genuinely wanted — teach bin/skills/share-build.sh to redact it and say why.\n' >&2
  exit 1
fi
exit 0
