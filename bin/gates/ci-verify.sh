#!/usr/bin/env bash
# ci-verify.sh — what CI must prove, in one command, for BOTH hosts.
#
# GitHub Actions and Forgejo Actions are two doors to the same room, so neither holds a
# copy of the checks: both call THIS. A workflow that re-listed the steps would be a second
# place for them to drift, which is the failure this whole repository is being taught to stop.
#
# Usage:
#   ci-verify.sh            # run every gate CI owes
#   ci-verify.sh --fast     # skip the heavy one (the real npm install)
#
# Exit: 0 everything proved · 1 a gate failed · 2 usage.
set -u

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

FAST=0
case "${1-}" in
  -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --fast)    FAST=1 ;;
  "")        ;;
  *)         printf 'error: unknown flag %s\nhelp: ci-verify.sh [--fast]\n' "${1-}" >&2; exit 2 ;;
esac

fail=0
printf 'ci_verify[4]{gate,status,detail}:\n'

gate() {  # <name> <description> <command...>
  local name="$1" what="$2"; shift 2
  local out; out="$( "$@" 2>&1 )" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '  "%s","PASS","%s"\n' "$name" "$what"
  else
    printf '  "%s","FAIL","%s"\n' "$name" "$what"
    # The failing gate's own tail — the single-line swallow hid WHICH check
    # died inside (e.g. pr-pretest's hull/sandbox/app-boot rows). Print the
    # last 12 lines so CI tells us the actual failing step.
    printf '%s\n' "$out" | grep -vE '^[[:space:]]*$' | tail -12 | sed 's/^/    /'
    fail=1
  fi
}

gate ward        "the tree wards (runtime, defaults)"   bash "$ROOT/bin/gates/guards.sh"

# Rule 11 — a tracked file is MOVED, never deleted. RULES/11 says the ward runs here; until
# 2026-11-03 nothing in this file called it, so a deletion passed CI unseen. The range is the
# PR's base when there is one, and an honest SKIP (not a green) when this checkout has no base.
nodelete_base() {
  local b=""
  if [ -n "${GITHUB_BASE_REF:-}" ] && git rev-parse -q --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
    b="origin/${GITHUB_BASE_REF}"
  elif git rev-parse -q --verify origin/main >/dev/null 2>&1; then
    b="origin/main"
  fi
  [ -n "$b" ] || return 1
  printf '%s' "$b"
}
if nd_base="$(nodelete_base)"; then
  gate no-delete "Rule 11 — a tracked file is moved, never deleted (against $nd_base)" \
       bash "$ROOT/bin/no-delete-guard.sh" --base "$nd_base"
else
  printf '  "%s","SKIP","%s"\n' "no-delete" "no base ref in this checkout — judged by the pre-push hook and on a PR"
fi
gate compliance  "the 15 governance gates"              bash "$ROOT/.agents/skills/galdr-ymirsystem/scripts/compliance-check.sh"
gate contracts   "the typed surfaces (one contract, two consumers)" bash "$ROOT/bin/gates/checks/contracts-check.sh"
gate queue       "the derived work queue is current"              bash "$ROOT/bin/gates/queue.sh" --check
gate plan-ledger  "every plan carries the contract (his words, a measure, proven phases, a refusal, questions, a number, a row with a status)" \
               bash "$ROOT/bin/gates/plan-audit.sh" --check
gate capability "the capability register is current"           bash "$ROOT/bin/gates/capabilities.sh" --check
gate home-index "the home's shelves are navigable"             bash "$ROOT/bin/gates/checks/home-index-check.sh"
gate usage      "no door became unused since the baseline"    bash "$ROOT/bin/gates/checks/usage-ratchet.sh"
gate portability "GNU-only callers may fall, never rise (RULES/05)"    bash "$ROOT/bin/gates/checks/portability-ratchet.sh" check
gate inventory  "the bin/backend index is current"            bash "$ROOT/bin/gates/inventory.sh" --check
gate workflows  "every Actions workflow parses"               bash "$ROOT/bin/gates/checks/workflow-check.sh" --quiet
gate units      "systemd reads every key in every unit template" bash "$ROOT/bin/gates/checks/unit-template-check.sh" --quiet
gate ext-api    "extensions speak Pi's real tool API"          bash "$ROOT/bin/gates/checks/extension-api-check.sh" --quiet
gate ext-smoke  "every Ymir tool ANSWERS when called like Pi calls it" \
               node --experimental-strip-types "$ROOT/tools/extension-smoke.mjs"
codex_checks() {
  local door
  for door in bin/engine/ymir-install.sh bin/agents/groa-update.sh bin/bridge/ymir-plan.sh; do
    bash -n "$ROOT/$door" || return 1
  done
  node --test "$ROOT/tests/test_codex_plugin.mjs" "$ROOT/tests/test_codex_install.mjs"
}
gate codex-plugin "the Codex tool catalog, shell syntax, install and refresh contract" codex_checks
if [ "$FAST" = 1 ]; then
  printf '  "%s","SKIP","%s"\n' pr-pretest "skipped by --fast"
else
  gate pr-pretest  "a REAL npm install of the publish artifact" bash "$ROOT/bin/forge/npm/pr-pretest.sh"
fi

if [ "$fail" -eq 0 ]; then
  exit 0
fi
printf 'ci-verify: a gate failed — see the FAIL row above\nhelp: run the failing gate directly\n' >&2
exit 1
