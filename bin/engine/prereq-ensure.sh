#!/usr/bin/env bash
# prereq-ensure.sh — self-healing prerequisite engine for Ymir.
#
# The installer should not leave the operator to fix prerequisites by hand.
# This helper provisions what it can, in USER SPACE (no sudo), and reports
# clearly what it could not do. Every action is idempotent.
#
# Engine:
#   bun       — installs via the official installer, then ~/.bun/bin on PATH
#   uv        — installs via the official installer (used for Python provisioning)
#   pip       — reported with a per-manager hint (needs a system package)
#   mcp<2     — pip-installed into the user site
#   pythonX.Y — fetched by uv in user space when a package needs another Python
#
# Usage:
#   bin/engine/prereq-ensure.sh bun | uv | mcp | python <X.Y> | all
#   bin/engine/prereq-ensure.sh --persist-path   # make ~/.bun/bin reached by a NON-INTERACTIVE shell
#   bin/engine/prereq-ensure.sh status
#   bin/engine/prereq-ensure.sh --version
#
# Output: Galdr TOON. Exit 0 when the target is present afterwards, 1 otherwise.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fleet/ymir-platform.sh
[ -r "$SCRIPT_DIR/../fleet/ymir-platform.sh" ] && . "$SCRIPT_DIR/../fleet/ymir-platform.sh"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
BUN_HOME="${BUN_INSTALL:-$HOME/.bun}"

add_path() { case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH" ;; esac; }
have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf 'prereq[1]{name,state,detail}:\n  "%s","%s","%s"\n' "$1" "$2" "$3"; }

# ── the PATH a LATER shell sees ──────────────────────────────────────────────
#
# WHY (2026-11-03, found on a clean Windows/WSL2 seat this house claims to support):
# `ensure_bun` installs to `~/.bun/bin`, and the installer then exports it into ITS OWN
# PATH and into nobody else's. A non-interactive shell — a validator, a systemd unit, the
# next `bin/engine/ymir-validate.sh` — therefore reports `missing: bun` on a host that has
# bun, and the operator is told to fix a thing that is not broken. That is the failure
# RULES/25 names: PROBE, NEVER ASSUME, and never let a claim about a machine depend on
# which shell happened to run it.
#
# So the directories this engine installs into are written down ONCE, in the profile the
# operator's shell actually reads: `~/.profile` for sh/bash (every Linux, and WSL2) and
# `~/.zprofile` for zsh (the macOS default). Both are probed, never assumed. A systemd unit
# does NOT read a profile, so every unit carries its own `Environment=` and
# `prereq-ensure.sh resolve <tool>` answers a caller by absolute path.
PATH_MARK="# >>> ymir prerequisites >>>"
PATH_MARK_END="# <<< ymir prerequisites <<<"

# Write (or replace in place) the marked block in one file. Never duplicates a block, and
# never rewrites a line the operator wrote.
write_block() {  # <file> <dirs, newline-separated>
  local file="$1" dirs="$2" block
  block="$PATH_MARK
$(printf '%s' "$dirs" | sed 's|^\(.*\)$|case ":$PATH:" in *":\1:"*) ;; *) export PATH="\1:$PATH" ;; esac|')
$PATH_MARK_END"
  if [ -f "$file" ] && grep -qF "$PATH_MARK" "$file" 2>/dev/null; then
    python3 - "$file" "$PATH_MARK" "$PATH_MARK_END" "$block" <<'PY' 2>/dev/null || return 1
import sys
path, start, end, block = sys.argv[1:5]
text = open(path, encoding='utf-8', errors='surrogateescape').read()
i, j = text.find(start), text.find(end)
if i == -1 or j == -1 or j < i:
    sys.exit(1)
open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text[:i] + block + text[j + len(end):])
PY
    return 0
  fi
  [ -w "$(dirname "$file")" ] || return 1
  { [ -s "$file" ] && printf '\n'; printf '%s\n' "$block"; } >>"$file" 2>/dev/null
}

persist_path() {
  local dirs="" d list=""
  for d in "$BUN_HOME/bin" "$HOME/.local/bin"; do
    [ -d "$d" ] || continue
    add_path "$d"                     # this run
    case "$dirs" in *"$d"$'\n'*) : ;; *) dirs="$dirs$d"$'\n' ; list="$list $d" ;; esac
  done
  [ -n "$dirs" ] || { say path present "every prerequisite directory is already on PATH"; return 0; }

  # WHICH PROFILE — the operator's own shell, probed. A machine that never runs zsh is never
  # given a .zprofile, and a home that already keeps one is honoured even if $SHELL says bash.
  local sh="${SHELL##*/}" candidates=""
  case "$sh" in
    zsh) candidates="$HOME/.zprofile" ;;
    *)   candidates="$HOME/.profile" ;;
  esac
  [ -f "$HOME/.zprofile" ] && case "$candidates" in *".zprofile"*) : ;; *) candidates="$candidates $HOME/.zprofile" ;; esac

  # ALREADY WRITTEN? A second run of the same update must change nothing and say so. The
  # PRIMARY profile is the one this operator's shell reads: the block must be there, with
  # every directory — a block in some other shell's file is not a pass.
  local f primary have_all=1
  primary="${candidates%% *}"
  if [ -f "$primary" ] && grep -qF "$PATH_MARK" "$primary" 2>/dev/null; then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      grep -qF "$d" "$primary" 2>/dev/null || have_all=0
    done <<EOF2
$dirs
EOF2
  else
    have_all=0
  fi
  if [ "$have_all" = 1 ]; then
    say path present "${list# } already written for a login shell"
    return 0
  fi

  local shells=""
  for f in $candidates; do
    write_block "$f" "$dirs" && shells="$shells $(basename "$f")"
  done
  if [ -n "$shells" ]; then
    say path persisted "${list# } written for a login shell:$shells"
  else
    say path skipped "the directories belong on PATH, but no shell profile here is writable"
  fi
  return 0
}

# Android/Termux: the well engine's sqlite-vec dependency publishes wheels for
# linux/macos/windows but NONE for aarch64-android, and there is no sdist. A phone
# is a `hand` — it reaches the heart's well as a door — so the local engine is an
# explicit opt-in (`YMIR_ENGRAM_LOCAL=1`) rather than a step that fails at install.
is_termux() { [ -n "${TERMUX_VERSION:-}" ] || { [ -n "${PREFIX:-}" ] && [ "${PREFIX#*com.termux}" != "$PREFIX" ]; }; }

# ── the memory engine (engram) ───────────────────────────────────────────────
# engram needs Python >=3.12,<3.14. A modern distro may ship something newer
# (this box: 3.14), so the engine is installed into a COMPATIBLE interpreter and
# that interpreter is recorded for the bridge to reuse. uv can supply one.
ENGRAM_PY_FILE="${YMIR_ENGRAM_PY:-$HOME/.config/ymir/engram-python}"

engram_python() {  # echo an interpreter that can (or could) run engram
  local p
  for p in "${YMIR_ENGRAM_PYTHON:-}" python3.12 python3.13; do
    [ -n "$p" ] || continue
    command -v "$p" >/dev/null 2>&1 && { printf '%s' "$p"; return 0; }
  done
  if command -v uv >/dev/null 2>&1; then
    p="$(uv python find 3.12 2>/dev/null || uv python find 3.13 2>/dev/null || true)"
    [ -n "$p" ] && { printf '%s' "$p"; return 0; }
  fi
  printf 'python3'
}

# engdbram (whose import name is `engram`) requires Python >= 3.11.
#
# NOTE THE NAME, because reading the wrong one cost a wrong diagnosis: the PyPI
# project *called* `engram` is a different package entirely (a differentiable
# rendering stack built on mitsuba/drjit) and its `<3.14,>=3.12` ceiling is NOT our
# constraint. The engine's own floor is 3.11, so a distro's 3.13 or 3.14 is fine.
engram_version_ok() {  # <python> -> 0 when >= 3.11
  "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)' >/dev/null 2>&1
}
engram_v() { "$1" -V 2>&1 | head -1; }

# A Python without pip can install nothing, and it says so only into /dev/null — which
# is how "no pip" was reported as a version problem. ensurepip is stdlib, so it is the
# first remedy; where a distro disables it (Debian ships it disabled) this returns
# non-zero and the caller says exactly that.
engram_ensure_pip() {  # <python> -> 0 when `-m pip --version` answers
  local py="$1"
  "$py" -m pip --version >/dev/null 2>&1 && return 0
  "$py" -m ensurepip --upgrade >/dev/null 2>&1 || "$py" -m ensurepip >/dev/null 2>&1 || true
  "$py" -m pip --version >/dev/null 2>&1
}

ensure_engram() {
  local py why=""; py="$(engram_python)"
  if "$py" -c 'import engram' >/dev/null 2>&1; then
    mkdir -p "$(dirname "$ENGRAM_PY_FILE")" 2>/dev/null
    printf '%s\n' "$py" >"$ENGRAM_PY_FILE" 2>/dev/null
    say engram present "importable under $(engram_v "$py")"
    return 0
  fi

  # Android/Termux has no sqlite-vec wheel and no sdist. A `hand` reaches the
  # heart's well over the gateway; only an explicit opt-in builds it from source.
  if is_termux && [ "${YMIR_ENGRAM_LOCAL:-0}" != 1 ]; then
    say engram skipped "Android/Termux — the well is the heart's door here; set YMIR_ENGRAM_LOCAL=1 to build sqlite-vec from source (docs/installations/termux.md)"
    return 1
  fi

  # Name the real cause, not a guess: an old interpreter, or one that cannot install.
  if ! engram_version_ok "$py"; then
    why="$(engram_v "$py") is older than engdbram needs (>=3.11)"
  elif ! engram_ensure_pip "$py"; then
    why="no pip for $(engram_v "$py"), and ensurepip could not supply one"
  fi

  # Either way, uv can supply an interpreter that both is new enough and can install.
  if [ -n "$why" ] && command -v uv >/dev/null 2>&1 && uv python install 3.12 >/dev/null 2>&1; then
    local cand; cand="$(uv python find 3.12 2>/dev/null || true)"
    if [ -n "$cand" ] && engram_version_ok "$cand" && engram_ensure_pip "$cand"; then
      py="$cand"; why=""
    fi
  fi

  if [ -z "$why" ]; then
    if "$py" -m pip install --user --break-system-packages -q engdbram >/dev/null 2>&1 \
       && "$py" -c 'import engram' >/dev/null 2>&1; then
      mkdir -p "$(dirname "$ENGRAM_PY_FILE")" 2>/dev/null
      printf '%s\n' "$(command -v "$py" 2>/dev/null || printf '%s' "$py")" >"$ENGRAM_PY_FILE" 2>/dev/null
      say engram installed "$(engram_v "$py")"
      return 0
    fi
    why="pip could not install engdbram under $(engram_v "$py")"
  fi

  say engram absent "$why — help: bin/engine/prereq-ensure.sh uv, then bin/engine/prereq-ensure.sh engram"
  return 1
}

ensure_pyyaml() {
  # The naming law's registry reads YAML. It is not part of the stdlib, so a seat
  # without it cannot build the registry and therefore cannot be NAMED — the door
  # answered a traceback instead of a remedy until 2026-10-24.
  local py; py="$(engram_python 2>/dev/null || printf 'python3')"
  if "$py" -c 'import yaml' >/dev/null 2>&1; then
    say pyyaml present "$(engram_v "$py" 2>/dev/null || printf '%s' "$py")"
    return 0
  fi
  engram_ensure_pip "$py" >/dev/null 2>&1 || true
  if "$py" -m pip install --user --break-system-packages -q pyyaml >/dev/null 2>&1 \
     && "$py" -c 'import yaml' >/dev/null 2>&1; then
    say pyyaml installed "$(engram_v "$py" 2>/dev/null || printf '%s' "$py")"
    return 0
  fi
  say pyyaml absent "pip could not install pyyaml under $(engram_v "$py" 2>/dev/null || printf '%s' "$py") — help: python3 -m pip install --user pyyaml"
  return 1
}

ensure_bun() {
  add_path "$BUN_HOME/bin"
  if have bun; then say bun present "$(bun --version 2>/dev/null)"; return 0; fi
  if curl -fsSL https://bun.sh/install 2>/dev/null | bash >/dev/null 2>&1; then
    add_path "$BUN_HOME/bin"
    if have bun; then say bun installed "$(bun --version 2>/dev/null)"; return 0; fi
  fi
  say bun absent "install manually: https://bun.sh (or your package manager)"
  return 1
}

ensure_uv() {
  add_path "$HOME/.local/bin"
  if have uv; then say uv present "$(uv --version 2>/dev/null | awk '{print $2}')"; return 0; fi
  if curl -fsSL https://astral.sh/uv/install.sh 2>/dev/null | sh >/dev/null 2>&1; then
    add_path "$HOME/.local/bin"
    if have uv; then say uv installed "$(uv --version 2>/dev/null | awk '{print $2}')"; return 0; fi
  fi
  say uv absent "install manually: https://astral.sh/uv"
  return 1
}

# Fetch a Python interpreter in user space via uv. Prints its path on success.
ensure_python() {
  local want="$1"
  if have "python$want"; then
    say "python$want" present "$(command -v "python$want")"
    command -v "python$want"
    return 0
  fi
  ensure_uv >/dev/null 2>&1 || true
  if have uv; then
    if uv python install "$want" >/dev/null 2>&1; then
      local p
      p="$(uv python find "$want" 2>/dev/null || true)"
      if [ -n "$p" ]; then say "python$want" installed "$p"; printf '%s\n' "$p"; return 0; fi
    fi
  fi
  say "python$want" absent "uv could not fetch it (offline?)"
  return 1
}

ensure_mcp() {
  if python3 -c "from mcp.server.fastmcp import FastMCP" >/dev/null 2>&1; then
    say "mcp<2" present "importable"
    return 0
  fi
  if python3 -m pip --version >/dev/null 2>&1; then
    if python3 -m pip install --user --break-system-packages -q 'mcp<2' >/dev/null 2>&1 \
       && python3 -c "from mcp.server.fastmcp import FastMCP" >/dev/null 2>&1; then
      say "mcp<2" installed "user site"
      return 0
    fi
  fi
  say "mcp<2" absent "needs pip (a system package on this distro)"
  return 1
}

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

case "$1" in
  --persist-path) persist_path ;;
  bun)    ensure_bun ;;
  uv)     ensure_uv ;;
  mcp)    ensure_mcp ;;
  engram) ensure_engram ;;
  pyyaml) ensure_pyyaml ;;
  python) ensure_python "${2:?usage: prereq-ensure.sh python <X.Y>}" ;;
  resolve)
    # Ask the MACHINE where a tool is, before any caller decides it is missing
    # (RULES/25 PROBE, NEVER ASSUME). Printed as a path; exit 1 when absent.
    case "${2-}" in
      bun) have bun && { command -v bun; exit 0; }
           for _c in "$BUN_HOME/bin/bun" "$HOME/.local/bin/bun" /opt/homebrew/bin/bun /usr/local/bin/bun; do
             [ -x "$_c" ] && { printf '%s\n' "$_c"; exit 0; }
           done
           exit 1 ;;
      *) printf 'error: unknown tool %s\nhelp: prereq-ensure.sh resolve bun\n' "${2-}" >&2; exit 2 ;;
    esac ;;
  status)
    engine="$(ymir_container_engine_name 2>/dev/null || true)"
    printf 'prereq[6]{name,state,detail}:\n'
    for c in git python3 bun gh uv; do
      if have "$c"; then printf '  "%s","present","%s"\n' "$c" "$(command -v "$c")"
      else printf '  "%s","absent","-"\n' "$c"; fi
    done
    # Docker or Podman — the one this host actually has.
    if [ -n "$engine" ]; then printf '  "%s","present","%s"\n' "$engine" "$(command -v "$engine")"
    else printf '  "docker/podman","absent","-"\n'; fi
    ;;
  all)
    rc=0
    ensure_bun || rc=1
    ensure_uv  || rc=1
    ensure_mcp || rc=1
    exit $rc ;;
  *) printf 'error: unknown target %s\nhelp: bin/engine/prereq-ensure.sh [bun|uv|mcp|engram|python X.Y|status|all]\n' "$1" >&2; exit 2 ;;
esac
