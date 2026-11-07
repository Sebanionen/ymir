#!/usr/bin/env bash
# new-module-test.sh — a new module arrives with a test, or with a reason it does not need one.
#
# The module that taught this house the gate was an 80-line interpreter added with no test at all, and the wards passed,
# because reachability is not behaviour.
#
# Usage: new-module-test.sh <base> [head]   exit 0 allowed · 1 an untested module · 2 usage
set -u
base="${1:-}"; head="${2:-HEAD}"
[ -n "$base" ] || { printf 'new-module-test: usage: new-module-test.sh <base> [head]\n' >&2; exit 2; }

allow=".module-test.allow"
added=$(git diff --diff-filter=A --name-only "$base" "$head" -- 'backend/*.ts' 'src/lib/*.ts' 'scripts/*.ts' 2>/dev/null \
  | grep -v '\.test\.ts$' | grep -vE '(^|/)server\.ts$')

[ -z "$added" ] && exit 0

missing=""
for module in $added; do
  stem=$(basename "$module" .ts)
  if grep -qs "$stem" .module-test.allow 2>/dev/null; then continue; fi
  if git grep -qs -l "$stem" -- '*test*' 2>/dev/null; then continue; fi
  missing="$missing $module"
done

[ -z "$missing" ] && exit 0
printf 'new-module-test refused: a module arrived with no test naming it\n' >&2
for m in $missing; do printf '    %s\n' "$m" >&2; done
printf '  a test beside it, or one line in %s saying why it needs none\n' "$allow" >&2
exit 1
