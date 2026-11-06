#!/usr/bin/env bash
# guards.sh — every TREE ward, in one command.
#
# The pre-push hook and BOTH CI hosts call this, so the set of wards has exactly one home:
# adding a ward means adding a line here, and nowhere else. A ward judges the tree and exits
# non-zero when it finds a fault; this only aggregates.
#
# Usage:
#   guards.sh          # run every tree ward
#   guards.sh --list   # name them
#
# Exit: 0 every ward clean · 1 a ward found a fault · 2 usage.
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

# ONE list. A new tree ward appears here or it does not run anywhere.
WARDS=(runtime-guard.sh runtime-pinned-guard.sh defaults-guard.sh app-folder-guard.sh app-functional-guard.sh rules-number-guard.sh inventory-guard.sh registers-guard.sh fleet-version-guard.sh subsystem-docs-guard.sh path-ledger-guard.sh path-legality-guard.sh packaging-guard.sh public-data-guard.sh cron-guard.sh features-guard.sh weave-guard.sh vault-guard.sh confidential-guard.sh dead-code-guard.sh docs-claims-guard.sh home-contract-guard.sh language-guard.sh pkill-guard.sh skills-share-guard.sh rules-compliance-guard.sh pr-ship-guard.sh model-rows-guard.sh)
#
# weave-guard (2026-11-04, plan 175 §3): the weaver was seated and NOTHING CALLED IT — so a stale
# index (RULES/README.md, a plan row, a feature page's catalogue row) was refused by no ward at all.
# It runs weave.sh --check and refuses, naming the gap; it never fixes, because a silent fix hides
# the hand-edit that caused the drift. The hook is convenience, CI keeps the last word.
#
# skills-share-guard (2026-11-04, plan 184): the skills door serves a BUILT copy, and a redaction
# pass trusted to be complete is how a hostname leaves in a footnote. The ward refuses machine
# paths, addresses, LAN hosts, ports, our people, mailboxes, phones, bench tables and our catalog's
# model ids over `hodd/skills-share/published/` — the last word is a refusal, not a review. It
# skips cleanly (and says so) on a machine that has published nothing yet.
# path-legality-guard (2026-11-03): a tracked NAME must be legal on every host RULES/05 claims —
# a `:` NTFS cannot hold made a Windows clone write no tree at all, for a month, unseen.
# packaging-guard (2026-11-03): every path a shipped installer names must exist — the Windows
# .nsi still named the OLD bootstrapper path after Rule 22 moved the host layers, and the build
# that would have said so (ymir-installers.yml) runs only on a tag nobody had cut.

case "${1-}" in
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --list)    printf '%s\n' "${WARDS[@]}"; exit 0 ;;
  "")        ;;
  *)         printf 'error: unknown flag %s\nhelp: guards.sh [--list]\n' "${1-}" >&2; exit 2 ;;
esac

fail=0
failed=()
printf 'guards[%s]{ward,status,finding}:\n' "${#WARDS[@]}"
for w in "${WARDS[@]}"; do
  s="$ROOT/bin/gates/guards/$w"
  if [ ! -r "$s" ]; then
    printf '  "%s","MISSING","bin/gates/guards/%s — a ward named in the list does not exist"\n' "$w" "$w"
    fail=1
    continue
  fi
  if out="$(bash "$s" check 2>&1)"; then
    printf '  "%s","PASS",""\n' "$w"
  else
    failed+=("$w")
    # The ward's own last line names the fault and its remedy; carry it up rather than
    # swallowing it, because a gate that does not say why is an obstacle. The pattern is the
    # ward SUFFIX, not two named wards: it read `^(defaults|runtime)-guard:` until 2026-11-04,
    # so every other ward's reason was thrown away and the FAIL row printed an empty finding
    # (inventory-guard, registers-guard, and the new weave-guard all said nothing).
    printf '  "%s","FAIL","%s"\n' "$w" "$(printf '%s' "$out" | grep -E '^[[:alnum:]_-]+-guard' | tail -1 | cut -c1-160)"
    fail=1
  fi
done

# WHOSE FAULT IS IT — the branch's, or main's? (plan 203 §15.2 gap 8)
# Measured 2026-11-05/06: three pushes in one night were refused by wards that were red on
# `origin/main`, not on the branch under review — and the refusal read as if the branch were
# broken, so a hand "fixed" work it had not caused. A failing ward is now judged against main
# as well, in one throwaway worktree (once, no matter how many wards failed), and the answer
# is printed where the finding is read.
if [ "$fail" -ne 0 ] && [ "${#failed[@]}" -gt 0 ] && git -C "$ROOT" rev-parse --verify -q origin/main >/dev/null 2>&1; then
  wt="$(mktemp -d "${TMPDIR:-/tmp}/guards-main-XXXXXX")"
  if git -C "$ROOT" worktree add -q --detach "$wt/main" origin/main 2>/dev/null; then
    also=0
    printf 'main_baseline[%s]{ward,on_main,verdict}:\n' "${#failed[@]}"
    for w in "${failed[@]}"; do
      if [ -r "$wt/main/bin/gates/guards/$w" ] && ! ( cd "$wt/main" && timeout 120 bash "bin/gates/guards/$w" check ) >/dev/null 2>&1; then
        also=$((also + 1))
        printf '  "%s","red","main is red too — this is not your branch (fix it, or wait for the hand that owns main)"\n' "$w"
      else
        printf '  "%s","green","your branch — this one is yours to fix"\n' "$w"
      fi
    done
    git -C "$ROOT" worktree remove --force "$wt/main" >/dev/null 2>&1 || true
    [ "$also" -gt 0 ] && printf 'guards: %s of %s failing ward(s) are red on origin/main, not on this branch\n' "$also" "${#failed[@]}" >&2
  fi
  rm -rf "$wt" 2>/dev/null || true
fi

if [ "$fail" -eq 0 ]; then
  exit 0
fi
printf 'guards: a ward found a fault — see the FAIL row above\nhelp: run the failing ward directly; its message names the remedy\n' >&2
exit 1
