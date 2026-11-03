#!/usr/bin/env bash
# registers-guard.sh — every generated register is current.
#
# The class this closes: a change adds a door, regenerates the register it knows
# about, and leaves the other one stale — which CI catches and a local ward does
# not. `bin/gates/registers.sh` owns the list of generators; this ward asks it, so
# the set a push checks and the set CI checks cannot drift.
#
# Usage: registers-guard.sh [check]
# Exit: 0 every register current · 1 a register is stale · 3 unavailable.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
DOOR="$ROOT/bin/gates/registers.sh"
[ -r "$DOOR" ] || { printf 'unavailable: bin/gates/registers.sh is missing\n' >&2; exit 3; }
exec bash "$DOOR" check
