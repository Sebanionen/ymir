#!/usr/bin/env bash
# ymir-validate.sh — verify the installation actually works.
#
# The installer reports what it did; this proves it. Every check is an
# observation of the running system (a live port, a readable store, a running
# process), never a restatement of intent. A FAIL means the install is not
# usable; a WARN means a documented-optional part is off.
#
# Usage:
#   bin/engine/ymir-validate.sh [--json] [--quiet]
#   bin/engine/ymir-validate.sh --version
#
# Exit: 0 all required checks pass, 1 a required check failed, 2 usage.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
# The cloth: colour and marks for the human reading this report; the TOON rows on
# stdout stay the data (bin/desktop/ymir-style.sh).
if [ -z "${YMIR_STYLE_LOADED:-}" ]; then
  . "$SCRIPT_DIR/../desktop/ymir-style.sh"; YMIR_STYLE_LOADED=1
fi
style_init
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

# shellcheck source=bin/fleet/ymir-platform.sh
. "$SCRIPT_DIR/../fleet/ymir-platform.sh"
# The one reader for the master registry's row keys (`realm:`, deprecated `workspace:`).
# shellcheck source=bin/skuld/registry-lib.sh
if [ -r "$SCRIPT_DIR/../skuld/registry-lib.sh" ]; then . "$SCRIPT_DIR/../skuld/registry-lib.sh"; fi
# Docker or rootless Podman (Fedora), whichever is present.
CONTAINER_ENGINE="$(ymir_container_engine_name 2>/dev/null || true)"
JSON=0; QUIET=0

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --quiet) QUIET=1; shift ;;
    *) printf 'error: unknown flag %s\nhelp: bin/engine/ymir-validate.sh [--json|--quiet]\n' "$1" >&2; exit 2 ;;
  esac
done

declare -a IDS STATES DETAILS
add() { IDS+=("$1"); STATES+=("$2"); DETAILS+=("$3"); }
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$1"; }

http_code() {  # <url> -> status code, or 000
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null || printf '000'
}
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# ── the role — a `hand` (phone) owns no services; a `dev`/`heart` does. Validate
# must SKIP what this role was never meant to run, never FAIL it for a service it
# does not hold. Resolved the same way the installer does (env → registry/card by
# hostname → the safe body, dev).
ROLE_SET="${YMIR_ROLE:-}"
if [ -z "$ROLE_SET" ] && [ -x "$ROOT/bin/skuld/role.sh" ]; then
  _t="$(printf '\t')"
  _rv="$(bash "$ROOT/bin/skuld/role.sh" resolve --host "${YMIR_HOST:-$(hostname -s 2>/dev/null)}" 2>/dev/null | head -1 || true)"
  case "$_rv" in
    *"$_t"registry|*"$_t"card|*"$_t"env) ROLE_SET="${_rv%%"$_t"*}" ;;
  esac
fi
ROLE_SET="${ROLE_SET:-dev}"
role_owns() { case ",$ROLE_SET," in *",$1,"*) return 0 ;; esac; return 1; }

# ── 1. prerequisites present ────────────────────────────────────────────────
# ASK THE MACHINE, never the PATH it was handed (RULES/25: PROBE, NEVER ASSUME). The
# installer writes `~/.bun/bin` for the NEXT login shell; a validator that only asked
# `command -v bun` reported `missing: bun` on a host that had it — measured on a clean
# Windows/WSL2 seat, 2026-11-03, where the operator was told to fix a working thing.
miss=""
for c in git python3 gh; do command -v "$c" >/dev/null 2>&1 || miss="$miss $c"; done
bun_path=""
role_owns dev && {
  bun_path="$(bash "$ROOT/bin/engine/prereq-ensure.sh" resolve bun 2>/dev/null | head -1 || true)"
  [ -n "$bun_path" ] || miss="$miss bun"
}
{ role_owns forge || role_owns dev; } && { [ -n "$CONTAINER_ENGINE" ] || miss="$miss docker/podman"; }
if [ -z "$miss" ]; then
  # Name the road that answered: a bun outside PATH is honest to report, not to hide.
  case "$bun_path" in
    ""|"$(command -v bun 2>/dev/null)") add prereqs PASS "git python3 gh present" ;;
    *) add prereqs PASS "git python3 gh present; bun at ${bun_path} (not on this shell's PATH — ~/.profile carries it)" ;;
  esac
else
  add prereqs FAIL "missing:$miss"
fi

# ── 2. Utgard sandbox image ─────────────────────────────────────────────────
if ! role_owns forge && ! role_owns dev; then
  add sandbox SKIP "not this machine's role (forge,dev only) — the sandbox"
elif [ -z "$CONTAINER_ENGINE" ]; then
  add sandbox WARN "no container engine (docker/podman) — sandbox unavailable"
elif "$CONTAINER_ENGINE" image inspect utgard-runner:latest >/dev/null 2>&1; then
  add sandbox PASS "utgard-runner:latest present ($CONTAINER_ENGINE)"
elif ! "$CONTAINER_ENGINE" info >/dev/null 2>&1; then
  add sandbox WARN "$CONTAINER_ENGINE not reachable (rootless podman: check login session; docker: check group)"
else
  add sandbox FAIL "utgard-runner:latest missing — run bin/forge/utgard.sh build"
fi

# ── 3. the gate API (:3889) — the control plane's data face ─────────────────
if ! role_owns heart && ! role_owns dev; then
  add gate-api SKIP "not this machine's role (heart,dev only) — the control plane"
else
code="$(http_code http://127.0.0.1:3889/api/health)"
case "$code" in
  200) add gate-api PASS "GET /api/health -> 200" ;;
  401) add gate-api PASS "GET /api/health -> 401 (up, auth enforced)" ;;
  000) add gate-api FAIL "no response on :3889 — run scripts/start.sh" ;;
  *)   add gate-api WARN "unexpected status $code on :3889" ;;
esac
fi

# ── 4. the SPA (:3888) ──────────────────────────────────────────────────────
if ! role_owns heart && ! role_owns dev; then
  add spa SKIP "not this machine's role (heart,dev only) — the SPA"
else
code="$(http_code http://127.0.0.1:3888/)"
if [ "$code" = 200 ]; then add spa PASS "GET / -> 200"
else add spa FAIL "no 200 on :3888 (got $code) — run scripts/start.sh"; fi
fi

# ── 5. Bifrost model bridge (:4603) — provider-aware, keyless-capable ───────
if ! role_owns heart && ! role_owns dev; then
  add bifrost SKIP "not this machine's role (heart,dev only) — the model bridge"
elif port_open 4603; then
  provider="$(curl -s --max-time 5 http://127.0.0.1:4603/v1/models 2>/dev/null | head -c 40)"
  if [ -n "$provider" ]; then add bifrost PASS "bridge up on :4603 (models served)"
  else add bifrost WARN "port 4603 open but /v1/models empty"; fi
else
  add bifrost FAIL "bridge down on :4603 — run bin/bridge/bifrost-bridge.sh --start"
fi

# ── 6. Nornir cron running ──────────────────────────────────────────────────
# The scheduler's cmdline is `bash -c <body>` and carries no "nornir" token, so
# ask nornir-cron-start.sh itself (it owns the identity check) instead of pgrep.
# A scheduler with NO live session lock retires ON PURPOSE (RULES: Nornir is started BY a
# session, never before one). Reporting that as a failure made a correct install look
# broken on a fresh seat — measured 2026-11-03 on Windows/WSL2. So: no live lock is a
# SKIP that names the reason; a live lock with no scheduler is the real FAIL.
session_lock_live() {
  local mach lockf owner st
  if [ -n "${BROKK_MACHINE_STATE_DIR:-}" ]; then mach="$BROKK_MACHINE_STATE_DIR"
  elif [ -f "$ROOT/state/.lock-path" ]; then
    mach="$(dirname "$(cat "$ROOT/state/.lock-path" 2>/dev/null || true)")"
    [ -d "$mach" ] || mach="${XDG_STATE_HOME:-$HOME/.local/state}/ymir"
  else mach="${XDG_STATE_HOME:-$HOME/.local/state}/ymir"; fi
  lockf="$mach/brokk.lock"
  owner="$(tr -d "[:space:]" <"$lockf" 2>/dev/null || true)"
  [ -n "$owner" ] || return 1
  st="$(ps -o stat= -p "$owner" 2>/dev/null | tr -d ' ')"
  [ -d "/proc/$owner" ] || return 1
  [ "${st#Z}" = "$st" ] && [ "${st#X}" = "$st" ]
}
if ! role_owns heart && ! role_owns dev; then
  add cron SKIP "not this machine's role (heart,dev only) — the record's schedule"
elif [ -x "$ROOT/bin/time/nornir-cron-start.sh" ]; then
  cron_out="$("$ROOT/bin/time/nornir-cron-start.sh" 2>/dev/null || true)"
  if printf '%s' "$cron_out" | grep -q 'cron: running'; then
    add cron PASS "$(printf '%s' "$cron_out" | grep -m1 'cron: running')"
  elif ! session_lock_live; then
    add cron SKIP "session-gated by design — the scheduler retires without a live seat; it starts with the next session"
  else
    add cron FAIL "nornir cron not running — run bin/time/nornir-cron-start.sh"
  fi
else
  add cron SKIP "no nornir-cron-start.sh"
fi

# ── 7. smidja db (visualizer readiness) ─────────────────────────────────────
# The same pair scripts/start.sh and bin/desktop/smidja-bootstrap.sh resolve: an existing
# $YMIR_HOME/smidja/smidja.db first, then an in-repo copy.
# The operator's home: env -> the recorded choice -> the ONE documented default
# (Rule 07; the default lives in bin/vault/hoard-lib.sh, never in a script).
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _ymir_yr="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _ymir_yc in "$_ymir_yr/hoard-lib.sh" "$_ymir_yr/../vault/hoard-lib.sh" "$_ymir_yr/../../vault/hoard-lib.sh"; do
    [ -r "$_ymir_yc" ] && { . "$_ymir_yc"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _ymir_yr _ymir_yc
fi
ymir_home_root YMIR_HOME
SMIDJA_DB_PATH="${SMIDJA_DB:-}"
if [ -z "$SMIDJA_DB_PATH" ]; then
  for c in "$YMIR_HOME/smidja/smidja.db" "$ROOT/apps/smidja/smidja_data/smidja.db"; do
    [ -f "$c" ] && { SMIDJA_DB_PATH="$c"; break; }
  done
  SMIDJA_DB_PATH="${SMIDJA_DB_PATH:-$YMIR_HOME/smidja/smidja.db}"
fi
if ! role_owns heart && ! role_owns dev; then
  add smidja-db SKIP "not this machine's role (heart,dev only) — the smithy"
elif [ -f "$SMIDJA_DB_PATH" ]; then
  add smidja-db PASS "smidja.db present"
else
  add smidja-db FAIL "smidja.db missing — run bin/desktop/smidja-bootstrap.sh"
fi

# ── 7b. visualizer (built ./dist AND its API actually listening) ────────────
# A PASS must mean the thing is UP. Probe the port, not just the build: a
# built-but-dead visualizer (a bad CMD_DB, a crashed API) is a FAIL, not green.
VIZ="${SMIDJA_VIZ:-}"
VIZ_PORT="${SMIDJA_VIZ_API_PORT:-8437}"
if ! role_owns dev; then
  add visualizer SKIP "not this machine's role (dev only) — the visualizer"
elif [ ! -d "$VIZ" ]; then
  add visualizer SKIP "no visualizer tree at $VIZ"
elif [ ! -d "$VIZ/dist" ]; then
  add visualizer FAIL "UI not built (./dist missing) — (cd $VIZ && bun run build)"
elif port_open "$VIZ_PORT"; then
  add visualizer PASS "UI built and served on :$VIZ_PORT"
else
  add visualizer FAIL "UI built but no API listening on :$VIZ_PORT — run scripts/start.sh"
fi

# ── 8. desktop apps (both Electron windows) ─────────────────────────────────
if ! role_owns dev; then
  add desktop SKIP "not this machine's role (dev only) — the desktop apps"
elif [ -x "$ROOT/scripts/electron.sh" ]; then
  st="$("$ROOT/scripts/electron.sh" status 2>/dev/null || true)"
  up_h=$(printf '%s' "$st" | grep -c '"hlidskjalf","up"' || true)
  up_s=$(printf '%s' "$st" | grep -c '"smidja","up"' || true)
  if [ "$up_h" = 1 ] && [ "$up_s" = 1 ]; then add desktop PASS "Hlidskjalf + Smíðja both up"
  elif [ "$up_h" = 1 ] || [ "$up_s" = 1 ]; then add desktop WARN "one desktop app up (h=$up_h s=$up_s) — run scripts/electron.sh start --both"
  else add desktop WARN "desktop apps not running — run scripts/electron.sh start --both"; fi
else
  add desktop SKIP "no scripts/electron.sh"
fi

# ── 9. the memory well (:4602) — documented optional ────────────────────────
if port_open 4602; then add memory PASS "Mimir bridge up on :4602"
else add memory WARN "well off (:4602) — needs the engram engine; platform runs without it"; fi

# ── 10. audit ledger intact ─────────────────────────────────────────────────
RUNES_LEDGER=""
# The ledger follows the hoard (Rule 06): 0004-hoard-and-realms moved it under
# hodd/memory/. Try the hoard first, then the pre-move locations.
for c in "${YMIR_HOME:+${YMIR_HOARD:-$YMIR_HOME/hodd}/memory/runes_audit.md}" \
         "${YMIR_HOME:+$YMIR_HOME/memory/runes_audit.md}" \
         "${YMIR_HOME:+$YMIR_HOME/hodd/memory/runes_audit.md}"; do
  # The flat `workspace/` shelf was retired by 0001-hoard-layout; a validator that
  # still names it is a stale reader, not a fallback (smoke: rename-sweep FAIL,
  # measured 2026-10-24). The hoard is the only home for the ledger (Rule 06).
  [ -n "$c" ] && [ -r "$c" ] && { RUNES_LEDGER="$c"; break; }
done
if [ -r "$RUNES_LEDGER" ]; then
  add runes PASS "audit ledger readable ($(wc -l <"$RUNES_LEDGER" | tr -d ' ') lines)"
else
  add runes FAIL "audit ledger unreadable"
fi

# ── 11. the master registry speaks the current key ─────────────────────────
# Plan 62 renamed a project row's `workspace:` to `realm:`. A row on the old key
# still resolves (bin/skuld/registry-lib.sh), so this is a WARN, never a FAIL — but it is
# named, because a silent rename is how a registry stops meaning what it says.
REG_FILE=""
if command -v registry_projects_file >/dev/null 2>&1; then REG_FILE="$(registry_projects_file 2>/dev/null || true)"; fi
if [ -z "$REG_FILE" ] || [ ! -r "$REG_FILE" ]; then
  add registry WARN "no master project registry readable — run bin/engine/ymir-install.sh"
else
  legacy=""
  command -v registry_deprecated_rows >/dev/null 2>&1 && legacy="$(registry_deprecated_rows "$REG_FILE" 2>/dev/null || true)"
  if [ -z "$legacy" ]; then
    add registry PASS "every project row names its realm ($REG_FILE)"
  else
    add registry WARN "deprecated key 'workspace:' still on $(printf '%s' "$legacy" | tr '\t\n' ', ' | sed 's/, $//') — renamed to 'realm:' (plan 62); rows still resolve, but rename them"
  fi
fi

# ── output ──────────────────────────────────────────────────────────────────
fails=0; warns=0
for s in "${STATES[@]}"; do
  [ "$s" = FAIL ] && fails=$((fails + 1))
  [ "$s" = WARN ] && warns=$((warns + 1))
done

if [ "$JSON" = 1 ]; then
  printf '{\n  "checks": [\n'
  first=1
  for i in "${!IDS[@]}"; do
    [ $first = 0 ] && printf ',\n'
    first=0
    printf '    {"id":"%s","status":"%s","detail":"%s"}' "${IDS[$i]}" "${STATES[$i]}" "${DETAILS[$i]}"
  done
  printf '\n  ],\n  "fails": %d,\n  "warns": %d\n}\n' "$fails" "$warns"
else
  say "validate[${#IDS[@]}]{check,status,detail}:"
  for i in "${!IDS[@]}"; do
    say "  \"${IDS[$i]}\",\"${STATES[$i]}\",\"${DETAILS[$i]}\""
  done
  # The same rows, rendered for the eye, on stderr: a human reads marks and
  # colour, a pipeline reads the TOON above, and neither parses the other.
  if [ "$QUIET" != 1 ]; then
    printf '\n' >&2
    for i in "${!IDS[@]}"; do
      style_line "${STATES[$i]}" "${IDS[$i]}" "${DETAILS[$i]}"
    done
  fi
fi

if [ "$fails" -gt 0 ]; then
  [ "$QUIET" = 1 ] || {
    style_rule 52
    style_line FAIL "not usable" "$fails required check(s) failed, $warns warning(s)"
    style_hint "mend it: ymir eir   (diagnose every surface, then mend what is broken)"
  }
  printf 'help: %s required check(s) failed, %s warning(s)\n' "$fails" "$warns" >&2
  exit 1
fi
[ "$QUIET" = 1 ] || {
  style_rule 52
  style_line OK "stands" "every required check passes ($warns warning(s))"
}
exit 0
