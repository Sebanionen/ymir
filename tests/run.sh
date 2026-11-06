#!/usr/bin/env bash
# Run every Snotra door test. Exit non-zero if any fails.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
for t in test_snotra_store.sh test_ping_room.sh test_snotra_autojoin.sh test_snotra_bot.sh test_utgard_box.sh; do
  printf '\n=== %s\n' "$t"
  bash "$HERE/$t" || fail=1
done
printf '\n%s\n' "$([ "$fail" -eq 0 ] && echo 'all suites passed' || echo 'a suite failed')"
exit "$fail"
