#!/usr/bin/env bash
# a2a-front.sh — the thin door to bin/bridge/a2a-front.py (Rule 23: one executor, a shell face).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/a2a-front.py" "$@"
