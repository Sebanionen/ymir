#!/usr/bin/env bash
# utgard.sh — the sealed execution barrier (Utgard, the realm outside the wall).
#
# Runs an untrusted task inside an ephemeral container: no host root, no network,
# CPU/RAM/timeout caps, a read-only rootfs, and only the task worktree mounted.
# A failed run leaves no trace on main. Galdr-style TOON output.
#
# Usage:
#   utgard.sh build [--tag <name>]
#   utgard.sh status
#   utgard.sh run <worktree> -- <command...> [--network none|on] [--cpus N] [--memory M] [--timeout S]
#   utgard.sh box <new|list|status|enter|url|seal|pull|stop|start|rm|gc|probe> …
#       a WHOLE COMPUTER for one run (the workshop), where `run` is a thirty-second
#       sealed command (the locker). See bin/forge/utgard-box.sh.
#   utgard.sh sandcastle <args…>   # the sandcastle engine (Docker/Podman/Vercel)
#   utgard.sh --version
#
# Engine: the isolated agent sandbox engine is **sandcastle**
# (github.com/mattpocock/sandcastle, `@ai-hero/sandcastle`); this script is the
# sealed Norse shell. `sandcastle` delegates to it; `run` uses utgard-runner.
#
# Exit: 0 ok, 1 error, 2 usage, 124 timeout.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
SANDBOX="$ROOT/.agents/sandbox"
TAG="${UTGARD_TAG:-utgard-runner:latest}"

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

CMD="${1-}"; shift || true
case "$CMD" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") usage; exit 0 ;;
esac

# `sandcastle` delegates to the sandbox engine (no docker-daemon requirement —
# it may use podman or vercel).
if [ "$CMD" = "sandcastle" ]; then
  command -v npx >/dev/null 2>&1 || { printf 'error: npx not found\nhelp: install node/npm to use sandcastle\n' >&2; exit 1; }
  exec npx --yes @ai-hero/sandcastle "$@"
fi

# `box` is the workshop: a durable computer, not a sealed command. It has its own
# door because it has its own laws (see bin/forge/utgard-box.sh).
if [ "$CMD" = "box" ]; then
  exec "$SCRIPT_DIR/utgard-box.sh" "$@"
fi

# shellcheck source=bin/fleet/ymir-platform.sh
. "$SCRIPT_DIR/../fleet/ymir-platform.sh"
ENGINE="$(ymir_container_engine)" || {
  printf 'error: no container engine (docker/podman) reachable\nhelp: install Docker or Podman, or set YMIR_CONTAINER_ENGINE to the one you use\n' >&2
  exit 1
}

case "$CMD" in
  build)
    while [ $# -gt 0 ]; do case "$1" in --tag) TAG=${2-}; shift 2 ;; *) shift ;; esac; done
    [ -f "$SANDBOX/Dockerfile.utgard" ] || { printf 'error: Dockerfile.utgard missing\n' >&2; exit 1; }
    if "$ENGINE" build -q -f "$SANDBOX/Dockerfile.utgard" -t "$TAG" "$SANDBOX" >/dev/null 2>&1; then
      printf 'utgard[1]{image,status}:\n  "%s","built"\n' "$TAG"
    else
      printf 'error: build failed for %s\nhelp: run %s build -f .agents/sandbox/Dockerfile.utgard -t %s .agents/sandbox\n' "$TAG" "$ENGINE" "$TAG" >&2
      exit 1
    fi
    ;;

  status)
    if "$ENGINE" image inspect "$TAG" >/dev/null 2>&1; then
      printf 'utgard[1]{image,status,net_default,caps}:\n  "%s","ready","none","cpus+mem+timeout"\n' "$TAG"
    else
      printf 'utgard[1]{image,status,net_default,caps}:\n  "%s","missing","none","cpus+mem+timeout"\n' "$TAG"
      printf 'help[1]: bin/forge/utgard.sh build\n'
    fi
    ;;

  run)
    WT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --) shift; break ;;
        --network) NET=${2-none}; shift 2 ;;
        --cpus) CPUS=${2-1.0}; shift 2 ;;
        --memory) MEM=${2-512m}; shift 2 ;;
        --timeout) TO=${2-30}; shift 2 ;;
        *) WT=$1; shift ;;
      esac
    done
    [ -n "$WT" ] || { printf 'error: run needs a worktree path\nhelp: bin/forge/utgard.sh run <worktree> -- <command>\n' >&2; exit 2; }
    [ -d "$WT" ] || { printf 'error: worktree not found: %s\n' "$WT" >&2; exit 1; }
    [ "$#" -gt 0 ] || { printf 'error: run needs a command after --\n' >&2; exit 2; }
    WT="$(cd "$WT" && pwd)"
    NET="${NET:-none}"; CPUS="${CPUS:-1.0}"; MEM="${MEM:-512m}"; TO="${TO:-30}"
    UID_GID="$(id -u):$(id -g)"
    "$ENGINE" image inspect "$TAG" >/dev/null 2>&1 || { printf 'error: image %s missing\nhelp: bin/forge/utgard.sh build\n' "$TAG" >&2; exit 1; }
    # Rootless Podman maps the host user differently: use --userns=keep-id so the
    # mounted worktree stays writable by the invoking user; Docker keeps --user.
    ARGS=(run --rm --network "$NET" --cpus "$CPUS" -m "$MEM"
          --security-opt no-new-privileges
          --read-only --tmpfs /tmp:rw,size=64m)
    if ymir_rootless_podman; then
      ARGS+=(--userns=keep-id)
    else
      ARGS+=(--user "$UID_GID")
    fi
    # `:Z` relabels the bind mount on enforcing-SELinux hosts (Fedora), else empty.
    ARGS+=(-v "$WT":/sandbox/workspace"$(ymir_volume_suffix)" -w /sandbox/workspace "$TAG" bash -lc "$*")
    timeout "$TO" "$ENGINE" "${ARGS[@]}"
    rc=$?
    [ "$rc" = 124 ] && { printf 'error: utgard run exceeded %ss timeout (sealed)\n' "$TO" >&2; exit 124; }
    exit "$rc"
    ;;

  *)
    printf 'error: unknown command %s\nhelp: bin/forge/utgard.sh [build|status|run|box|sandcastle|--version]\n' "$CMD" >&2
    exit 2 ;;
esac
