#!/usr/bin/env bash
# arm.sh — the Gná arm, honestly: what the watch is, and whether THIS harness can arm it.
#
#   arm.sh status            # the unit, the heartbeat, the lock — the truth about arming
#   arm.sh hook <harness>    # the session-start hook a harness with hooks must install
#
# The watch LOOP is harness-agnostic (the ymir-syn-watch unit + bin/pi/syn-watch-arm.sh);
# the SESSION SIDE (relaying a wake into a live session) is owned by a harness extension:
# Pi (gna-pi-watch) and OpenCode (syn-watch-arm.js) have one. A harness with no hook and no
# extension cannot be armed — and this door says so instead of pretending.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "${1:-status}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  status)
    # no session bus is not "absent": say unknown, so a wrong claim never closes the question
    if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      unit="unknown (no session bus in this context)"
    else
      unit="$(systemctl --user is-active ymir-syn-watch.service 2>/dev/null || echo absent)"
    fi
    printf 'arm[3]{what,value,note}:\n'
    printf '  "watch unit","%s","the loop runs outside the session"\n' "$unit"
    printf '  "lock","%s","the session that holds the helm"\n' "$(cat "$HOME/.pi/agent/extensions/.lock" 2>/dev/null || printf 'none')"
    case "$(uname -s)" in *) : ;; esac
    if [ "$unit" = active ]; then printf '  "arm","possible","the session side is an extension (Pi: gna-pi-watch; OpenCode: syn-watch-arm.js)"\n'
    else printf '  "arm","not possible — the watch loop is not running","start ymir-syn-watch.service"\n'; fi ;;
  hook)
    h="${2:-}"; case "$h" in
      claude) printf 'claude: add a SessionStart hook that runs: %s/bin/time/saga-session-start.sh\n' "$ROOT" ;;
      hermes) printf 'hermes: hermes hooks — add a session-start hook running: %s/bin/time/saga-session-start.sh\n' "$ROOT" ;;
      codex|cursor) printf '%s: no session hook surface installed — it can read the digest by running %s/bin/time/saga-session-start.sh, but cannot be armed mid-session (named, never faked)\n' "$h" "$ROOT" ;;
      *) printf 'usage: arm.sh hook <claude|hermes|codex|cursor>\n' ;;
    esac ;;
  *) printf 'error: unknown action %s\nhelp: arm.sh [status|hook <harness>]\n' "$1" >&2; exit 2 ;;
esac
