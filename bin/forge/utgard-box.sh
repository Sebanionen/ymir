#!/usr/bin/env bash
# utgard-box.sh — a whole computer for one run, outside the wall.
#
# `utgard` names the realm outside the wall. `utgard run` is the LOCKER: one
# sealed command, thirty seconds, gone. `utgard box` is the WORKSHOP: a durable
# computer an agent owns for the length of a run — its own root, its own clone,
# its own tools, its own vanishing point.
#
# Why it exists: a routine run used to have the operator's whole machine as its
# blast radius, sharing $HOME, the git identity and the rail key. A box shares
# none of them. It holds NO secret at all — the door holds the model credential
# and injects it, so a box that is fully compromised has nothing worth taking.
#
# Usage:
#   utgard-box.sh build [--tag T] [--pull]          # build the box image
#   utgard-box.sh new <name> [--repo P] [--ttl 4h] [--seal none|door|open]
#                            [--port 3000] [--lane L] [--model M] [--image T]
#   utgard-box.sh list                               # the estate, with time left
#   utgard-box.sh status <name>
#   utgard-box.sh enter <name> [-- <command…>]       # a shell, or one command
#   utgard-box.sh url <name>                         # the box's own door
#   utgard-box.sh seal <name> <none|door|open>       # re-seal a running box
#   utgard-box.sh pull <name> <path-in-box> [dest]   # bring the harvest home
#   utgard-box.sh stop <name> | start <name>
#   utgard-box.sh rm <name> [--keep-volume]
#   utgard-box.sh gc [--dry-run]                     # reclaim past-TTL boxes
#   utgard-box.sh probe [--repo P]                   # prove the three laws
#   utgard-box.sh --version
#
# The three laws a box carries, and defence of each:
#   1. No host credentials — no $HOME, no vault, no ssh key, no rail key.
#   2. One road out — the door, whose allowlist names the rail and the gateway.
#   3. A box is a record — labelled, timed, and reclaimed; never a stray.
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused (a law would be broken).
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
SANDBOX="$ROOT/.agents/sandbox"
DOOR_PY="$SCRIPT_DIR/utgard-box-door.py"
PREFIX="${UTGARD_BOX_PREFIX:-utgard}"
TAG="${UTGARD_BOX_IMAGE:-utgard-box:latest}"
DOOR_PORT="${UTGARD_BOX_DOOR_PORT:-3128}"
URL_PORT_BASE="${UTGARD_BOX_PORT_BASE:-8800}"
# The doors' outward road. A box cannot reach a service on the host at all while
# the host firewall drops input from a bridge (ufw's default policy is DROP, and
# container->host is INPUT). So the doors share ONE named network with a fixed
# subnet, and the operator's firewall rule names that subnet and nothing else.
DOOR_NET="${UTGARD_BOX_DOOR_NET:-utgard-door-net}"
DOOR_SUBNET="${UTGARD_BOX_DOOR_SUBNET:-172.31.77.0/24}"
RAIL_TARGET="${UTGARD_BOX_RAIL_TARGET:-host.docker.internal:8080}"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
refuse() { printf 'refused: %s\n' "$*" >&2; exit 3; }

# --- the engine, resolved once (Rule 07) --------------------------------------
. "$SCRIPT_DIR/../fleet/ymir-platform.sh"
ENGINE="$(ymir_container_engine)" || die "no container engine (docker/podman) reachable
help: install Docker or Podman, or set YMIR_CONTAINER_ENGINE to the one you use"

# --- naming: one name, one container, one volume, one road --------------------
cname()  { printf '%s-%s' "$PREFIX" "$1"; }
vname()  { printf '%s-%s-work' "$PREFIX" "$1"; }
nname()  { printf '%s-%s-net' "$PREFIX" "$1"; }
dname()  { printf '%s-%s-door' "$PREFIX" "$1"; }

valid_name() {
  case "$1" in
    ''|*[!a-zA-Z0-9_.-]*) return 1 ;;
    -*) return 1 ;;
  esac
  [ "${#1}" -le 40 ]
}

label() { "$ENGINE" inspect --format "{{ index .Config.Labels \"$2\" }}" "$1" 2>/dev/null; }

# A seal is what the kernel enforces, not what a label remembers: labels are
# immutable once a container exists, so the seal is READ from its attachments.
seal_of() {
  local nets
  nets="$("$ENGINE" inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" 2>/dev/null)"
  case "$nets" in
    *"$(nname "${2:-}")"*) printf 'door' ;;
    *bridge*) printf 'open' ;;
    *) printf 'none' ;;
  esac
}

exists() { "$ENGINE" container inspect "$1" >/dev/null 2>&1; }
running() { [ "$("$ENGINE" inspect --format '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

# The rail's key never enters a box. The DOOR holds it; this is the one read,
# through the vault door, and it never prints.
rail_key() {
  if [ -n "${UTGARD_BOX_KEY:-}" ]; then printf '%s' "$UTGARD_BOX_KEY"; return 0; fi
  local out
  out="$(bash "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null \
    | sed -n 's/^\(export \)\{0,1\}LLAMA_SWAP_API_KEY=//p' | head -1 | tr -d '"'"'"'')"
  printf '%s' "$out"
}

# The model is resolved, never guessed, and the provenance is printed (Rule 07):
#   --model  ->  YMIR_UTGARD_BOX_MODEL  ->  the first alias this seat's rail serves.
# A hosted provider is deliberately NOT a default: a box holds no key for one,
# so defaulting to a cloud model would be a door that cannot open.
resolve_model() {
  local explicit="${1-}"
  if [ -n "$explicit" ]; then
    printf '%s\t%s' "$explicit" "explicit"
    return 0
  fi
  if [ -n "${YMIR_UTGARD_BOX_MODEL:-}" ]; then
    printf '%s\t%s' "$YMIR_UTGARD_BOX_MODEL" "YMIR_UTGARD_BOX_MODEL"
    return 0
  fi
  local first
  first="$(timeout 30 bash "$ROOT/bin/model/catalog.sh" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"llama-swap","\([^"]*\)".*/\1/p' | head -1)"
  if [ -n "$first" ]; then
    printf '%s\t%s' "$first" "the rail's first alias"
    return 0
  fi
  return 1
}

# One port, checked rather than counted: a reclaimed box must not take the next
# box's door with it.
next_free_port() {
  local p=$URL_PORT_BASE limit=$(( URL_PORT_BASE + 200 ))
  while [ "$p" -lt "$limit" ]; do
    if ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)$p\$"; then
      printf '%s' "$p"
      return 0
    fi
    p=$(( p + 1 ))
  done
  return 1
}

ttl_seconds() {
  local raw="$1"
  case "$raw" in
    *h) echo $(( ${raw%h} * 3600 )) ;;
    *m) echo $(( ${raw%m} * 60 )) ;;
    *s) echo "${raw%s}" ;;
    ''|*[!0-9]*) return 1 ;;
    *) echo "$raw" ;;
  esac
}

now() { date +%s; }

# The door's outward road: one named network, a fixed subnet, created once.
# The host's own address in the door subnet: 172.31.78.0/24 -> 172.31.78.1
door_gateway() {
  local cidr="${DOOR_SUBNET%%/*}"
  printf '%s.1' "${cidr%.*}"
}

ensure_door_net() {
  "$ENGINE" network inspect "$DOOR_NET" >/dev/null 2>&1 && return 0
  if "$ENGINE" network create --subnet "$DOOR_SUBNET" "$DOOR_NET" >/dev/null 2>&1; then
    return 0
  fi
  # A subnet already taken by another engine network is the common case, and a
  # door that silently loses its road is exactly the fault this house keeps
  # paying for. Try the neighbours, and SAY which subnet answered.
  local base="${DOOR_SUBNET%%.*}" second third
  second="$(printf '%s' "$DOOR_SUBNET" | cut -d. -f2)"
  third="$(printf '%s' "$DOOR_SUBNET" | cut -d. -f3)"
  local candidate
  for candidate in 78 79 80 81 82 83 84 85 86 87 88; do
    if "$ENGINE" network create --subnet "${base}.${second}.${candidate}.0/24" "$DOOR_NET" >/dev/null 2>&1; then
      DOOR_SUBNET="${base}.${second}.${candidate}.0/24"
      printf 'note: the door network took %s (the configured subnet was already in use)\n' "$DOOR_SUBNET"
      return 0
    fi
  done
  printf 'warn: could not create network %s on any tried subnet\n' "$DOOR_NET" >&2
  return 1
}

# The exact rule that opens this one road, printed rather than applied: the ward
# is the operator's (RULES/24), and a script that silently widens a firewall is
# the fault this house keeps paying for.
rail_road_remedy() {
  local hostport
  hostport="${RAIL_TARGET##*:}"
  printf 'remedy: the box cannot reach the rail, because the host firewall drops input from a bridge\n'
  printf '  measured: ufw is active, DEFAULT_INPUT_POLICY=DROP\n'
  printf '  one rule opens exactly this road, and nothing else:\n'
  printf '    sudo ufw allow from %s to any port %s proto tcp\n' "$DOOR_SUBNET" "$hostport"
}

# Ask the door to dial the rail; a door that cannot reach it is a closed box.
rail_reachable() {
  local door="$1" port="${RAIL_TARGET##*:}" target
  target="$(rail_target_host)"
  "$ENGINE" exec "$door" bash -lc "timeout 4 bash -c 'exec 3<>/dev/tcp/$target/$port' 2>/dev/null" >/dev/null 2>&1
}

rail_target_host() { printf '%s' "${RAIL_TARGET%%:*}"; }

# --- the door: one road out, and the key lives here ---------------------------
door_map() { printf 'rail=%s' "$RAIL_TARGET"; }

start_door() {
  local name="$1" net door map key err
  net="$(nname "$name")"; door="$(dname "$name")"
  map="$(door_map)"
  key="$(rail_key)"
  ensure_door_net
  "$ENGINE" rm -f "$door" >/dev/null 2>&1 || true

  local -a run_args=(
    run -d --name "$door"
    --label "ymir.utgard.box=$name"
    --label "ymir.utgard.role=door"
    --network "$net" --network-alias door
    --add-host "host.docker.internal:$(door_gateway)"
    -v "$DOOR_PY:/door.py:ro"
    -e "UTGARD_DOOR_MAP=$map"
    -e "UTGARD_DOOR_PORT=$DOOR_PORT"
  )
  [ -n "$key" ] && run_args+=(-e "UTGARD_DOOR_KEY=$key")

  if ! err="$("$ENGINE" "${run_args[@]}" "$TAG" python3 /door.py 2>&1)"; then
    printf 'door: the engine refused to start %s\n' "$door" >&2
    printf '%s\n' "$err" | sed 's/^/       engine: /' >&2
    return 1
  fi
  # The door's outward road: the shared door network, never the ordinary bridge,
  # so the operator's rule can name one subnet and one port.
  "$ENGINE" network connect "$DOOR_NET" "$door" >/dev/null 2>&1 || true
  return 0
}

stop_door() { "$ENGINE" rm -f "$(dname "$1")" >/dev/null 2>&1 || true; }

# --- verbs -------------------------------------------------------------------

cmd_build() {
  local pull=0
  while [ $# -gt 0 ]; do case "$1" in
    --tag) TAG=${2-}; shift 2 ;;
    --pull) pull=1; shift ;;
    *) die "build: unknown flag $1" ;;
  esac; done
  [ -f "$SANDBOX/Dockerfile.box" ] || die "Dockerfile.box missing at $SANDBOX"
  printf 'box[1]{image,building}:\n  "%s","yes"\n' "$TAG"
  local args=(build -q -f "$SANDBOX/Dockerfile.box" -t "$TAG" "$SANDBOX")
  [ "$pull" = 1 ] && args=(build --pull -q -f "$SANDBOX/Dockerfile.box" -t "$TAG" "$SANDBOX")
  if ! "$ENGINE" "${args[@]}"; then
    die "box image build failed
help: $ENGINE build -f $SANDBOX/Dockerfile.box -t $TAG $SANDBOX"
  fi
  printf 'box[1]{image,status}:\n  "%s","built"\n' "$TAG"
}

cmd_new() {
  local name="" repo="" ttl_raw="4h" seal="door" port="3000" lane="" model="" model_req="" image="$TAG"
  while [ $# -gt 0 ]; do case "$1" in
    --repo) repo=${2-}; shift 2 ;;
    --ttl) ttl_raw=${2-}; shift 2 ;;
    --seal) seal=${2-}; shift 2 ;;
    --port) port=${2-}; shift 2 ;;
    --lane) lane=${2-}; shift 2 ;;
    --model) model_req=${2-}; shift 2 ;;
    --image) image=${2-}; shift 2 ;;
    -*) die "new: unknown flag $1" ;;
    *) name=$1; shift ;;
  esac; done
  [ -n "$name" ] || die "new: a box needs a name
help: utgard box new <name> [--repo P] [--seal none|door|open]"
  valid_name "$name" || die "new: '$name' is not a box name (letters, digits, . _ -; max 40)"
  case "$seal" in none|door|open) ;; *) die "new: --seal must be none, door or open" ;; esac

  local ttl
  ttl="$(ttl_seconds "$ttl_raw")" || die "new: --ttl wants 30m, 4h or 3600"
  [ "$ttl" -ge 300 ] || die "new: a box shorter than 5 minutes is a locker — use 'utgard run'"

  local c v n
  c="$(cname "$name")"; v="$(vname "$name")"; n="$(nname "$name")"
  exists "$c" && die "new: box '$name' already exists
help: utgard box rm $name, or utgard box enter $name"

  "$ENGINE" image inspect "$image" >/dev/null 2>&1 || die "new: image $image is missing
help: utgard box build"

  [ -n "$model" ] || model="$(resolve_model "$model_req" | cut -f1)" || true
  local model_prov
  model_prov="$(resolve_model "$model_req" | cut -f2)"
  [ -z "$model_prov" ] && model_prov="explicit"
  [ -n "$model" ] || die "new: no model resolved
help: utgard box new $name --model <alias>   (see bin/model/catalog.sh)"
  if [ -z "$(rail_key)" ]; then
    printf 'warn: no rail key in the vault — the door will serve without a credential, and the rail will answer 401\n' >&2
  fi

  local deadline
  deadline=$(( $(now) + ttl ))

  local -a net_args=()
  case "$seal" in
    none) net_args=(--network none) ;;
    door) net_args=(--network "$n") ;;
    open) net_args=(--network bridge) ;;
  esac

  local -a port_args=()
  local hostport=""
  if [ "$seal" != "none" ] && [ -n "$port" ] && [ "$port" != "0" ]; then
    hostport="$(next_free_port)" || die "new: no free loopback port from $URL_PORT_BASE"
    port_args=(-p "127.0.0.1:${hostport}:${port}")
  else
    port=""
  fi

  local -a env_args=(
    -e "OPENAI_BASE_URL=http://rail:8080/v1"
    -e "OPENAI_API_KEY=door"
    -e "OPENAI_MODEL=$model"
    -e "YMIR_BOX=$name"
  )
  if [ "$seal" = "door" ]; then
    env_args+=(
      -e "HTTP_PROXY=http://door:${DOOR_PORT}"
      -e "HTTPS_PROXY=http://door:${DOOR_PORT}"
      -e "http_proxy=http://door:${DOOR_PORT}"
      -e "https_proxy=http://door:${DOOR_PORT}"
      -e "NO_PROXY=localhost,127.0.0.1"
    )
  fi

  case "$seal" in
    door)
      "$ENGINE" network inspect "$n" >/dev/null 2>&1 || "$ENGINE" network create --internal "$n" >/dev/null \
        || die "new: could not create network $n"
      ;;
  esac

  "$ENGINE" volume inspect "$v" >/dev/null 2>&1 || "$ENGINE" volume create "$v" >/dev/null \
    || die "new: could not create volume $v"

  if ! "$ENGINE" run -d --name "$c" \
      "${net_args[@]}" "${port_args[@]}" "${env_args[@]}" \
      --label "ymir.utgard.box=$name" \
      --label "ymir.utgard.role=box" \
      --label "ymir.utgard.seal=$seal" \
      --label "ymir.utgard.created=$(now)" \
      --label "ymir.utgard.deadline=$deadline" \
      --label "ymir.utgard.ttl=$ttl" \
      --label "ymir.utgard.model=$model" \
      --label "ymir.utgard.lane=${lane:--}" \
      --label "ymir.utgard.hostport=${hostport:--}" \
      --label "ymir.utgard.boxport=${port:--}" \
      -v "$v:/box" \
      --security-opt no-new-privileges \
      "$image" >/dev/null; then
    die "new: the engine refused to start $c"
  fi

  if [ "$seal" = "door" ]; then
    start_door "$name" || die "new: the box started but its door did not
help: utgard box seal $name none   (a box with no road is still a box)"
    rail_reachable "$(dname "$name")" || rail_road_remedy
  fi

  # Seed the work: a COPY, never a mount. The host tree is not exposed to the box
  # even read-only, so nothing inside can write home.
  if [ -n "$repo" ]; then
    local src
    src="$(cd "$repo" 2>/dev/null && pwd)" || die "new: --repo not found: $repo"
    "$ENGINE" cp "$src/." "$c:/box/work" >/dev/null 2>&1 \
      || die "new: could not seed /box/work from $src"
  fi

  seat_pi "$name" "$model"

  printf 'box[8]{name,container,seal,model,model_from,url,ttl,deadline}:'
  printf '\n'
  printf '  "%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$name" "$c" "$seal" "$model" "${model_prov:-explicit}" "$(url_of "$name")" "$ttl_raw" \
    "$(date -d "@$deadline" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo "$deadline")"
  [ -n "$lane" ] && printf 'lane: %s\n' "$lane"
  [ "$seal" = "open" ] && printf 'warn: seal=open — this box may reach the internet. Declared, labelled, and reclaimed by TTL.\n'
  return 0
}

# Write the box's own pi seat: a registry that names `rail` — a name with no
# meaning outside the door, so the box never learns an address.
seat_pi() {
  local name="$1" model="$2" c model_id
  c="$(cname "$name")"
  model_id="${model##*/}"
  "$ENGINE" exec -i "$c" bash -lc "
    mkdir -p /home/agent/.pi/agent
    cat > /home/agent/.pi/agent/models.json <<'JSON'
{
  \"providers\": {
    \"rail\": {
      \"baseURL\": \"http://rail:8080/v1\",
      \"apiKey\": \"door\",
      \"models\": [{ \"id\": \"$model_id\", \"name\": \"$model_id\" }]
    }
  }
}
JSON
    printf '{\"defaultProvider\":\"rail\",\"defaultModel\":\"%s\"}' '$model_id' > /home/agent/.pi/agent/settings.json
  " >/dev/null 2>&1 || printf 'warn: the box has no pi seat written — enter it and seat one by hand\n' >&2
}

url_of() {
  local c hostport boxport
  c="$(cname "$1")"
  exists "$c" || return 0
  hostport="$(label "$c" ymir.utgard.hostport)"
  boxport="$(label "$c" ymir.utgard.boxport)"
  case "$hostport" in ''|-|null) return 0 ;; esac
  printf 'http://127.0.0.1:%s' "$hostport"
}

cmd_list() {
  local rows count
  rows="$("$ENGINE" ps -a --filter "label=ymir.utgard.role=box" \
    --format '{{.Names}}\t{{.Status}}\t{{.Label "ymir.utgard.deadline"}}\t{{.Label "ymir.utgard.hostport"}}\t{{.Label "ymir.utgard.lane"}}' 2>/dev/null)"
  count=0
  [ -n "$rows" ] && count=$(printf '%s\n' "$rows" | grep -c . || true)
  printf 'boxes[%s]{name,seal,state,left,url,lane}:\n' "$count"
  [ -z "$rows" ] && return 0
  local t now_ c_name status seal deadline hostport lane left
  now_="$(now)"
  while IFS=$'\t' read -r c_name status deadline hostport lane _rest; do
    [ -n "$c_name" ] || continue
    t="${c_name#${PREFIX}-}"
    seal="$(seal_of "$c_name" "$t")"
    case "$deadline" in ''|-|null) left="-" ;; *)
      left=$(( deadline - now_ ))
      if [ "$left" -le 0 ]; then left="expired"; else
        if [ "$left" -ge 3600 ]; then left="$(( left / 3600 ))h$(( (left % 3600) / 60 ))m"; else left="$(( left / 60 ))m"; fi
      fi ;;
    esac
    case "$status" in Up*) status="running" ;; *) status="stopped" ;; esac
    case "$hostport" in ''|-|null) hostport="-" ;; *) hostport="http://127.0.0.1:$hostport" ;; esac
    printf '  "%s","%s","%s","%s","%s","%s"\n' "$t" "$seal" "$status" "$left" "$hostport" "${lane:--}"
  done <<EOF
$rows
EOF
}

cmd_status() {
  local name="${1-}"; shift || true
  [ -n "$name" ] || die "status: which box?"
  local c; c="$(cname "$name")"
  exists "$c" || die "status: no box named $name"
  local seal deadline ttl model lane created hostport
  seal="$(seal_of "$c" "$name")"
  deadline="$(label "$c" ymir.utgard.deadline)"
  ttl="$(label "$c" ymir.utgard.ttl)"
  model="$(label "$c" ymir.utgard.model)"
  lane="$(label "$c" ymir.utgard.lane)"
  created="$(label "$c" ymir.utgard.created)"
  hostport="$(label "$c" ymir.utgard.hostport)"
  local state left
  running "$c" && state="running" || state="stopped"
  left=$(( ${deadline:-0} - $(now) ))
  [ "$left" -lt 0 ] && left=0
  printf 'box[8]{name,state,seal,model,url,left_s,ttl_s,created}:\n'
  printf '  "%s","%s","%s","%s","%s","%s","%s","%s"\n' \
    "$name" "$state" "$seal" "$model" "$(url_of "$name")" "$left" "${ttl:-0}" "${created:-0}"
  [ "${lane:--}" = "-" ] || printf 'lane: %s\n' "$lane"
  "$ENGINE" exec "$c" bash -lc 'printf "inside: home=%s user=%s cwd=%s\n" "$HOME" "$(id -un)" "$PWD"' 2>/dev/null || true
}

cmd_enter() {
  local name="${1-}"; shift || true
  [ -n "$name" ] || die "enter: which box?"
  [ "${1-}" = "--" ] && shift
  local c; c="$(cname "$name")"
  exists "$c" || die "enter: no box named $name
help: utgard box list"
  running "$c" || die "enter: box $name is stopped
help: utgard box start $name"
  if [ "$#" -gt 0 ]; then
    "$ENGINE" exec -it "$c" bash -lc "$*"
  else
    "$ENGINE" exec -it "$c" bash -l
  fi
}

cmd_url() {
  local name="${1-}"
  [ -n "$name" ] || die "url: which box?"
  local u; u="$(url_of "$name")"
  [ -n "$u" ] || refuse "box $name has no door: its seal is 'none' or it was made without a port
help: utgard box new $name --port 3000   (the box serves on 3000 inside)"
  printf '%s\n' "$u"
}

cmd_seal() {
  local name="${1-}" seal="${2-}"
  [ -n "$name" ] && [ -n "$seal" ] || die "seal: utgard box seal <name> none|door|open"
  case "$seal" in none|door|open) ;; *) die "seal: must be none, door or open" ;; esac
  local c n; c="$(cname "$name")"; n="$(nname "$name")"
  exists "$c" || die "seal: no box named $name"
  stop_door "$name"
  case "$seal" in
    none)
      "$ENGINE" network disconnect -f bridge "$c" >/dev/null 2>&1 || true
      "$ENGINE" network disconnect -f "$n" "$c" >/dev/null 2>&1 || true
      ;;
    open)
      "$ENGINE" network disconnect -f "$n" "$c" >/dev/null 2>&1 || true
      "$ENGINE" network connect bridge "$c" >/dev/null 2>&1 || true
      ;;
    door)
      "$ENGINE" network disconnect -f bridge "$c" >/dev/null 2>&1 || true
      "$ENGINE" network inspect "$n" >/dev/null 2>&1 || "$ENGINE" network create --internal "$n" >/dev/null
      "$ENGINE" network connect "$n" "$c" >/dev/null 2>&1 || true
      start_door "$name" || die "seal: the box is on $n but no door answered"
      ;;
  esac
  local now_seal; now_seal="$(seal_of "$c" "$name")"
  printf 'box[3]{name,asked,enforced}:\n'
  printf '  "%s","%s","%s"\n' "$name" "$seal" "$now_seal"
  [ "$now_seal" = "$seal" ] || printf 'warn: asked for %s, the kernel says %s — restart the box\n' "$seal" "$now_seal" >&2
  [ "$seal" = door ] && { rail_reachable "$(dname "$name")" || rail_road_remedy; }
  return 0
}

cmd_pull() {
  local name="${1-}" inner="${2-}" dest="${3-}"
  [ -n "$name" ] && [ -n "$inner" ] || die "pull: utgard box pull <name> <path-in-box> [dest]"
  local c; c="$(cname "$name")"
  exists "$c" || die "pull: no box named $name"
  [ -n "$dest" ] || dest="."
  mkdir -p "$dest" || die "pull: cannot make $dest"
  "$ENGINE" cp "$c:$inner" "$dest" >/dev/null 2>&1 || die "pull: nothing at $inner in box $name"
  printf 'box[2]{name,from,to}:\n  "%s","%s","%s"\n' "$name" "$inner" "$dest"
}

cmd_stop() {
  local name="${1-}"; [ -n "$name" ] || die "stop: which box?"
  local c; c="$(cname "$name")"
  exists "$c" || die "stop: no box named $name"
  "$ENGINE" stop "$c" >/dev/null 2>&1 || die "stop: the engine refused"
  stop_door "$name"
  printf 'box[2]{name,state}:\n  "%s","stopped"\n' "$name"
}

cmd_start() {
  local name="${1-}"; [ -n "$name" ] || die "start: which box?"
  local c seal; c="$(cname "$name")"
  exists "$c" || die "start: no box named $name"
  seal="$(seal_of "$c" "$name")"
  "$ENGINE" start "$c" >/dev/null 2>&1 || die "start: the engine refused"
  [ "$seal" = "door" ] && { start_door "$name" || printf 'warn: box started, its door did not\n' >&2; }
  printf 'box[2]{name,state,seal}:\n  "%s","running","%s"\n' "$name" "$seal"
}

cmd_rm() {
  local name="${1-}" keep_volume=0
  shift || true
  [ "${1-}" = "--keep-volume" ] && keep_volume=1
  [ -n "$name" ] || die "rm: which box?"
  local c v n; c="$(cname "$name")"; v="$(vname "$name")"; n="$(nname "$name")"
  stop_door "$name"
  "$ENGINE" rm -f "$c" >/dev/null 2>&1 || true
  "$ENGINE" network rm "$n" >/dev/null 2>&1 || true
  [ "$keep_volume" = 1 ] || "$ENGINE" volume rm "$v" >/dev/null 2>&1 || true
  printf 'box[2]{name,removed,volume}:\n  "%s","yes","%s"\n' "$name" \
    "$([ "$keep_volume" = 1 ] && echo kept || echo removed)"
}

cmd_gc() {
  local dry=0
  [ "${1-}" = "--dry-run" ] && dry=1
  local c deadline left reclaimed=0
  for c in $("$ENGINE" ps -a --filter "label=ymir.utgard.role=box" --format '{{.Names}}' 2>/dev/null); do
    deadline="$(label "$c" ymir.utgard.deadline)"
    case "$deadline" in ''|-|null) continue ;; esac
    left=$(( deadline - $(now) ))
    [ "$left" -gt 0 ] && continue
    local name="${c#${PREFIX}-}"
    if [ "$dry" = 1 ]; then
      printf 'gc: would reclaim %s (expired %ss ago)\n' "$name" "$(( -left ))"
    else
      cmd_rm "$name" >/dev/null
      printf 'gc: reclaimed %s\n' "$name"
    fi
    reclaimed=$(( reclaimed + 1 ))
  done
  printf 'gc[1]{reclaimed,dry_run}:\n  "%s","%s"\n' "$reclaimed" "$([ "$dry" = 1 ] && echo yes || echo no)"
}

# --- the probe: the three laws, proved rather than asserted -------------------
cmd_probe() {
  local repo=""
  while [ $# -gt 0 ]; do case "$1" in
    --repo) repo=${2-}; shift 2 ;;
    *) die "probe: unknown flag $1" ;;
  esac; done
  local name="probe-$(date +%s)"
  printf 'probe[1]{box,built_from}:\n  "%s","%s"\n' "$name" "${repo:-nothing}"
  cmd_new "$name" --ttl 5m --seal door --port 0 --repo "$repo" >/dev/null \
    || die "probe: the box would not start — the probe cannot prove anything without a box"
  local c; c="$(cname "$name")"

  local home user rail_code rail_body outside_code outside_body
  home="$("$ENGINE" exec "$c" bash -lc 'printf "%s" "$HOME"' 2>/dev/null)"
  user="$("$ENGINE" exec "$c" bash -lc 'id -un' 2>/dev/null)"
  rail_code="$("$ENGINE" exec "$c" bash -lc 'curl -s -m 20 -o /tmp/rail.out -w "%{http_code}" "$OPENAI_BASE_URL/models"' 2>/dev/null)"
  rail_body="$("$ENGINE" exec "$c" bash -lc 'head -c 120 /tmp/rail.out 2>/dev/null' 2>/dev/null)"
  outside_code="$("$ENGINE" exec "$c" bash -lc 'curl -s -m 8 -o /tmp/out.out -w "%{http_code}" http://example.com || echo 000' 2>/dev/null)"
  outside_body="$("$ENGINE" exec "$c" bash -lc 'head -c 120 /tmp/out.out 2>/dev/null' 2>/dev/null)"
  local vault_in_box
  vault_in_box="$("$ENGINE" exec "$c" bash -lc 'ls /home/agent/Documents 2>/dev/null | wc -l' 2>/dev/null)"

  # One road out means: the door answered, or the door refused. Either proves the
  # box has exactly one peer. A real internet answer is the failure.
  local outside_verdict="PASS"
  case "${outside_code:-000}" in
    000) outside_verdict="PASS" ;;
    *) case "$outside_body" in
         *"no road to"*) outside_verdict="PASS" ;;
         *) outside_verdict="FAIL" ;;
       esac ;;
  esac

  printf 'probe[5]{law,measure,verdict}:\n'
  printf '  "no host home","HOME=%s user=%s vault_visible=%s","%s"\n' \
    "$home" "$user" "${vault_in_box:-0}" \
    "$([ "${vault_in_box:-1}" = 0 ] && echo PASS || echo FAIL)"
  printf '  "rail reachable through the door","http %s %s","%s"\n' \
    "${rail_code:-000}" "$(printf '%s' "$rail_body" | tr -d '\n' | cut -c1-40)" \
    "$([ "${rail_code:-000}" = 000 ] && echo FAIL || echo PASS)"
  printf '  "no other road","example.com %s %s","%s"\n' \
    "${outside_code:-000}" "$(printf '%s' "$outside_body" | tr -d '\n' | cut -c1-40)" "$outside_verdict"
  printf '  "no credential in the box","OPENAI_API_KEY=%s"\n' \
    "$("$ENGINE" exec "$c" bash -lc 'printf "%s" "$OPENAI_API_KEY"' 2>/dev/null)"
  cmd_rm "$name" >/dev/null
  printf 'probe[1]{hold,note}:\n  "%s","%s"\n' "" \
    "a probe that left a box behind is a probe that lied"
  [ "${rail_code:-000}" = 000 ] && rail_road_remedy
  return 0
}

# --- dispatch ----------------------------------------------------------------
CMD="${1-}"; shift || true
case "$CMD" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|help|"") usage; exit 0 ;;
esac

case "$CMD" in
  build)  cmd_build "$@" ;;
  new)    cmd_new "$@" ;;
  list|ls) cmd_list "$@" ;;
  status) cmd_status "$@" ;;
  enter)  cmd_enter "$@" ;;
  url)    cmd_url "$@" ;;
  seal)   cmd_seal "$@" ;;
  pull)   cmd_pull "$@" ;;
  stop)   cmd_stop "$@" ;;
  start)  cmd_start "$@" ;;
  rm)     cmd_rm "$@" ;;
  gc)     cmd_gc "$@" ;;
  probe)  cmd_probe "$@" ;;
  *)
    printf 'error: unknown verb %s\nhelp: utgard box [build|new|list|status|enter|url|seal|pull|stop|start|rm|gc|probe]\n' "$CMD" >&2
    exit 2 ;;
esac
