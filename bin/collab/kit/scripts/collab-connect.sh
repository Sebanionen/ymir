#!/usr/bin/env bash
# collab-connect.sh — what a collaborator pastes, and the token the house mints.
#
#   collab-connect.sh snippet --endpoint URL [--harness pi|opencode]
#   collab-connect.sh mint --peer NAME --skill ID [--aud NAME] [--minutes N] [--key FILE]
#   collab-connect.sh check --token JWT --pub FILE [--aud NAME] [--skill ID]
#
# The token half delegates to bin/bridge/a2a-front.py (one implementation, no second JWT).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
FRONT="$ROOT/bin/bridge/a2a-front.py"
die() { printf 'collab-connect: %s\n' "$*" >&2; exit 2; }

case "${1-}" in
  snippet)
    shift; url=""; harness="pi"
    while [ $# -gt 0 ]; do case "$1" in
      --endpoint) url="${2-}"; shift 2 ;;
      --harness) harness="${2-}"; shift 2 ;;
      *) die "unknown argument $1" ;;
    esac; done
    [ -n "$url" ] || die "usage: collab-connect.sh snippet --endpoint URL [--harness pi|opencode]"
    case "$harness" in
      pi) printf '{ "mcpServers": { "snotra": { "url": "%s/mcp" } } }\n' "${url%/}" ;;
      opencode) printf '{ "mcp": { "snotra": { "type": "remote", "url": "%s/mcp" } } }\n' "${url%/}" ;;
      *) die "unknown harness '$harness' (pi|opencode)" ;;
    esac
    ;;
  mint)
    shift; [ -x "$FRONT" ] || [ -r "$FRONT" ] || die "bin/bridge/a2a-front.py is missing — the token door is not installed"
    python3 "$FRONT" mint "$@"
    ;;
  check)
    shift; python3 "$FRONT" verify "$@"
    ;;
  *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
