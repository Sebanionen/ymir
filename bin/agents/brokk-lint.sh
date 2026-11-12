#!/usr/bin/env bash
# brokk-lint.sh — the Brokk lint gate. Single owner of lint for CI and
# no-mistakes; run by .github/workflows and `commands.lint` in .no-mistakes.yaml.
# Galdr-style: TOON output, structured errors, no prompts, idempotent.
#
# Usage: bin/agents/brokk-lint.sh [--quiet] ; bin/agents/brokk-lint.sh --version
# Exit: 0 clean, 1 findings, 2 usage.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
QUIET=0
[ "${1-}" = "--quiet" ] && QUIET=1

declare -a N S; fails=0
add() { N+=("$1"); S+=("$2"); [ "$2" = FAIL ] && fails=$((fails + 1)); }

# 1. shell syntax
shell=OK
for f in "$ROOT"/bin/*.sh; do
  [ -e "$f" ] || continue
  bash -n "$f" 2>/dev/null || shell=FAIL
done
add "shell syntax" "$shell"

# 2. plugin JS
js=OK
if command -v node >/dev/null 2>&1; then
  while IFS= read -r f; do
    node --check "$f" 2>/dev/null || js=FAIL
  # The adapters' SOURCE is .agents/harness/opencode/plugins/; the project-level
  # .opencode/plugins door is gone (one home — 2026-11-12), so lint the source.
  done < <(find "$ROOT/.agents/harness/opencode/plugins" "$ROOT/.opencode/plugins" -name '*.js' 2>/dev/null)
fi
add "plugin syntax" "$js"

# 3. JSON parse
json=OK
for f in "$ROOT/opencode.json" "$ROOT"/.agents/config/*.json "$ROOT"/.claude/settings.json "$ROOT"/.codex/hooks.json "$ROOT"/.cursor/hooks.json "$ROOT"/.agents/harness/opencode/plugins/package.json "$ROOT"/.opencode/plugins/package.json; do
  [ -e "$f" ] || continue
  python3 -m json.tool "$f" >/dev/null 2>&1 || json=FAIL
done
add "json parse" "$json"

# 4. Galdr/Tyr compliance gates
if bash "$ROOT/.agents/skills/galdr-ymirsystem/scripts/compliance-check.sh" >/dev/null 2>&1; then
  add "galdr compliance" OK
else
  add "galdr compliance" FAIL
fi

if [ "$QUIET" = 0 ]; then
  printf 'lint[%s]{check,status}:\n' "${#N[@]}"
  for i in "${!N[@]}"; do printf '  "%s","%s"\n' "${N[$i]}" "${S[$i]}"; done
fi
if [ "$fails" -gt 0 ]; then
  printf 'error: %s lint check(s) failed\n' "$fails" >&2
  printf 'help: run bin/agents/brokk-lint.sh to see the failing check\n' >&2
  exit 1
fi
exit 0
