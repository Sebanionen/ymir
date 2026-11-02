#!/usr/bin/env bash
# ymir-platform.sh — the portability layer.
#
# Ymir must run on Linux, macOS and Windows (through WSL2 or MSYS/Git Bash).
# GNU coreutils are not guaranteed: BSD `readlink` has no `-f`, BSD `stat` uses
# `-f` not `-c`, macOS `date` has no `%N`, and `nproc`, `setsid`, `flock` and
# `/proc` do not exist there at all. This file is the ONE place that knows a
# platform difference; every other script calls these functions.
#
# Sourced, never executed:   . "$ROOT/bin/fleet/ymir-platform.sh"
# It defines functions only and has no side effects.
#
# Convention: every function is `ymir_*`, prints to stdout, and never exits the
# caller. A capability that is genuinely absent returns a non-zero status so the
# caller can decide; a capability with a sane fallback always succeeds.

# ── platform ─────────────────────────────────────────────────────────────────

ymir_os() {  # linux | macos | wsl | msys | android | unknown
  case "$(uname -s 2>/dev/null)" in
    Linux*)
      # Android/Termux says "Linux", but it is not a desktop distribution: there is no
      # /home/<user>/Documents, $PREFIX is Termux's, and `USER` is unset. Detected by
      # `uname -o`, Termux's own version var, or the Termux prefix — any one suffices.
      _android=0
      [ "$(uname -o 2>/dev/null)" = "Android" ] && _android=1
      [ -n "${TERMUX_VERSION:-}" ] && _android=1
      case "${PREFIX:-}" in *com.termux*) _android=1 ;; esac
      if [ "$_android" = 1 ]; then
        printf 'android'
      elif [ -r /proc/version ] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        printf 'wsl'
      else
        printf 'linux'
      fi ;;
    Darwin*)               printf 'macos' ;;
    MINGW*|MSYS*|CYGWIN*)  printf 'msys' ;;
    *)                     printf 'unknown' ;;
  esac
}


# ── basic tools ──────────────────────────────────────────────────────────────


ymir_readlink_f() {  # resolve symlinks; BSD readlink has no -f
  [ $# -ge 1 ] || return 1
  local p=$1
  if readlink -f -- "$p" >/dev/null 2>&1; then readlink -f -- "$p"; return 0; fi
  # Portable resolution: follow one link at a time, keeping the result absolute.
  local dir base target hops=0
  case "$p" in /*) : ;; *) p="$PWD/$p" ;; esac
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    hops=$((hops+1))
    dir=$(dirname "$p"); base=$(basename "$p")
    target=$(readlink "$p") || break
    case "$target" in /*) p="$target" ;; *) p="$dir/$target" ;; esac
  done
  # normalise . and .. lexically
  local resolved
  resolved=$(printf '%s' "$p" | awk -F/ '{
    n=0; for (i=1;i<=NF;i++) { if ($i==""||$i==".") continue; if ($i=="..") { if (n>0) n--; continue } a[++n]=$i }
    out=""; for (i=1;i<=n;i++) out=out"/"a[i]; if (out=="") out="/"; print out }')
  # Mirror GNU -f: every component but the last must exist, or the call fails
  # and prints nothing. Callers rely on that to detect a dangling link.
  if [ ! -d "$(dirname "$resolved")" ]; then return 1; fi
  printf '%s' "$resolved"
}



# ── stat: GNU -c vs BSD -f ───────────────────────────────────────────────────






# ── processes ────────────────────────────────────────────────────────────────

ymir_pid_alive() {  # 0 when the pid exists
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

ymir_pid_cmdline() {  # the command line of a pid, one line; empty when gone
  local pid=${1:-}
  [ -n "$pid" ] || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null
  else
    ps -o command= -p "$pid" 2>/dev/null     # works on macOS and BSD
  fi
}


ymir_kill_matching() {  # <pattern> [signal] — signal processes whose cmdline matches
  # NEVER a blanket kill: a pattern matcher that knows its own line takes the caller
  # with it (measured 2026-10-20 — twice). So the match is done here, by pid, and the
  # caller's own pid, its parent, and this function's own shell are excluded by name.
  local pat=${1:-} sig=${2:-TERM}
  [ -n "$pat" ] || return 1
  local self=$$ parent=0 pids="" pid args
  parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
  for pid in $(ps -eo pid= 2>/dev/null); do
    [ "$pid" = "$self" ] && continue
    [ "$pid" = "$parent" ] && continue
    args=$(ymir_pid_cmdline "$pid") || continue
    case "$args" in
      *"$pat"*) case "$args" in *ymir_kill_matching*|*"ps -eo pid="*) continue ;; esac
                pids="$pids $pid" ;;
    esac
  done
  [ -n "$pids" ] && kill -s "$sig" $pids 2>/dev/null || true
  return 0
}

ymir_detach() {  # run a command detached from this shell's lifetime
  # setsid where available (Linux/WSL); MSYS has it; macOS does not.
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" < /dev/null &
  else
    nohup "$@" < /dev/null > /dev/null 2>&1 &
  fi
  printf '%s' "$!"
}

# ── locking: flock vs a portable mkdir lock ─────────────────────────────────


# ── services: systemd (Linux) vs launchd (macOS) vs nothing ─────────────────



# ── containers: Docker or rootless Podman ───────────────────────────────────

# Which container engine to use. Fedora ships rootless Podman and frequently has
# no `docker` at all; Debian/Ubuntu usually have Docker. YMIR_CONTAINER_ENGINE
# forces one. Prints the engine name and returns 0, or returns 1 when none of
# them can actually be reached.
ymir_container_engine() {
  local e
  for e in ${YMIR_CONTAINER_ENGINE:-} docker podman; do
    [ -n "$e" ] || continue
    command -v "$e" >/dev/null 2>&1 || continue
    # podman answers `info` with no daemon; docker needs one running. Accept either.
    if "$e" info >/dev/null 2>&1; then printf '%s' "$e"; return 0; fi
  done
  return 1
}

# The engine binary that exists, even if its daemon is not reachable. Useful for
# diagnostics that want to name the engine rather than run it.
ymir_container_engine_name() {
  local e
  for e in ${YMIR_CONTAINER_ENGINE:-} docker podman; do
    [ -n "$e" ] || continue
    command -v "$e" >/dev/null 2>&1 && { printf '%s' "$e"; return 0; }
  done
  return 1
}

# true when SELinux is enforcing (Fedora). A bind mount into a container then
# needs the :Z relabel, or the container is denied access to the host path.
ymir_selinux_enforcing() {
  if [ -r /sys/fs/selinux/enforce ]; then
    [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = 1 ]
  elif command -v getenforce >/dev/null 2>&1; then
    [ "$(getenforce 2>/dev/null)" = "Enforcing" ]
  else
    return 1
  fi
}

# true when the resolved engine is Podman — including when the `docker` binary is
# really Podman (the podman-docker shim), which names itself in `info`.
ymir_engine_is_podman() {
  local e
  e="$(ymir_container_engine 2>/dev/null || ymir_container_engine_name 2>/dev/null)" || return 1
  [ -n "$e" ] || return 1
  [ "$e" = podman ] && return 0
  "$e" info 2>/dev/null | grep -qi podman
}

# true when rootless Podman: bind-mount ownership then needs --userns=keep-id so
# files land owned by the invoking user. Docker (and rootful Podman) do not.
ymir_rootless_podman() {
  ymir_engine_is_podman && [ "$(id -u)" -ne 0 ]
}

# true when Ymir itself is running inside a container (podman or docker).
ymir_in_container() {
  [ -e /run/.containerenv ] || [ -e /.dockerenv ] || [ -n "${container:-}" ]
}

# The `-v` suffix for a bind mount: `:Z` whenever SELinux is enforcing — Docker
# and Podman both need the relabel there — else empty. Append to `<host>:<ctr>`.
# FIX 2026-09-24: print-and-SUCCEED. The old `ymir_selinux_enforcing && printf ':Z'`
# returned 1 on every non-SELinux host, and under `set -e` that aborted any caller
# that captured the substitution (einherjar-spawn.sh:40 — the dispatcher died
# mute at rc=1 with zero output on Arch/macOS/most hosts). An empty suffix is a
# valid outcome, never an error.
ymir_volume_suffix() {
  if ymir_selinux_enforcing; then
    printf ':Z'
  fi
  return 0
}

# ── GPUs: report what exists, without assuming NVIDIA ───────────────────────




# ── paths ────────────────────────────────────────────────────────────────────



# ── isolation: is bwrap usable here? ─────────────────────────────────────────

# True when bubblewrap can actually create the namespaces it needs. This is a
# real probe, not a presence check: inside a hardened container (rootless Podman
# Quadlet), nested user namespaces are often denied and bwrap fails with
# "Creating new namespace failed: Operation not permitted". Callers must degrade,
# never assume.
ymir_bwrap_available() {
  command -v bwrap >/dev/null 2>&1 || return 1
  bwrap --unshare-all --die-with-parent --ro-bind / / true >/dev/null 2>&1
}

# True when Ymir itself is running inside a container (podman or docker).
ymir_in_container() {
  [ -e /run/.containerenv ] || [ -e /.dockerenv ] || [ -n "${container:-}" ]
}

# The isolation layers available here, outermost first. Prints a csv of any of
# `container,bwrap,none` — the caller picks, never assumes bwrap.
ymir_isolation_layers() {
  local out=""
  ymir_in_container && out="container"
  if ymir_bwrap_available; then out="${out:+$out,}bwrap"; fi
  [ -n "$out" ] || out="none"
  printf '%s' "$out"
}

# ── the host facilities every door uses, without naming a GNU tool ───────────
#
# Measured 2026-11-02: 43 scripts call `stat -c`, 43 call `sha256sum`, 10 `flock`, 7 `mapfile`, 6 `setsid`,
# 5 `nproc`, 4 `sed -i` — every one of them GNU-only, and none routed through here. These are the verbs;
# a script that needs the facility calls the verb (RULES/05, 2026-11-02 appended).

ymir_stat() {  # <format: size|mtime|mode> <path>
  local what=$1 path=$2
  case "$(ymir_os)" in
    macos|msys)
      case "$what" in
        size)  stat -f '%z' "$path" ;;
        mtime) stat -f '%m' "$path" ;;
        mode)  stat -f '%Lp' "$path" ;;
        *)     return 2 ;;
      esac ;;
    *)
      case "$what" in
        size)  stat -c '%s' "$path" ;;
        mtime) stat -c '%Y' "$path" ;;
        mode)  stat -c '%a' "$path" ;;
        *)     return 2 ;;
      esac ;;
  esac
}

ymir_sha256() {  # <file|-> — prints the bare digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r "$@" | awk '{print $1}'
  else return 1; fi
}

ymir_nproc() {  # how many CPUs this host will give us
  if command -v nproc >/dev/null 2>&1; then nproc
  elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu 2>/dev/null || printf '1'
  else printf '1'; fi
}

ymir_sed_i() {  # <script> <file...> — in place, whichever sed this is
  case "$(ymir_os)" in
    macos|msys) sed -i '' "$@" ;;
    *)          sed -i "$@" ;;
  esac
}

ymir_lock() {  # <lockfile> <command...> — an exclusive lock, flock where it exists, a mkdir-lock where not
  local lock=$1; shift
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lock" || return 1
    flock -n 9 || return 1
    "$@"; local rc=$?
    flock -u 9 2>/dev/null || true
    return $rc
  fi
  local d="$lock.d"
  mkdir "$d" 2>/dev/null || return 1
  "$@"; local rc=$?
  rmdir "$d" 2>/dev/null || true
  return $rc
}

ymir_read_lines() {  # <array-name> <file> — mapfile where bash has it, a while-read where it does not (3.2)
  local __name=$1 __file=$2 __line
  eval "$__name=()"
  if [ "${BASH_VERSINFO[0]}" -ge 4 ] && [ -n "${BASH_VERSINFO[1]:-}" ]; then
    mapfile -t "$__name" <"$__file" && return 0
  fi
  while IFS= read -r __line || [ -n "$__line" ]; do
    eval "$__name+=(\"\$__line\")"
  done <"$__file"
}
