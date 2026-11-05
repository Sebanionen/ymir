#!/usr/bin/env bash
# dead-code-guard.sh — code that exists and is never reached is a claim that a feature exists.
#
# Rule: RULES/17-no-dead-code.md
#
# Two shapes, because this tree has two kinds of code and each fails differently:
#
#   1. A SOURCE FILE with no importer — a module, component or package file nothing reads.
#      It claims a surface is rendered or an API is used. This is the shape that occurred:
#      three components written for tickets, documented, and imported by nothing.
#
#   2. A SHELL FUNCTION defined and never called — it claims a capability the scripts have.
#      In a tree with ~1,900 scripts that is the common form of the same lie.
#
#   dead-code-guard.sh check     # the ward (used by bin/gates/guards.sh)
#   dead-code-guard.sh         # alias for check
#   dead-code-guard.sh --list  # what this ward scans, and what it cannot see
#
# Exit: 0 clean · 1 findings · 2 usage.
#
# ── WHAT THIS CANNOT SEE, stated so nobody assumes it does ────────────────────
#   · an export used only inside its own file
#   · a branch that can never be reached
#   · a constant nothing reads
#   · a file reached only through a string built at runtime
# Those are dead code by the rule. This ward catches the shapes that actually occur, and a
# ward that claims more than it checks is the failure the rule exists to stop.
set -u

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"

# Source roots, and the allowlist. One home each.
SRC_ROOTS=(apps packages tools src)
ALLOW="$ROOT/RUNTIME-GUARD.allow"          # reused: one allowlist shape for the tree
DEAD_ALLOW="$ROOT/dead-code.allow"

case "${1-check}" in
  -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --list)
    printf 'dead-code-guard scans:\n'
    for r in "${SRC_ROOTS[@]}"; do [ -d "$ROOT/$r" ] && printf '  %s/\n' "$r"; done
    printf '  shell functions under bin/ and scripts/\n'
    printf 'allowlist: %s\n' "${DEAD_ALLOW#$ROOT/}"
    exit 0 ;;
  check|"") ;;
  *) printf 'error: unknown flag %s\nhelp: dead-code-guard.sh [check|--list]\n' "${1-}" >&2; exit 2 ;;
esac

# An allowlist line carries one of exactly two things, and neither is a deferral:
#
#   path/to/file      # consumer: <who reads it, outside this tree>
#       The RULES/16 exception — code exported for a named external reader.
#
#   path/to/file      # todo:<TODO.md section> — <what will resolve it>
#       A work item. The file is dead TODAY, it is tracked, and closing the ticket means deleting
#       the line. This is a queue with a date on it, not amnesty.
#
# A blank reason, or one that says "later", "maybe", "for now" or "TODO", is neither (RULES/16).
allowed() {
  local needle="$1" line reason
  [ -r "$DEAD_ALLOW" ] || return 1
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in "$needle"*) ;; *) continue ;; esac
    reason="${line#*#}"
    reason="$(printf '%s' "$reason" | tr -d '[:space:]')"
    # No reason, or a reason that is really a deferral.
    if [ -z "$reason" ]; then
      printf '  "%s","BAD ALLOWLIST","no reason — name the consumer (RULES/16)"\n' "$needle"
      return 2
    fi
    case "$reason" in *maybe*|*later*|*future*|*might*|*TODO*|*fornow*|*temporary*)
      printf '  "%s","BAD ALLOWLIST","\\"%s\\" is a deferral, not a consumer or a ticket (RULES/16)"\n' "$needle" "$reason"
      return 2 ;;
    esac
    # Either a named external consumer, or a ticket. Anything else is not a reason.
    case "$reason" in
      consumer:*|ticket:*|todo:*) return 0 ;;
      *)
        printf '  "%s","BAD ALLOWLIST","say who consumes it (consumer: <who>) or what resolves it (todo: <section>)"\n' "$needle"
        return 2 ;;
    esac
  done < "$DEAD_ALLOW"
  return 1
}

findings=0
badallow=0
scanned=0

# Shapes that are REACHED, just not by an import statement. Each was a false positive on this tree,
# and each is named rather than left to a heuristic — a guard that guesses "this looks fine"
# produces findings nobody reads, and the one real finding is then ignored with the rest.
#
#   *.config.*        read by a CLI (vite, capacitor, electron-vite, i18next)
#   /out/ /dist/ /build/ /coverage/   build output, generated
#   /public/ /resources/ /assets/     loaded by URL at runtime
#   /scripts/         run by npm or by a human
#   sw.js             registered by URL: navigator.serviceWorker.register
#   preload.js        named by path in an Electron BrowserWindow
#   /templates/ /fixtures/ /examples/ /migrations/   copied or read, never imported
NOT_REACHED_BY_IMPORT='(\.test\.|\.spec\.|\.config\.|/dist/|/build/|/out/|/coverage/|/templates/|/fixtures/|/examples/|/migrations/|/public/|/resources/|/assets/|/scripts/|/sw\.js$|/preload\.js$)'

# ── 1. source files with no importer ─────────────────────────────────────────
# Collect the source set once, and build ONE index of every import specifier in the tree.
#
# The first version grepped the whole tree per file and asked `grep -q ... | grep -v`, which is
# self-cancelling — `-q` stops at the first match and `-v` inverts it — so it reported 311 of 329
# files as dead. A guard that is wrong on 94% of its input is worse than no guard: it trains the
# reader to ignore it, and then the one real finding is ignored too.
#
# Building the index once is also the only version fast enough to run on every push.
mapfile -t SOURCES < <(
  for r in "${SRC_ROOTS[@]}"; do
    [ -d "$ROOT/$r" ] || continue
    find "$ROOT/$r" -type d -name node_modules -prune -o \
      -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \) -print 2>/dev/null
  done | grep -vE "$NOT_REACHED_BY_IMPORT"
)

INDEX="$(mktemp)"
trap 'rm -f "$INDEX"' EXIT
# Every quoted string in an import position — the set of names the tree actually reaches for.
#
# The first version piped through `sed -E "s/.*['\"]//"` to strip the leading `from "`. With a
# GREEDY `.*` that matches to the LAST quote, so it removed the specifier too and left an empty
# line for every import: the index was EMPTY, and every file therefore looked unreached. Extract
# the quoted run directly instead of trying to trim around it.
grep -rhoE "(from|import\(|require\(|export \* from)[[:space:]]*['\"][^'\"]+['\"]" \
  --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
  --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build \
  "${SRC_ROOTS[@]/#/$ROOT/}" 2>/dev/null \
  | grep -oE "['\"][^'\"]+['\"]$" | tr -d "'\"" | sort -u > "$INDEX"
# Shell scripts reach files by path as well.
grep -rhoE "['\"][^'\"]+['\"]" --include='*.sh' "$ROOT/bin" "$ROOT/scripts" 2>/dev/null \
  | tr -d "'\"" | sort -u >> "$INDEX"
printf 'index: %s specifiers\n' "$(wc -l < "$INDEX")" >&2

indexed() { grep -qE "(^|/)$1(\.[a-zA-Z]+)?$" "$INDEX"; }

for f in "${SOURCES[@]}"; do
  rel="${f#$ROOT/}"
  scanned=$((scanned + 1))
  stem="$(basename "$f")"; stem="${stem%.*}"
  # Entry points are reached by the runtime, not by an import; a barrel is reached as its directory.
  case "$stem" in
    index|main|server|cli|setup|vite.config|next.config|tailwind.config|__init__) continue ;;
  esac
  # `foo.test` and `foo.stories` sit beside `foo`; the index carries the base name either way.
  case "$stem" in *.d) continue ;; esac

  indexed "$stem" && continue

  allowed "$rel"; rc=$?
  if [ "$rc" = "2" ]; then badallow=$((badallow + 1)); continue; fi
  [ "$rc" = "0" ] && continue

  printf '  "%s","DEAD FILE","nothing imports it — use it or delete it (RULES/16)"\n' "$rel"
  findings=$((findings + 1))
done

# ── 2. shell functions defined and never called ──────────────────────────────
# A function defined in bin/ or scripts/ that no other script references. Small, well-named
# helpers are the usual case, and they are the ones that read as working plumbing.
#
# O(tree), not O(names × tree). The first version ran a FULL-TREE grep per function
# name (~6,600 names over ~1,260 scripts ≈ 8.3M file scans — minutes per push, so the
# hook looked like it had hung). The tree ward must run on every push, so every name is
# a pattern in ONE pass: `grep -F -f` is multi-pattern, never a loop. The semantics are
# unchanged — a name is "used" if it appears on any line that is not a function
# definition, exactly what the per-name count asked.
mapfile -t SHELLS < <(find "$ROOT/bin" "$ROOT/scripts" \
  -type d \( -name .yggdrasil -o -name node_modules \) -prune -o \
  -type f -name '*.sh' -print 2>/dev/null)
if [ "${#SHELLS[@]}" -eq 0 ]; then
  printf 'error: dead-code guard found no shell files to judge; check the checkout and find command\n' >&2
  exit 1
fi
# The USAGE index covers the WHOLE tree: a bin/ function is called from skill scripts
# under .agents/, from tests under tools/, from apps — a search that reads only bin/
# and scripts/ reports those callers missing and calls a live function dead. Only the
# JUDGED set (the definitions above) is bin/ and scripts/.
USAGE_FILES=()
for r in bin scripts apps packages tools src .agents; do
  [ -d "$ROOT/$r" ] || continue
  while IFS= read -r _f; do USAGE_FILES+=("$_f"); done < <(
    find "$ROOT/$r" -type d \( -name .yggdrasil -o -name node_modules \) -prune -o \
      -type f -name '*.sh' -print 2>/dev/null)
done
NAMES="$(mktemp)"; DEFCOUNT="$(mktemp)"; OCC="$(mktemp)"
for f in "${SHELLS[@]:-}"; do
  [ -n "$f" ] || continue
  grep -ohE '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' "$f" 2>/dev/null \
    | sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*\(\)//'
done > "$NAMES.raw"
sort -u "$NAMES.raw" > "$NAMES"
sort "$NAMES.raw" | uniq -c > "$DEFCOUNT"
# A name is USED iff it occurs as a WORD on a line other than its own definition.
# Word matching (`-w`) is what keeps meta_get from counting because fm_meta_get exists;
# COUNTING occurrences minus definitions — rather than excluding every definition line —
# is what keeps a call inside a one-liner definition from being lost:
#   fm_transition_pane_id() { fm_transition_field "$1" 1; }   # calls fm_transition_field
if [ "${#USAGE_FILES[@]}" -gt 0 ] && [ -s "$NAMES" ]; then
  grep -hF -o -w -f "$NAMES" -- "${USAGE_FILES[@]}" 2>/dev/null | sort | uniq -c > "$OCC"
fi
declare -A TOTAL=() DEFS=()
while read -r _c _n; do [ -n "$_n" ] && TOTAL["$_n"]="$_c"; done < "$OCC"
while read -r _c _n; do [ -n "$_n" ] && DEFS["$_n"]="$_c"; done < "$DEFCOUNT"

# Dynamic dispatch: `"s_$s"` builds a command name at runtime, so no static search can
# ever see `s_floors`. Any literal identifier PREFIX the tree uses to BUILD a command
# (`"prefix_$x"`) marks every defined name with that prefix reachable — the dispatcher
# is the consumer. A bare `"$x"` has no literal prefix and marks nothing.
DISPATCH="$(mktemp)"
trap 'rm -f "$INDEX" "$NAMES" "$NAMES.raw" "$DEFCOUNT" "$OCC" "$DISPATCH"' EXIT
grep -rhoE "['\"][A-Za-z_][A-Za-z0-9_]*\\\$" --include='*.sh' \
  --exclude-dir=.yggdrasil --exclude-dir=node_modules \
  "$ROOT/bin" "$ROOT/scripts" 2>/dev/null \
  | sed -E "s/^['\"]//; s/\\\$//" | sort -u > "$DISPATCH"
dispatched() {  # a name the tree can construct, so "unused" would be a false finding
  local name="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$name" in "$p"*) return 0 ;; esac
  done < "$DISPATCH"
  return 1
}

for f in "${SHELLS[@]:-}"; do
  [ -n "$f" ] || continue
  rel="${f#$ROOT/}"
  # `name() {` or `function name {`
  while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    case "$fn" in main|usage|help|die|log|warn|err) continue ;; esac
    [ "${TOTAL[$fn]:-0}" -gt "${DEFS[$fn]:-0}" ] && continue
    dispatched "$fn" && continue
    allowed "$rel"; rc=$?
    if [ "$rc" = "2" ]; then badallow=$((badallow + 1)); continue; fi
    [ "$rc" = "0" ] && continue
    printf '  "%s","DEAD FUNCTION","%s is defined and never called (RULES/16)"\n' "$rel" "$fn"
    findings=$((findings + 1))
  done < <(grep -ohE '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' "$f" 2>/dev/null \
             | sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*\(\)//' | sort -u)
done

printf 'dead-code-guard[3]{scanned,findings,bad_allowlist}:\n'
printf '  "%s","%s","%s"\n' "$scanned" "$findings" "$badallow"
if [ "$findings" -gt 0 ] || [ "$badallow" -gt 0 ]; then
  printf 'note: use it, or delete it, or add a line to %s naming WHO consumes it.\n' "${DEAD_ALLOW#$ROOT/}" >&2
  printf 'note: "we might need it later" is not a consumer — RULES/17-no-dead-code.md\n' >&2
  exit 1
fi
exit 0
