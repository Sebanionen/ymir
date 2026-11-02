#!/usr/bin/env bash
# ymir-install.sh — THE FIRST SETUP. Stand the full Ymir up for the operator:
# prerequisites, the single-tenant workspace tree, the OSS engines (treehouse /
# sandcastle / no-mistakes), the sandbox image, the well (engram) + harness MCP,
# the loaders, the registries, and the runtime services. Idempotent. Galdr TOON.
#
# Usage:
#   bin/engine/ymir-install.sh [--check] [--role heart|forge|dev|hand] [--skip-engines] [--skip-services] [--no-desktop] [--yes]
#   bin/engine/ymir-install.sh --plan [--json]     # the plan, computed — changes nothing
#   bin/engine/ymir-install.sh --yes | --non-interactive | --accept-all-defaults
#   bin/engine/ymir-install.sh --status
#   bin/engine/ymir-install.sh --version
#
# The consent a real install asks for is not a recited paragraph: it is the PLAN
# printed by bin/bridge/ymir-plan.sh — probed on THIS host, one row per step, each with
# its state and the reason for it. A paragraph drifts behind the code; a plan is
# computed from it every run.
#
# Exit: 0 all good (or --check/--plan), 1 a step failed, 2 usage, 3 declined.
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

# The operator's settings and secrets live in the home they chose, never in the
# code tree — a packaged install replaces its tree on upgrade, and a credential
# must never sit in a tree that ships (Rule 04).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yr="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _yc in "$_yr/hoard-lib.sh" "$_yr/../vault/hoard-lib.sh" "$_yr/../../vault/hoard-lib.sh"; do
    [ -r "$_yc" ] && { . "$_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _yr _yc
fi
hoard_settings_dir YMIR_SETTINGS_DIR
hoard_local_env YMIR_ENV_FILE
# The home is the OPERATOR's to choose, never ours to assume. Resolution:
# $YMIR_HOME (explicit) → the choice recorded at a previous installation →
# the one documented default. An interactive run ASKS and RECORDS the answer
# (step_home); --check never writes, --yes takes what is recorded.
# The hoard resolves through the shared lib, so the installer can never disagree
# with bin/vault/hodd.sh about where private data lives — and never points inside the
# repo (Rule 04).
# shellcheck source=bin/vault/hoard-lib.sh
. "$SCRIPT_DIR/../vault/hoard-lib.sh"
# The role lib — what this machine IS, and the components its roles owe (plan 51
# P1). It resolves the home through hoard-lib, so it loads right after it.
if [ -z "${YMIR_ROLE_LIB_LOADED:-}" ] && [ -r "$SCRIPT_DIR/../skuld/role-lib.sh" ]; then
  . "$SCRIPT_DIR/../skuld/role-lib.sh"; YMIR_ROLE_LIB_LOADED=1
fi
# shellcheck source=bin/desktop/app-lib.sh
. "$SCRIPT_DIR/../desktop/app-lib.sh"
# The runtime resolver answers for every desktop surface (P1, 2026-09-24); load
# it beside app-lib so the install steps and the verifier speak its language.
if [ -z "${YMIR_ELECTRON_LIB_LOADED:-}" ] && [ -r "$SCRIPT_DIR/../desktop/electron-lib.sh" ]; then
  . "$SCRIPT_DIR/../desktop/electron-lib.sh"; YMIR_ELECTRON_LIB_LOADED=1
fi
ymir_home_root YMIR_HOME
# Where the smithy's parts live: apps/smidja-factory in a clone, or the
# @zerwiz/smidja-factory package in an npm install (bin/desktop/smidja-lib.sh).
if [ -z "${YMIR_SMIDJA_LIB_LOADED:-}" ]; then
  _ys="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _yc in "$_ys/smidja-lib.sh" "$(CDPATH='' cd "$_ys" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)/bin/desktop/smidja-lib.sh"; do
    [ -r "$_yc" ] && { . "$_yc"; YMIR_SMIDJA_LIB_LOADED=1; break; }
  done
  unset _ys _yc
fi
smidja_visualizer_dir SMIDJA_VIZ
smidja_factory_dir SMIDJA_FACTORY

WORKSPACE="${YMIR_WORKSPACE:-$YMIR_HOME/workspaces}"
hoard_root HOARD
DOMAINS="company marketing development life me"

CHECK=0; SKIP_ENGINES=0; SKIP_SERVICES=0; ASSUME_YES=0; NO_DESKTOP=0; PLAN_ONLY=0; PLAN_ARGS=(); ROLE_FLAG=""
case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;; -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --plan|--dry-run) PLAN_ONLY=1; shift ;;
    --json|--blocked) PLAN_ARGS+=("$1"); shift ;;
    --phase) PLAN_ARGS+=("$1" "${2-}"); shift 2 ;;   # --phase carries its number
    --role) ROLE_FLAG="${2-}"; shift 2 ;;
    --role=*) ROLE_FLAG="${1#--role=}"; shift ;;
    --skip-engines) SKIP_ENGINES=1; shift ;;
    --skip-services) SKIP_SERVICES=1; shift ;;
    --no-desktop) NO_DESKTOP=1; shift ;;
    --yes|-y|--non-interactive|--accept-all-defaults) ASSUME_YES=1; shift ;;
    --status) exec "$SCRIPT_DIR/ymir-install.sh" --check ;;
    *) printf 'error: unknown flag %s\nhelp: bin/engine/ymir-install.sh [--check|--plan|--role heart|forge|dev|hand|--skip-engines|--skip-services|--no-desktop|--yes]\n' "$1" >&2; exit 2 ;;
  esac
done

# A role named on the command line is the strongest statement of what this
# machine IS. An unknown name is REFUSED here, before anything changes — never
# mapped to a guessed set. (The resolved role is exported so every child —
# bin/skuld/role.sh, bin/fleet/topology.sh, the plan — reads the same fact.)
if [ -n "$ROLE_FLAG" ]; then
  for _r in ${ROLE_FLAG//,/ }; do
    case " heart forge dev hand " in *" $_r "*) ;; *)
      printf 'error: unknown role %s\nhelp: --role heart|forge|dev|hand (a comma list names a machine with two roles)\n' "$_r" >&2; exit 2 ;;
    esac
  done
  export YMIR_ROLE="$ROLE_FLAG"
fi
unset _r

# The plan is a question, not a change: it prints and exits without writing.
if [ "$PLAN_ONLY" = 1 ]; then
  exec "$SCRIPT_DIR/../bridge/ymir-plan.sh" ${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}
fi

# The cloth (bin/desktop/ymir-style.sh): colour, marks and spacing for the human, while
# every row of data stays TOON on stdout.
. "$SCRIPT_DIR/../desktop/ymir-style.sh"
style_init

declare -a IDS STATUS DETAIL
# The code minted for this install, reported at the end so it is not lost in the
# step table. Empty on --check, and when no code could be minted.
INVITE_CODE=""
add() { IDS+=("$1"); STATUS+=("$2"); DETAIL+=("$3"); }
have() { command -v "$1" >/dev/null 2>&1; }
TOON="install[0]{step,status,detail}:"

# The step chain below is gated on exactly this; nothing else selects components.
# The resolution chain, the component table, and the machine-card writer live in
# bin/skuld/role-lib.sh (functions only), so a test drives them without an install.
ROLE_SET=""; ROLE_SRC="none"; ROLE_HOST=""; ROLE_COMPONENTS="core"; ROLE_DEFAULTED=0

role_gate() {  # <id> <role|r,r> <what> — a step runs only when this machine holds one
  local id="$1" need="$2" what="$3" r
  [ -n "$ROLE_SET" ] || { add "$id" SKIP "no role declared — pass --role <r> or bin/skuld/role.sh set <host> heart|forge|dev|hand"; return 1; }
  for r in ${need//,/ }; do role_has "$r" && return 0; done
  add "$id" SKIP "not this machine's role ($need only) — $what"
  return 1
}

# ── consent ──────────────────────────────────────────────────────────────
# Show exactly what will change and require explicit acceptance. A real
# install touches the machine (packages, a docker image, raised services),
# so it never proceeds on silence. The plan is COMPUTED here (bin/bridge/ymir-plan.sh
# probes this host) — never a paragraph that can drift behind the code.
confirm_install() {
  [ "$ASSUME_YES" = 1 ] && return 0
  if [ ! -t 0 ]; then
    printf 'error: refusing a non-interactive install without --yes\nhelp: re-run with --yes to accept non-interactively, or --plan / --check to preview\n' >&2
    exit 3
  fi
  style_title "Ymir first setup" "the plan below is probed on this machine, not recited"
  cat <<'PLAN'
Each row is a phase, a step, its state, and why.

  DO        a change will be made
  SKIP      already satisfied — nothing to do
  INFO      a fact about this host; no change implied
  BLOCKED   cannot run — the reason names what is missing
  CONSENT   needs your word (a credential, an invite, the desktop shells)

Nothing is deleted. Every step is idempotent.
PLAN
  printf '\n'
  # The rendering lives on stderr (the cloth); the TOON on stdout is data and is
  # dropped here. Sending BOTH to /dev/null is how the plan became invisible.
  bash "$SCRIPT_DIR/../bridge/ymir-plan.sh" --colour >/dev/null || true
  printf '\nProceed with the install? [y/N] '
  read -r reply || reply=""
  case "$reply" in
    y|Y|yes|YES)
      # Consent must not be followed by silence: the install is minutes of work, so say
      # how much follows and let each step name itself as it runs.
      printf '\n  proceeding — %s steps. Each names itself as it runs, with its time.\n\n' "${STEP_TOTAL:-29}"
      ;;
    *) printf 'install declined — nothing was changed.\n'; exit 3 ;;
  esac
}

# ── 1. prereqs ───────────────────────────────────────────────────────────────
#
# Self-healing: `bin/engine/prereq-ensure.sh` provisions what it can in user space
# (bun, uv, mcp<2) with no sudo. Anything it cannot do is reported with an
# exact command. engram is OPTIONAL and reported honestly, never as a failure.
ENGRAM_PY=""
step_prereqs() {
  # Provision only what THIS role owes (plan 51 P1 · the components table). A
  # `hand` — the phone — owns `core` alone: it builds no visualizer, so it owes no
  # bun (and Android ships none), and it runs no sandbox, so it owes no
  # docker/podman. Requiring either on a hand is how a phone install hung at step
  # 2/27; the role table already answers the question.
  local need_bun=0 need_engine=0 need_well=0
  role_has dev && need_bun=1
  { role_has forge || role_has dev; } && need_engine=1
  { role_has heart || role_has dev; } && need_well=1
  if [ "$CHECK" = 0 ] && [ -x "$SCRIPT_DIR/prereq-ensure.sh" ]; then
    [ "$need_bun" = 1 ] && "$SCRIPT_DIR/prereq-ensure.sh" bun >/dev/null 2>&1 || true
    "$SCRIPT_DIR/prereq-ensure.sh" uv  >/dev/null 2>&1 || true
    "$SCRIPT_DIR/prereq-ensure.sh" mcp >/dev/null 2>&1 || true
    # bun installs to ~/.bun/bin; adopt it for the rest of this run.
    [ -x "$HOME/.bun/bin/bun" ] && export PATH="$HOME/.bun/bin:$PATH"
    [ -x "$HOME/.local/bin/uv" ] && export PATH="$HOME/.local/bin:$PATH"
  fi
  local miss="" engine="" ready="git python3"
  for c in git python3; do have "$c" || miss="$miss $c"; done
  if [ "$need_bun" = 1 ]; then have bun || miss="$miss bun"; ready="$ready bun"; fi
  python3 -c "from mcp.server.fastmcp import FastMCP" >/dev/null 2>&1 || miss="$miss mcp<2"
  # Docker or Podman — whichever this host has; never assume the binary name.
  if [ "$need_engine" = 1 ]; then
    engine="$(ymir_container_engine_name 2>/dev/null || true)"
    [ -n "$engine" ] || miss="$miss docker/podman"
    [ -n "$engine" ] && ready="$ready $engine"
  fi
  have gh || miss="$miss gh"
  # mcp<2 is needed by every role's harness doors; name it in the OK row too.
  [ -z "$miss" ] && ready="$ready gh mcp<2"
  if [ -n "$miss" ]; then add prereqs WARN "missing:$miss"; else add prereqs OK "$ready"; fi
  # The well engine: a `hand` reaches the heart's well as a door and does not run
  # the engine locally; heart/dev provision it. engram needs Python 3.12/3.13, so
  # prereq-ensure installs it into a compatible interpreter and records which one.
  if [ "$need_well" = 0 ]; then
    add memory-well SKIP "not this machine's role (heart,dev) — the well is the heart's door"
    return 0
  fi
  if [ -x "$SCRIPT_DIR/prereq-ensure.sh" ]; then
    if "$SCRIPT_DIR/prereq-ensure.sh" engram >/dev/null 2>&1; then
      add memory-well OK "engram installed for the engine's Python"
    else
      add memory-well WARN "engram could not be installed — bin/engine/prereq-ensure.sh engram (needs Python 3.12/3.13)"
    fi
  else
    add memory-well SKIP "no prereq-ensure.sh"
  fi
}

# ── 2. workspace tree ────────────────────────────────────────────────────────
step_tree() {
  if [ "$CHECK" = 1 ]; then
    local ok=1
    [ -d "$WORKSPACE/work" ] && [ -d "$WORKSPACE/personal" ] && [ -f "$HOARD/identity/workspaces.yaml" ] && [ -f "$HOARD/identity/projects.yaml" ] || ok=0
    # Phase 3: validate client_of references (plan 128)
    if [ -d "$HOARD/identity/places" ] && [ -x "$SCRIPT_DIR/../identity/place-validate.sh" ]; then
      local place_err
      if ! place_err=$(bash "$SCRIPT_DIR/../identity/place-validate.sh" --all 2>&1); then
        add tree WARN "client_of validation failed — $place_err"
        ok=0
      fi
    fi
    if [ "$ok" = 1 ]; then add tree OK "workspace tree present"; else add tree WARN "workspace tree incomplete"; fi
    return
  fi
  local created=0
  for ws in work:company,marketing,development,life personal:me,life,development; do
    local name="${ws%%:*}" domains="${ws#*:}"
    for d in ${domains//,/ }; do
      [ -d "$WORKSPACE/$name/$d" ] || { mkdir -p "$WORKSPACE/$name/$d"; created=$((created+1)); }
    done
  done
  mkdir -p "$WORKSPACE/companies" "$WORKSPACE/memory/daily" "$HOARD/identity"
  # The hoard is OUTSIDE the repo (Rule 04): this creates its layout at the
  # resolved root, never in the checkout. Idempotent.
  "$SCRIPT_DIR/../vault/hodd.sh" init >/dev/null 2>&1 || true
  # A missing platform env makes `bin/vault/hodd.sh emit secrets/platform.env` fail on a
  # fresh machine; seed an empty one (0600) so the reference always resolves.
  if [ ! -f "$HOARD/secrets/platform.env" ]; then
    mkdir -p "$HOARD/secrets"
    ( umask 077; : >"$HOARD/secrets/platform.env" )
    created=$((created+1))
  fi
  # The files a home must HOLD arrive through their own doors, never from a heredoc here
  # (RULES/42): the identity registers belong to bin/identity/registers-seed.sh, and every
  # other shape to bin/engine/home-seed.sh, which walks .agents/home-contract.yaml. Two
  # writers of one file is how a template and an install drift apart — measured 2026-11-02:
  # this step wrote `workspaces.yaml` inline, in a shape its own shipped template did not teach.
  if seeded=$(bash "$SCRIPT_DIR/home-seed.sh" 2>&1); then
    created=$((created + $(printf '%s' "$seeded" | grep -c '^home-seed: seeded ' || true)))
  else
    add tree WARN "the home contract could not be seeded — $(printf '%s' "$seeded" | tail -1)"
  fi
  add tree OK "workspace/{personal} · companies · registries · hoard (outside the repo) (created $created)"
}

# ── 2b. the client register — a company we SERVE is never a house we ARE ──────
# Plan 128. `companies.yaml` holds the houses the operator IS; `clients.yaml` holds the
# companies a house SERVES. They are two facts, so they are two files, and each arrives
# from its template in registry/ — one source each, never a heredoc in this script.
#
# The relation is the point: a place that declares `client_of: <house>` must resolve
# against a register that exists. `place-validate.sh --all` is the one door that decides
# that, so the install cannot disagree with the operator's own check. A refusal here is a
# RED naming the file and the fix — absent is not a shrug (plan 128 §4 phase 3).
step_clients() {
  local id="$HOARD/identity"
  local made=0 seeded="" out why
  if [ "$CHECK" = 0 ]; then
    # One owner for the copy — bin/identity/registers-seed.sh — and one template per fact
    # on the registry shelf. An existing register is never touched.
    out="$(YMIR_HOME="$YMIR_HOME" bash "$ROOT/bin/identity/registers-seed.sh" 2>&1)" || true
    made="$(printf '%s' "$out" | grep -c 'seeded ' || true)"
    [ "$made" -gt 0 ] && seeded=" · seeded $made register file(s) from registry/"
  fi

  # The register's SHAPE: a bad one is refused by the door that owns it, never read
  # speculatively by this step.
  if [ -f "$id/clients.yaml" ]; then
    if out="$(YMIR_HOME="$YMIR_HOME" bash "$ROOT/bin/identity/clients.sh" validate 2>&1)"; then
      :
    else
      add clients FAIL "hodd/identity/clients.yaml has a bad shape — $(printf '%s' "$out" | head -1) (fix: state is lead|prospect|active|paused|ended, served_by names a house)"
      return 0
    fi
  fi

  # The places that POINT at the register. `place-validate.sh --all` is the one door
  # that decides a place's relation, so this step cannot disagree with the operator.
  if [ -d "$id/places" ]; then
    if out="$(YMIR_HOME="$YMIR_HOME" bash "$ROOT/bin/identity/place-validate.sh" --all 2>&1)"; then
      if [ -f "$id/clients.yaml" ]; then
        add clients OK "${out##*$'\n'}$seeded"
      else
        add clients WARN "no clients register at hodd/identity/clients.yaml — nothing to resolve yet$seeded (a real run seeds it from registry/clients.yaml.example)"
      fi
    else
      why="$(printf '%s' "$out" | grep -m1 '^FAIL ' | sed 's/^FAIL  *//')"
      add clients FAIL "${why:-a place was refused — run bin/identity/place-validate.sh --all to see it}"
    fi
    return 0
  fi
  if [ -f "$id/clients.yaml" ]; then
    add clients OK "register present$seeded · no places shelf to resolve"
  else
    add clients SKIP "no register yet and no places — nothing to resolve$seeded"
  fi
}

# ── 2a. the home the operator chooses ────────────────────────────────────────
# Everything private — docs, secrets, identity, projects, workspaces, memory —
# lives in ONE place the operator owns, and it is the operator's to name. A real
# interactive run asks once and records the answer under ~/.config/ymir/home, so
# every later script resolves the same home without being told again. --check
# never writes; --yes takes what is already recorded (or the documented default).
step_home() {
  local rec="" chosen=""
  ymir_home_record rec
  if [ -n "${YMIR_HOME:-}" ] && [ "$CHECK" = 1 ]; then add home OK "home: $YMIR_HOME"; return; fi
  if [ -n "$rec" ]; then
    add home OK "home: $YMIR_HOME (the choice recorded at installation)"
    return
  fi
  if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
    if ymir_home_record_set "$YMIR_HOME" 2>/dev/null; then
      add home OK "home: $YMIR_HOME (default recorded — change it any time with YMIR_HOME=<path> bin/engine/ymir-install.sh)"
    else
      add home WARN "home: $YMIR_HOME (could not record the choice under $YMIR_CONFIG_DIR — pass YMIR_HOME=<path> to every run)"
    fi
    return
  fi
  printf '\nWhere shall your home live?\n'
  printf 'Everything private is kept there — docs, secrets, identity, projects,\n'
  printf 'workspaces, memory — never in the code tree, never in this package.\n'
  printf 'Home [%s]: ' "$YMIR_HOME"
  IFS= read -r chosen || true
  [ -n "$chosen" ] && YMIR_HOME="${chosen/#\~/$HOME}"
  if [ -e "$YMIR_HOME" ]; then
    printf 'using %s — what is already there is kept; nothing is deleted.\n' "$YMIR_HOME"
  fi
  # Re-resolve the roots the choice moved: the hoard within the home, and the
  # workspace tree beneath it. A second run finds the record and never asks again.
  hoard_root HOARD
  WORKSPACE="${YMIR_WORKSPACE:-$YMIR_HOME/workspaces}"
  if ymir_home_record_set "$YMIR_HOME"; then
    add home OK "home: $YMIR_HOME (recorded — later runs need not ask)"
  else
    add home WARN "home: $YMIR_HOME (could not record the choice; pass YMIR_HOME=<path> to every run)"
  fi
}

# ── 2b. app repos (the app split) ────────────────────────────────────────────
# The apps live in their OWN repos (zerwiz/hlidskjalf · hlidskjalf-mobile ·
# odrerir · sessrumnir · smidja), registered in the home registry with a
# `repo: apps/<path>` block. The monorepo never tracks them; installation
# clones each into the tree — never guessing a remote, always reading the
# registry. A present repo is fast-forwarded; a missing one cloned. The smithy
# engine (apps/smidja) is stamped from the cloned factory's templates, exactly
# as install.py does for a target repo.
step_apps() {
  role_gate apps heart,dev "the web surfaces (Hlidskjalf · Óðrerir · Sessrúmnir · Smíðja)" || return 0
  # A packaged install has no apps/ of its own on purpose: the surfaces arrive as
  # dependencies. Cloning the repos into node_modules/@zerwiz/ymir/apps/ is how a
  # hollow directory shadowed a real package, so a package tree clones nothing.
  # A CLONE still clones — that is the shape this step exists for.
  # One repo (plan 35): when the surfaces ship IN this tree there is nothing to
  # clone — the resolver's first shape (`<root>/apps/<surface>`) is already true.
  if [ -f "$ROOT/apps/hlidskjalf/package.json" ] && [ -f "$ROOT/apps/odrerir/package.json" ] \
     && [ -f "$ROOT/apps/sessrumnir/package.json" ]; then
    add apps PASS "in-tree — apps/ ships with the package (plan 35)"
    return 0
  fi
  case "$ROOT" in
    */node_modules/*)
      add apps SKIP "a package install — the surfaces are dependencies (npm i -g @zerwiz/ymir)"
      return 0 ;;
  esac
  local reg="$HOARD/identity/projects.yaml"
  if [ ! -r "$reg" ]; then
    # The fork path: no private hoard — fall back to the PUBLIC app map so a
    # fresh clone still pulls the five surfaces (config/app-repos.yaml).
    reg="$ROOT/config/app-repos.yaml"
  fi
  if [ ! -r "$reg" ]; then
    add apps SKIP "no app registry — neither the hoard's projects.yaml nor config/app-repos.yaml"
    return 0
  fi
  # Parse blocks that carry `repo: apps/<path>` and a `git:` inline dict.
  local entries
  entries=$(awk '
    /^  - id:/ { repo="" }
    /^    repo: apps\// { repo=substr($2, 6) }
    /^    git: / {
      line=$0; host=""; owner=""; grepo=""
      if (match(line, /host: [A-Za-z0-9._-]+/)) host=substr(line, RSTART+6, RLENGTH-6)
      if (match(line, /owner: [A-Za-z0-9_-]+/)) owner=substr(line, RSTART+7, RLENGTH-7)
      if (match(line, /repo: [A-Za-z0-9._-]+/)) grepo=substr(line, RSTART+6, RLENGTH-6)
      if (repo != "" && owner != "" && grepo != "") print repo "|" host "|" owner "|" grepo
      repo=""
    }' "$reg")
  if [ -z "$entries" ]; then
    add apps OK "no apps/ projects registered — nothing to pull"
    return 0
  fi
  local ok=0 skip=0 fail=0 missing=0
  while IFS='|' read -r rel host owner grepo; do
    [ -n "$rel" ] || continue
    local path="$ROOT/apps/$rel"
    if [ "$CHECK" = 1 ]; then
      if [ -d "$path/.git" ]; then add apps OK "$rel present ($owner/$grepo)"; ok=$((ok+1));
      elif [ -d "$path" ]; then add apps WARN "$rel present but not a git clone — re-install to replace"; skip=$((skip+1));
      else add apps WARN "$rel absent — a full run clones $owner/$grepo"; missing=$((missing+1)); fi
      continue
    fi
    if [ -d "$path/.git" ]; then
      if (cd "$path" && git fetch origin 2>/dev/null && git merge --ff-only origin/main >/dev/null 2>&1); then add apps OK "$rel up to date ($owner/$grepo)"; ok=$((ok+1));
      else add apps OK "$rel present ($owner/$grepo; pull refused — local changes?)"; skip=$((skip+1)); fi
    elif [ -d "$path" ]; then
      add apps WARN "$rel present but not a git clone — move $path aside and re-run"; skip=$((skip+1))
    else
      local url="https://github.com/$owner/$grepo.git"
      if git clone -q "$url" "$path" 2>/dev/null; then add apps OK "$rel cloned ($owner/$grepo)"; ok=$((ok+1));
      else add apps WARN "$rel clone failed — run: git clone $url $path"; fail=$((fail+1)); fi
    fi
  done <<< "$entries"
  # The smithy engine: apps/smidja is stamped from the cloned factory's
  # templates (the monorepo tracks neither). The config template follows.
  local factory="$ROOT/apps/smidja-factory" eng="$ROOT/apps/smidja"
  if [ "$CHECK" = 0 ] && [ -d "$factory/templates/smidja" ] && [ ! -e "$eng/smidja_modules" ]; then
    mkdir -p "$eng"
    cp -rn "$factory/templates/smidja/." "$eng/" 2>/dev/null
    [ -f "$factory/templates/smidja.config.yaml" ] && { mkdir -p "$eng/smidja_smidja_config"; cp -n "$factory/templates/smidja.config.yaml" "$eng/smidja_smidja_config/smidja.config.yaml" 2>/dev/null; }
    add apps OK "smidja engine stamped into apps/smidja"
  fi
  if [ "$fail" -gt 0 ]; then add apps WARN "$fail app clone(s) failed (offline?)"; fi
}

# ── 3. engines ───────────────────────────────────────────────────────────────
step_engines() {
  [ "$SKIP_ENGINES" = 1 ] && { add engines SKIP "--skip-engines"; return; }
  if [ "$CHECK" = 1 ]; then
    local has=""
    have treehouse && has="$has treehouse"
    have no-mistakes && has="$has no-mistakes"
    { [ -d "$ROOT/node_modules/@ai-hero/sandcastle" ] || have sandcastle; } && has="$has sandcastle"
    if [ -n "$has" ]; then add engines OK "present:$has"; else add engines WARN "none present"; fi
    return
  fi
  local got=""
  if have treehouse; then got="$got treehouse"; else
    if curl -fsSL https://kunchenguid.github.io/treehouse/install.sh 2>/dev/null | sh >/dev/null 2>&1 && have treehouse; then got="$got treehouse"; fi
  fi
  if have no-mistakes; then got="$got no-mistakes"; else
    if curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh 2>/dev/null | sh >/dev/null 2>&1 && have no-mistakes; then got="$got no-mistakes"; fi
  fi
  if [ -d "$ROOT/node_modules/@ai-hero/sandcastle" ] || have sandcastle; then got="$got sandcastle"; fi
  if [ -z "$got" ]; then add engines WARN "none installed (offline?) — install manually"; else add engines OK "installed:$got"; fi
}

# ── 3a2. the Pi agent + local models ────────────────────────────────────────
# Ensure pi and the Pi packages Ymir needs (pi-mcp-adapter, pi-web-access,
# pi-lmstudio — Pi has no native MCP/web/local-model support), detect the LOCAL
# model runtimes actually here (never assume llama.cpp), and seed
# ~/.pi/agent/models.json only when the operator has none.
step_models() {
  role_gate models forge,dev "the harness (pi) and its local models" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add models SKIP "--skip-engines"; return; }
    # The user's OWN models, read from the ROOT pi home — never assumed. A roster can
    # name a model this machine has never seen, and nothing in the report said so.
    if [ -x "$SCRIPT_DIR/../model/models-report.sh" ]; then
      msum="$("$SCRIPT_DIR/../model/models-report.sh" 2>/dev/null)"
      if [ -n "$msum" ]; then
        add models-config OK "the user's models — $msum"
      else
        add models-config WARN "no models.json in the root pi home — the user's models are unread"
      fi
  if [ "$CHECK" = 1 ]; then add models OK "would ensure pi + packages and detect local models"; return; fi
  if [ -x "$SCRIPT_DIR/../pi/pi-ensure.sh" ]; then
    if "$SCRIPT_DIR/../pi/pi-ensure.sh" ensure --install >/dev/null 2>&1; then add models OK "pi + packages present";
    else add models WARN "pi or a Pi package missing — run bin/pi/pi-ensure.sh install"; fi
  else
    add models SKIP "no pi-ensure.sh"
  fi
  if [ -x "$SCRIPT_DIR/../model/models-detect.sh" ]; then
    local detected
    detected="$("$SCRIPT_DIR/../model/models-detect.sh" --json 2>/dev/null | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin).get("providers",{}).keys()))' 2>/dev/null)"
    add models OK "local runtimes: ${detected:-none}"
    fi
    if [ ! -f "$HOME/.pi/agent/models.json" ]; then
      "$SCRIPT_DIR/../model/models-detect.sh" --write >/dev/null 2>&1 && add models OK "seeded ~/.pi/agent/models.json (was absent)"
    fi
  fi
  if [ -x "$SCRIPT_DIR/../model/model-hardware.sh" ]; then
    "$SCRIPT_DIR/../model/model-hardware.sh" >/dev/null 2>&1 && add models OK "profiled this machine (data/local-models.md; online research left for Brokk)"
  fi
}

# ── 3a3. the local model: engine, the user's model, pi, ymir ────────────────
# Installation stands a local brain up for THIS hardware (plan 57). It ADOPTS an
# existing CUDA llama.cpp engine (never rebuilds what stands), chooses the best
# model that fits the PROBED hardware, fetches it (consent first), wires pi, and
# registers the same model with Ymir in the hoard — one model road. When a local
# server already serves models, nothing is downloaded: the operator's registered
# model is adopted. Loud refusals throughout; never a silent skip.
step_local_model() {
  role_gate local-model forge,dev "the model rail" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add local-model SKIP "--skip-engines"; return; }
  [ "${YMIR_SKIP_LOCAL_MODEL:-0}" = 1 ] && { add local-model SKIP "YMIR_SKIP_LOCAL_MODEL=1"; return; }

  # 1. the engine — adopt what stands, build only when none.
  if [ ! -x "$SCRIPT_DIR/../model/llama-ensure.sh" ]; then add local-model SKIP "no llama-ensure.sh"; return; fi
  local eng
  if eng="$("$SCRIPT_DIR/../model/llama-ensure.sh" ensure 2>&1)"; then
    [ "$CHECK" = 1 ] && add local-model OK "engine would stand (adopt/build) CUDA llama-server" \
                     || add local-model OK "engine: $(printf '%s' "$eng" | awk -F'\",\"' '/"(adopt|built)"/{print $3; exit}')"
  else
    add local-model WARN "engine: $(printf '%s' "$eng" | tail -1)"
    return
  fi

  # 2. the model. If a local rail already serves models, ADOPT the registered one
  #    (no download); else fit one to the probed hardware and fetch it by consent.
  local provider model base url served="" key=""
  provider="$("$SCRIPT_DIR/../fleet/agents-config.sh" default --provider 2>/dev/null || true)"
  model="$("$SCRIPT_DIR/../fleet/agents-config.sh" default --model 2>/dev/null || true)"
  base="$([ -n "$provider" ] && "$SCRIPT_DIR/../fleet/agents-config.sh" provider-url "$provider" 2>/dev/null || true)"
  [ -n "$base" ] || base="http://127.0.0.1:8080/v1"
  url="${base%/}/models"
  # The rail is keyed: read the provider's key from the operator's pi auth (a
  # reference, never a value in the tree), else the hoard env.
  key="$(python3 - "$HOME/.pi/agent/auth.json" "$provider" <<'PY' 2>/dev/null
import json, sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
p=d.get(sys.argv[2])
print((p.get("key") or p.get("apiKey")) if isinstance(p, dict) else (p if isinstance(p,str) else ""))
PY
)"
  if [ -z "$key" ]; then
    [ -r "$YMIR_ENV_FILE" ] && key="$(. "$YMIR_ENV_FILE" 2>/dev/null; printf '%s' "${LLAMA_SWAP_API_KEY:-}")"
  fi
  if have curl; then
    local -a curl_args=(-fsS --max-time 4)
    [ -n "$key" ] && curl_args+=(-H "Authorization: Bearer $key")
    curl_args+=("$url")
    served="$(curl "${curl_args[@]}" 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
ids=[m.get("id") for m in (d.get("data") or []) if m.get("id")]
print(ids[0] if ids else "")' 2>/dev/null)"
  fi

  if [ -n "$served" ]; then
    # A rail stands: register + wire the operator's model (or the first served).
    [ -n "$model" ] || model="$served"
    if [ "$CHECK" = 1 ]; then add local-model OK "rail serves models — would register ${provider}/${model}"; return; fi
    [ -x "$SCRIPT_DIR/../model/model-register.sh" ] && "$SCRIPT_DIR/../model/model-register.sh" --provider "$provider" --model "$model" --base-url "$base" >/dev/null 2>&1
    [ -x "$SCRIPT_DIR/../pi/pi-model-wire.sh" ] && "$SCRIPT_DIR/../pi/pi-model-wire.sh" --provider "$provider" --model "$model" --base-url "$base" --no-prove >/dev/null 2>&1
    add local-model OK "adopted rail model ${provider}/${model} (no download)"
    [ -x "$SCRIPT_DIR/../model/model-tune.sh" ] && "$SCRIPT_DIR/../model/model-tune.sh" --model-id "$model" --dry-run >/dev/null 2>&1 && add local-model-tune INFO "tune available: bin/model/model-tune.sh --model-id ${model}"
    return
  fi

  # No rail: fit a model to this hardware.
  local choice_json choice_id
  if ! choice_json="$("$SCRIPT_DIR/../model/model-fit.sh" --json 2>/dev/null)"; then
    add local-model BLOCKED "no model fits — $( "$SCRIPT_DIR/../model/model-fit.sh" 2>&1 | tail -1 )"
    return
  fi
  choice_id="$(printf '%s' "$choice_json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["choice"]["id"])' 2>/dev/null)"
  [ -n "$choice_id" ] || { add local-model WARN "could not read the fit choice"; return; }

  if [ "$CHECK" = 1 ]; then add local-model OK "would fetch + wire '${choice_id}' for this hardware"; return; fi

  # Consent for the multi-GB download: --yes, or the explicit env door.
  if [ "$ASSUME_YES" != 1 ] && [ "${YMIR_LOCAL_MODEL_CONSENT:-0}" != 1 ]; then
    add local-model CONSENT "would download '${choice_id}' — re-run with --yes or YMIR_LOCAL_MODEL_CONSENT=1"
    return
  fi
  if ! "$SCRIPT_DIR/../model/model-fetch.sh" "$choice_id" --consent >/dev/null 2>&1; then
    add local-model WARN "fetch failed for '${choice_id}' — see bin/model/model-fetch.sh ${choice_id}"
    return
  fi
  add local-model OK "fetched '${choice_id}' into the hoard models dir"
}

# ── 3b. hermes runtime ───────────────────────────────────────────────────────
step_hermes() {
  role_gate hermes forge,dev "the worker runtime (heavy workers)" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add hermes SKIP "--skip-engines"; return; }
  if [ -x "$SCRIPT_DIR/hermes-ensure.sh" ]; then
    if [ "$CHECK" = 1 ]; then
      if "$SCRIPT_DIR/hermes-ensure.sh" status >/dev/null 2>&1; then add hermes OK "present"; else add hermes WARN "absent"; fi
    else
      if "$SCRIPT_DIR/hermes-ensure.sh" ensure --install >/dev/null 2>&1; then add hermes OK "present"; else add hermes WARN "not installed (run bin/engine/hermes-ensure.sh install)"; fi
    fi
  else add hermes SKIP "no hermes-ensure.sh"; fi
}

# ── 3b1b. Snotra, the meeting ear's engine ──────────────────────────────────
# The ear captures on the meeting seat and transcribes with whisper.cpp. The
# engine is per-OS (pacman/apt/build) and the model is fetched once; a seat that
# already carries a whisper build or voxtype is left untouched. The MCP face and
# unit ride the fleet step (bin/fleet/fleet-ensure.sh) — and so does the WATCH
# (snotra-detect), which the fleet step raises by CAPABILITY on any seat with a
# microphone: a call seat owes the ear's watch, a headless heart reports a
# clean skip.
# ── 3b1c. the voice engines: whisper (STT) + piper (TTS) ──────────────────────
# Voice is a machine property: the engines and models live on the host / in the
# hoard. This step ADOPTS what stands and installs what is missing; the whisper
# half is owned by systems/snotra/services/ear/snotra-ensure.sh (one road), so voice-ensure
# delegates it rather than growing a second whisper installer.
step_voice() {
  [ "$SKIP_ENGINES" = 1 ] && { add voice SKIP "--skip-engines"; return; }
  [ "${YMIR_SKIP_VOICE:-0}" = 1 ] && { add voice SKIP "YMIR_SKIP_VOICE=1"; return; }
  local ve="$SCRIPT_DIR/../voice/voice-ensure.sh"
  if [ ! -x "$ve" ]; then add voice SKIP "no bin/voice/voice-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if "$ve" status >/dev/null 2>&1; then add voice OK "whisper (STT) + piper (TTS) present (adopted)"
    else add voice DO "would install whisper.cpp (STT) + piper (TTS) + models"; fi
    return
  fi
  if "$ve" ensure --install >/dev/null 2>&1; then
    add voice OK "whisper (STT) + piper (TTS) present"
  else
    add voice WARN "voice engine or model missing (run bin/voice/voice-ensure.sh install)"
  fi
}

step_snotra() {
  role_gate snotra heart,dev "the meeting ear" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add snotra SKIP "--skip-engines"; return; }
  if [ ! -x "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" ]; then add snotra SKIP "no snotra-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" status >/dev/null 2>&1; then add snotra OK "whisper engine + model present"; else add snotra WARN "engine or model missing"; fi
    return
  fi
  if "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" ensure --install >/dev/null 2>&1; then
    add snotra OK "whisper engine + model present"
  else
    add snotra WARN "engine or model missing (run systems/snotra/services/ear/snotra-ensure.sh install)"
  fi
  # The lifecycle skeleton, agnostic: shelf, operator template, register, framework,
  # cron. Never a company or a participant.
  if [ -x "$SCRIPT_DIR/../../systems/snotra/services/record/snotra-init.sh" ]; then
    if "$SCRIPT_DIR/../../systems/snotra/services/record/snotra-init.sh" apply >/dev/null 2>&1; then
      add snotra-meetings OK "meetings shelf + framework + cron skeleton"
    else
      add snotra-meetings WARN "run systems/snotra/services/record/snotra-init.sh apply"
    fi
  fi
}

# ── 3b1c. Ratatoskr — the A2A mesh engine (a2abridge) ───────────────────────
# The mesh is the MIT engine **a2abridge**: a local directory daemon every
# agent announces to (:7777), plus the MCP bridge that gives each harness the
# a2a tools. The heart's A2A *node* (:8301) is a fleet service (step_fleet);
# THIS step seats the engine and wires it, so a fresh install is a mesh of one
# with no hand-copy — and Eir can repair it (bin/agents/eir-doctor.sh a2abridge).
step_a2a() {
  role_gate a2a heart,dev "the A2A mesh directory" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add a2a SKIP "--skip-engines"; return; }
  if [ ! -x "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" ]; then add a2a SKIP "no a2abridge-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" status >/dev/null 2>&1; then add a2a OK "engine + directory present"; else add a2a WARN "engine absent (run bin/bridge/a2abridge-ensure.sh ensure --install)"; fi
    return
  fi
  # The ensure's own post-start probe can race the daemon's first bind, so the
  # truth is the status check AFTER it, never its exit alone.
  "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" ensure --install >/dev/null 2>&1 || true
  if "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" status >/dev/null 2>&1; then
    add a2a OK "engine + directory up"
  else
    add a2a WARN "engine absent — run bin/bridge/a2abridge-ensure.sh ensure --install (offline?)"
  fi
  if [ -x "$SCRIPT_DIR/../bridge/a2a-mcp.sh" ] && "$SCRIPT_DIR/../bridge/a2a-mcp.sh" install >/dev/null 2>&1; then
    add a2a-mcp OK "a2abridge + engram wired into pi + opencode"
  else
    add a2a-mcp WARN "run bin/bridge/a2a-mcp.sh install to wire the mesh"
  fi
}

# ── 3b2. Sessrúmnir desktop GUI ──────────────────────────────────────────────
# The seat-hall: a vendored, re-themed fork of pi-desktop (Apache-2.0) at
# apps/sessrumnir. Deps are never committed; the ensure step installs them on
# first run, exactly as scripts/electron.sh does for the other desktop apps.
step_sessrumnir() {
  role_gate sessrumnir dev "the dev desktop layer" || return 0
  [ "$SKIP_ENGINES" = 1 ] && { add sessrumnir SKIP "--skip-engines"; return; }
  if [ -x "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" ]; then
    if [ "$CHECK" = 1 ]; then
      if "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" status >/dev/null 2>&1; then add sessrumnir OK "ready"; else add sessrumnir WARN "not ready (run bin/desktop/sessrumnir-ensure.sh install)"; fi
    else
      if "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" ensure --install >/dev/null 2>&1; then add sessrumnir OK "ready"; else add sessrumnir WARN "not ready — run bin/desktop/sessrumnir-ensure.sh install"; fi
    fi
  else add sessrumnir SKIP "no sessrumnir-ensure.sh"; fi
}

# ── 3c. Þjazi backend (herdr-first) ──────────────────────────────────────────
# Ymir spawns agents into terminal panes, so a backend must exist. herdr is
# preferred (protocol 14+, presentation spaces at 0.8.0+); tmux is an accepted
# reference backend. Never a silent fallback — a missing backend is reported.
step_backend() {
  if [ ! -x "$SCRIPT_DIR/../seat/herdr-ensure.sh" ]; then add backend SKIP "no herdr-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if out="$("$SCRIPT_DIR/../seat/herdr-ensure.sh" status 2>&1)"; then
      local b; b="$(printf '%s' "$out" | grep -oE '"(herdr|tmux|none)"' | head -1 | tr -d '"')"
      add backend OK "$b"
    else
      add backend WARN "no terminal backend (install herdr or tmux)"
    fi
  else
    if "$SCRIPT_DIR/../seat/herdr-ensure.sh" ensure --install >/dev/null 2>&1; then
      local b; b="$( "$SCRIPT_DIR/../seat/herdr-ensure.sh" status 2>&1 | grep -oE '"(herdr|tmux|none)"' | head -1 | tr -d '"' )"
      add backend OK "$b"
    else
      add backend WARN "no terminal backend — install herdr or tmux"
    fi
  fi
}

# ── 3d. host integration ─────────────────────────────────────────────────
# Learn the machine and place the desktop apps on EVERY host; the Omarchy-specific
# extras (the post-update hook) apply only when Omarchy is present. A non-Omarchy
# host still gets host learning and desktop placement — this is not a bonus for
# Omarchy, it is part of a normal install.
# ── 3b. the Omarchy installation layer (Rule 05) ─────────────────────────────
# Ymir is Omarchy-first: the desktop integration is a LAYER beside the portable
# core, and it owns its own installer. The core calls it here and reports one
# line; everything inside is the layer's business.
step_omarchy() {
  role_gate omarchy dev "the dev desktop layer" || return 0
  if [ ! -x "$SCRIPT_DIR/../host/omarchy-install.sh" ]; then add omarchy SKIP "no omarchy-install.sh"; return 0; fi
  if [ "$CHECK" = 1 ]; then
    "$SCRIPT_DIR/../host/omarchy-install.sh" --check >/dev/null 2>&1
  else
    "$SCRIPT_DIR/../host/omarchy-install.sh" >/dev/null 2>&1
  fi
  rc=$?
  if [ "$rc" = 0 ]; then
    if [ -d /usr/share/omarchy ]; then add omarchy OK "layer applied (sense · hook · plugins · desktops · editor · alarm · backend)"
    else add omarchy SKIP "not an Omarchy host — the core runs without this layer"; fi
  else
    add omarchy WARN "layer reported a failing step — run bin/host/omarchy-install.sh to see which"
  fi
}

step_host() {
  # Core host learning: sense THIS machine on EVERY host with the portable
  # sensor (Rule 05). The Omarchy-specific RECORDING (omarchy-sense observe), the
  # post-update hook, desktop placement, the plugin offer, and the desktop alarm
  # channel belong to the Omarchy layer and are applied by step_omarchy; nothing
  # here assumes Omarchy.
  local seen="unknown"
  if [ -x "$SCRIPT_DIR/../host/host-sense.sh" ]; then
    # host-sense TOON row 2 is: os, id, family, session, desktop
    local row; row="$("$SCRIPT_DIR/../host/host-sense.sh" 2>/dev/null | sed -n '2p')"
    [ -n "$row" ] && seen="$(printf '%s' "$row" | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//; s/","/ \/ /g')"
  fi
  add host OK "host sensed: ${seen}"

  # The Eindri dispatch profile (D4, 2026-09-24). A shipped template that still
  # carries unfilled model tokens must never steer dispatch, and install must
  # not leave the template to look active. Derive a REAL profile from this
  # machine (config/agents.yaml + the pi catalog) into the hoard's config dir
  # once; the private override wins over the repo file thereafter.
  if [ -x "$SCRIPT_DIR/../fleet/dispatch-profile.sh" ] && [ -n "${HOARD:-}" ]; then
    local hoprofile="$HOARD/config/eindri-dispatch.json"
    if [ -f "$hoprofile" ]; then
      add dispatch-profile OK "kept (private override at $hoprofile)"
    elif [ "$CHECK" = 1 ]; then
      add dispatch-profile OK "derived at install (private override: $hoprofile)"
    elif mkdir -p "$HOARD/config" && "$SCRIPT_DIR/../fleet/dispatch-profile.sh" derive --out "$hoprofile" >/dev/null 2>&1; then
      add dispatch-profile OK "derived from this machine: $hoprofile"
    else
      add dispatch-profile WARN "could not derive $hoprofile (is config/agents.yaml present and pi installed?)"
    fi
  fi

  # The operator's own agent setup, seeded from the tracked template into the
  # home's settings dir — settings are the operator's, never the package's.
  # Idempotent: the seeded file is private and is never overwritten once set.
  # --check writes nothing, so it only reports. The template is code, so it is
  # read from wherever the tree keeps it: `config/` in a clone (a symlink the
  # npm tarball cannot carry), else `.agents/config/`.
  if [ -e "$YMIR_SETTINGS_DIR/agents.yaml" ]; then
    add agents-config OK "kept (private, never overwritten)"
    return 0
  fi
  local tpl="$ROOT/config/agents.yaml.example"
  [ -r "$tpl" ] || tpl="$ROOT/.agents/config/agents.yaml.example"
  if [ "$CHECK" = 1 ]; then
    add agents-config WARN "not seeded yet — a real run writes $YMIR_SETTINGS_DIR/agents.yaml"
  elif [ -r "$tpl" ] && mkdir -p "$YMIR_SETTINGS_DIR" && cp "$tpl" "$YMIR_SETTINGS_DIR/agents.yaml" 2>/dev/null; then
    add agents-config OK "seeded $YMIR_SETTINGS_DIR/agents.yaml from the template"
  else
    add agents-config WARN "could not seed $YMIR_SETTINGS_DIR/agents.yaml"
  fi
}



# ── the machine's profile (2026-10-20) ───────────────────────────────────────
# Probe what this box actually is before installing anything for it: OS, GPU,
# RAM, disk, tools, and the capabilities they imply. A missing capability is
# recorded as absent, never assumed (Rule 25).
step_profile() {
  if [ ! -x "$SCRIPT_DIR/../agents/profile.sh" ]; then add profile SKIP "no profile.sh"; return 0; fi
  if [ "$CHECK" = 1 ]; then add profile WARN "not probed in --check"; return 0; fi
  local out; out="$("$SCRIPT_DIR/../agents/profile.sh" probe 2>&1)" || { add profile WARN "$out"; return 0; }
  add profile OK "$(printf '%s' "$out" | tail -1)"
}


# ── the ward (2026-10-20) ────────────────────────────────────────────────────
# Security is measured and ASKED, never silently changed. The install reports the
# findings and writes the decisions; closing a door stays the Allfather's act.
step_ward() {
  if [ "$CHECK" = 1 ]; then add ward WARN "not audited in --check"; return 0; fi
  if [ -x "$SCRIPT_DIR/../ward/verdr.sh" ]; then
    "$SCRIPT_DIR/../ward/verdr.sh" report --no-alert >/dev/null 2>&1 || true
  fi
  if [ -x "$SCRIPT_DIR/../ward/ward-ask.sh" ]; then
    local out rc
    out="$("$SCRIPT_DIR/../ward/ward-ask.sh" 2>&1)"; rc=$?
    if [ "$rc" -eq 3 ]; then add ward WARN "$(printf '%s' "$out" | grep -c '^  "WARD-' | tr -d ' ') decision(s) waiting — bin/ward/ward-ask.sh"
    else add ward OK "nothing above the floor"; fi
  else add ward SKIP "no ward-ask.sh"; fi
}

# ── the seat's name (2026-10-20) ─────────────────────────────────────────────
# A seat must not inherit "Brokk". The roster is the one source; the registry is
# the collision system; --ensure asks, takes YMIR_SEAT_NAME, or refuses loudly.
step_identity() {
  if [ ! -x "$SCRIPT_DIR/../agents/seat-identity.sh" ]; then add identity SKIP "no seat-identity.sh"; return 0; fi
  local host; host="$(hostname -s)"
  if [ "$CHECK" = 1 ]; then add identity WARN "not installed in --check"; return 0; fi
  if [ -x "$SCRIPT_DIR/../agents/name-registry.sh" ]; then
    "$SCRIPT_DIR/../agents/name-registry.sh" scan >/dev/null 2>&1 || true
  fi
  local out rc
  out="$("$SCRIPT_DIR/../agents/seat-identity.sh" --ensure "$host" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then add identity OK "$out"; else add identity WARN "$out"; fi
}

# ── 3c-bis. the role — what this machine IS in the fleet (plan 51, P1) ────────
# Role is the one fact every surface derives from: install, update, the MCP
# config, the cron set, the model rail, and dispatch. It is resolved BEFORE the
# step chain (establish_roles) so the chain installs only this role's parts; this
# step reports what was resolved, records it in the fleet registry, and writes
# the machine card into the ONE registry (`hodd/data/machines.md`). A host that
# was nowhere declared and could not be asked is reported LOUDLY as the safe
# body (dev) — never silence, and never the union of every role's parts.
step_role() {
  local host="$ROLE_HOST" roles="$ROLE_SET" link="" card="" detail=""
  if [ ! -x "$SCRIPT_DIR/../skuld/role.sh" ]; then add role SKIP "no role.sh"; return 0; fi
  case "$ROLE_SRC" in
    env|registry|card|declared) detail="role: $roles (source: $ROLE_SRC)" ;;
    *) detail="no role declared — the safe body '$ROLE_SET'" ;;
  esac
  if [ -x "$SCRIPT_DIR/../fleet/topology.sh" ]; then
    link="$("$SCRIPT_DIR/../fleet/topology.sh" 2>/dev/null | sed -nE 's/^  "link","([^"]+)".*/\1/p')"
  fi
  # Record the declared role where the rest of the fleet reads it — a real run
  # only; --check writes nothing. The registry already has it when it answered.
  if [ "$CHECK" = 0 ] && [ "$ROLE_SRC" != registry ]; then
    "$SCRIPT_DIR/../skuld/role.sh" set "$host" "$ROLE_SET" >/dev/null 2>&1 || true
  fi
  if [ "$CHECK" = 0 ]; then card="$(machine_card_write "$host" "$ROLE_SET" "$ROLE_COMPONENTS" "$ROLE_SRC")"; fi
  detail="$detail${link:+ · link: $link} · components: $ROLE_COMPONENTS${card:+ · card: $card}"
  case "$ROLE_SRC" in
    env|registry|card|declared) add role OK "$detail" ;;
    *) add role WARN "$detail — declare it: --role <r>, or bin/skuld/role.sh set $host heart|forge|dev|hand" ;;
  esac
}

# ── 3d. the warden — Heimdall's ssh-key ward ─────────────────────────────────
# The seat admits its entrant by the rune they carry on GitHub
# (github.com/<user>.keys, validated, refreshed every 15 min). One published
# key opens every warded computer, Omarchy or Ubuntu — this is Heimdall's law.
# The ensure surface carries the ward: installs the script to a stable path
# (~/.local/bin), records the operator's GitHub user, fetches + merges the
# keys, and arms the refresh timer. Idempotent; --install may add openssh
# (sudo, system package), never silently.
step_heimdall() {
  if [ ! -x "$SCRIPT_DIR/../host/heimdall-ensure.sh" ]; then add heimdall SKIP "no heimdall-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if "$SCRIPT_DIR/../host/heimdall-ensure.sh" status >/dev/null 2>&1; then add heimdall OK "the ward stands — GitHub keys, 15-min refresh"
    else add heimdall WARN "the ward is not armed — a real run installs it"; fi
    return
  fi
  if "$SCRIPT_DIR/../host/heimdall-ensure.sh" ensure --install >/dev/null 2>&1; then
    add heimdall OK "ward armed — GitHub keys admitted, refresh timer live"
  else
    add heimdall WARN "run bin/host/heimdall-ensure.sh ensure --install (needs sudo for openssh?); or seat keys by hand (hodd/docs/ssh)"
  fi
}

# ── 3e. the fleet services (the heart's surfaces) ─────────────────────────────
# well-mcp (the served well) · ratatoskr A2A node · the mill worker · the
# embedding stone · the cards root — raised as user units from tools/, and the
# seat's pi mcp.json pointed at the served well. ROLE-GATED (plan 51): a seat
# rises exactly what its roles owe, one target (ymir.target) pulls the set at
# boot, and a program that cannot rise is a FAILURE with its reason — never a
# warn the install steps past (law, 2026-09-24).
step_fleet() {
  role_gate fleet heart,dev "the record offices and this body's doors" || return 0
  if [ ! -x "$SCRIPT_DIR/../fleet/fleet-ensure.sh" ]; then add fleet SKIP "no fleet-ensure.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    if "$SCRIPT_DIR/../fleet/fleet-ensure.sh" status >/dev/null 2>&1; then add fleet OK "services mapped — role-gated raise on a real run"
    else add fleet WARN "no user manager — a real run raises the role set"; fi
    return
  fi
  if "$SCRIPT_DIR/../fleet/fleet-ensure.sh" ensure >/dev/null 2>&1; then
    add fleet OK "role-owed services raised and verified (ymir.target enabled)"
  else
    add fleet FAIL "a role-owed service could not rise — run bin/fleet/fleet-ensure.sh ensure to see the unit and the reason"
  fi
}

# ── 3f. autoboot (the boot law) ──────────────────────────────────────────────
# Every Ymir program rises at boot, by itself — role-gated. This step asserts
# the two things that make that true: the ONE target is enabled (fleet-ensure
# did it) and the seat's user units survive a reboot (Linger, on a headless
# seat). The Linger value is reported here on EVERY seat — the DoD.
# ── 3g. Gróa, seated (one per install) ───────────────────────────────────────
# The updater arrives WITH the installation, not copied by hand. Her body is
# bin/agents/groa-agent/: a leashed OpenCode agent that wakes daily, asks Gróa's
# hands for a check, and fast-forwards only when they say so. A phone has no
# systemd; a checkout with no systemd is not hers to keep.
step_groa() {
  if [ ! -d "$SCRIPT_DIR/../agents/groa-agent" ]; then add groa SKIP "no groa-agent pack"; return; fi
  if ! have systemctl || [ ! -d /run/systemd/system ]; then add groa SKIP "no systemd on this host — the timer is a seat concern"; return; fi
  if [ "$CHECK" = 1 ]; then
    if systemctl --user list-unit-files groa-agent.timer 2>/dev/null | grep -q groa-agent.timer; then
      add groa OK "her timer is seated — daily wake, leashed"
    else
      add groa WARN "her timer is not seated — a real run seats it"
    fi
    return
  fi
  if "$SCRIPT_DIR/../agents/groa-agent/seat.sh" --quiet >/dev/null 2>&1; then
    add groa OK "seated — one Gróa per install (daily wake, leashed)"
  else
    add groa FAIL "could not seat her — run bin/agents/groa-agent/seat.sh to see why"
  fi
}

step_autoboot() {
  # A phone (Android/Termux) has no systemd and no loginctl; boot units are the
  # heart's concern. Report honestly and never dereference $USER — Termux leaves
  # it unset, and `set -u` turns that into a crash at step 19/27.
  local user="${USER:-$(id -un 2>/dev/null || printf '%s' unknown)}"
  if ! have loginctl || [ ! -d /run/systemd/system ]; then
    add autoboot SKIP "no systemd/loginctl on this host — boot services are the heart's"
    return 0
  fi
  local v=""
  v="$(loginctl show-user "$user" -p Linger 2>/dev/null | sed 's/^Linger=//')"
  case "$v" in yes) ;; *) v="no" ;; esac
  if [ "$CHECK" = 1 ]; then
    add autoboot OK "Linger=$v · would enable ymir.target + assert linger on a real run"
    return
  fi
  # A headless seat (heart/forge/server) has no login to raise its session:
  # without linger, every enabled user unit is dead until someone logs in —
  # and no surface says so. Enable it, or fail with the exact remedy.
  if [ "$v" = no ]; then
    if { [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ "$(ymir_os 2>/dev/null || echo other)" != macos ]; }; then
      if loginctl enable-linger "$user" 2>/dev/null; then
        v="$(loginctl show-user "$user" -p Linger 2>/dev/null | sed 's/^Linger=//')"; [ "$v" = yes ] || v="no"
        if [ "$v" = yes ]; then
          add autoboot OK "Linger enabled ($user) — headless boot services will rise"
          return
        fi
      fi
      add autoboot FAIL "Linger=no on a headless seat — boot services would never rise; remedy: sudo loginctl enable-linger $user"
      return
    fi
  fi
  add autoboot OK "Linger=$v — boot is role-gated and proven (bin/engine/ymir-autoboot.sh verify)"
}

# ── 4. sandbox image ─────────────────────────────────────────────────────────
step_sandbox() {
  role_gate sandbox forge,dev "Utgard — the build/farm sandbox" || return 0
  local engine; engine="$(ymir_container_engine_name 2>/dev/null || true)"
  if [ -z "$engine" ]; then add sandbox SKIP "no container engine (docker/podman)"; return; fi
  if "$engine" image inspect utgard-runner:latest >/dev/null 2>&1; then
    add sandbox OK "utgard-runner:latest present ($engine)"
  elif [ "$CHECK" = 1 ]; then
    add sandbox WARN "utgard-runner:latest missing (run without --check)"
  else
    # Distinguish "engine not reachable" from "build failed" so the operator gets
    # an actionable message instead of a blanket failure.
    if ! "$engine" info >/dev/null 2>&1; then
      local who; who="$(id -un)"
      if ymir_engine_is_podman 2>/dev/null; then
        add sandbox WARN "rootless podman unreachable — ensure a login session (loginctl enable-linger) and XDG_RUNTIME_DIR are set"
      elif id -nG "$who" 2>/dev/null | grep -qw docker; then
        add sandbox WARN "docker daemon unreachable — log out and back in so the docker group applies"
      else
        add sandbox WARN "docker permission denied — add $who to the docker group, then re-login"
      fi
      return
    fi
    if "$SCRIPT_DIR/../forge/utgard.sh" build >/dev/null 2>&1; then add sandbox OK "utgard-runner:latest built ($engine)"; else add sandbox WARN "image build failed (see $engine)"; fi
  fi
}

# ── 5. memory (well + harness MCP) ───────────────────────────────────────────
step_memory() {
  role_gate memory heart,dev "the well (the record's store · a body's door)" || return 0
  # The well is ONE memory and it lives in the hoard — always.
  if [ -n "${ENGRAM_DB:-}" ]; then
    local db="$ENGRAM_DB"
  else
    . "$SCRIPT_DIR/../vault/hoard-lib.sh" 2>/dev/null || true
    hoard_memory_store db
  fi
  local mcp=0
  [ "$CHECK" = 0 ] && "$SCRIPT_DIR/../bridge/mimir-bridge.sh" --start >/dev/null 2>&1 || true
  for f in "$ROOT/opencode.json" "$HOME/.config/opencode/opencode.json" "$HOME/.pi/agent/settings.json" "$HOME/.claude.json" "$HOME/.cursor/mcp.json"; do
    [ -f "$f" ] && grep -q '"engram"' "$f" 2>/dev/null && mcp=$((mcp+1))
  done
  local store="absent"; [ -f "$db" ] && store="present"
  add memory OK "engram store $store · MCP in $mcp harness configs"
}

# ── 5a2. the record — the heart's offices (plan 51 P1) ───────────────────────
# The record — the home, the engram store, the Runes ledger, the plans and the
# journal FOLD — lives on ONE machine: the heart. The fold receiver and the
# record crons are the heart's to run; a body that ran them would fork the chain
# (Law 7). So this step exists only where the heart does, and a body reports the
# SKIP with its reason — never a substituted install.
step_record() {
  role_gate record heart "the record (fold · store · record crons) lives on the heart" || return 0
  local db="" store="absent" fold="absent" crons="0" cronf=""
  command -v hoard_memory_store >/dev/null 2>&1 && hoard_memory_store db
  [ -n "$db" ] && [ -f "$db" ] && store="present"
  [ -x "$SCRIPT_DIR/../records/journal-receive.sh" ] && fold="present"
  command -v hoard_settings_dir >/dev/null 2>&1 && hoard_settings_dir cronf
  [ -n "$cronf" ] && [ -f "$cronf/cron.yaml" ] || cronf="$ROOT/.agents/config"
  [ -f "$cronf/cron.yaml" ] && crons="$(grep -c '@heart' "$cronf/cron.yaml" 2>/dev/null || printf 0)"
  if [ "$CHECK" = 1 ]; then
    add record OK "would hold the record — engram store $store · journal fold $fold · $crons record cron(s)"
    return
  fi
  if [ "$store" != present ] || [ "$fold" != present ]; then
    add record WARN "the record is incomplete — engram store $store, journal fold $fold (bin/bridge/mimir-bridge.sh --start)"
    return
  fi
  add record OK "holds the record — engram store $store · journal fold $fold · $crons record cron(s)"
}

# ── 5b. smidja db (visualizer readiness) ─────────────────────────────
step_smidja() {
  role_gate smidja heart,dev "the smithy" || return 0
  if [ -x "$SCRIPT_DIR/../desktop/smidja-bootstrap.sh" ]; then
    if [ "$CHECK" = 1 ]; then
      local dbok vizok
      [ -f "$YMIR_HOME/smidja/smidja.db" ] && dbok=present || dbok=missing
      [ -n "${SMIDJA_VIZ:-}" ] && [ -d "$SMIDJA_VIZ/dist" ] && vizok=built || vizok=unbuilt
      if [ "$dbok" = missing ]; then
        add smidja WARN "smidja.db missing — a full run (without --check) creates it and seeds one bootstrap session"
      else
        add smidja OK "smidja.db $dbok · visualizer UI $vizok"
      fi
    elif ! have uv; then
      # The bootstrap creates the schema through the tracer, run under uv so the
      # smidja deps resolve without a system install.
      add smidja WARN "needs uv — bin/engine/prereq-ensure.sh uv (the visualizer stays empty without it)"
    else
      if "$SCRIPT_DIR/../desktop/smidja-bootstrap.sh" >/dev/null 2>&1; then add smidja OK "smidja.db ready (visualizer has data)"; else add smidja WARN "could not bootstrap smidja.db — run bin/desktop/smidja-bootstrap.sh to see why"; fi
    fi
  else add smidja SKIP "no smidja-bootstrap.sh"; fi
  # The visualizer API serves its UI from ./dist — without a build it answers
  # the API but shows "No ./dist build found". Build it once when absent.
  local viz="${SMIDJA_VIZ:-}"; [ -n "$viz" ] || return 0
  [ -d "$viz" ] || return 0
  if [ -d "$viz/dist" ]; then
    add visualizer OK "UI built (served on :8437)"
  elif [ "$CHECK" = 1 ]; then
    add visualizer WARN "UI not built (run without --check)"
  elif command -v bun >/dev/null 2>&1; then
    if [ ! -d "$viz/node_modules" ] && ! (cd "$viz" && bun install >/dev/null 2>&1); then
      add visualizer WARN "bun install failed — (cd $viz && bun install)"
    elif (cd "$viz" && bun run build >/dev/null 2>&1); then
      add visualizer OK "UI built (served on :8437)"
    else
      add visualizer WARN "UI build failed — (cd $viz && bun run build)"
    fi
  else
    add visualizer WARN "no bun — cannot build the visualizer UI"
  fi
}

# ── 5c. the SPA ──────────────────────────────────────────────────────────────
# Hlidskjalf installs with npm (its own lockfile), not bun, and its API serves the
# UI from ./dist. Without this step a fresh clone has no SPA and no build.
step_spa() {
  role_gate hlidskjalf heart,dev "the control plane (Hlidskjalf)" || return 0
  local app; app_dir hlidskjalf app || app=""
  local app_ok="$app"
  [ -d "$app" ] || { add hlidskjalf SKIP "no apps/hlidskjalf"; return 0; }
  if [ "$CHECK" = 0 ]; then
    if ! have npm; then
      add hlidskjalf WARN "no npm — cannot install the SPA"; return 0
    fi
    if [ ! -d "$app/node_modules" ] && ! (cd "$app" && npm install --no-audit --no-fund >/dev/null 2>&1); then
      add hlidskjalf WARN "npm install failed — (cd $app && npm install --no-audit --no-fund)"; return 0
    fi
    if [ ! -d "$app/dist" ] && ! (cd "$app" && npm run build >/dev/null 2>&1); then
      add hlidskjalf WARN "installed, build failed — (cd $app && npm run build)"; return 0
    fi
  fi
  if [ ! -d "$app/node_modules" ] || [ ! -d "$app/dist" ]; then
    add hlidskjalf WARN "not installed (run without --check)"; return 0
  fi
  # Electron's runtime comes from a gated postinstall. package.json pins the
  # approval, but verify the binary so the desktop shell never fails silently.
  # The answer comes from the resolver (P1): app-local, workspace-hoisted, or
  # the sibling package — never one hardcoded path.
  if [ "$(electron_runtime_state "$app" "$ROOT" "$(app_pkg hlidskjalf)" 2>/dev/null || echo absent)" = ok ]; then
    add hlidskjalf OK "installed + built + electron (served on :3888)"
  else
    add hlidskjalf WARN "installed + built, but electron has no binary — npm rebuild electron"
  fi
}

# ── 5i. the council of models ────────────────────────────────────────────────
# Plan 92. The extension ships in `.pi/extensions/logretta/`, but a council with no
# stack is a loud skip — and plan 66 §7 is the law here: a feature is not done when its
# code exists, it is done when the install seats it. The ensure door seeds the roster
# from the template ONLY when the home has none; an existing stack is the operator's
# models and is never overwritten.
step_council() {
  local ens="$SCRIPT_DIR/../pi/logretta-ensure.sh"
  [ -x "$ens" ] || { add council SKIP "no logretta-ensure.sh"; return; }
  if [ "$CHECK" = 1 ]; then
    add council OK "would seat the council's roster (<home>/config/logretta-stack.yaml) if absent"
    return
  fi
  if out="$("$ens" ensure 2>&1)"; then
    if printf '%s' "$out" | grep -q '"seeded"'; then
      add council OK "roster seeded — name YOUR models: logretta_stack"
    else
      add council OK "roster already seated"
    fi
  else
    add council WARN "the council's roster is invalid — run bin/pi/logretta-ensure.sh status"
  fi
}

# ── 6. loaders ───────────────────────────────────────────────────────────────
step_loaders() {
  if [ -x "$SCRIPT_DIR/../seat/valknut-load.sh" ]; then
    if [ "$CHECK" = 1 ]; then add loaders OK "valknut-load.sh present"; else
      # Rule: a seat that cannot be seated is not installed. This warned and
      # carried on, which is how a capability exists in the repo and is silently
      # absent on the machine (plan 66 §7).
      if "$SCRIPT_DIR/../seat/valknut-load.sh" >/dev/null 2>&1; then
        add loaders OK "agents/skills/extensions loaded"
      else
        add loaders FAIL "the seat could not be seated — run bin/seat/valknut-load.sh --status"
      fi

      # The phone gateway (plan 68 P1). Installed and UPDATED, not just written: a capability
      # that is committed and never seated is the exact failure this file already fails on
      # (see the Rule comment above), so the gateway gets the same treatment as the extensions —
      # its adopted dependency is installed, and it is PROVEN by its own smoke test before this
      # install is allowed to call itself done.
      if [ "$CHECK" = 1 ]; then
        add gateway OK "ymir-gateway present (tools/ymir-gateway)"
      else
        ( cd "$SCRIPT_DIR/tools/ymir-gateway" 2>/dev/null \
            && npm i --no-audit --no-fund @agentclientprotocol/sdk >/dev/null 2>&1 ) || true
        if bash "$SCRIPT_DIR/tools/ymir-gateway/smoke.sh" >/dev/null 2>&1; then
          add gateway OK "ymir-gateway seated and its smoke test answers"
        else
          add gateway FAIL "ymir-gateway smoke test failed — run bash tools/ymir-gateway/smoke.sh"
        fi
      fi
      # Seat the post-merge rebind hook as well. Pi loads its extensions from
      # ${HOME}/.pi/agent/extensions/, so a merged extension fix stays invisible
      # to the running harness unless the bind re-runs. No install and no update
      # should leave the surfaces stale.
      "$SCRIPT_DIR/../seat/valknut-load.sh" --install >/dev/null 2>&1 \
        && add loaders OK "post-merge rebind hook seated" \
        || add loaders WARN "post-merge hook not seated"
    fi
  else add loaders SKIP "no valknut-load.sh"; fi
}

# ── opencode V2 plugin: Ymir tools as first-class OpenCode tools & commands (Plan 109)
step_opencode_v2_plugin() {
  # Tier 0, not a dev privilege: the harness integration is what makes Ymir exist for an OpenCode user
  # (RULES/25, 2026-11-02 — the tiers). Gate on the harness being installed, never on a fleet role.
  have opencode || { add opencode-v2-plugin SKIP "no opencode on this host — nothing to integrate with"; return 0; }
  local plugin_dir="$ROOT/.opencode/plugins"
  local target_dir="${HOME}/.config/opencode/plugins"
  local tool_file="ymir-tools.ts"
  local pkg_file="package.json"
  
  if [ ! -f "$plugin_dir/$tool_file" ] || [ ! -f "$plugin_dir/$pkg_file" ]; then
    add opencode-v2-plugin SKIP "source plugin not found in $plugin_dir"
    return
  fi
  
  if [ "$CHECK" = 1 ]; then
    if [ -f "$target_dir/$tool_file" ] && [ -f "$target_dir/$pkg_file" ]; then
      # Verify they're identical
      if diff -q "$plugin_dir/$tool_file" "$target_dir/$tool_file" >/dev/null 2>&1 && \
         diff -q "$plugin_dir/$pkg_file" "$target_dir/$pkg_file" >/dev/null 2>&1; then
        add opencode-v2-plugin OK "V2 plugin deployed and current"
      else
        add opencode-v2-plugin WARN "V2 plugin deployed but stale (run without --check to update)"
      fi
    else
      add opencode-v2-plugin WARN "V2 plugin not deployed (run without --check to deploy)"
    fi
    return
  fi
  
  # Deploy to global plugin directory
  mkdir -p "$target_dir"
  cp "$plugin_dir/$tool_file" "$target_dir/"
  cp "$plugin_dir/$pkg_file" "$target_dir/"
  
  # Verify deployment
  if [ -f "$target_dir/$tool_file" ] && [ -f "$target_dir/$pkg_file" ]; then
    add opencode-v2-plugin OK "V2 plugin deployed to ~/.config/opencode/plugins/"
  else
    add opencode-v2-plugin FAIL "could not deploy V2 plugin"
  fi
}

# ── Codex plugin: the same Ymir doors, served through stdio MCP ──────────────
step_codex_plugin() {
  have codex || { add codex-plugin SKIP "no codex on this host — nothing to integrate with"; return 0; }
  have node || { add codex-plugin FAIL "node is required for the Codex plugin"; return 0; }
  local door="$SCRIPT_DIR/../seat/codex-plugin-install.mjs" output
  [ -f "$door" ] || { add codex-plugin FAIL "the Codex plugin installer is missing from this package"; return 0; }
  local args=(); [ "$CHECK" = 1 ] && args+=(--check)
  if output="$(node "$door" "${args[@]}" 2>&1)"; then
    add codex-plugin OK "$output"
  else
    add codex-plugin FAIL "$output"
  fi
}

# ── 6b. delivery gates (git hooks) ───────────────────────────────────────────
#
# Rule 08: work leaves by PR, and every push carries a fix note. The
# guards live in bin/ (branch-guard, fixes-guard, secret-guard) but git
# only reads .git/hooks, so the install seats them there — the gate is live
# from the first commit of a fresh clone. Idempotent: each --install rewrites
# its own hook.
# ── 6a. the vault — Hnitbjörg, the encrypted document stronghold ─────────────
# A LUKS2 container, sealed by default, opened only with sudo and the operator's
# passphrase. This step ensures cryptsetup and the vault directory; it NEVER
# creates a vault — init asks for a passphrase only the operator may type.
step_vault() {
  local ens="$SCRIPT_DIR/../vault/hnitbjorg-ensure.sh"
  [ -x "$ens" ] || { add vault SKIP "no hnitbjorg-ensure.sh"; return; }
  if [ "$CHECK" = 1 ]; then
    add vault OK "would ensure cryptsetup + the vault path (init offered, never automatic)"
    return
  fi
  if "$ens" ensure --install >/dev/null 2>&1; then
    . "$SCRIPT_DIR/../vault/hoard-lib.sh" 2>/dev/null || true
    local home="" img="" state="absent"
    command -v ymir_home_root >/dev/null 2>&1 && ymir_home_root home
    if [ -n "$home" ]; then
      img="${YMIR_VAULT_DIR:-$home/vault}/hnitbjorg.img"
      [ -e "$img" ] && state="sealed"
    fi
    add vault OK "cryptsetup present · vault $state (init: bin/vault/hnitbjorg.sh init)"
  else
    add vault WARN "cryptsetup absent — bin/vault/hnitbjorg-ensure.sh ensure --install"
  fi
}

step_room() {
  # Gladsheim — the fleet room (plan 73/75). ROLE-AWARE by construction: the engine runs
  # ONCE per operator install — here on a lone box, on the HEART in a fleet — and every
  # other seat is a client that skips cleanly. gladsheim-ensure.sh asks the ONE shape
  # resolver (bin/fleet/topology.sh) rather than re-deriving it (plan 76).
  local ens="$SCRIPT_DIR/../room/gladsheim-ensure.sh"
  [ -x "$ens" ] || { add room SKIP "no gladsheim-ensure.sh"; return; }
  if [ "$CHECK" = 1 ]; then
    add room OK "would seat the room's role for this machine's shape (engine on the heart; client on a seat)"
    return
  fi
  if "$ens" ensure >/dev/null 2>&1; then
    local role="engine"; "$ens" status 2>/dev/null | grep -q '"holds_engine","no"' && role="client"
    add room OK "the room's role is seated ($role) · bin/room/gladsheim.sh send|read"
  else
    add room WARN "could not seat the room — bin/room/gladsheim-ensure.sh ensure"
  fi
}

step_gates() {
  local hooks="$ROOT/.git/hooks" pre_commit="$ROOT/.git/hooks/pre-commit" pre_push="$ROOT/.git/hooks/pre-push"
  if [ ! -d "$hooks" ]; then add gates SKIP "not a git checkout"; return; fi
  if [ "$CHECK" = 1 ]; then
    if [ -x "$pre_commit" ] && [ -x "$pre_push" ]; then
      add gates OK "pre-commit + pre-push installed"
    else
      add gates WARN "hooks not installed — bin/gates/guards/secret-guard.sh --install && bin/gates/guards/fixes-guard.sh --install"
    fi
    # The home repo is where the private data lives, so its ward matters more
    # than this repo's four. Report it separately so a dormant vault is visible.
    local hh; hh="${YMIR_HOME}/.git/hooks/pre-commit"
    if [ -x "$hh" ]; then add hoard-gate OK "home pre-commit seated";
    else add hoard-gate WARN "home hooks not installed — bin/gates/guards/hoard-guard.sh --install"; fi
    return
  fi
  [ -x "$SCRIPT_DIR/../gates/guards/secret-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/secret-guard.sh" --install >/dev/null 2>&1 || true
  [ -x "$SCRIPT_DIR/../gates/guards/fixes-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/fixes-guard.sh" --install >/dev/null 2>&1 || true
  # Seat the ward on the PRIVATE home too — every install layer, every machine.
  [ -x "$SCRIPT_DIR/../gates/guards/hoard-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/hoard-guard.sh" --install >/dev/null 2>&1 || true
  if [ -x "$pre_commit" ] && [ -x "$pre_push" ]; then add gates OK "pre-commit + pre-push installed"
  else add gates WARN "could not write .git/hooks — gates are dormant"; fi
  local hh; hh="${YMIR_HOME}/.git/hooks/pre-commit"
  if [ -x "$hh" ]; then add hoard-gate OK "home pre-commit seated";
  else add hoard-gate WARN "home hooks not seated — bin/gates/guards/hoard-guard.sh --install"; fi
}

# ── 6c. desktop marks (the rune, the entry, the contract) ────────────────────
#
# Every app wears its OWN rune in the operator's desktop: the icon into the icon
# theme, the .desktop entry into their applications dir (so every app is
# dockable and pinnable), and the Ymir contract deployed into pi's agent home so
# every session - in ANY folder - loads Brokk. Idempotent, and it writes to the
# operator's real data dir, never a sandbox one.
step_marks() {
  role_gate marks dev "the dev desktop layer" || return 0
  if [ ! -x "$SCRIPT_DIR/../desktop/design-icon.sh" ]; then add marks SKIP "no design-icon.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    # A check reports what is TRUE, not what reassures: count the entries really on
    # disk, and name the halls that are not.
    local cw=(hlidskjalf odrerir sessrumnir smidja) cn=0 cgone=""
    for v in "${cw[@]}"; do
      if [ -f "$HOME/.local/share/applications/ymir-$v.desktop" ]; then cn=$((cn+1)); else cgone="$cgone $v"; fi
    done
    if [ "$cn" -eq "${#cw[@]}" ]; then
      add marks OK "${cn} desktop app marks installed"
    else
      add marks WARN "${cn}/${#cw[@]} desktop app marks - missing:$cgone (run without --check to write them)"
    fi
    return
  fi
  # The apps' own launcher templates land first (the freedesktop half of desktop
  # integration, for ANY Linux desktop), and the rune marks are minted and
  # installed over them — so the themed rune name wins for the surfaces that have
  # one, instead of a template's absolute .png.
  if [ -x "$SCRIPT_DIR/../desktop/desktop-place.sh" ]; then
    "$SCRIPT_DIR/../desktop/desktop-place.sh" entries >/dev/null 2>&1 || true
  fi
  "$SCRIPT_DIR/../desktop/design-icon.sh" mint --all >/dev/null 2>&1 || true
    "$SCRIPT_DIR/../desktop/design-icon.sh" install >/dev/null 2>&1 || true
    [ -r "$HOME/.pi/agent/AGENTS.md" ] || [ -d "$HOME/.pi/agent" ] && {
      ln -sfn "$ROOT/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" 2>/dev/null || true
    }
    # VERIFY, never claim. This step once reported four marks while Smidja's entry had
    # never been written: it counted what design-icon.sh PRINTED, not what landed. A
    # mark is present when its file is on disk, executable, with an Exec that resolves
    # and an Icon the theme carries.
    local want=(hlidskjalf odrerir sessrumnir smidja) missing=0 weak=0 gone=""
    for v in "${want[@]}"; do
      f="$HOME/.local/share/applications/ymir-$v.desktop"
      if [ ! -f "$f" ]; then missing=$((missing+1)); gone="$gone $v"; continue; fi
      [ -x "$f" ] || chmod +x "$f" 2>/dev/null || true
      exe="$(sed -n 's/^Exec=//p' "$f" | head -1 | awk '{print $1}')"
      ico="$(sed -n 's/^Icon=//p' "$f" | head -1)"
      { [ -n "$exe" ] && [ -x "$exe" ]; } || weak=$((weak+1))
      [ -f "$HOME/.local/share/icons/hicolor/scalable/apps/$ico.svg" ] || weak=$((weak+1))
    done
    local total=${#want[@]}
    if [ "$missing" -gt 0 ]; then
      add marks WARN "$((total-missing))/$total marks - MISSING:$gone (checked the files, not a log line)"
    elif [ "$weak" -gt 0 ]; then
      add marks WARN "$total marks present but $weak do not resolve (Exec or Icon)"
    else
      add marks OK "$total marks verified - entry + glyph + resolvable Exec, each hall"
    fi
}

# ── 7. services ──────────────────────────────────────────────────────────────
step_services() {
  role_gate services heart,dev "the role's web stack" || return 0
  [ "$SKIP_SERVICES" = 1 ] && { add services SKIP "--skip-services"; return; }
  if [ "$CHECK" = 1 ]; then
    local up=0
    for p in 3888 3889 4602 4603; do (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && up=$((up+1)); done
    add services OK "$up/4 ports up (3888/3889/4602/4603)"; return
  fi
  # The web stack is SEATED as user units on dev seats (hlidskjalf-spa · gate ·
  # mimir · bifrost · smidja, all joined to ymir.target and raised by the fleet
  # step above) — the old "run scripts/start.sh and hope" road is retired. This
  # step PROVES the raise: the boot proof reads systemd directly and exits
  # non-zero when a role-owed program is not enabled. Desktop windows stay on
  # demand; the services are what boot owes.
  if out="$("$SCRIPT_DIR/ymir-autoboot.sh" verify 2>&1)"; then
    add services OK "autoboot verified — every dev-seat service is enabled and standing"
  else
    local nbad; nbad="$(printf '%s' "$out" | grep -cE '"disabled"|"failed"|"inactive"' || true)"
    add services FAIL "boot proof failed ($nbad program(s)) — bin/engine/ymir-autoboot.sh verify names them"
  fi
}

# ── 7b. desktop (both Electron apps) ──────────────────────────
# The operator should SEE the applications when the install finishes, so we
# raise both desktop shells (Hlidskjalf + Smíðja) as separate processes.
step_desktop() {
  role_gate desktop dev "the dev desktop layer" || return 0
  if [ "$NO_DESKTOP" = 1 ]; then add desktop SKIP "--no-desktop"; return; fi
  if [ ! -x "$ROOT/scripts/electron.sh" ]; then add desktop SKIP "no scripts/electron.sh"; return; fi
  if [ "$CHECK" = 1 ]; then
    # A check probes: every surface must RESOLVE an executable runtime and be
    # routed by the right class (bin/desktop/desktop-verify.sh — read-only, few
    # seconds). Fails loudly, naming the surface and the resolved path.
    if [ -x "$ROOT/bin/desktop/desktop-verify.sh" ]; then
      if out="$("$ROOT/bin/desktop/desktop-verify.sh" 2>&1)"; then
        add desktop OK "verified: every surface resolves a runnable Electron and is routed right"
      else
        add desktop FAIL "$(printf '%s' "$out" | grep -m1 'FAIL' | sed 's/^  //')"
      fi
    else
      add desktop OK "would verify + launch the desktop shells"
    fi
    return
  fi
  # A headless host has no display; launching a window would only fail.
  # DISPLAY/WAYLAND_DISPLAY are X11/Wayland variables — macOS has a display and
  # neither of them, so testing only those would wrongly skip every Mac.
  if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ "$(ymir_os)" != macos ]; then
    add desktop SKIP "no display (headless) — run scripts/electron.sh start --both"; return
  fi
  # P4 (2026-09-24): the INSTALL-TIME guarantee — before any window is claimed,
  # every surface must resolve an executable runtime that ANSWERS --version and
  # is routed by the right class. A runtime that is merely absent is a FAILURE,
  # never the old silent SKIP: the launcher must not proceed into a path that
  # npm will never make.
  if [ -x "$ROOT/bin/desktop/desktop-verify.sh" ]; then
    local vout vrc
    vout="$("$ROOT/bin/desktop/desktop-verify.sh" 2>&1)"
    vrc=$?
    if [ "$vrc" != 0 ]; then
      add desktop FAIL "$(printf '%s' "$vout" | grep -m1 'FAIL' | sed 's/^  //')"
      return 0
    fi
  fi
  # One window per surface that is here: the halls are not one app.
  raised=0
  for _v in hlidskjalf smidja odrerir; do
    "$ROOT/scripts/electron.sh" start --view "$_v" >/dev/null 2>&1 && raised=$((raised+1))
  done
  [ -x "$ROOT/bin/desktop/sessrumnir-launch.sh" ] && "$ROOT/bin/desktop/sessrumnir-launch.sh" start >/dev/null 2>&1 && raised=$((raised+1))
  if [ "$raised" -ge 2 ]; then
    add desktop OK "verified + raised $raised window(s) — Hlidskjalf · Smíðja · Óðrerir · Sessrúmnir"
  else
    add desktop WARN "could not raise every desktop app — ymir hlidskjalf | smidja | sessrumnir"
  fi
  # The routing is then proven LIVE (P5): with the windows up, the compositor
  # must actually hold each surface's class. One retry lets a slow map settle.
  if [ -x "$ROOT/bin/desktop/desktop-verify.sh" ] && command -v hyprctl >/dev/null 2>&1; then
    local t=0
    while [ "$t" -lt 2 ] && ! "$ROOT/bin/desktop/desktop-verify.sh" --live >/dev/null 2>&1; do
      t=$((t+1)); sleep 3
    done
    if ! "$ROOT/bin/desktop/desktop-verify.sh" --live >/dev/null 2>&1; then
      add desktop FAIL "a raised surface's window is missing its class on the compositor — bin/desktop/desktop-verify.sh --live names it"
    fi
  fi
}

# ── 8. register ──────────────────────────────────────────────────────────────
# ── 8b. the way in ────────────────────────────────
# One operator owns the instance; an invite code is how someone *else* is let in
# to try it. Registration stays closed until a live code exists, so the gate is
# never open by accident.
step_invite() {
  role_gate invite heart,dev "the control plane's way in" || return 0
  if [ "$CHECK" = 1 ]; then add invite OK "would mint an invite code"; return; fi
  if [ ! -x "$ROOT/bin/engine/ymir-invite.sh" ]; then add invite SKIP "bin/engine/ymir-invite.sh not executable"; return; fi
  if ! command -v bun >/dev/null 2>&1; then add invite SKIP "bun missing — no account store"; return; fi
  local out
  if ! out=$(bash "$ROOT/bin/engine/ymir-invite.sh" ensure 2>&1); then add invite WARN "could not mint a code"; return; fi
  INVITE_CODE=$(printf '%s\n' "$out" | sed -n '2p' | tr -d ' "' | cut -d, -f1)
  if [ -n "$INVITE_CODE" ]; then add invite OK "invite ${INVITE_CODE} — share it to let someone register"; else add invite WARN "no code found"; fi
}

# ── 8a. the operator's way in ────────────────────────────────────────────────
# The gate has two doors — a local password (HLIDSKJALF_AUTH) or GitHub sign-in
# (a GitHub OAuth app). Neither is seeded by a checkout, so a fresh instance has
# no way in until the operator sets one. Interactive installs prompt; --yes and
# non-tty leave it to bin/engine/ymir-setup-auth.sh.
step_auth() {
  role_gate auth heart,dev "the control plane's way in" || return 0
  if [ ! -x "$ROOT/bin/engine/ymir-setup-auth.sh" ]; then add auth SKIP "bin/engine/ymir-setup-auth.sh not executable"; return; fi
  local door
  door=$(bash "$ROOT/bin/engine/ymir-setup-auth.sh" status 2>/dev/null | sed -n '2p' | cut -d, -f1 | tr -d ' "')
  if [ -n "$door" ] && [ "$door" != none ]; then add auth OK "operator credential present ($door)"; return; fi
  if [ "$CHECK" = 1 ]; then add auth WARN "no operator credential — run bin/engine/ymir-setup-auth.sh set|github"; return; fi
  if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then
    add auth WARN "no operator credential — set one: bin/engine/ymir-setup-auth.sh set (or github)"
    return
  fi
  printf '\nSet the operator credential now? [p]assword / [g]ithub / [s]kip: '
  local choice; IFS= read -r choice || true
  case "${choice:-s}" in
    p|P) bash "$ROOT/bin/engine/ymir-setup-auth.sh" set && add auth OK "operator password set" || add auth WARN "password setup failed" ;;
    g|G) bash "$ROOT/bin/engine/ymir-setup-auth.sh" github && add auth OK "GitHub sign-in configured" || add auth WARN "GitHub setup failed" ;;
    *)   add auth SKIP "left unset — run bin/engine/ymir-setup-auth.sh set|github later" ;;
  esac
}

step_register() {
  if [ "$CHECK" = 1 ]; then add register OK "would write workspace/INSTALL.md"; return; fi
  local out="$WORKSPACE/INSTALL.md"
  {
    printf '# Ymir — first setup\n\n'
    printf 'Provisioned by `bin/engine/ymir-install.sh` at %s.\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '## Workspaces\n\n'; printf -- '- personal\n\n'
    printf '## Engines\n\n- Yggdrasil → treehouse\n- Utgard → sandcastle\n- Mjollnir/Glitnir → no-mistakes\n- Hermes → hermes-agent (worker runtime)\n- Sessrúmnir → pi-desktop (desktop GUI, vendored at apps/sessrumnir)\n\n'
    printf '## Next\n\n1. `gh auth login` (your own GitHub login).\n'
    printf '2. Register your projects and their `git{}` blocks in `hoard/identity/projects.yaml`.\n'
    printf '3. The services rise at boot (role-gated; `bin/engine/ymir-autoboot.sh status` shows them).\n'
    printf '   `scripts/start.sh` remains the manual raise when a window is wanted.\n'
    printf '4. To let someone else try it, share the invite code printed above\n'
    printf '   (or mint another: `bin/engine/ymir-invite.sh mint <n>`). They register at the\n'
    printf '   login screen; `bin/engine/ymir-invite.sh list` shows what is spent.\n'
  } >"$out"
  add register OK "wrote workspace/INSTALL.md"
}

# ── 9. validate ───────────────────────────────────
# Prove the installation actually works: live ports, readable stores, running
# processes. The installer says what it did; this observes the result.
step_validate() {
  # The final gate proves the BOOT as well as the running system: ymir-validate
  # checks live ports/stores; the autoboot proof checks that every role-owed
  # program would RISE at boot (enabled + standing). Both must pass for the
  # install to claim "it stands".
  if [ ! -x "$SCRIPT_DIR/ymir-validate.sh" ] || [ ! -x "$SCRIPT_DIR/ymir-autoboot.sh" ]; then
    add validate SKIP "no ymir-validate.sh / ymir-autoboot.sh"; return
  fi
  if [ "$CHECK" = 1 ]; then add validate OK "would verify the running system and the boot proof"; return; fi
  local boot_ok=1 live_ok=0 out nf
  if "$SCRIPT_DIR/ymir-autoboot.sh" verify --quiet >/dev/null 2>&1; then boot_ok=0; fi
  if out="$("$SCRIPT_DIR/ymir-validate.sh" --quiet 2>&1)"; then live_ok=1; else nf="$(printf '%s' "$out" | grep -oE '[0-9]+ required check\(s\) failed' | head -1)"; fi
  if [ "$boot_ok" = 0 ] && [ "$live_ok" = 1 ]; then
    add validate OK "all checks pass — the roll is verified (bin/engine/ymir-autoboot.sh verify)"
  else
    local why=""
    [ "$boot_ok" = 1 ] && why="boot proof failed — bin/engine/ymir-autoboot.sh verify"
    [ -n "$why" ] && [ "$live_ok" = 0 ] && why="$why; "
    [ "$live_ok" = 0 ] && why="${why}${nf:-some live checks} failed — bin/engine/ymir-validate.sh"
    add validate WARN "$why"
  fi
}

# ── 0. herdr panes (visible when inside herdr) ──────────────
# When the Allfather sits within herdr, the install should be SEEN: a pane is
# raised for the run and the steps are executed within it. Outside herdr this is
# a clean fall-through — the same steps, no panes. Nothing here can lose work:
# if a pane cannot be made, the caller runs its command inline.
step_panes() {
  local runner="$SCRIPT_DIR/../seat/herdr-run.sh"
  if [ ! -x "$runner" ]; then add panes SKIP "no herdr-run.sh"; return; fi
  if ! "$runner" available >/dev/null 2>&1; then
    add panes SKIP "no herdr session — steps run inline"
    return
  fi
  if [ "$CHECK" = 1 ]; then
    add panes OK "herdr present — steps would run in visible panes"
    return
  fi
  # Keep the panes the run makes, so the Allfather can read them afterwards.
  YMIR_HERDR_KEEP=1 "$runner" run "install" -- bash -c \
    'echo "Ymir first setup begins $(date -u +%H:%M:%SZ)"; echo "the steps follow in this pane"; echo "repo: $PWD"' \
    >/dev/null 2>&1 && add panes OK "run shown in a herdr pane" || add panes WARN "could not raise a herdr pane"
}

# Ask before touching the machine; --check only previews and never asks.
[ "$CHECK" = 0 ] && confirm_install

# Resolve what this machine IS — BEFORE any step runs, because the role picks the
# component set the whole chain installs (plan 51 P1). This asks when nothing is
# declared and a person is present; otherwise it takes the documented safe body.
establish_roles
[ "$CHECK" = 0 ] && style_patience "the halls are being stood up for the first time"

# ── progress ─────────────────────────────────────────────────────────────────
# The install takes minutes; a user must SEE work rather than silence. Each step
# announces itself before it runs and reports its elapsed time after, so a slow step
# reads as work and a hung one is obvious. Progress goes to stderr: the TOON report
# on stdout stays clean for anything that parses it.
# The step count is the number of `^run_step ` calls below — counted from THIS file so
# adding a step cannot silently drift the [N/M] counter (it read 29/27 after the last
# three steps were added, and the spoken count once said 19). Falls back to a literal
# when the script cannot read itself (e.g. piped from curl | bash).
# The hound: auditd senses + two units. It needs root for the system unit and the
# audit rules, so a machine without passwordless sudo reports a clean skip rather
# than pretending. Its settings are the operator's, in the hoard.
step_garmr() {
  local door="$ROOT/bin/ward/garmr.sh"
  [ -x "$door" ] || { add garmr SKIP "bin/ward/garmr.sh is absent"; return 0; }
  if sudo -n true 2>/dev/null; then
    bash "$door" install >/dev/null 2>&1 && add garmr OK "senses armed, hound and brain seated" \
      || add garmr WARN "install failed — run bin/ward/garmr.sh install by hand"
  else
    add garmr SKIP "needs one sudo — run: bin/ward/garmr.sh install"
  fi
}

STEP_TOTAL="$(grep -c '^run_step ' "${BASH_SOURCE[0]}" 2>/dev/null || true)"
case "$STEP_TOTAL" in ''|0|*[!0-9]*) STEP_TOTAL=29 ;; esac
STEP_N=0
run_step() {  # <runner-function> <label spoken to the user>
  STEP_N=$((STEP_N + 1))
  local t0=$SECONDS
  if [ -t 2 ]; then
    # A terminal: rewrite one line in place, so the list stays short and alive.
    printf '\r\033[K  [%2d/%2d] %s …' "$STEP_N" "$STEP_TOTAL" "$2" >&2
    "$1"
    printf '\r\033[K  [%2d/%2d] %s — %ss\n' "$STEP_N" "$STEP_TOTAL" "$2" "$((SECONDS - t0))" >&2
  else
    # Piped or logged: one plain line each, no escapes, so a log reads clean.
    printf '  [%2d/%2d] %s …\n' "$STEP_N" "$STEP_TOTAL" "$2" >&2
    "$1"
    printf '  [%2d/%2d] %s — %ss\n' "$STEP_N" "$STEP_TOTAL" "$2" "$((SECONDS - t0))" >&2
  fi
}

run_step step_panes "panes"
run_step step_prereqs "prerequisites"
run_step step_home "home"
run_step step_tree "workspace tree"
run_step step_clients "the client register"
run_step step_apps "apps"
run_step step_engines "engines"
run_step step_models "models"
run_step step_local_model "the local model"
run_step step_hermes "hermes"
run_step step_profile "the machine's profile"
run_step step_identity "the seat's name"
run_step step_ward "the ward"
run_step step_snotra "the meeting ear"
run_step step_voice "the voice engines"
run_step step_a2a "the A2A mesh"
run_step step_room "the room"
run_step step_sessrumnir "the seat"
run_step step_backend "backend"
run_step step_host "host"
run_step step_role "role"
run_step step_heimdall "the warden"
run_step step_fleet "fleet services"
run_step step_autoboot "autoboot"
run_step step_groa "Gróa, the updater"
run_step step_sandbox "sandbox"
run_step step_memory "memory"
run_step step_record "the record"
run_step step_smidja "the smithy"
run_step step_spa "the spa"
run_step step_omarchy "omarchy layer"
run_step step_loaders "loaders"
  run_step step_opencode_v2_plugin "opencode V2 plugin"
run_step step_codex_plugin "Codex plugin"
  run_step step_council "the council of models"
run_step step_vault "the vault"
run_step step_garmr "the hound"
run_step step_gates "gates"
run_step step_marks "marks"
# Migrations MOVE private data — that is a write, and `--check` promises none.
# Only a real run heals the home forward; the preview leaves it untouched.
if [ "$CHECK" = 0 ]; then bin/engine/ymir-migrate.sh apply >/dev/null 2>&1 || true; fi
step_auth; step_invite; step_register
[ "$CHECK" = 0 ] && step_services
[ "$CHECK" = 0 ] && step_desktop
[ "$CHECK" = 0 ] && step_validate

# The panes were raised for the Allfather to read; leave them standing when we
# made them, and close them only when the operator asks (herdr-run close-all).

printf 'install[%d]{step,status,detail}:\n' "${#IDS[@]}"
for i in "${!IDS[@]}"; do printf '  "%s","%s","%s"\n' "${IDS[$i]}" "${STATUS[$i]}" "${DETAIL[$i]}"; done
# The same rows, rendered for the eye (stderr) — the TOON above is the data a
# script reads, this is what a person gets. An install that ends in a raw table
# has no design, and design here is not decoration: it is whether a reader can
# see, at a glance, what stands, what warned, and what was skipped and why.
if [ "${STYLE_ON:-0}" = 1 ]; then
  ok=0; warn=0; skip=0; fail=0
  for s_ in "${STATUS[@]}"; do
    case "$s_" in OK) ok=$((ok+1)) ;; WARN) warn=$((warn+1)) ;; SKIP) skip=$((skip+1)) ;; FAIL) fail=$((fail+1)) ;; esac
  done
  style_rule 56
  if [ "$fail" -gt 0 ]; then
    style_line FAIL "not usable" "$fail step(s) failed — nothing below it can be trusted"
  elif [ "$warn" -gt 0 ]; then
    style_line OK   "it stands" "$ok steps done · $warn warned · $skip skipped"
  else
    style_line OK   "it stands" "$ok steps done · $skip skipped — nothing warned"
  fi
  # the warnings carry the why; they are the rows a person must read
  for i in "${!IDS[@]}"; do
    [ "${STATUS[$i]}" = WARN ] && style_line WARN "${IDS[$i]}" "${DETAIL[$i]}"
    [ "${STATUS[$i]}" = FAIL ] && style_line FAIL "${IDS[$i]}" "${DETAIL[$i]}"
  done
  # and the skips as one line, with their reasons, since they are decisions not faults
  skips=""
  for i in "${!IDS[@]}"; do [ "${STATUS[$i]}" = SKIP ] && skips="$skips ${IDS[$i]}"; done
  [ -n "$skips" ] && style_hint "skipped:$skips — each with its reason in the table above"
fi
printf '\nnext: gh auth login · register your projects in hoard/identity/projects.yaml · open http://127.0.0.1:3888/\n'
[ -n "$INVITE_CODE" ] && printf 'invite: %s — share it to let someone register (bin/engine/ymir-invite.sh list shows what is spent)\n' "$INVITE_CODE"

for s in "${STATUS[@]}"; do [ "$s" = FAIL ] && exit 1; done
exit 0
