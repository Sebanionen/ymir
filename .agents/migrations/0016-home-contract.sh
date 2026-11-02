#!/usr/bin/env bash
# 0016-home-contract — heal an existing home with the files the runtime READS and it never
# received (RULES/42).
#
# WHY. An update is a `git pull` for the checkout and nothing at all for the home. Every
# home built before the contract therefore lacks whatever its author never hand-wrote — and
# measured 2026-11-02 that is most of the digest: `hodd/data/operator.md`,
# `learnings.md`, `machines.md`, `projects.md`, the roster `hodd/identity/seats.yaml` and
# the realm's `HOOD.md`. A user who installs today gets them; a user who installed last
# month does not, and no error anywhere says so. That is the drift Rule 25 names.
#
# WHAT IT DOES — exactly two calls, and both refuse to overwrite:
#   * bin/identity/registers-seed.sh   the four identity registers, if absent
#   * bin/engine/home-seed.sh          every `seeded` / `stub` row of .agents/home-contract.yaml, if absent
#
# WHAT IT DELIBERATELY DOES NOT DO:
#   * it does not write a file that exists — a home file is the operator's record, and a
#     migration that overwrites one is a rollback nobody asked for;
#   * it invents no name, no seat, no company and no project (the roster ships EMPTY and
#     says how to name a seat, because a name is the operator's act);
#   * it touches no record: hodd/memory, hodd/docs, hodd/reference, hodd/state and the
#     plans are read by nothing here (Rules 06, 11, 20).
#
# Idempotent: a second run seeds nothing and says so.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_DIR="${YMIR_HOME:-}"
[ -n "$HOME_DIR" ] || { . "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null && ymir_home_root HOME_DIR; }
[ -n "${HOME_DIR:-}" ] || { echo "0016: the home is unresolved — nothing touched"; exit 0; }
[ -d "$HOME_DIR" ] || { echo "0016: no home at $HOME_DIR — nothing touched"; exit 0; }

export YMIR_HOME="$HOME_DIR"

for door in bin/identity/registers-seed.sh bin/engine/home-seed.sh; do
  [ -r "$ROOT/$door" ] || { echo "0016: $door is not in this checkout — nothing seeded (update the tree first)"; exit 0; }
done

out="$(bash "$ROOT/bin/identity/registers-seed.sh" 2>&1)" || true
printf '%s\n' "$out" | sed 's/^/0016: /'

out="$(bash "$ROOT/bin/engine/home-seed.sh" 2>&1)" || {
  printf '%s\n' "$out" | sed 's/^/0016: /'
  echo "0016: the home contract refused — the rows it named above are not shipped in this tree"
  exit 1
}
printf '%s\n' "$out" | sed 's/^/0016: /'

# The roster's one-line hint is printed by bin/engine/home-seed.sh, the door that owns it —
# a second copy here would be the same sentence said twice.
exit 0
