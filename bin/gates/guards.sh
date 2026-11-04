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
WARDS=(runtime-guard.sh runtime-pinned-guard.sh defaults-guard.sh app-folder-guard.sh app-functional-guard.sh rules-number-guard.sh inventory-guard.sh registers-guard.sh fleet-version-guard.sh subsystem-docs-guard.sh path-ledger-guard.sh path-legality-guard.sh packaging-guard.sh public-data-guard.sh cron-guard.sh features-guard.sh weave-guard.sh vault-guard.sh confidential-guard.sh dead-code-guard.sh docs-claims-guard.sh home-contract-guard.sh language-guard.sh pkill-guard.sh skills-share-guard.sh)
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
    # The ward's own last line names the fault and its remedy; carry it up rather than
    # swallowing it, because a gate that does not say why is an obstacle. The pattern is the
    # ward SUFFIX, not two named wards: it read `^(defaults|runtime)-guard:` until 2026-11-04,
    # so every other ward's reason was thrown away and the FAIL row printed an empty finding
    # (inventory-guard, registers-guard, and the new weave-guard all said nothing).
    printf '  "%s","FAIL","%s"\n' "$w" "$(printf '%s' "$out" | grep -E '^[[:alnum:]_-]+-guard' | tail -1 | cut -c1-160)"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  exit 0
fi
printf 'guards: a ward found a fault — see the FAIL row above\nhelp: run the failing ward directly; its message names the remedy\n' >&2
exit 1
