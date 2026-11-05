#!/usr/bin/env bash
# rules-compliance-guard.sh — a push proves the house's own rules were followed.
#
# Why this exists: RULES/ 01–46 are law, and until now a push was judged by wards that
# each knew ONE rule (numbering, weave, language, the ward's own list). Nothing asked the
# cheap universal questions every new document must answer:
#
#   R1  a NEW document carries its history            (RULES/06; home RULES/changelog)
#   R2  a new RULE names itself and is indexed        (RULES/README.md)
#   R3  a new document carries no internal address
#       and no plain-HTTP cross-host URL              (home RULES/network.md N1/N7; RULES/39)
#   R4  a new door is executable and has a shebang    (RULES/12, RULES/23)
#
# It judges the PUSH RANGE only (what this push adds), so a legacy tree is never
# re-litigated. Every refusal names file and line — a gate that prints a summary is a
# gate nobody can act on.
#
# Usage: rules-compliance-guard.sh [check] [BASE] [HEAD]
# Exit: 0 clean or clean-skip · 1 a rule is broken · 3 cannot determine the range
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
cd "$ROOT" || exit 3

BASE="${2:-}"
HEAD="${3:-HEAD}"

if [ -z "$BASE" ]; then
  if git rev-parse --verify -q origin/main >/dev/null; then BASE=origin/main
  elif git rev-parse --verify -q main >/dev/null; then BASE=main
  else
    printf 'rules-compliance: SKIP — no base ref (fetch first); the range is UNVERIFIED\n'
    exit 0
  fi
fi
git rev-parse --verify -q "$BASE" >/dev/null || { printf 'rules-compliance: SKIP — base %s is unknown\n' "$BASE"; exit 0; }

added=$(git diff --name-only --diff-filter=A "$BASE..$HEAD")
[ -z "$added" ] && { printf 'rules-compliance[1]{state,detail}:\n  "clean","the push adds no new file"\n'; exit 0; }

fail=0
say() { printf 'rules-compliance[1]{file,line,rule,finding}:\n  "%s","%s","%s","%s"\n' "$1" "$2" "$3" "$4"; fail=1; }

# A template is a SHAPE, copied into a message; a changelog inside it would be copied too.
# Its history is the repository's. Exempt, with the reason written here.
is_shape() { case "$1" in .agents/templates/*) return 0 ;; *) return 1 ;; esac; }
is_meta() { case "$1" in RULES/README.md|docs/features/_catalogue/*|bin/README.md|.agents/backend/README.md|FEATURES.md|*/plans/README.md) return 0 ;; *) return 1 ;; esac; }

# R1 — a NEW document carries its history.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.md) ;; *) continue ;; esac
  is_meta "$f" && continue
  is_shape "$f" && continue
  grep -qiE '^#+ *change[ -]?log' "$f" 2>/dev/null || \
    say "$f" "-" "RULES/06 · append-only" "a new document has no CHANGE LOG section"
done <<EOF
$added
EOF

# R2 — a new RULE names itself and is indexed.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in RULES/[0-9][0-9]-*.md) ;; *) continue ;; esac
  base=$(basename "$f"); num=${base%%-*}
  head=$(sed -n '1p' "$f")
  case "$head" in
    "# $num "*) ;;
    *) say "$f" "1" "RULES/README" "the first line must be '# $num — <title>' (found: ${head:0:60})" ;;
  esac
  grep -qF "$base" RULES/README.md 2>/dev/null || grep -qF "$num" RULES/README.md 2>/dev/null || \
    say "$f" "-" "RULES/README" "a new rule is not named in RULES/README.md"
done <<EOF
$added
EOF

# R3 — no internal address, no plain-HTTP cross-host URL in what this push ADDS.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.md|*.yml|*.yaml|*.json|*.example|*.sh|*.py) ;; *) continue ;; esac
  is_meta "$f" && continue
  # a ward that SEARCHES for a pattern is not a document that carries one
  case "$f" in bin/gates/guards/*) continue ;; esac
  tmp=$(mktemp)
  git diff -U0 "$BASE..$HEAD" -- "$f" 2>/dev/null | grep '^+' | grep -v '^+++' >"$tmp" || { rm -f "$tmp"; continue; }
  while IFS= read -r hit; do
    say "$f" "added" "RULES/39 · network N1/N7" "address or plain-HTTP URL in a new line: ${hit:0:90}"
  done < <(grep -nE '(\b192\.168\.[0-9]+\.|\b10\.[0-9]+\.[0-9]+\.[0-9]+|\.local\b|http://)' "$tmp" 2>/dev/null \
             | grep -vE '127\.0\.0\.1|localhost|<[a-z-]+>' | head -20)
  rm -f "$tmp"
done <<EOF
$added
EOF

# R4 — a new door has a shebang and is executable.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in bin/*.sh|systems/*.sh|tools/*.sh|scripts/*.sh|bin/*.py|systems/*.py|tools/*.py) ;; *) continue ;; esac
  head -1 "$f" | grep -qE '^#!' || say "$f" "1" "RULES/12 · RULES/23" "a new door has no shebang"
  [ -x "$f" ] || say "$f" "-" "RULES/12 · RULES/23" "a new door is not executable (chmod +x)"
done <<EOF
$added
EOF

if [ "$fail" = 0 ]; then
  n=$(printf '%s\n' "$added" | grep -c . || true)
  printf 'rules-compliance[2]{state,added,range}:\n  "clean",%s,"%s..%s"\n' "${n:-0}" "$BASE" "$HEAD"
fi
exit "$fail"
