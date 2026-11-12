#!/usr/bin/env bash
# hoard-lib.sh — where the operator's HOME lives, and the two roots beneath it.
#
# The law (RULES/04-hoard.md): no private thing — not a name, a key, a plan, a
# schedule, a client, a note — ever sits inside this repo. It lives in ONE place
# the operator OWNS and CHOSE at installation, and every script resolves that
# place HERE, so the answer can never drift between them (Rule 07: configuration
# is never hardcoded; ONE documented default).
#
#   ymir_home_root   the chosen home        ($YMIR_HOME → the recorded choice → the default)
#   hoard_root       the hoard within it    ($YMIR_HOARD → <home>/hodd)
#   hoard_data_dir   this machine's records ($YMIR_DATA_DIR → <hoard>/data)
#   hoard_state_dir  runtime state          ($YMIR_STATE_DIR → <home>/state)
#
# The recorded choice is machine state, not user data: a path under
# `~/.config/ymir/` (the same place `engram-python` and `accounts.json` live), so
# a packaged install can be told where the home is without the home having to sit
# in the package. The tree is code; the home is the operator's.
#
# Source-safe, defines functions only; call `<fn> <result-var>`.
set -u

# Where a machine records its choices (never in the repo, never in the home).
YMIR_CONFIG_DIR="${YMIR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ymir}"
YMIR_HOME_DEFAULT="${YMIR_HOME_DEFAULT:-$HOME/Documents/ymirhome}"

ymir_home_record() {  # <result-var> — the home recorded at installation, or empty
  local result_var=${1-} f="$YMIR_CONFIG_DIR/home"
  [ -n "$result_var" ] || return 2
  if [ -r "$f" ]; then
    # Only the line ending is stripped. `tr -d '[:space:]'` deleted EVERY space,
    # so a home under a profiled Windows path ("C:/Users/Agent Seb/ymirhome")
    # came back as "…/AgentSeb/ymirhome" — a directory that cannot exist, read
    # by every unit, script and door that resolves the home (2026-11-12).
    printf -v "$result_var" '%s' "$(head -n1 "$f" 2>/dev/null | tr -d '\r\n')"
  else
    printf -v "$result_var" '%s' ""
  fi
}

ymir_home_root() {  # <result-var> — the operator's home: env → recorded → default
  local result_var=${1-} rec=""
  [ -n "$result_var" ] || return 2
  if [ -n "${YMIR_HOME:-}" ]; then
    printf -v "$result_var" '%s' "$YMIR_HOME"; return 0
  fi
  ymir_home_record rec
  printf -v "$result_var" '%s' "${rec:-$YMIR_HOME_DEFAULT}"
}

ymir_home_record_set() {  # <path> — record the operator's choice (machine state)
  local home=${1-}
  [ -n "$home" ] || return 2
  mkdir -p "$YMIR_CONFIG_DIR" 2>/dev/null || return 1
  printf '%s\n' "$home" >"$YMIR_CONFIG_DIR/home" || return 1
}

hoard_root() {  # <result-var> — the hoard inside the home (may not exist yet)
  local result_var=${1-} home
  [ -n "$result_var" ] || return 2
  if [ -n "${YMIR_HOARD:-}" ]; then
    printf -v "$result_var" '%s' "$YMIR_HOARD"; return 0
  fi
  ymir_home_root home
  printf -v "$result_var" '%s' "$home/hodd"
}

hoard_env() {  # <result-var> — the platform env file inside the hoard
  local result_var=${1-} root
  [ -n "$result_var" ] || return 2
  hoard_root root
  printf -v "$result_var" '%s' "$root/secrets/platform.env"
}

# This machine's own records (operator, fleet, the host profile) and the runtime
# state (pids, logs, locks). Both live in the HOME — never in the code tree: a
# packaged install treats its tree as read-only and the next upgrade replaces it,
# so state written there is state lost. One documented default each; an env
# override wins, so a single machine can point a root elsewhere without a fork.
hoard_data_dir() {  # <result-var> — where this machine's records live
  local result_var=${1-} root
  [ -n "$result_var" ] || return 2
  hoard_root root
  printf -v "$result_var" '%s' "${YMIR_DATA_DIR:-$root/data}"
}

hoard_state_dir() {  # <result-var> — runtime state: ephemeral, outside the tree
  local result_var=${1-} home
  [ -n "$result_var" ] || return 2
  ymir_home_root home
  printf -v "$result_var" '%s' "${YMIR_STATE_DIR:-$home/state}"
}

# The operator's SETTINGS — the agent set, cron, the local env file with its
# credentials. Settings are the operator's, not the package's: a packaged tree is
# replaced on upgrade, and a credential must never sit in a tree that ships.
hoard_settings_dir() {  # <result-var> — the settings dir inside the home
  local result_var=${1-} home
  [ -n "$result_var" ] || return 2
  ymir_home_root home
  printf -v "$result_var" '%s' "${YMIR_SETTINGS_DIR:-$home/config}"
}

hoard_local_env() {  # <result-var> — the operator's env file (secrets, ports)
  local result_var=${1-} home
  [ -n "$result_var" ] || return 2
  ymir_home_root home
  printf -v "$result_var" '%s' "${YMIR_ENV_FILE:-$home/.env.local}"
}

hoard_memory_store() {  # <result-var> — Kaia's engram store, ALWAYS in the hoard
  # The well is one memory and it lives in the hoard (hodd/memory) — never in
  # the tree, never in a migrated copy. Everything that reads the store resolves
  # through here so no script can point the well at a duplicate (Rule 04/07).
  local result_var=${1-} home
  [ -n "$result_var" ] || return 2
  ymir_home_root home
  printf -v "$result_var" '%s' "$home/hodd/memory/kaia.engram"
}
