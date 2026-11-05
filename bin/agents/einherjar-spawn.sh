#!/usr/bin/env bash
# einherjar-spawn.sh - gather an Eindri worker (Einherjar = the chosen who are
# gathered to fight) into a Yggdrasil worktree, optionally sealed by Utgard,
# and expose its launch through the runtime backend (tmux/herdr).
#
# Usage:
#   einherjar-spawn.sh <task-id> <project-dir> --mode <direct-PR|local-only|no-mistakes>
#       [--yolo on|off] [--harness <name>] [--model <token|request>]
#       [--effort <low|medium|high|xhigh|max>] [--backend tmux|herdr]
#       [--isolation on|off|auto] [--force] [--dry-run]
#   einherjar-spawn.sh <task-id> <project-dir> --scout [--harness ...] [--model ...]
#       [--effort ...] [--backend ...] [--isolation ...] [--force] [--dry-run]
#   einherjar-spawn.sh <task-id> --relaunch [--harness ...] [--model ...]
#       [--effort ...] [--isolation ...] [--force] [--dry-run]
#
# It creates or reuses the Yggdrasil worktree at <BROKK_HOME>/.yggdrasil/<id>,
# records state/<id>.meta, and refuses to launch a ship task whose brief's
# fixed "Delivery contract: mode=<mode>" line disagrees with the explicit
# --mode, so an adjusted brief and the recorded task cannot drift.
#
# The rule (settled 2026-09-24): herdr is the ORDINARY road — a normal deploy
# runs in a herdr workspace in the worktree, with no container. Utgard is the
# EXCEPTION, chosen for untrusted code or an outsized task, never for routine
# work and never merely because an image is present. Isolation is DECLARED in
# the brief as `Isolation: herdr|utgard — <why>`; `--isolation auto` honours
# that declaration. A declared utgard with no image is a LOUD refusal, never a
# silent downgrade. The choice and its reason are recorded in state/<id>.meta.
# worth-a-smith REFUSES by default: an errand that is not worktree-shaped is
# refused with the reason and the remedy; --force overrides and is recorded.
# The harness and model resolve from the MACHINE, in order: explicit flags ->
# a named model via bin/model/model-resolve.sh -> config/agents.yaml (the private
# home) -> the fleet law (local model -> pi, hosted -> opencode). Never from a
# repo template; provenance is printed and recorded.
#
# --dry-run resolves and PRINTS the whole plan before anything is created:
# engine, isolation (+ reason), backend (+ why), harness, model (+ provenance),
# worktree, brief, mode, yolo, worth-a-smith verdict, and the launch shape.
#
# Every spawn prints:
#   spawned <id> harness=<h> kind=<kind> [mode=<m> yolo=<y>] backend=<b> target=<t> worktree=<wt> isolation=<on|off>
set -eu
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

# D1 (2026-09-24): a non-zero exit is never silent. Every failing command names
# its line and text; the dispatcher that died twice at rc=1 with zero output
# stays dead forever now.
log_err() {
  local rc=$? line=${1:-} cmd=${2:-}
  printf 'einherjar-spawn: ERROR at line %s — %s (exit %s)\n' "$line" "$cmd" "$rc" >&2
}
trap 'log_err "$LINENO" "${BASH_COMMAND:-}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fleet/ymir-platform.sh
. "$SCRIPT_DIR/../fleet/ymir-platform.sh"
# Docker or rootless Podman (Fedora). Empty when neither is reachable.
ENGINE="$(ymir_container_engine 2>/dev/null || true)"
VOL_SUFFIX="$(ymir_volume_suffix)"
# Rootless Podman needs --userns=keep-id for bind-mount ownership. Guarded:
# the substitution must SUCCEED (empty) on hosts that are not rootless Podman,
# or set -e aborts the dispatcher mute — which it did (2026-09-24, rc=1 zero
# output on heimdall: every spawn died at this line before any message).
USERNS_FLAG="$( { ymir_rootless_podman 2>/dev/null && printf -- '--userns=keep-id'; } || true )"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
BROKK_HOME="${BROKK_HOME:-${BROKK_ROOT_OVERRIDE:-$ROOT}}"
STATE="${BROKK_STATE_OVERRIDE:-$BROKK_HOME/state}"
DATA="${BROKK_DATA_OVERRIDE:-$BROKK_HOME/data}"
CONFIG="${BROKK_CONFIG_OVERRIDE:-$BROKK_HOME/config}"

# --- one identity, or a refusal ----------------------------------------------
# Overrides may MOVE the house; they may never SPLIT it. Each *_OVERRIDE is
# honoured on its own, so a caller that sets only BROKK_STATE_OVERRIDE gets a
# STATE from one root while DATA and WT_ROOT still resolve from another. That is
# how one errand id came to own TWO Yggdrasil worktrees on 2026-10-06
# (dag-runes-p1), with the task record naming one and the worker seated in the
# other — so `--relaunch` and `start` disagreed about what existed.
#
# ROOT is the ENGINE root (this script lives in <root>/bin/agents), which is why
# it is not the checkout root; that is long-standing and correct. What was not
# correct was letting the derived paths disagree with an override.
_state_base="$(dirname "$STATE")"
_data_base="$(dirname "$DATA")"
_config_base="$(dirname "$CONFIG")"
if [ "$_state_base" != "$_data_base" ] || [ "$_state_base" != "$_config_base" ]; then
  {
    echo "error: the house is split — state, data and config resolve to different bases."
    echo "  state: $STATE"
    echo "  data:  $DATA"
    echo "  config:$CONFIG"
    echo "help: move the whole house with BROKK_HOME (or BROKK_ROOT_OVERRIDE),"
    echo "      or override NONE. Overriding one path alone is refused, because one"
    echo "      errand with two homes names a worktree its worker is not sitting in."
  } >&2
  exit 1
fi
unset _state_base _data_base _config_base

# Adapters this platform has verified for direct launches. An adapter outside
# this set is refused unless a raw launch command is supplied.
VERIFIED_HARNESSES='opencode pi pi-signed'

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

resolve_dir() {  # <name> <path>
  local name=$1 path=$2 resolved
  case "$path" in
    /*) printf '%s\n' "$path"; return 0 ;;
  esac
  resolved=$(CDPATH='' cd -- "$path" 2>/dev/null && pwd -P) || {
    echo "error: $name directory cannot be resolved: $path" >&2
    return 1
  }
  printf '%s\n' "$resolved"
}

# --- parse ------------------------------------------------------------------
KIND=ship
SCOUT=0
RELAUNCH=0
MODE=
MODE_SET=0
YOLO=off
HARNESS_ARG=
MODEL=
MODEL_SET=0
EFFORT=
EFFORT_SET=0
BACKEND=
BACKEND_SET=0
ISOLATION=auto
FORCE=0
DRY=0
POS=()
want_value=
for a in "$@"; do
  if [ -n "$want_value" ]; then
    case "$a" in
      --*) echo "error: --$want_value requires a value" >&2; exit 1 ;;
    esac
    case "$want_value" in
      mode) MODE=$a; MODE_SET=1 ;;
      yolo) YOLO=$a ;;
      harness) HARNESS_ARG=$a ;;
      model) MODEL=$a; MODEL_SET=1 ;;
      effort) EFFORT=$a; EFFORT_SET=1 ;;
      backend) BACKEND=$a; BACKEND_SET=1 ;;
      isolation) ISOLATION=$a ;;
      *) echo "error: internal parser state for --$want_value" >&2; exit 1 ;;
    esac
    want_value=
    continue
  fi
  case "$a" in
    --scout) SCOUT=1 ;;
    --relaunch) RELAUNCH=1 ;;
    --mode) want_value=mode ;;
    --mode=*) MODE=${a#--mode=}; MODE_SET=1 ;;
    --yolo) want_value=yolo ;;
    --yolo=*) YOLO=${a#--yolo=} ;;
    --harness) want_value=harness ;;
    --harness=*) HARNESS_ARG=${a#--harness=} ;;
    --model) want_value=model ;;
    --model=*) MODEL=${a#--model=}; MODEL_SET=1 ;;
    --effort) want_value=effort ;;
    --effort=*) EFFORT=${a#--effort=}; EFFORT_SET=1 ;;
    --backend) want_value=backend ;;
    --backend=*) BACKEND=${a#--backend=}; BACKEND_SET=1 ;;
    --isolation) want_value=isolation ;;
    --isolation=*) ISOLATION=${a#--isolation=} ;;
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) POS+=("$a") ;;
  esac
done
[ -z "$want_value" ] || { echo "error: --$want_value requires a value" >&2; exit 1; }

ID=${POS[0]:-}
[ -n "$ID" ] || { echo "error: task-id is required" >&2; exit 2; }
case "$ID" in
  */*|.*|*' '*) echo "error: invalid task-id '$ID' (no slashes, no leading dot, no spaces)" >&2; exit 2 ;;
esac

case "$YOLO" in on|off) ;; *) echo "error: --yolo must be on or off (got '$YOLO')" >&2; exit 1 ;; esac
case "$ISOLATION" in on|off|auto) ;; *) echo "error: --isolation must be on, off, or auto (got '$ISOLATION')" >&2; exit 1 ;; esac
if [ -n "$EFFORT" ]; then
  case "$EFFORT" in low|medium|high|xhigh|max) ;; *) echo "error: --effort must be one of low, medium, high, xhigh, max (got '$EFFORT')" >&2; exit 1 ;; esac
fi

if [ "$RELAUNCH" -eq 1 ]; then
  [ "$SCOUT" -eq 0 ] || { echo "error: --scout is refused with --relaunch; the kind comes from the task record" >&2; exit 1; }
  [ "$MODE_SET" -eq 0 ] || { echo "error: --mode is refused with --relaunch; the mode comes from the task record" >&2; exit 1; }
  [ "${#POS[@]}" -le 1 ] || { echo "error: a project positional is refused with --relaunch; it comes from the task record" >&2; exit 1; }
else
  if [ "$SCOUT" -eq 1 ]; then
    [ "$MODE_SET" -eq 0 ] || { echo "error: --mode applies only to ship spawns; a scout delivers a report" >&2; exit 1; }
  else
    [ "$MODE_SET" -eq 1 ] || { echo "error: ship spawns require --mode <direct-PR|local-only|no-mistakes>" >&2; exit 1; }
    case "$MODE" in
      direct-PR|local-only|no-mistakes) ;;
      *) echo "error: --mode must be one of direct-PR, local-only, no-mistakes (got '$MODE')" >&2; exit 1 ;;
    esac
  fi
fi
[ "$BACKEND_SET" -eq 0 ] || case "$BACKEND" in tmux|herdr) ;; *) echo "error: --backend must be tmux or herdr (got '$BACKEND')" >&2; exit 1 ;; esac

if [ "$RELAUNCH" -eq 1 ]; then
  KIND=ship
fi
if [ "$SCOUT" -eq 1 ]; then
  KIND=scout
fi

# --- explicit harness -------------------------------------------------------
RAW_LAUNCH=
HARNESS=
HARNESS_PROV=
if [ -n "$HARNESS_ARG" ]; then
  case "$HARNESS_ARG" in
    *' '*) RAW_LAUNCH=$HARNESS_ARG ;;
    *) HARNESS=$HARNESS_ARG ;;
  esac
fi

# --- dispatch profile: active means "consult your rules" --------------------
# D4 (2026-09-24): a profile that still carries unfilled <...> model tokens is
# NOT active and steers nothing. Only a real profile (a $YMIR_HOME/hodd/config
# override, or a repo config resolved from the machine) gates the backstop.
DISPATCH_ACTIVE=
_disp=$("$SCRIPT_DIR/../fleet/dispatch-profile.sh" active 2>/dev/null) || _disp=
if [ -n "$_disp" ]; then
  DISPATCH_ACTIVE=$(printf '%s\n' "$_disp" | sed -n '2p' | sed -E 's/^ *"[^"]+","([^"]+)".*/\1/')
fi
if [ "$RELAUNCH" -eq 0 ] && [ -z "$HARNESS" ] && [ "$MODEL_SET" -eq 0 ] && [ -n "$DISPATCH_ACTIVE" ]; then
  echo "error: an ACTIVE dispatch profile governs this machine ($DISPATCH_ACTIVE) - pass an explicit --harness/--model resolved from its rules (consultation backstop, so the profiles are never silently skipped)" >&2
  exit 1
fi
unset _disp

# --- backend resolution -----------------------------------------------------
# D5 (2026-09-24): the default is herdr when the herdr SERVER answers; tmux is
# the fallback. The gate is the server's existence (pgrep/status API), NEVER
# `bin/seat/herdr-run.sh available` — that verb answers for a SESSION's HERDR_ENV
# ("is this shell inside herdr?"), not for whether a server can host a worker.
# A herdr server can host a worker even when the dispatcher sits outside herdr;
# conflating the two left the backend on tmux while `herdr server` ran.
herdr_server_present() {
  pgrep -f 'herdr server' >/dev/null 2>&1 && return 0
  command -v herdr >/dev/null 2>&1 || return 1
  herdr status --json 2>/dev/null | grep -qE '"running"[[:space:]]*:[[:space:]]*true' && return 0
  return 1
}

RESOLVED_BACKEND=
BACKEND_WHY=
if [ "$BACKEND_SET" -eq 1 ]; then
  RESOLVED_BACKEND=$BACKEND
  BACKEND_WHY="explicit --backend"
else
  b="${BROKK_BACKEND:-}"
  if [ -z "$b" ] && [ -f "$CONFIG/backend" ]; then
    b=$(head -n1 "$CONFIG/backend" | tr -d '[:space:]')
  fi
  if [ -n "$b" ]; then
    case "$b" in
      tmux|herdr) RESOLVED_BACKEND=$b; BACKEND_WHY="explicit (BROKK_BACKEND/config/backend)" ;;
      *) echo "error: unsupported backend '$b' (supported: tmux, herdr)" >&2; exit 1 ;;
    esac
  elif herdr_server_present; then
    RESOLVED_BACKEND=herdr
    BACKEND_WHY="the herdr server answers (pgrep/API) — herdr is the fleet backend; tmux is only the fallback"
  elif command -v tmux >/dev/null 2>&1; then
    RESOLVED_BACKEND=tmux
    BACKEND_WHY="no herdr server answering — tmux is the fallback"
  else
    echo "error: no backend available — herdr server is not running and tmux is not on PATH" >&2
    exit 1
  fi
fi

if [ "$RESOLVED_BACKEND" = tmux ]; then
  command -v tmux >/dev/null 2>&1 || { echo "error: backend tmux selected but tmux is not on PATH" >&2; exit 1; }
elif [ "$RESOLVED_BACKEND" = herdr ]; then
  command -v herdr >/dev/null 2>&1 || { echo "error: backend herdr selected but herdr is not on PATH" >&2; exit 1; }
fi

# --- meta / relaunch resolution ---------------------------------------------
META="$STATE/$ID.meta"
meta_value() {  # <file> <key>
  grep "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

PROJECT_DIR=
WT=
BRIEF=
if [ "$RELAUNCH" -eq 1 ]; then
  [ -f "$META" ] || { echo "error: --relaunch requires an existing task record at $META" >&2; exit 1; }
  KIND=$(meta_value "$META" kind); KIND=${KIND:-ship}
  WT=$(meta_value "$META" worktree)
  PROJECT_DIR=$(meta_value "$META" project)
  [ -n "$WT" ] || { echo "error: task record $META records no worktree" >&2; exit 1; }
  [ -d "$WT" ] || { echo "error: recorded worktree $WT no longer exists; recover it before relaunching" >&2; exit 1; }
  if [ "$KIND" = ship ] && [ "$MODE_SET" -eq 0 ]; then
    MODE=$(meta_value "$META" mode)
    case "$MODE" in direct-PR|local-only|no-mistakes) ;; *) echo "error: task record $META records no valid mode" >&2; exit 1 ;; esac
  fi
  if [ -z "$HARNESS_ARG" ]; then
    RECORDED_RAW=$(meta_value "$META" raw_launch)
    RECORDED_HARNESS=$(meta_value "$META" harness)
    if [ -n "$RECORDED_RAW" ]; then
      RAW_LAUNCH=$RECORDED_RAW
      HARNESS=${RECORDED_HARNESS:-$(printf '%s' "$RECORDED_RAW" | awk '{print $1}')}
      HARNESS_PROV="recorded raw_launch (relaunch)"
    else
      HARNESS=$RECORDED_HARNESS
      HARNESS_PROV="recorded in the task record (relaunch)"
    fi
  fi
  BRIEF="$DATA/$ID/brief.md"
  [ -f "$BRIEF" ] || { echo "error: no brief at $BRIEF; regenerate it: bin/agents/erindi-brief.sh $ID --relaunch" >&2; exit 1; }
else
  [ "${#POS[@]}" -ge 2 ] || { echo "error: <project-dir> is required for a fresh spawn" >&2; exit 2; }
  PROJECT_DIR=$(resolve_dir "project" "${POS[1]}") || exit 1
  [ -d "$PROJECT_DIR" ] || { echo "error: project directory not found: $PROJECT_DIR" >&2; exit 1; }
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "error: $PROJECT_DIR is not a git working tree; Yggdrasil needs one to create the task worktree" >&2
    exit 1
  }
  BRIEF="$DATA/$ID/brief.md"
  [ -f "$BRIEF" ] || {
    echo "error: no brief at $BRIEF; scaffold it first: bin/agents/erindi-brief.sh $ID <repo> --mode $MODE" >&2
    exit 1
  }
  if [ "$KIND" = ship ]; then
    contract=$(grep -E '^Delivery contract: mode=' "$BRIEF" 2>/dev/null | head -1 | sed 's/^Delivery contract: mode=//') || true
    if [ -z "$contract" ]; then
      echo "warning: brief $BRIEF has no 'Delivery contract: mode=' line; launching on the explicit --mode=$MODE" >&2
    elif [ "$contract" != "$MODE" ]; then
      echo "error: brief $BRIEF records mode=$contract but spawn requested mode=$MODE; reconcile them before launching" >&2
      exit 1
    fi
  fi
fi

# --- worth-a-smith: refuse a smith for work that does not need one ----------
# D7 (2026-09-24): the first law lives in einherjar-spawn too, not only in
# bin/seat/herdr-run.sh. The errand is the brief's # Task text. A refusal is LOUD
# with the reason and the remedy; --force overrides and is recorded.
WORTH_VERDICT=yes
WORTH_WHY=forced
task_text=$(sed -n '/^# Task/,/^# \(Delivery contract\|Setup\|Rules\)/{ /^# /d; p; }' "$BRIEF" 2>/dev/null | head -c 1500)
if printf '%s' "$task_text" | grep -q '{TASK}'; then
  WORTH_VERDICT=no
  WORTH_WHY='the brief still carries the unfilled {TASK} errand text — write the errand into the brief before dispatch'
elif [ "${#task_text}" -le 1 ]; then
  WORTH_VERDICT=no
  WORTH_WHY='the brief has no # Task section to judge — fill the errand before dispatch'
elif [ -x "$SCRIPT_DIR/../seat/herdr-run.sh" ]; then
  wout=$("$SCRIPT_DIR/../seat/herdr-run.sh" worth-a-smith "$task_text" 2>/dev/null) || true
  if [ -n "$wout" ]; then
    _w=$(printf '%s\n' "$wout" | sed -n '2p')
    _verdict=$(printf '%s' "$_w" | sed -E 's/^ *"([^"]*)".*/\1/')
    _why=$(printf '%s' "$_w" | sed -E 's/^ *"[^"]*","([^"]*)".*/\1/')
    case "$_verdict" in
      yes) WORTH_VERDICT=yes; WORTH_WHY=$_why ;;
      no) WORTH_VERDICT=no; WORTH_WHY=$_why ;;
      *) WORTH_VERDICT=yes; WORTH_WHY="worth-a-smith verdict unreadable; dispatching on the brief" ;;
    esac
  fi
fi
if [ "$WORTH_VERDICT" = no ] && [ "$FORCE" -ne 1 ]; then
  echo "error: this errand is not worth a smith ($WORTH_WHY). The first law: a SHORT ERRAND IS DONE IN HAND — answer it yourself, do not seat a worker. If it truly needs a smith, pass --force (recorded in the meta)." >&2
  if [ "$DRY" -eq 0 ]; then exit 1; fi
  echo "preflight: would REFUSE (not worth a smith: $WORTH_WHY) — --force overrides and is recorded in the meta" >&2
fi

# --- harness + model resolution FROM THE MACHINE (D3) -----------------------
# Order: (1) explicit flags; (2) a named model via bin/model/model-resolve.sh;
# (3) this machine's agent default (config/agents.yaml / bin/fleet/agents-config.sh,
# the PRIVATE home — never a repo template); (4) the fleet law — local model
# -> pi, hosted -> opencode. Provenance is printed and recorded.
MODEL_LOCAL=no
WT_ROOT="$BROKK_HOME/.yggdrasil"

catalog_has() {  # <provider/model> -> 0 when the door says the pair is listed
  # ONE owner for the answer (audit 2026-10-24): `pi --list-models` behind
  # bin/model/catalog.sh. This guard used to parse the catalogue itself, so its
  # reading could disagree with the resolver's table and with AGENTS.md's prose.
  [ -x "$SCRIPT_DIR/../model/catalog.sh" ] || return 1
  "$SCRIPT_DIR/../model/catalog.sh" --has "$1" >/dev/null 2>&1
}

pi_first_local_model() {  # -> the first served provider/model from the pi catalog
  python3 - <<'PY'
import subprocess
try:
    out = subprocess.check_output(["pi", "--list-models"], text=True, stderr=subprocess.DEVNULL)
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 2 and "@" in p[1]:
            print(f"{p[0]}/{p[1]}")
            raise SystemExit(0)
except Exception:
    pass
raise SystemExit(1)
PY
}

agent_yaml_local_providers() {  # -> the local_providers list from agents.yaml
  local y
  y=$(python3 - "$SCRIPT_DIR" <<'PY'
import sys, os
home = os.environ.get("YMIR_HOME")
if not home:
    _rec = os.path.join(os.path.expanduser("~"), ".config", "ymir", "home")
    home = open(_rec).read().strip() if os.path.exists(_rec) else ""
if not home:
    raise SystemExit("YMIR_HOME is unset and no home is recorded (Rule 07; bin/vault/hoard-lib.sh)")
cands = [
    os.environ.get("YMIR_AGENTS_YAML") or "",
    os.path.join(home, "config", "agents.yaml"),
]
try:
    import yaml
    for c in cands:
        if c and os.path.exists(c):
            d = yaml.safe_load(open(c)) or {}
            lp = (d.get("harness") or {}).get("local_providers") or []
            if lp:
                print(" ".join(str(x) for x in lp))
                raise SystemExit(0)
except Exception:
    pass
raise SystemExit(0)
PY
)
  printf '%s' "$y"
}

LOCAL_PROVIDERS="$(agent_yaml_local_providers)"
is_local_provider() {  # <provider>
  local p=$1
  [ -n "$p" ] || return 1
  case " $LOCAL_PROVIDERS " in *" $p "*) return 0 ;; esac
  case "$p" in llama*|*llama*|lmstudio|apodex) return 0 ;; *) return 1 ;; esac
}
model_is_token() {  # <model> -> 0 when it is a concrete provider/model token
  case "$1" in */*) return 0 ;; *) return 1 ;; esac
}

# refused when the chosen harness cannot serve the resolved model (D3/D4)
serve_ok() {  # <harness> <model> -> 0 servable
  local h=$1 m=$2
  [ -n "$m" ] && [ "$m" != default ] || return 0
  case "$m" in
    *"<"*|*" "*|*your-model*|*/) return 1 ;;
  esac
  if [ "$h" = opencode ]; then
    if is_local_provider "${m%%/*}"; then
      catalog_has "$m" && return 0 || return 1
    fi
    return 0
  fi
  catalog_has "$m" && return 0 || return 1
}

resolve_harness_model() {
  local req mr mrow m5 prov h conf _m _h _first _clean _f1 _f2
  # (1) an explicit CONCRETE model token; harness by locality when unset
  if [ "$MODEL_SET" -eq 1 ] && [ -n "$MODEL" ] && model_is_token "$MODEL"; then
    MODEL_PROV="explicit flag (--model $MODEL)"
    if [ -z "$HARNESS" ]; then
      if is_local_provider "${MODEL%%/*}"; then HARNESS=pi; HARNESS_PROV="fleet law (local provider -> pi)"
      else HARNESS=opencode; HARNESS_PROV="fleet law (hosted provider -> opencode)"; fi
    fi
  # (2) an explicit model REQUEST resolved by bin/model/model-resolve.sh
  elif [ "$MODEL_SET" -eq 1 ] && [ -n "$MODEL" ]; then
    req=$MODEL
    mr=$("$SCRIPT_DIR/../model/model-resolve.sh" resolve "$req" 2>/dev/null) || true
    mrow=$(printf '%s\n' "$mr" | sed -n '2p')
    _clean=$(printf '%s' "$mrow" | tr -d '"')
    IFS=',' read -r _f1 _f2 h prov m5 conf <<<"$_clean" || true
    if [ "$conf" = unresolved ] || [ -z "$m5" ] || [ -z "$prov" ]; then
      echo "error: model request '$req' could not be resolved (bin/model/model-resolve.sh) - ask the Allfather which model, then pass a concrete --model provider/model" >&2
      exit 1
    fi
    MODEL="${prov}/${m5}"
    MODEL_PROV="bin/model/model-resolve.sh resolve \"$req\" (confidence=$conf)"
    if [ -z "$HARNESS" ] && [ -n "$h" ] && [ "$h" != default ]; then
      HARNESS=$h
      HARNESS_PROV="bin/model/model-resolve.sh (resolved harness)"
    fi
    unset _clean _f1 _f2
  # (3) this machine's agent default (the private home, never a repo template)
  elif [ "$MODEL_SET" -eq 0 ]; then
    if [ -x "$SCRIPT_DIR/../fleet/agents-config.sh" ]; then
      _m=$("$SCRIPT_DIR/../fleet/agents-config.sh" get brokk model 2>/dev/null | sed -n '1p')
      if [ -n "$_m" ] && [ "$_m" != default ]; then
        MODEL=$_m
        MODEL_PROV="config/agents.yaml via bin/fleet/agents-config.sh (this machine)"
        if [ -z "$HARNESS" ]; then
          _h=$("$SCRIPT_DIR/../fleet/agents-config.sh" get brokk harness 2>/dev/null | sed -n '1p')
          HARNESS=$_h
          [ -n "$HARNESS" ] && HARNESS_PROV="config/agents.yaml via bin/fleet/agents-config.sh (harness rule)"
        fi
      fi
    fi
  fi
  # (4) the fleet law: unresolved harness, and the machine's local truth
  if [ -z "$HARNESS" ]; then
    if [ -z "$MODEL" ]; then
      _first=$(pi_first_local_model || true)
      if [ -n "$_first" ]; then
        MODEL=$_first
        MODEL_LOCAL=yes
        MODEL_PROV="fleet law — first served local model from the pi catalog"
        HARNESS=pi
        HARNESS_PROV="fleet law — a local model catalog exists, so local -> pi"
      else
        HARNESS=opencode
        HARNESS_PROV="fleet law — no local catalog, hosted -> opencode"
      fi
    elif [ "$MODEL_LOCAL" != yes ]; then
      HARNESS=opencode
      HARNESS_PROV="fleet law — hosted model -> opencode"
    else
      HARNESS=pi
      HARNESS_PROV="fleet law — local model -> pi"
    fi
  fi
  [ -z "$MODEL" ] && MODEL_PROV="none — the harness default is served"
  if [ -n "$MODEL" ]; then
    if is_local_provider "${MODEL%%/*}"; then MODEL_LOCAL=yes; else MODEL_LOCAL=no; fi
  fi
  if ! serve_ok "$HARNESS" "$MODEL"; then
    echo "error: harness '$HARNESS' cannot serve model '${MODEL:-<harness default>}' on this machine — resolve a servable token (bin/model/model-resolve.sh list) or pass an explicit --model provider/model" >&2
    exit 1
  fi
}

if [ -n "$RAW_LAUNCH" ]; then
  HARNESS=$(printf '%s' "$RAW_LAUNCH" | awk '{for(i=1;i<=NF;i++) if ($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/) {print $i; exit}}')
  HARNESS=$(basename -- "$HARNESS")
  HARNESS_PROV="raw launch command (escape hatch)"
  echo "warning: launching a raw command as harness '$HARNESS' (not on the verified adapter set)" >&2
else
  resolve_harness_model
  verified=0
  for v in $VERIFIED_HARNESSES; do
    if [ "$HARNESS" = "$v" ]; then verified=1; break; fi
  done
  if [ "$verified" -ne 1 ]; then
    echo "error: harness '$HARNESS' is not verified for direct launch; verified: $VERIFIED_HARNESSES. Supply a raw launch command via --harness to trial a new adapter." >&2
    exit 1
  fi
  if ! command -v "$HARNESS" >/dev/null 2>&1; then
    echo "error: harness '$HARNESS' executable not found on PATH; install it or select a verified harness" >&2
    exit 1
  fi
fi

# --- isolation: the brief DECLARES it; the spawn validates it (D2) ----------
# herdr is the ordinary road (no container). Utgard is the exception, chosen
# for untrusted code or an outsized task. `--isolation auto` honours the
# brief's `Isolation: herdr|utgard — <why>` line. A declared utgard with no
# image is a LOUD refusal; an explicit --isolation off against a declared
# utgard is refused too (the declaration is never silently downgraded).
ISOLATION_DECLARED=herdr
ISOLATION_REASON="no Isolation: line in the brief — herdr is the ordinary road"
_isoline=$(grep -m1 -E '^[[:space:]]*#?[[:space:]]*Isolation:[[:space:]]+(herdr|utgard)([^A-Za-z0-9]|$)' "$BRIEF" 2>/dev/null || true)
if [ -n "$_isoline" ]; then
  _iso_word=$(printf '%s' "$_isoline" | sed -E 's/^[[:space:]]*#?[[:space:]]*Isolation:[[:space:]]+([A-Za-z]+).*/\1/')
  _iso_rest=$(printf '%s' "$_isoline" | sed -E 's/^[[:space:]]*#?[[:space:]]*Isolation:[[:space:]]+[A-Za-z]+([[:space:]]*(-|—)[[:space:]]*)?//')
  case "$_iso_word" in
    herdr|utgard) ISOLATION_DECLARED=$_iso_word; [ -n "$_iso_rest" ] && ISOLATION_REASON=$_iso_rest ;;
    *) ISOLATION_DECLARED=herdr; ISOLATION_REASON="unrecognized isolation declaration '$_iso_word' — herdr is the ordinary road" ;;
  esac
fi
unset _isoline _iso_word _iso_rest

confirm_utgard_image() {  # -> 0 present (engine + image), else loud refusal
  [ -n "$ENGINE" ] || {
    echo "error: isolation=utgard requires a container engine, but neither docker nor podman is reachable — REFUSED, not downgraded. Remedy: start docker/podman, or edit the brief to 'Isolation: herdr — <why>'." >&2
    return 1
  }
  "$ENGINE" image inspect utgard-runner:latest >/dev/null 2>&1 || {
    echo "error: isolation=utgard requires the Utgard image 'utgard-runner:latest', which is absent — REFUSED, not downgraded. Remedy: build it (bin/forge/utgard.sh build) or edit the brief to 'Isolation: herdr — <why>'." >&2
    return 1
  }
  return 0
}

ISOLATION_EFFECTIVE=off
case "$ISOLATION" in
  on)
    confirm_utgard_image || { if [ "$DRY" -eq 0 ]; then exit 1; fi; }
    ISOLATION_EFFECTIVE=on
    [ "$DRY" -eq 1 ] || echo "warning: Utgard runs with --network none — the worker's model endpoint must be reachable INSIDE the sandbox, or the agent dies silently. The ordinary road is herdr (the worktree, no container)." >&2
    ;;
  off)
    if [ "$ISOLATION_DECLARED" = utgard ]; then
      echo "error: brief $BRIEF declares Isolation: utgard but --isolation off forces the worktree — a declared isolation is never silently downgraded; edit the brief's declaration (Isolation: herdr — <why>) or relaunch without --isolation off" >&2
      exit 1
    fi
    ISOLATION_EFFECTIVE=off
    ;;
  auto)
    case "$ISOLATION_DECLARED" in
      utgard)
        if ! confirm_utgard_image; then
          [ "$DRY" -eq 0 ] && exit 1
          echo "preflight: would REFUSE (declared utgard, no image — never a silent downgrade); --isolation off or a herdr declaration changes it" >&2
        fi
        ISOLATION_EFFECTIVE=on
        ;;
      herdr) ISOLATION_EFFECTIVE=off ;;
      *) echo "error: brief $BRIEF carries an unreadable isolation declaration — fix the 'Isolation: herdr|utgard — <why>' line" >&2; exit 1 ;;
    esac
    ;;
esac

# --- local-model lock (D6) ---------------------------------------------------
# The rail is --models-max 1: one resident model, a request evicts. A local
# worker must not evict Brokk's own model while he thinks. For a LOCAL model we
# pre-check the lock (refuse with the holder named when the host is at
# capacity) and wrap the launched command in bin/model/local-model-lock.sh so the
# flock is held from before the worker starts until after it exits.
LOCKED=no
if [ "$MODEL_LOCAL" = yes ] && [ -x "$SCRIPT_DIR/../model/local-model-lock.sh" ]; then
  out=$("$SCRIPT_DIR/../model/local-model-lock.sh" check 2>/dev/null) || true
  case "$(printf '%s\n' "$out" | sed -n '2p')" in
    '"free"*') LOCKED=yes ;;
    '"busy"*')
      LOCK_HOLDER=$(printf '%s\n' "$out" | sed -n '3p' 2>/dev/null | tr -d '"')
      [ -n "$LOCK_HOLDER" ] || LOCK_HOLDER="a local seat already runs (bin/model/local-model-lock.sh check)"
      if [ "$DRY" -eq 1 ]; then
        LOCKED=yes
        echo "preflight: local-model-lock BUSY — holder: $LOCK_HOLDER; a real run refuses (the launched command still serializes under the lock if --force)" >&2
      else
        echo "error: local-model-lock is BUSY ($LOCK_HOLDER) and the resolved model '$MODEL' is LOCAL — two local workers (or a worker + Brokk) would thrash the single-model rail. Wait for the holder, or pass a hosted model." >&2
        exit 1
      fi
      ;;
    *) LOCKED=yes ;;
  esac
fi

# --- engine-first (plan 58, Phase 1): the strangler's hinge -------------------
# The engine (`src/ymir_runtime/`) owns an errand end to end — worktree, harness,
# backend, record, heartbeat. When it says it CANNOT (exit 4: a sandbox seat, an
# unverified harness, a relaunch, a backend that cannot answer) this script runs
# the road it already had, unchanged. That predicate lives in the engine; there
# is no second copy of it here. YMIR_ENGINE=off skips the handoff.
if [ "$DRY" -eq 0 ] && [ "${YMIR_ENGINE:-auto}" != "off" ] && [ -x "$SCRIPT_DIR/../engine/ymir-engine.sh" ]; then
  engine_args=(seat "$ID" --project "$PROJECT_DIR" --kind "$KIND" --mode "${MODE:-scout}" --yolo "$YOLO"
               --backend "$RESOLVED_BACKEND" --harness "${RAW_LAUNCH:-$HARNESS}"
               --worth-a-smith "$WORTH_VERDICT" --worth-why "$WORTH_WHY")
  if [ -n "${MODEL:-}" ]; then engine_args+=(--model "$MODEL"); fi
  if [ -n "${EFFORT:-}" ]; then engine_args+=(--effort "$EFFORT"); fi
  if [ -f "$BRIEF" ]; then engine_args+=(--brief "$BRIEF"); fi
  if [ "$ISOLATION_EFFECTIVE" = on ]; then
    engine_args+=(--isolation utgard)
  else
    engine_args+=(--isolation herdr)
  fi
  if [ "$LOCKED" = yes ] && [ -x "$SCRIPT_DIR/../model/local-model-lock.sh" ]; then
    engine_args+=(--lock "$SCRIPT_DIR/../model/local-model-lock.sh")
  fi
  if [ "$FORCE" -eq 1 ]; then engine_args+=(--force); fi
  engine_args+=(--compat)
  engine_rc=0
  "$SCRIPT_DIR/../engine/ymir-engine.sh" "${engine_args[@]}" || engine_rc=$?
  if [ "$engine_rc" -eq 0 ]; then exit 0; fi
  if [ "$engine_rc" -ne 4 ]; then
    printf 'error: the engine failed to seat %s (exit %s) — the old road was NOT run, because a half-seat is worse than none\nhelp: bin/engine/ymir-engine.sh seat %s --project %s\n' \
      "$ID" "$engine_rc" "$ID" "$PROJECT_DIR" >&2
    exit 1
  fi
  printf 'engine: cannot own %s — running the existing road\n' "$ID" >&2
fi

# --- dry-run: print the whole resolved plan, create nothing ------------------
if [ "$DRY" -eq 1 ]; then
  _wt="$WT_ROOT/$ID"
  _cwd=$_wt
  [ "$ISOLATION_EFFECTIVE" = on ] && _cwd=/sandbox/workspace
  printf 'preflight[1]{engine,isolation,isolation_reason,backend,backend_why,harness,harness_prov,model,model_prov,worktree,brief,mode,yolo,worth,lock}:\n'
  printf '  "%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "${ENGINE:-none}" "$ISOLATION_EFFECTIVE" "$ISOLATION_REASON" "$RESOLVED_BACKEND" "$BACKEND_WHY" \
    "$HARNESS" "${HARNESS_PROV:-}" "${MODEL:-<harness default>}" "${MODEL_PROV:-}" "$_wt" "$BRIEF" \
    "${MODE:-scout}" "$YOLO" "$WORTH_VERDICT" "${LOCKED:-no}${LOCK_HOLDER:+ (busy: $LOCK_HOLDER)}"
  printf '  launch: cd %s && %s%s --prompt "$(cat %s)"\n' \
    "$_cwd" "$HARNESS" "${MODEL:+ --model $MODEL}" "$BRIEF"
  [ "$ISOLATION_DECLARED" = utgard ] && [ "$ISOLATION_EFFECTIVE" != on ] && printf '  note: brief declares Isolation: utgard; effective %s. A declared utgard is never silently downgraded; the refusal above is the law, not a fallback.\n' "$ISOLATION_EFFECTIVE"
  [ "$ISOLATION_DECLARED" = herdr ] && [ "$ISOLATION_EFFECTIVE" = on ] && printf '  note: brief declares Isolation: herdr (the ordinary road) but --isolation on forced the sandbox\n'
  printf '  dispatch_profile: %s\n' "${DISPATCH_ACTIVE:-<none active — the machine resolution governs>}"
  exit 0
fi

# --- Yggdrasil worktree ------------------------------------------------------
if [ -z "$WT" ]; then
  WT="$WT_ROOT/$ID"
  mkdir -p "$WT_ROOT"
  if [ -e "$WT/.git" ]; then
    top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null || true)
    [ "$top" = "$WT" ] || { echo "error: $WT exists but is not the expected worktree root" >&2; exit 1; }
  elif [ -e "$WT" ]; then
    echo "error: $WT already exists and is not a Yggdrasil worktree; remove it or choose another task id" >&2
    exit 1
  else
    base=
    # Rule 45 — FETCH first. A worktree is cut from refs/remotes/origin/<default>, so
    # an unfetched remote ref hands the worker yesterday's code and calls it the tip.
    # 2026-11-04: a seat seven commits behind asked the plan ledger for the next
    # number, was handed one already taken, and two plans shared it. A failed fetch is
    # STATED here, never silent — and it is never fatal: a seat offline must still be
    # able to work from the tree it has.
    git -C "$PROJECT_DIR" fetch --quiet --prune origin 2>/dev/null \
      || echo "warning: could not fetch origin — this worktree's base is UNVERIFIED against the remote (Rule 45)" >&2
    remote_head=$(git -C "$PROJECT_DIR" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)
    if [ -n "$remote_head" ]; then
      remote_head=${remote_head#refs/remotes/}
      if git -C "$PROJECT_DIR" rev-parse --verify -q "refs/remotes/$remote_head" >/dev/null 2>&1; then
        base="refs/remotes/$remote_head"
      fi
    fi
    [ -n "$base" ] || base=HEAD
    git -C "$PROJECT_DIR" worktree add --detach "$WT" "$base" >/dev/null || {
      echo "error: Yggdrasil could not create worktree $WT from $PROJECT_DIR" >&2
      exit 1
    }
  fi
fi
[ -d "$WT" ] || { echo "error: Yggdrasil worktree missing: $WT" >&2; exit 1; }

# A linked worktree's .git file points at the project's common git dir. Mount
# that dir at the same path in the sandbox so git resolves inside Utgard.
GIT_COMMON=
if [ -n "$PROJECT_DIR" ]; then
  gc=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null || true)
  if [ -n "$gc" ]; then
    GIT_COMMON=$(CDPATH='' cd -- "$PROJECT_DIR" && CDPATH='' cd -- "$gc" && pwd -P) || GIT_COMMON=
  fi
fi

# --- launch script + command -------------------------------------------------
mkdir -p "$STATE" "$DATA/$ID"
LAUNCH_SCRIPT="$STATE/$ID.launch.sh"

if [ "$ISOLATION_EFFECTIVE" = on ]; then
  # The worktree is mounted at the Utgard target; state/ and data/ are
  # mounted at their own host paths so the brief's status, inbox, and report
  # paths resolve identically inside the container.
  LAUNCH_CWD=/sandbox/workspace
else
  LAUNCH_CWD=$WT
fi
# --- pre-dispatch context injection (W0006): drink before you act -----------
# Recall what the well remembers about this task and hand it to the worker with
# the brief. A dry well never blocks; recall is a boost.
CTX="$DATA/$ID/context.md"
TITLE=$(grep -m1 -E '^#|title' "$BRIEF" 2>/dev/null | sed 's/^#* *//' || true)
"$SCRIPT_DIR/../records/mimir.sh" recall "${TITLE:-$ID}" --k 4 >"$CTX" 2>/dev/null || : >"$CTX"
PROMPT="$DATA/$ID/prompt.md"
{
  cat "$BRIEF"
  printf '\n\n---\n\n## Recalled context (the well — Mimirsbrunn)\n\n'
  cat "$CTX"
} >"$PROMPT" 2>/dev/null || cp "$BRIEF" "$PROMPT"
BRIEF_REF=$PROMPT

# The launcher is GENERATED by ONE door, never assembled here.
#
# Why (measured 2026-11-04 and again 2026-11-05): the seat's settings name the PRIMARY checkout's
# extensions tree absolutely, and Pi ALSO discovers the project tree under the working directory. In a
# Yggdrasil worktree those are two different paths, so every tool was registered twice and Pi refused
# to load a single extension — "Tool constellation_list conflicts with
# …/.yggdrasil/<id>/.pi/extensions/constellation/index.ts" — and workers were born dead while the
# dispatcher printed `spawned` (RULES/13). Two launchers for one shape is how a worktree killed a
# worker, so the shape lives in bin/seat/pi-launcher.sh and this spawner only CALLS it.
PI_LAUNCHER="$SCRIPT_DIR/../seat/pi-launcher.sh"

build_launch_command() {  # prints the worker command WITHOUT the leading exec
  local brief_ref=$1 model_flag=
  if [ -n "$MODEL" ] && [ "$MODEL" != default ]; then
    model_flag="--model $(shell_quote "$MODEL") "
  fi
  case "$HARNESS" in
    opencode)
      # `exec VAR=value cmd` is not a thing: exec takes a command, not assignments,
      # so the old form died with "exec: OPENCODE_CONFIG_CONTENT=…: not found" and
      # EVERY opencode seat was born dead while the dispatcher said "spawned"
      # (measured 2026-10-24, four dispatches, four empty panes). `env` carries the
      # assignment through the exec.
      printf 'env OPENCODE_CONFIG_CONTENT=%s opencode %s--prompt "$(cat %s)"' \
        "$(shell_quote '{"permission":{"*":"allow"}}')" "$model_flag" "$(shell_quote "$brief_ref")"
      ;;
    pi|pi-signed)
      # `-ne` plus every extension named ONCE from the worktree — the door's shape, never ours.
      local pi_args=()
      [ -n "$MODEL" ] && [ "$MODEL" != default ] && pi_args+=(--model "$MODEL")
      [ -n "$EFFORT" ] && [ "$EFFORT" != default ] && pi_args+=(--thinking "$EFFORT")
      "$PI_LAUNCHER" print "$LAUNCH_CWD" ${pi_args[@]+"${pi_args[@]}"} --brief "$brief_ref"
      ;;
    *)
      local cmd=$RAW_LAUNCH
      if printf '%s' "$cmd" | grep -q '__BRIEF__'; then
        cmd=${cmd//__BRIEF__/$(shell_quote "$brief_ref")}
      fi
      printf '%s' "$cmd"
      ;;
  esac
}

LAUNCH_CMD=$(build_launch_command "$BRIEF_REF")
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -eu\n'
  printf 'cd %s\n' "$(shell_quote "$LAUNCH_CWD")"
  if [ "$LOCKED" = yes ]; then
    printf 'exec %s bash -c %s\n' "$(shell_quote "$SCRIPT_DIR/../model/local-model-lock.sh")" "$(shell_quote "$LAUNCH_CMD")"
  else
    printf 'exec %s\n' "$LAUNCH_CMD"
  fi
} > "$LAUNCH_SCRIPT"
chmod +x "$LAUNCH_SCRIPT"

if [ "$ISOLATION_EFFECTIVE" = on ]; then
  GIT_MOUNT_ARGS=
  GIT_MOUNT_LINE=none
  if [ -n "$GIT_COMMON" ]; then
    GIT_MOUNT_ARGS=" -v $(shell_quote "$GIT_COMMON:$GIT_COMMON")"
    GIT_MOUNT_LINE=$GIT_COMMON:$GIT_COMMON
  fi
  cat > "$STATE/$ID.utgard" <<EOF
image=utgard-runner:latest
network=none
cpus=1.0
memory=512m
security_opt=no-new-privileges
user=$(id -u):$(id -g)
worktree_mount=$WT:/sandbox/workspace
git_common_mount=$GIT_MOUNT_LINE
state_mount=$STATE:$STATE
data_mount=$DATA:$DATA
launch=$LAUNCH_SCRIPT
EOF
  # Rootless Podman: keep-id maps the host user so the mounted worktree stays
  # writable; Docker keeps an explicit --user. Both get :Z under enforcing SELinux.
  if [ -n "$USERNS_FLAG" ]; then USER_ARG=""; else USER_ARG="--user $(shell_quote "$(id -u):$(id -g)")"; fi
  PANE_CMD="$ENGINE run --rm -it --network none --cpus 1.0 --memory 512m --security-opt no-new-privileges $USERNS_FLAG $USER_ARG -e HOME=/tmp -v $(shell_quote "$WT:/sandbox/workspace$VOL_SUFFIX")$GIT_MOUNT_ARGS -v $(shell_quote "$STATE:$STATE$VOL_SUFFIX") -v $(shell_quote "$DATA:$DATA$VOL_SUFFIX") -w /sandbox/workspace utgard-runner:latest bash $(shell_quote "$LAUNCH_SCRIPT")"
  if [ "$LOCKED" = yes ]; then
    # the flock is HOST-side: it must wrap the docker run itself, not a
    # command inside the container (the lockfile is the host's inode).
    PANE_CMD="$SCRIPT_DIR/../model/local-model-lock.sh $PANE_CMD"
  fi
else
  rm -f "$STATE/$ID.utgard"
  PANE_CMD="bash $(shell_quote "$LAUNCH_SCRIPT")"
fi

# --- the seat's OWN machine state: the helm must not be stolen ---------------
# pi's session-start writes brokk.lock and .pi-watch-extension-loaded. Without a
# private BROKK_MACHINE_STATE_DIR, EVERY worker raised by this road took the
# PRIMARY's helm and killed Brokk's watcher — twice on 2026-09-24, both times
# silently, the extension reporting only "cannot restore continuity".
# herdr-run.sh and pi-seat.sh already give a seat its own dir (their --env on tab
# create); this road never did. Same convention, so a seat is a seat everywhere:
#   ${XDG_STATE_HOME:-$HOME/.local/state}/ymir/seats/<id>
# The assignment prefixes the pane command, so it holds on every backend and for
# the Utgard path too (inside the sandbox HOME=/tmp, so it is inert there).
SEAT_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ymir/seats/$ID"
mkdir -p "$SEAT_STATE_DIR" 2>/dev/null || true
PANE_CMD="BROKK_MACHINE_STATE_DIR=$(shell_quote "$SEAT_STATE_DIR") BROKK_STATE_OVERRIDE=$(shell_quote "$SEAT_STATE_DIR") $PANE_CMD"

# --- backend launch ----------------------------------------------------------
launch_tmux() {  # -> prints target
  local session wname wid
  if [ -n "${TMUX:-}" ]; then
    session=$(tmux display-message -p '#S')
  else
    session="${BROKK_TMUX_SESSION:-brokk}"
    tmux has-session -t "$session" 2>/dev/null || tmux new-session -d -s "$session" || {
      echo "error: could not create tmux session '$session'" >&2; return 1; }
  fi
  wname="eindri-$ID"
  if tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -qx "$wname"; then
    echo "error: tmux window $session:$wname already exists; tear it down or relaunch" >&2
    return 1
  fi
  wid=$(tmux new-window -dP -F '#{window_id}' -t "$session:" -n "$wname" -c "$WT") || {
    echo "error: tmux failed to create window $session:$wname" >&2; return 1; }
  tmux set-window-option -t "$wid" automatic-rename off 2>/dev/null || true
  tmux set-window-option -t "$wid" allow-rename off 2>/dev/null || true
  tmux send-keys -t "$wid" -l "$PANE_CMD"
  tmux send-keys -t "$wid" Enter
  printf '%s\n' "$wid"
}

launch_herdr() {  # -> prints pane id
  local out ws pane
  # The seat gets its OWN machine-state dir at creation time: `--env` sets the
  # environment of the LAUNCHED PROCESS, which is the road herdr-run.sh and
  # pi-seat.sh already use. A command-prefix (VAR=x cmd) is NOT enough here — it
  # was tried on 2026-09-24 and the worker still took the primary's helm, because
  # the pane's own environment wins for everything the harness reads at startup.
  [ -n "$SEAT_STATE_DIR" ] && mkdir -p "$SEAT_STATE_DIR" 2>/dev/null || true
  out=$(herdr workspace create --cwd "$WT" --label "eindri-$ID" --no-focus \
    --env "BROKK_MACHINE_STATE_DIR=$SEAT_STATE_DIR" \
    --env "BROKK_STATE_OVERRIDE=$SEAT_STATE_DIR" 2>/dev/null) || {
    echo "error: herdr workspace create failed (is a herdr server running? try: herdr)" >&2
    return 1
  }
  ws=$(printf '%s\n' "$out" | sed -n 's/.*"workspace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$ws" ] || ws=$(printf '%s\n' "$out" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$ws" ] || ws=$(printf '%s\n' "$out" | head -1)
  [ -n "$ws" ] || { echo "error: could not resolve a herdr workspace id from: $out" >&2; return 1; }
  pane=$(herdr pane list --workspace "$ws" 2>/dev/null | sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  [ -n "$pane" ] || { echo "error: no pane found in herdr workspace $ws" >&2; return 1; }
  herdr pane send-text "$pane" "$PANE_CMD" 2>/dev/null || true
  herdr pane send-keys "$pane" Enter 2>/dev/null || true
  printf '%s\n' "$pane"
}

if [ "$RESOLVED_BACKEND" = tmux ]; then
  RUN_TARGET=$(launch_tmux) || exit 1
else
  RUN_TARGET=$(launch_herdr) || exit 1
fi

# --- PROVE THE SEAT: a spawn is not a seat until `herdr agent list` shows it --
# Measured 2026-11-05 (plan 190 §4.1): this dispatcher printed `spawned …
# target=wQ:p1` for an errand whose pane held a bare shell while the agent had
# come up in another pane entirely, and three errands died the same way while
# their records claimed a seat. `state/<id>.meta` is a claim; the agent list is
# the evidence. So after the pane is handed the launcher we ASK the door —
# bin/seat/herdr-agents.py, the one reader of `herdr agent list` — for the agent
# standing in this worktree or in the recorded pane, and we correct the record
# when the door names a different pane than the one we chose.
SEAT_PROVEN=no
SEAT_PANE=$RUN_TARGET
SEAT_STATE=unknown
SEAT_NOTE=""
SEAT_SETTLE="${YMIR_SEAT_SETTLE:-25}"
# ONE proof door, shared with the engine (src/ymir_runtime/seat.py), so the two
# roads cannot disagree about whether a seat is standing.
if seat_out=$("$SCRIPT_DIR/../seat/seat-prove.sh" "$RUN_TARGET" "$WT" \
    --backend "$RESOLVED_BACKEND" --settle "$SEAT_SETTLE" 2>"$STATE/.$ID.seat-prove"); then
  SEAT_PROVEN=yes
  SEAT_PANE=${seat_out%%$'\t'*}
  SEAT_STATE=$(printf '%s' "$seat_out" | cut -f2)
  [ "$SEAT_PANE" = "$RUN_TARGET" ] || \
    SEAT_NOTE="seated at $SEAT_PANE, not the pane $RUN_TARGET this spawn chose — the record follows the agent"
else
  SEAT_STATE=$(tail -n1 "$STATE/.$ID.seat-prove" 2>/dev/null | sed 's/^seat-prove: //' || true)
  rm -f "$STATE/.$ID.seat-prove"
  printf 'seat[1]{id,state,pane,settle}:\n  "%s","UNPROVEN","%s","%ss"\n' "$ID" "$RUN_TARGET" "$SEAT_SETTLE" >&2
  printf 'seat-unproven: the launch produced NO agent — state/%s.meta recorded pane %s but no agent stands there or in %s. The errand is not seated; do not steer it.\n' \
    "$ID" "$RUN_TARGET" "$WT" >&2
fi
# The pane the RECORD carries is the one the agent actually stands in.
RUN_TARGET=$SEAT_PANE

# --- heartbeat baseline (D8) -------------------------------------------------
# The supervisor distinguishes a silent worker from a thinking one by the
# freshness of state/<id>.status. Record the launch in the meta and append the
# first heartbeat line so the baseline exists before the worker's own first
# line. bin/agents/eindri-heartbeat.sh holds the silence judgement; a worker with no
# append inside the window wakes Brokk with id, elapsed, and last line.
LAUNCH_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LAUNCH_EPOCH=$(date +%s)
printf 'working: launched %s (heartbeat baseline)\n' "$LAUNCH_ISO" >> "$STATE/$ID.status" 2>/dev/null || true

# --- record state ------------------------------------------------------------
SPAWN_GEN="s$(date +%s).${BASHPID:-$$}.$RANDOM"
META_TMP="$STATE/.$ID.meta.${BASHPID:-$$}"
{
  printf 'id=%s\n' "$ID"
  printf 'kind=%s\n' "$KIND"
  if [ "$KIND" = ship ]; then
    printf 'mode=%s\n' "$MODE"
    printf 'yolo=%s\n' "$YOLO"
  fi
  printf 'harness=%s\n' "$HARNESS"
  printf 'raw_launch=%s\n' "$RAW_LAUNCH"
  printf 'harness_provenance=%s\n' "${HARNESS_PROV:-}"
  printf 'model=%s\n' "$MODEL"
  printf 'model_provenance=%s\n' "${MODEL_PROV:-}"
  printf 'model_local=%s\n' "$MODEL_LOCAL"
  printf 'effort=%s\n' "$EFFORT"
  printf 'backend=%s\n' "$RESOLVED_BACKEND"
  printf 'backend_reason=%s\n' "$BACKEND_WHY"
  printf 'window=%s\n' "$RUN_TARGET"
  printf 'seat=%s\n' "$SEAT_PROVEN"
  printf 'seat_pane=%s\n' "$SEAT_PANE"
  printf 'seat_state=%s\n' "$SEAT_STATE"
  if [ -n "$SEAT_NOTE" ]; then printf 'seat_note=%s\n' "$SEAT_NOTE"; fi
  printf 'worktree=%s\n' "$WT"
  printf 'project=%s\n' "$PROJECT_DIR"
  printf 'brief=%s\n' "$BRIEF"
  printf 'isolation=%s\n' "$ISOLATION_EFFECTIVE"
  printf 'isolation_declared=%s\n' "$ISOLATION_DECLARED"
  printf 'isolation_reason=%s\n' "$ISOLATION_REASON"
  printf 'worth_a_smith=%s\n' "${WORTH_VERDICT:-yes}"
  printf 'worth_why=%s\n' "$WORTH_WHY"
  printf 'force=%s\n' "$FORCE"
  printf 'locked=%s\n' "$LOCKED"
  printf 'launched=%s\n' "$LAUNCH_EPOCH"
  printf 'launch_iso=%s\n' "$LAUNCH_ISO"
  printf 'launch=%s\n' "$LAUNCH_SCRIPT"
  printf 'spawn_gen=%s\n' "$SPAWN_GEN"
} > "$META_TMP"
mv "$META_TMP" "$META"

# --- arm the silence watch, AND PROVE IT ARMED -------------------------------
# This used to be `|| true`, so a seat could be launched with no watchdog and nobody knew:
# eighteen statuses claimed to be working for up to 719 hours because nothing was ever
# going to notice the silence (2026-10-24). Arming is now verified, and a failure is loud
# and recorded in the meta — a seat without a watchdog is a fact the next reader can see.
WATCH_STATE=unarmed
if [ -x "$SCRIPT_DIR/eindri-watch.sh" ]; then
  if "$SCRIPT_DIR/eindri-watch.sh" arm-silence "$ID" --window "${EINDRI_SILENT_WINDOW:-1800}" >/dev/null 2>&1; then
    "$SCRIPT_DIR/eindri-watch.sh" list 2>/dev/null | grep -q "when-${ID}-silent" && WATCH_STATE=armed
  fi
fi
if [ "$WATCH_STATE" != armed ]; then
  printf 'watch[1]{seat,state,why}:\n  "%s","UNARMED","the silence watch did not register — nobody will notice this seat going quiet"\n' "$ID" >&2
  printf 'watch=unarmed\n' >> "$META" 2>/dev/null || true
  [ -x "$ROOT/bin/notify/send.sh" ] && bash "$ROOT/bin/notify/send.sh" --source seat --severity HIGH \
    --key "seat-unwatched:$ID" --message "seat $ID launched with NO silence watch — it can die silently" >/dev/null 2>&1 || true
else
  printf 'watch=armed window=%s\n' "${EINDRI_SILENT_WINDOW:-1800}" >> "$META" 2>/dev/null || true
fi

if [ "$KIND" = ship ]; then
  printf 'spawned %s harness=%s kind=%s mode=%s yolo=%s backend=%s target=%s worktree=%s isolation=%s seat=%s\n' \
    "$ID" "$HARNESS" "$KIND" "$MODE" "$YOLO" "$RESOLVED_BACKEND" "$RUN_TARGET" "$WT" "$ISOLATION_EFFECTIVE" "$SEAT_PROVEN"
else
  printf 'spawned %s harness=%s kind=%s backend=%s target=%s worktree=%s isolation=%s seat=%s\n' \
    "$ID" "$HARNESS" "$KIND" "$RESOLVED_BACKEND" "$RUN_TARGET" "$WT" "$ISOLATION_EFFECTIVE" "$SEAT_PROVEN"
fi

# --- an unproven seat is a FAILURE, reported and corrected at the source ------
# The dispatcher used to say `spawned` whether or not an agent ever stood in the
# pane. A record that claims a worker nobody can steer costs a whole errand, so
# the claim is corrected here — with the pane named — and Gná carries the word to
# the seat (bin/notify/send.sh) instead of a cheerful summary line.
if [ "$SEAT_PROVEN" != yes ]; then
  printf 'failed: the launch produced NO agent — pane %s (%s backend) holds no agent after %ss and no agent stands in %s (herdr agent list)\n' \
    "$SEAT_PANE" "$RESOLVED_BACKEND" "$SEAT_SETTLE" "$WT" >> "$STATE/$ID.status" 2>/dev/null || true
  printf 'seat=unproven pane=%s\n' "$SEAT_PANE" >> "$META" 2>/dev/null || true
  if [ -x "$ROOT/bin/notify/send.sh" ]; then
    bash "$ROOT/bin/notify/send.sh" --source seat --severity HIGH --key "seat-unproven:$ID:$SPAWN_GEN" \
      --message "seat $ID launched with NO agent in pane $SEAT_PANE — the errand is not running" >/dev/null 2>&1 || true
  fi
  printf 'error: %s is NOT seated — do not steer pane %s\nhelp: read the pane tail, then relaunch with a fresh launcher\n' "$ID" "$SEAT_PANE" >&2
  exit 3
fi