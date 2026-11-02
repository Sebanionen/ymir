#!/usr/bin/env bash
# groa-update.sh — Gróa, the völva who renews.
#
# Gróa is the updater shaman: she fast-forwards Brokk and every registered
# Eindri-home to the latest, then mends the tree forward (migrations, fleet
# preferences). Brokk runs her; Galdr owns the assets she must be reflected in
# when the instruction surface moves; the `groa-update` skill is her door.
#
# Fast-forward only. Never forces, never stashes, never creates a merge commit.
# Anything dirty, diverged, offline, or on a non-default branch is skipped and
# reported. Touches only Brokk repos and their worktrees — never projects/.
#
# Usage:
#   groa-update.sh [--check] [--remote <name>] [--branch <name>]
#   groa-update.sh --version
#
# The `groa-update` skill invokes her; `bin/agents/brokk-update.sh` is a back-compat
# alias. Prints one row per target, then the action lines:
#   reread-Brokk: yes|no
#   galdr-reread: yes|no                 (Galdr must refresh the owning assets)
#   nudge-eindri-homes: <id> ...|none
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _yc in "${ROOT:-}/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/bin/vault/hoard-lib.sh" \
             "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/hoard-lib.sh"; do
    [ -n "$_yc" ] && [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yc
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
# The registry lives in the hoard (RULES/04-hoard.md; correction 2026-09-17).
# Resolve through hoard-lib so the path can never drift again.
if [ -r "$SCRIPT_DIR/../vault/hoard-lib.sh" ]; then
  # shellcheck source=bin/vault/hoard-lib.sh
  . "$SCRIPT_DIR/../vault/hoard-lib.sh"; hoard_root _hoard
else
  _hoard="${YMIR_HOARD:-$YMIR_HOME/hodd}"
fi
REG="${BROKK_EINDRI_HOMES:-$_hoard/data/eindri-homes.md}"
REMOTE=""; BRANCH=""; CHECK=0

case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;; -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --remote) REMOTE=${2-}; shift 2 ;;
    --branch) BRANCH=${2-}; shift 2 ;;
    *) printf 'error: unknown flag %s\nhelp: bin/agents/groa-update.sh [--check|--remote|--branch]\n' "$1" >&2; exit 2 ;;
  esac
done

# Resolve remote/branch from the master registry when the resolver is present.
if [ -x "$SCRIPT_DIR/project-git.sh" ] && "$SCRIPT_DIR/project-git.sh" list 2>/dev/null | grep -q 'ymir-platform'; then
  [ -n "$REMOTE" ] || REMOTE="$("$SCRIPT_DIR/project-git.sh" ymir-platform --field remote 2>/dev/null)"
  [ -n "$BRANCH" ] || BRANCH="$("$SCRIPT_DIR/project-git.sh" ymir-platform --field default_branch 2>/dev/null)"
fi
REMOTE="${REMOTE:-origin}"
BRANCH="${BRANCH:-main}"

declare -a ROWS; NUDGE_IDS=""
reread=no
changed_surface=0

# Guarded fast-forward of one Brokk home. Sets FF_STATE/FF_DETAIL.
ff_home() { # <path> <label>
  local p="$1" label="$2"
  if [ ! -d "$p" ]; then FF_STATE="skipped"; FF_DETAIL="not found: $p"; return; fi
  if ! git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then FF_STATE="skipped"; FF_DETAIL="not a git repo"; return; fi
  local cur; cur="$(git -C "$p" branch --show-current 2>/dev/null || echo '')"
  if [ -n "$cur" ] && [ "$cur" != "$BRANCH" ]; then FF_STATE="skipped"; FF_DETAIL="on branch $cur"; return; fi
  local dirty; dirty="$(git -C "$p" status --porcelain | wc -l | tr -d ' ')"
  if [ "$dirty" != "0" ]; then FF_STATE="skipped"; FF_DETAIL="dirty ($dirty)"; return; fi
  git -C "$p" fetch --quiet --prune "$REMOTE" 2>/dev/null || { FF_STATE="skipped"; FF_DETAIL="offline ($REMOTE)"; return; }
  local local_h target
  local_h="$(git -C "$p" rev-parse HEAD)"
  target="$(git -C "$p" rev-parse "$REMOTE/$BRANCH" 2>/dev/null)" || { FF_STATE="skipped"; FF_DETAIL="$REMOTE/$BRANCH missing"; return; }
  if [ "$local_h" = "$target" ]; then FF_STATE="current"; FF_DETAIL="${local_h:0:8}"; return; fi
  if ! git -C "$p" merge-base --is-ancestor "$local_h" "$target"; then FF_STATE="skipped"; FF_DETAIL="diverged"; return; fi
  if [ "$CHECK" = 1 ]; then FF_STATE="behind"; FF_DETAIL="$(git -C "$p" rev-list --count "$local_h..$target") behind"; return; fi
  if git -C "$p" merge --ff-only -q "$target" 2>/dev/null; then
    FF_STATE="updated"; FF_DETAIL="${local_h:0:8}..$(git -C "$p" rev-parse --short HEAD)"
    if [ -n "$(git -C "$p" diff --name-only "$local_h" "$target" -- AGENTS.md bin .agents/skills 2>/dev/null)" ]; then
      [ "$label" = "$ROOT" ] && changed_surface=1
    fi
  else FF_STATE="skipped"; FF_DETAIL="fast-forward failed"; fi
}

add_row() { ROWS+=("$1"); }

# 1. This home.
ff_home "$ROOT" "$ROOT"
add_row "  \"$ROOT\",\"this Brokk home\",\"$FF_STATE\",\"$FF_DETAIL\""

# 2. Registered Eindri-homes.
if [ -f "$REG" ]; then
  while IFS= read -r line; do
    case "$line" in '- '*) ;; *) continue ;; esac
    id="$(printf '%s' "$line" | sed -nE 's/^- ([^ ]+).*/\1/p')"
    host="$(printf '%s' "$line" | sed -nE 's/.*\(host: ([^;)]+).*/\1/p' | tr -d ' ')"
    home="$(printf '%s' "$line" | sed -nE 's/.*\(.*home: ([^;)]+).*/\1/p' | sed -E 's/ *(host:.*)?$//' | tr -d ' ')"
    [ -n "$id" ] || continue
    if [ -n "$host" ]; then
      root="$(printf '%s' "$line" | sed -nE 's/.*root: ([^;)]+).*/\1/p' | tr -d ' ')"
      add_row "  \"$id\",\"remote $host:${root:-$home}\",\"skipped\",\"remote route — run bin/agents/groa-update.sh on $host\""
      continue
    fi
    [ -n "$home" ] || home="$id"
    ff_home "$home" "$home"
    add_row "  \"$id\",\"$home\",\"$FF_STATE\",\"$FF_DETAIL\""
    [ "$FF_STATE" = "updated" ] && NUDGE_IDS="$NUDGE_IDS $id"
  done <"$REG"
else
  add_row "  \"-\",\"registry\",\"absent\",\"$REG (no Eindri-homes registered)\""
fi

# reread-Brokk: yes when this home's instruction surface advanced.
[ "$changed_surface" = 1 ] && reread=yes

printf 'groa[1]{state,root,remote,branch,mode}:\n  "renew","%s","%s","%s","%s"\n' "$ROOT" "$REMOTE" "$BRANCH" "$([ "$CHECK" = 1 ] && echo check || echo apply)"
printf 'update[%d]{id,target,state,detail}:\n' "${#ROWS[@]}"
printf '%s\n' "${ROWS[@]}"
printf 'reread-Brokk: %s\n' "$reread"
# Galdr owns the assets; when the instruction surface moved she must be reflected
# in the same pass (the code/plan/asset agreement law).
printf 'galdr-reread: %s\n' "$reread"
# The seat's name is part of the update surface: scan the collision registry and
# report a drifted seat instead of silently keeping the old identity.
if [ -x "$SCRIPT_DIR/../agents/name-registry.sh" ]; then
  "$SCRIPT_DIR/../agents/name-registry.sh" scan >/dev/null 2>&1 || true
fi
if [ -x "$SCRIPT_DIR/../agents/seat-identity.sh" ]; then
  printf 'seat-identity: %s\n' "$("$SCRIPT_DIR/../agents/seat-identity.sh" --check "${YMIR_HOST:-$(hostname -s)}" 2>&1 | tail -1)"
fi
if [ -n "${NUDGE_IDS# }" ]; then printf 'nudge-eindri-homes: %s\n' "${NUDGE_IDS# }"; else printf 'nudge-eindri-homes: none\n'; fi

# Keep the whole fleet on the fleet preferences (writes each home's gitignored
# state/; never touches a tracked tree).
[ -x "$SCRIPT_DIR/../fleet/fleet-apply.sh" ] && "$SCRIPT_DIR/../fleet/fleet-apply.sh" >/dev/null 2>&1 || true

# Heal this home forward (structure migrations) after every update.
[ -x "$SCRIPT_DIR/../engine/ymir-migrate.sh" ] && "$SCRIPT_DIR/../engine/ymir-migrate.sh" apply >/dev/null 2>&1 || true
# the hound's units are rendered from the repo, so an update re-seats them
[ -x "$SCRIPT_DIR/../ward/garmr.sh" ] && "$SCRIPT_DIR/../ward/garmr.sh" refresh >/dev/null 2>&1 || true

# Gróa's own body is rendered from the repo too: an update re-seats her, so the
# features of the new tree are the features she runs. Never fatal.
[ -x "$SCRIPT_DIR/groa-agent/seat.sh" ] && "$SCRIPT_DIR/groa-agent/seat.sh" --quiet >/dev/null 2>&1 || true

# Eir checks after every update, so a desktop that cannot open is REPORTED and
# never silently dead (P8, 2026-09-24). The update is never blocked on a
# broken surface — the report is the loudness; the Nornir job keeps the watch
# daily.
if [ -x "$SCRIPT_DIR/eir-doctor.sh" ]; then
  if eir_out="$("$SCRIPT_DIR/eir-doctor.sh" check 2>&1)"; then
    printf 'eir: check clean\n'
  else
    eir_broken="$(printf '%s' "$eir_out" | sed -n '2s/.*,\([0-9][0-9]*\)$/\1/p')"
    printf 'eir: %s surface(s) need mending — bin/agents/eir-doctor.sh (the row above names them)\n' "${eir_broken:-?}"
  fi
fi

# REBIND the harness surfaces (Valknut). An update pulls new agents, skills and
# Pi extensions into the tree, but the harnesses load them from their OWN homes —
# Pi reads ${HOME}/.pi/agent/extensions/. Without this step a merged extension
# fix sits in the repo while the RUNNING harness keeps the old code, which is how
# a hand-copy became necessary (2026-09-23). No installation or update should
# leave the surfaces stale: bind them here, every time.
if [ -x "$SCRIPT_DIR/../seat/valknut-load.sh" ]; then
  print_step "loaders" 2>/dev/null || printf '  loaders: '
  # An update that leaves the phone gateway broken is NOT complete, for the same reason the
  # seat is not complete: extensions that were seated but never re-proved stay broken quietly.
  if [ -x "$SCRIPT_DIR/tools/ymir-gateway/smoke.sh" ]; then
    if bash "$SCRIPT_DIR/tools/ymir-gateway/smoke.sh" >/dev/null 2>&1; then
      printf 'gateway: ok — ymir-gateway answers after the update\n'
    else
      printf 'FAIL — ymir-gateway smoke test failed after this update.\n'
      printf '      run bash tools/ymir-gateway/smoke.sh (YMIR_LIVE=1 to include the local rail)\n' >&2
      GATEWAY_FAILED=1
    fi
  fi

  # THE HOME: an update cannot assume the home exists. Measured 2026-11-02 — a fresh operator was told
  # "everything private lives in your home" and then met an empty directory. An update that finds it missing
  # says so in plain words and lays it out; it never guesses and never overwrites.
  if [ -x "$SCRIPT_DIR/../engine/home-seed.sh" ]; then
    if [ "${CHECK:-0}" = "1" ]; then
      if bash "$SCRIPT_DIR/../engine/home-seed.sh" --check >/dev/null 2>&1; then
        printf 'home: shelves complete\n'
      else
        printf 'home: shelves incomplete — an update would lay them out (bin/engine/home-seed.sh)\n'
      fi
    else
      bash "$SCRIPT_DIR/../engine/home-seed.sh" --yes >/dev/null 2>&1 \
        && printf 'home: shelves laid out and readme written\n' \
        || printf 'home: home-seed could not lay the shelves out — run bin/engine/home-seed.sh and read its rows\n'
    fi
  fi
  # THE HARNESSES: an update that leaves a user's agent reading last month's law, or running without the
  # house's extensions, is not an update (RULES/13, 2026-11-02; his word: "all extentons and packets to all
  # harnesses must come on uptaaes"). One verb does all of it, per harness the descriptors know about —
  # contracts, plugins, hooks, rules — and it NAMES what it will not merge blindly (a user's own JSON).
  if [ -x "$SCRIPT_DIR/../seat/harness-extensions-install.sh" ]; then
    if [ "${CHECK:-0}" = "1" ]; then
      # --check changes NOTHING: report, never write (an updater that writes during a dry run is not a dry run)
      if bash "$SCRIPT_DIR/../seat/harness-extensions-install.sh" --check >/dev/null 2>&1; then
        printf 'harnesses: extensions and contracts current\n'
      else
        printf 'harnesses: extensions or contracts are stale — an update would refresh them\n'
      fi
    elif ! bash "$SCRIPT_DIR/../seat/harness-extensions-install.sh" --check >/dev/null 2>&1; then
      if bash "$SCRIPT_DIR/../seat/harness-extensions-install.sh" >/dev/null 2>&1; then
        printf 'harnesses: extensions and contracts refreshed on every harness present\n'
      else
        printf 'FAIL — the harness extensions could not be refreshed.\n' >&2
        printf '      run bin/seat/harness-extensions-install.sh and read its rows\n' >&2
        seat_failed=1
      fi
    else
      printf 'harnesses: extensions and contracts current\n'
    fi
  fi
  if [ -x "$SCRIPT_DIR/../seat/harness-contract-install.sh" ]; then
    if ! bash "$SCRIPT_DIR/../seat/harness-contract-install.sh" --check >/dev/null 2>&1; then
      bash "$SCRIPT_DIR/../seat/harness-contract-install.sh" >/dev/null 2>&1 \
        && printf 'harness contracts: relinked to the seat contract\n' \
        || { printf 'FAIL — a harness contract is stale and could not be relinked.\n' >&2; seat_failed=1; }
    fi
  fi
  if [ "${CHECK:-0}" = "1" ]; then
    printf 'rebound: skipped (check mode writes nothing)\n'
  elif "$SCRIPT_DIR/../seat/valknut-load.sh" --all --global >/dev/null 2>&1; then
    printf 'rebound (agents · skills · pi extensions)\n'
  else
    # A seat that could NOT be seated is not updated. This used to WARN and carry
    # on, which is how an extension fix merged but never loaded (2026-09-30).
    printf 'FAIL — valknut-load could not seat the seat; this update is NOT complete.\n' >&2
    printf '      run bin/seat/valknut-load.sh --status, then bin/seat/verify-seat.sh\n' >&2
    seat_failed=1
  fi
fi

# The seating verdict is the update's verdict: a seat that could not be seated is
# not updated, and the caller must be able to SEE that in an exit code.
if [ "${seat_failed:-0}" != 0 ]; then
  printf 'groa-update: SEATING FAILED — the tree moved but the seat did not\n' >&2
  exit 1
fi
# A flag nobody reads is a gate that reports and does not fail — the exact shape of fault
# this file already refuses. Fail the update when the gateway did not answer.
exit "$(( ${seat_failed:-0} || ${GATEWAY_FAILED:-0} ))"

# What CHANGED for you, since your last update. Every change carries a note in
# docs/fixes/; until now nothing printed them, so an updating user saw "updated" and
# nothing else. This is the reader that closes the loop (plan 66 §7).
if [ -x "$ROOT/bin/gates/update-notes.sh" ]; then
  printf '\n'
  bash "$ROOT/bin/gates/update-notes.sh" || true
fi
