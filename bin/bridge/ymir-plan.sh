#!/usr/bin/env bash
# ymir-plan.sh — THE INSTALL PLAN. Probe this machine, print what would change,
# change nothing.
#
# The consent a real install asks for used to be a hardcoded paragraph, and a
# paragraph cannot know the host: it named an Omarchy version on a Mac, promised
# a workspace tree that already stood, and never mentioned that no application
# had been installed at all. This is the replacement: a plan COMPUTED from the
# same host the install will act on, one row per step, each row carrying its
# state and the reason for it.
#
#   DO        a change will be made
#   SKIP      already satisfied — nothing to do
#   DO ·      (with a note) the step is available but conditional
#   BLOCKED   cannot run; the reason names what is missing
#   CONSENT   needs the operator's word before it may run
#   INFO      a fact about this host, discovered — no change implied
#
# Usage:
#   bin/bridge/ymir-plan.sh                 # the plan (TOON)
#   bin/bridge/ymir-plan.sh --json          # the same, as JSON, for automation
#   bin/bridge/ymir-plan.sh --phase 5       # one phase
#   bin/bridge/ymir-plan.sh --blocked       # only what cannot proceed, and why
#
# Exit: 0 the plan was printed (a BLOCKED row is a fact, not a failure), 1 error,
# 2 usage.
set -u

# --- portability shim: bin/fleet/ymir-platform.sh --------------------------------
if [ -z "${YMIR_PLATFORM_LOADED:-}" ]; then
  _ymir_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  for _ymir_c in "${_ymir_dir}/../fleet/ymir-platform.sh" "$(CDPATH='' cd "$_ymir_dir" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)/bin/fleet/ymir-platform.sh"; do
    [ -r "$_ymir_c" ] && { . "$_ymir_c"; YMIR_PLATFORM_LOADED=1; break; }
  done
  unset _ymir_dir _ymir_c
fi

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

# --- where an app lives: bin/desktop/app-lib.sh --------------------------
# apps/<surface> in a clone, node_modules/@zerwiz/<package> in an npm install —
# both shapes, ONE resolver (Rule 07). Seated HERE, at the top, because the plan
# resolves apps both in app_row and in the shell check below, and a resolver that
# arrives after its callers is the same as no resolver at all (2026-10-12).
if [ -z "${YMIR_APP_LIB_LOADED:-}" ]; then
  for _app_c in "${SCRIPT_DIR}/../desktop/app-lib.sh" "$ROOT/bin/desktop/app-lib.sh"; do
    [ -r "$_app_c" ] && { . "$_app_c"; YMIR_APP_LIB_LOADED=1; break; }
  done
  unset _app_c
fi
# Whether the home was named explicitly matters: a home that was chosen is not
# the same as one we defaulted to, and the plan says which.
YMIR_HOME_WAS_SET=0; [ -n "${YMIR_HOME:-}" ] && YMIR_HOME_WAS_SET=1
# shellcheck source=bin/vault/hoard-lib.sh
. "$SCRIPT_DIR/../vault/hoard-lib.sh"
ymir_home_root YMIR_HOME
hoard_root HOARD

JSON=0; COLOUR=0; ONLY_PHASE=""; ONLY_BLOCKED=0
case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --colour|--color) COLOUR=1; shift ;;
    --phase) ONLY_PHASE="${2-}"; shift 2 ;;
    --blocked) ONLY_BLOCKED=1; shift ;;
    --role) export YMIR_ROLE="${2-}"; shift 2 ;;
    --role=*) export YMIR_ROLE="${1#--role=}"; shift ;;
    *) printf 'error: unknown flag %s\nhelp: bin/bridge/ymir-plan.sh [--json|--colour] [--phase N] [--blocked] [--role heart|forge|dev|hand]\n' "$1" >&2; exit 2 ;;
  esac
done

declare -a P_N P_NAME P_STEP P_STATE P_WHY
emit() { P_N+=("$1"); P_NAME+=("$2"); P_STEP+=("$3"); P_STATE+=("$4"); P_WHY+=("$5"); }

have() { command -v "$1" >/dev/null 2>&1; }
port_up() {  # <port>
  if have curl; then curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$1/" 2>/dev/null && return 0; fi
  if have ss; then ss -ltn 2>/dev/null | grep -q ":$1 " && return 0; fi
  return 1
}
# Where an app lives is NOT decided here. bin/desktop/app-lib.sh owns that
# question (apps/<surface> in a clone, node_modules/@zerwiz/<package> in an install),
# and the loader at the top of this file seats it before any row is emitted. A local
# second copy of the resolver is exactly how the two shapes drifted apart: this file
# kept the OLD signature and the canonical lib kept the new one, so sourcing the lib
# here would have silently blanked every app path (2026-10-12).

# ── phase 0 · resolve — where this runs, and against what ────────────────────
resolve_phase() {
  local os="" desk="terminal"
  os="$(ymir_os 2>/dev/null || printf unknown)"
  [ -n "${WAYLAND_DISPLAY:-}" ] && desk="wayland"
  [ -n "${DISPLAY:-}" ] && desk="x11"
  [ -d /usr/share/omarchy ] && desk="$desk · omarchy first-class"
  case "$os" in
    wsl) desk="$desk · wsl2" ;;
    msys) desk="$desk · msys (best-effort)" ;;
  esac
  emit 0 resolve os INFO "$os · $desk"

  local eng=""
  if command -v ymir_container_engine >/dev/null 2>&1; then eng="$(ymir_container_engine_name 2>/dev/null || true)"; fi
  [ -z "$eng" ] && have docker && eng=docker
  [ -z "$eng" ] && have podman && eng=podman
  if [ -n "$eng" ]; then emit 0 resolve engine INFO "$eng"
  else emit 0 resolve engine BLOCKED "no docker or podman on PATH — the Utgard image cannot be built"; fi

  case "$ROOT" in
    */node_modules/*) emit 0 resolve code INFO "$ROOT — a package install (read-only at runtime)" ;;
    *) emit 0 resolve code INFO "$ROOT — a source checkout" ;;
  esac

  case "$HOARD" in
    "$ROOT"/*) emit 0 resolve home BLOCKED "the home ($HOARD) sits inside the code tree — private data would live in the package" ;;
    *) emit 0 resolve home INFO "$HOARD (the home = $YMIR_HOME)" ;;
  esac

  # The home is the OPERATOR's to choose. Until they have, it is only a default,
  # and the install will ask — so the plan says so rather than pretending.
  local rec=""
  ymir_home_record rec
  if [ -n "$rec" ]; then
    emit 0 resolve chosen SKIP "the home was chosen at installation: $rec"
  elif [ "$YMIR_HOME_WAS_SET" = 1 ]; then
    emit 0 resolve chosen SKIP "the home is set by \$YMIR_HOME: $YMIR_HOME"
  else
    emit 0 resolve chosen CONSENT "no home chosen yet — the install asks, then records it (default $YMIR_HOME_DEFAULT)"
  fi

  # What this machine IS (plan 51 P1). The install resolves the role BEFORE its
  # step chain and installs only that role's components, so the plan names the
  # role and where it came from — the preview can no longer read as one shape
  # everywhere on every host.
  local rline="" rroles="" rsrc=""
  if [ -x "$ROOT/bin/skuld/role.sh" ]; then
    rline="$(bash "$ROOT/bin/skuld/role.sh" resolve --why 2>/dev/null | head -1)"
    rroles="${rline%%$'\t'*}"; rsrc="${rline##*$'\t'}"
  fi
  if [ -n "$rroles" ]; then
    emit 0 resolve role INFO "$rroles (source: ${rsrc:-none}) — only this role's components install"
  else
    emit 0 resolve role CONSENT "no role in the registry for this host — the install asks (or pass --role heart|forge|dev|hand)"
  fi
}

# ── phase 1 · code — the tree itself, and its purity ────────────────────────
code_phase() {
  local n=0
  [ -x "$ROOT/bin/engine/ymir-install.sh" ] && n=$(find "$ROOT/bin" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l)
  if [ "$n" -gt 0 ] && [ -d "$ROOT/.agents/skills" ] && [ -d "$ROOT/RULES" ]; then
    emit 1 code integrity SKIP "tree intact — $n scripts, .agents/skills, RULES/"
  else
    emit 1 code integrity BLOCKED "bin/, .agents/skills or RULES/ is missing — reinstall the package or re-clone"
  fi

  # The law this row enforces: the package is the code that RUNS the programs.
  # Everything the operator owns — their records, their state, their settings,
  # their credentials — lives in the home they chose. A packaged install replaces
  # its tree on upgrade, so anything of theirs kept here is kept at its peril.
  # A settings file GIT TRACKS is not theirs: that is the distro's shipped
  # default, and it stays where the code ships it.
  local leaked="" f n
  n="$(ls -A "$ROOT/data" 2>/dev/null | grep -vc '^\.gitkeep$' || true)"
  [ -d "$ROOT/data" ] && [ "${n:-0}" -gt 0 ] && leaked="$leaked data/"
  n="$(ls -A "$ROOT/state" 2>/dev/null | grep -vc '^\.gitkeep$' || true)"
  [ -d "$ROOT/state" ] && [ "${n:-0}" -gt 0 ] && leaked="$leaked state/"
  for f in config/agents.yaml config/cron.yaml config/tailscale-sync.yaml config/wedge-alarm .env.local; do
    [ -e "$ROOT/$f" ] || continue
    # `config` is a symlink into .agents/config, and git tracks the REAL path —
    # ask it about the name the index holds, not the link the tree shows.
    local ask="$f"
    case "$f" in config/*) [ -L "$ROOT/config" ] && ask=".agents/config/${f#config/}" ;; esac
    if command -v git >/dev/null 2>&1 && git -C "$ROOT" ls-files --error-unmatch "$ask" >/dev/null 2>&1; then
      continue    # the distro ships this one — code, not the operator's own
    fi
    leaked="$leaked $f"
  done
  if [ -n "$leaked" ]; then
    emit 1 code purity DO "the operator's own things sit in the code tree ($leaked) — they belong in $YMIR_HOME, or the next upgrade will erase them"
  else
    emit 1 code purity SKIP "nothing of the operator's is written into the code tree"
  fi
}

# ── phase 2 · home — the operator's world, outside the tree ─────────────────
home_phase() {
  if [ -d "$HOARD/identity" ] && [ -d "$HOARD/secrets" ]; then
    emit 2 home hoard SKIP "hodd/{identity,secrets,memory} present"
  else
    emit 2 home hoard DO "create hodd/{identity,secrets,docs,tenants,memory} — all private data lives here"
  fi
  if [ -d "$YMIR_HOME/workspaces" ]; then
    emit 2 home workspaces SKIP "$YMIR_HOME/workspaces present"
  else
    emit 2 home workspaces DO "create workspaces/{work,personal} and the registries"
  fi
  # Settings are the operator's: they live in the home, never in the package.
  local settings; hoard_settings_dir settings
  if [ -e "$settings/agents.yaml" ]; then
    emit 2 home agents-config SKIP "the agent set is seeded ($settings/agents.yaml)"
  else
    emit 2 home agents-config DO "seed the private agent set into $settings/agents.yaml (harness + model per agent)"
  fi
}

# ── phase 3 · runtimes — every one proven by a probe, never assumed ─────────
runtimes_phase() {
  local missing=""
  for c in git python3; do have "$c" || missing="$missing $c"; done
  if [ -n "$missing" ]; then
    emit 3 runtimes system BLOCKED "missing$missing — a system package (apt/dnf/brew), not user space"
  else
    emit 3 runtimes system SKIP "git and python3 present"
  fi

  local user=""
  for c in bun uv; do have "$c" || user="$user $c"; done
  if [ -n "$user" ]; then emit 3 runtimes userspace DO "install in user space (no sudo):$user"
  else emit 3 runtimes userspace SKIP "bun and uv present"; fi

  if have mcp; then emit 3 runtimes mcp SKIP "mcp<2> present"; else emit 3 runtimes mcp DO "install mcp<2> via pip"; fi
  if have pi; then emit 3 runtimes pi SKIP "the Pi harness present"; else emit 3 runtimes pi DO "install the Pi harness"; fi
  if have hermes; then emit 3 runtimes hermes SKIP "the Hermes worker runtime present"; else emit 3 runtimes hermes DO "install the Hermes worker runtime"; fi

  if have herdr; then emit 3 runtimes backend SKIP "herdr — Þjazi (the preferred terminal backend)"
  elif have tmux; then emit 3 runtimes backend SKIP "tmux — the accepted reference backend"
  else emit 3 runtimes backend DO "install herdr (Þjazi), else tmux — without a backend no Eindri can be seated"; fi
}

# ── phase 4 · engines — the OSS anvils Ymir wraps ───────────────────────────
engine_row() {  # <bin> <label>
  if have "$1"; then emit 4 engines "$1" SKIP "$2 present"
  else emit 4 engines "$1" DO "install $2 ($1)"; fi
}
engines_phase() {
  engine_row treehouse "Yggdrasil (the worktree engine)"
  engine_row no-mistakes "the clean-PR gate (Mjollnir · Glitnir)"
  if have sandcastle; then emit 4 engines sandcastle SKIP "Utgard present"
  else emit 4 engines sandcastle DO "install sandcastle (Utgard) if available"; fi

  # The local model (plan 57): adopt the engine, fit a model to THIS hardware.
  if [ -x "$ROOT/bin/model/llama-ensure.sh" ]; then
    if "$ROOT/bin/model/llama-ensure.sh" status >/dev/null 2>&1; then
      emit 4 engines local-model SKIP "a CUDA llama-server stands (adopted, not rebuilt)"
    elif "$ROOT/bin/model/llama-ensure.sh" status 2>&1 | grep -q 'CPU-ONLY'; then
      emit 4 engines local-model DO "a CPU-only llama-server stands — install a CUDA build (a CPU bench is ~10x slow)"
    else
      emit 4 engines local-model DO "no llama-server — build llama.cpp with CUDA (GGML_CUDA=ON)"
    fi
  else
    emit 4 engines local-model BLOCKED "bin/model/llama-ensure.sh is absent"
  fi

  # The voice engines: whisper (STT) + piper (TTS). Adopt-first, in the voice shelf.
  if [ -x "$ROOT/bin/voice/voice-ensure.sh" ]; then
    if "$ROOT/bin/voice/voice-ensure.sh" status >/dev/null 2>&1; then
      emit 4 engines voice SKIP "whisper (STT) + piper (TTS) present (adopted)"
    else
      emit 4 engines voice DO "install whisper.cpp (STT) + piper (TTS) and their models"
    fi
  fi

  if have docker || have podman; then
    local img
    if have docker && docker image inspect utgard-runner:latest >/dev/null 2>&1; then
      emit 4 engines utgard-image SKIP "utgard-runner:latest present"
    elif have podman && podman image exists utgard-runner:latest >/dev/null 2>&1; then
      emit 4 engines utgard-image SKIP "utgard-runner:latest present (podman)"
    else
      emit 4 engines utgard-image DO "build the sandbox image utgard-runner:latest"
    fi
  else
    emit 4 engines utgard-image BLOCKED "no container engine — the sandbox cannot be built"
  fi
}

# ── phase 5 · apps — the surfaces the operator actually sees ────────────────
# Four surfaces, one shape each: web build required, Electron shell gated.
# The apps are their own packages (@zerwiz/<app>) — the distro depends on them.
app_row() {  # <surface> <about> [<package>]
  local name="$1" about="$2" pkg="${3:-$1}" dir
  if app_dir "$name" dir; then
    if [ -d "$dir/dist" ] || [ -d "$dir/out" ]; then
      emit 5 apps "$name" SKIP "$about — installed, and its build shipped with it"
    else
      emit 5 apps "$name" DO "$about — installed from source; the web build is still to make"
    fi
  elif grep -q "\"@zerwiz/$pkg\"" "$ROOT/package.json" 2>/dev/null; then
    # Declared as a dependency of the distro but not present: the package exists,
    # the tree simply has not fetched it. That is a DO, not a dead end.
    emit 5 apps "$name" DO "$about — declared as a dependency but not fetched (npm i -g @zerwiz/ymir fetches it)"
  else
    emit 5 apps "$name" BLOCKED "$about — no apps/$name, no @zerwiz/$pkg package, and the distro does not depend on it"
  fi
}
apps_phase() {
  app_row hlidskjalf "the control plane (the high seat), served on :3888"
  app_row odrerir "the live hall (chat + council)"
  app_row sessrumnir "the seat-hall desktop"
  app_row smidja "the smithy and its visualizer (:8437)" smidja-factory

  # A shell is ready only when its runtime VERIFIES: npm gates install scripts,
  # and a skipped Electron postinstall leaves a partial runtime that still builds
  # the web app and still reports success (bin/desktop/electron-lib.sh).
  if [ -z "${YMIR_ELECTRON_LIB_LOADED:-}" ]; then
    for c in "$SCRIPT_DIR/../desktop/electron-lib.sh"; do [ -r "$c" ] && { . "$c"; YMIR_ELECTRON_LIB_LOADED=1; }; done
  fi
  local shells=0 partial="" missing=0 d
  for d in hlidskjalf odrerir sessrumnir; do
    dir=""; app_dir "$d" dir 2>/dev/null || true
    if [ -z "$dir" ]; then missing=$((missing+1)); continue; fi
    case "$(electron_runtime_state "$dir" "$ROOT" "$(app_pkg "$d")" 2>/dev/null || true)" in
      ok) shells=$((shells+1)) ;;
      partial) partial="$partial $d" ;;
      *) missing=$((missing+1)) ;;
    esac
  done
  if [ "$shells" -ge 3 ]; then
    emit 5 apps electron SKIP "the three desktop shells' runtimes verify"
  elif [ -n "$partial" ]; then
    emit 5 apps electron DO "the runtime is PARTIAL for:$partial — npm skipped the Electron postinstall; the web surfaces stand, the shells will not launch"
  elif [ "${YMIR_NO_DESKTOP:-0}" = 1 ]; then
    emit 5 apps electron SKIP "declined (--no-desktop) — the web surfaces stand without the shells"
  else
    emit 5 apps electron CONSENT "build the desktop shells? each pulls a ~100 MB Electron runtime — the web surfaces need none of it"
  fi
}

# ── phase 6 · wire — the way in, and the agent set ──────────────────────────
wire_phase() {
  if ! have codex; then
    emit 6 wire codex-plugin SKIP "Codex is not installed on this host"
  elif ! have node; then
    emit 6 wire codex-plugin BLOCKED "Node.js is required to install the Ymir Codex plugin"
  elif node "$ROOT/bin/seat/codex-plugin-install.mjs" --check >/dev/null 2>&1; then
    emit 6 wire codex-plugin SKIP "Ymir's Codex plugin is installed, enabled and current"
  else
    emit 6 wire codex-plugin DO "register the local Ymir marketplace and install or refresh its Codex tools"
  fi
  local door="none"
  if [ -x "$ROOT/bin/engine/ymir-setup-auth.sh" ]; then
    door="$(bash "$ROOT/bin/engine/ymir-setup-auth.sh" status 2>/dev/null | sed -n '2p' | cut -d, -f1 | tr -d ' "')"
  fi
  if [ -n "$door" ] && [ "$door" != none ]; then
    emit 6 wire auth SKIP "an operator credential is set ($door)"
  else
    emit 6 wire auth CONSENT "no credential — a password or GitHub sign-in; without it the gate has no door"
  fi

  local codes=""
  [ -x "$ROOT/bin/engine/ymir-invite.sh" ] && codes="$(bash "$ROOT/bin/engine/ymir-invite.sh" list 2>/dev/null | grep -c '^  "' || true)"
  if [ "${codes:-0}" -gt 0 ]; then emit 6 wire invite SKIP "a live invite code exists"
  else emit 6 wire invite CONSENT "mint an invite code — how anyone else is let in (registration stays closed without one)"; fi

  # Heimdall — the ssh-key ward: entry by the rune carried on GitHub. The
  # plan row is computed, never recited: a warded seat is a SKIP, a bare one a
  # DO. Never a BLOCKED — a seat can stand without it, it just has no second
  # door.
  if [ -x "$ROOT/bin/host/heimdall-ensure.sh" ] && "$ROOT/bin/host/heimdall-ensure.sh" status >/dev/null 2>&1; then
    emit 6 wire heimdall SKIP "Heimdall guards this seat (GitHub keys, 15-min refresh)"
  else
    emit 6 wire heimdall DO "arm Heimdall — the ward admits GitHub keys into this seat's authorized_keys (one published key, all doors)"
  fi

  if [ -d /usr/share/omarchy ]; then
    emit 6 wire launchers DO "place each app on its own numbered desktop + write the launcher entries"
  else
    emit 6 wire launchers SKIP "not an Omarchy host — the Omarchy layer skips cleanly (Rule 05)"
  fi
}

# ── phase 7 · raise — the services, then what the operator sees ─────────────
raise_phase() {
  local down="" p
  for p in 3888:Hlidskjalf 3889:gate-API 4603:Bifrost 8437:Smidja-visualizer; do
    port_up "${p%%:*}" || down="$down ${p#*:}"
  done
  if [ -n "$down" ]; then emit 7 raise services DO "raise:$down"
  else emit 7 raise services SKIP "every service is listening (SPA · gate API · Bifrost · visualizer)"; fi
  if have hermes; then emit 7 raise well INFO "the memory well (engram) is provisioned by its own step"; fi
  emit 7 raise desktop CONSENT "open the desktop apps so they are seen, not merely installed"
}

# ── phase 8 · verify — what stands, honestly ────────────────────────────────
verify_phase() {
  if [ -x "$SCRIPT_DIR/../engine/ymir-validate.sh" ]; then
    emit 8 verify validate DO "observe the result: ports, stores, processes, the sandbox image"
  else
    emit 8 verify validate BLOCKED "bin/engine/ymir-validate.sh is absent — the install could not be proven"
  fi
}

resolve_phase; code_phase; home_phase; runtimes_phase; engines_phase; apps_phase; wire_phase; raise_phase; verify_phase

# ── output ──────────────────────────────────────────────────────────────────
if [ "$JSON" = 1 ]; then
  printf '['
  local_i=0
  for i in "${!P_STEP[@]}"; do
    [ -n "$ONLY_PHASE" ] && [ "${P_N[$i]}" != "$ONLY_PHASE" ] && continue
    [ "$ONLY_BLOCKED" = 1 ] && [ "${P_STATE[$i]}" != BLOCKED ] && continue
    [ "$local_i" -gt 0 ] && printf ','
    printf '\n  {"phase":%s,"name":"%s","step":"%s","state":"%s","why":"%s"}' \
      "${P_N[$i]}" "${P_NAME[$i]}" "${P_STEP[$i]}" "${P_STATE[$i]}" "${P_WHY[$i]}"
    local_i=$((local_i+1))
  done
  [ "$local_i" -gt 0 ] && printf '\n'
  printf ']\n'
  exit 0
fi

shown=0
for i in "${!P_STEP[@]}"; do
  [ -n "$ONLY_PHASE" ] && [ "${P_N[$i]}" != "$ONLY_PHASE" ] && continue
  [ "$ONLY_BLOCKED" = 1 ] && [ "${P_STATE[$i]}" != BLOCKED ] && continue
  shown=$((shown+1))
done

if [ "$shown" -eq 0 ]; then
  if [ "$ONLY_BLOCKED" = 1 ]; then printf 'plan: 0 blocked steps — nothing is holding the install back\n'
  else printf 'plan: 0 rows for phase %s\n' "$ONLY_PHASE"; fi
  exit 0
fi

# A human sees the same rows, rendered in the cloth, on stderr — the TOON below
# stays the data on stdout, so a pipeline never parses a decoration.
if [ "$COLOUR" = 1 ]; then
  . "$SCRIPT_DIR/../desktop/ymir-style.sh"
  style_init
  last_phase=""
  for i in "${!P_STEP[@]}"; do
    [ -n "$ONLY_PHASE" ] && [ "${P_N[$i]}" != "$ONLY_PHASE" ] && continue
    [ "$ONLY_BLOCKED" = 1 ] && [ "${P_STATE[$i]}" != BLOCKED ] && continue
    if [ "${P_N[$i]}" != "$last_phase" ]; then
      style_heading "${P_NAME[$i]}"
      last_phase="${P_N[$i]}"
    fi
    style_line "${P_STATE[$i]}" "${P_STEP[$i]}" "${P_WHY[$i]}"
  done
fi

printf 'plan[%d]{phase,name,step,state,why}:\n' "$shown"
for i in "${!P_STEP[@]}"; do
  [ -n "$ONLY_PHASE" ] && [ "${P_N[$i]}" != "$ONLY_PHASE" ] && continue
  [ "$ONLY_BLOCKED" = 1 ] && [ "${P_STATE[$i]}" != BLOCKED ] && continue
  printf '  "%s","%s","%s","%s","%s"\n' "${P_N[$i]}" "${P_NAME[$i]}" "${P_STEP[$i]}" "${P_STATE[$i]}" "${P_WHY[$i]}"
done
exit 0
