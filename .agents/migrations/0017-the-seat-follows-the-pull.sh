#!/usr/bin/env bash
# 0017-the-seat-follows-the-pull — heal the SEAT that a `git pull` cannot reach.
#
# WHY (2026-11-03, found on a clean Windows/WSL2 seat that this house calls supported).
# An update is a `git pull` for the checkout and nothing at all for the seat around it:
#
#   · the installed hooks are files in .git/hooks, written by whoever installed FIRST — the
#     pre-commit one baked one machine's absolute path and carried no Rule 11 ward, so a
#     reclaimed worktree took the whole gate with it;
#   · `~/.bun/bin` was exported into the installer's own shell and into nobody else's, so the
#     validator printed `missing: bun` on a host that has bun (RULES/25: probe, never assume);
#   · the validator read "the scheduler retired because no seat held the lock" as a FAILURE,
#     when that is the design.
#
# None of that lives in the repository, so no pull can fix it. This migration is the door that
# does — and it is the only one the installer, `bin/agents/groa-update.sh` and
# `bin/agents/eir-doctor.sh fix` all call, so a seat is healed the same way whichever verb the
# operator reaches for.
#
# WHAT IT DOES — three idempotent calls, each to the door that owns the answer:
#   * the hook installers (`secret-guard.sh --install`, `fixes-guard.sh --install`) — they write
#     hooks that resolve the repo root at RUN time;
#   * `prereq-ensure.sh --persist-path` — the marked PATH block, in the profile of the shell the
#     operator actually runs (probed: $SHELL, and a zsh user gets ~/.zprofile);
#   * the pinned runtime, REPORTED not moved: `runtime-deploy.sh --check` says whether the units
#     stand on the merged head, and moving it is the operator's act, not a migration's.
#
# WHAT IT DELIBERATELY DOES NOT DO:
#   * it never rewrites a file the operator wrote — the profile block is marked and replaced in
#     place, and a hook that exists is simply re-seated with the current content;
#   * it touches no record: hodd/memory, hodd/docs, hodd/reference and the plans are read by
#     nothing here (Rules 06, 11, 20);
#   * it does not restart a unit or move the runtime.
#
# Idempotent: a second run re-seats the same content and prints "present" for the PATH.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_DIR="${YMIR_HOME:-}"
[ -n "$HOME_DIR" ] || { . "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null && ymir_home_root HOME_DIR; }
[ -d "${HOME_DIR:-/nonexistent}" ] || { echo "0017: no home resolved — the checkout is still healed by the pull"; }

say() { printf '0017: %s\n' "$1"; }

# ── 1. hooks: the same content the installer writes, resolved at run time ───────────────────
hooks_dir="$(cd "$ROOT" && git rev-parse --git-path hooks 2>/dev/null || printf '%s/.git/hooks' "$ROOT")"
case "$hooks_dir" in /*) ;; *) hooks_dir="$ROOT/$hooks_dir" ;; esac
if [ -d "$hooks_dir" ]; then
  seated=""
  for pair in "secret-guard.sh pre-commit" "fixes-guard.sh pre-push"; do
    set -- $pair
    installer="$ROOT/bin/gates/guards/$1"; hook="$hooks_dir/$2"
    [ -x "$installer" ] || continue
    [ -e "$hook" ] || continue                     # never seat a ward on a repo that had none
    "$installer" --install >/dev/null 2>&1 && seated="$seated $2"
  done
  [ -n "$seated" ] && say "hooks re-seated, root resolved at run time:$seated"
else
  say "no .git/hooks here — a clone or an npm install, not a seat; nothing to re-seat"
fi

# ── 2. the PATH a later shell (and a validator) sees ───────────────────────────────────────
if [ -x "$ROOT/bin/engine/prereq-ensure.sh" ]; then
  out="$("$ROOT/bin/engine/prereq-ensure.sh" --persist-path 2>&1)" && \
    say "$(printf '%s' "$out" | sed -n 's/.*"path","\([^"]*\)","\([^"]*\)".*/\1 — \2/p' | head -1)"
else
  say "no prereq-ensure.sh in this tree — the PATH is unchanged"
fi

# ── 3. the pinned runtime, reported ────────────────────────────────────────────────────────
if [ -x "$ROOT/bin/engine/runtime-deploy.sh" ]; then
  rt="$("$ROOT/bin/engine/runtime-deploy.sh" --check 2>&1 | head -3 | tr '\n' ' ')"
  case "$rt" in
    *"deployed"*|*"current"*|*"up to date"*) say "pinned runtime: ${rt}" ;;
    "") say "pinned runtime: no answer (not this role, or nothing pinned yet)" ;;
    *) say "pinned runtime needs the operator's word: bin/engine/runtime-deploy.sh — ${rt}" ;;
  esac
fi

say "done — the seat follows the pull; \`bin/engine/ymir-validate.sh\` proves it"
