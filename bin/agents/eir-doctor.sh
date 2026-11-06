#!/usr/bin/env bash
# eir-doctor.sh — Eir, the healer: diagnose the running system, then mend it.
#
# Eir composes the surfaces that already own their health — she does not
# re-implement them. `check` (default) reports each surface; `fix` runs the
# matching repair path for the broken ones. She never arms supervision (the
# harness extension owns that) and never touches a tracked tree.
#
# Usage:
#   eir-doctor.sh [check]      # diagnose every surface, aggregate TOON
#   eir-doctor.sh fix          # mend what can be mended safely, then re-check
#   eir-doctor.sh --version
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

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
STATE="${BROKK_STATE_OVERRIDE:-$YMIR_HOME/state}"

# The cloth: colour and marks for the human reading this report; the TOON rows on
# stdout stay the data (bin/desktop/ymir-style.sh).
if [ -z "${YMIR_STYLE_LOADED:-}" ]; then . "$SCRIPT_DIR/../desktop/ymir-style.sh"; YMIR_STYLE_LOADED=1; fi
style_init
# Where an app lives: apps/<surface> in a clone, node_modules/@zerwiz/<pkg> in an
# npm install — both shapes, one resolver (bin/desktop/app-lib.sh).
if [ -z "${YMIR_APP_LIB_LOADED:-}" ]; then
  _ya="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for _yac in "$_ya/app-lib.sh" "$(CDPATH='' cd "$_ya" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)/bin/desktop/app-lib.sh"; do
    [ -r "$_yac" ] && { . "$_yac"; YMIR_APP_LIB_LOADED=1; break; }
  done
  unset _ya _yac
fi
app_dir sessrumnir APP_SESSRUMNIR || APP_SESSRUMNIR=""


case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;; -h|--help|"") sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
ACTION="${1:-check}"; shift || true

have() { command -v "$1" >/dev/null 2>&1; }
say_ok() { return 0; }

# ── the platform and the role: a `hand` on Android is a lawful substrate with
# lawful absences. Before 2026-10-21 Eir asked every surface the same question
# everywhere, so the phone reported ten red rows — vault (cryptsetup cannot exist
# under Android), desktop shells (Electron is not built for bionic), autoboot (no
# systemd) — and the two REAL breaks hid among eight false ones. Rule 25: probe,
# never assume; and a clean skip is a pass.
PLATFORM="linux"
if [ -n "${PREFIX:-}" ] && [ -d "${PREFIX:-}/etc" ]; then PLATFORM="termux"; fi
ROLE=""
for _seat in "${HOME}/.pi/agent/extensions/.ymir-seat" "${YMIR_HOME:-/nonexistent}/state/.ymir-seat"; do
  [ -r "$_seat" ] || continue
  ROLE="$(sed -n 's/^role=//p' "$_seat" 2>/dev/null | head -1)"
  [ -n "$ROLE" ] && break
done
unset _seat

# surface_skip <surface> — 0 when this substrate/role cannot owe the surface.
surface_skip() {
  # The mail desk is a systemd user unit; a substrate without systemd cannot owe it
  # (a hand). A clean skip with its reason is a pass (RULES/25).
  if [ "$1" = mail ] && [ "$PLATFORM" = termux ]; then return 0; fi
  [ "$ROLE" = "hand" ] || return 1
  case "$1" in
    # Hnitbjörg needs cryptsetup + loop devices; a hand has neither, and by law the
    # vault is a server-side property (Rule 15/16), never the roaming seat's.
    vault)      return 0 ;;
    # The Electron shells are not built for Android; the seat is the harness.
    shells|sessrumnir) return 0 ;;
    # No systemd on Android: there is no boot unit to enable. The Pi watcher owns
    # supervision here, and `ymir-autoboot.sh verify` already names the gap.
    autoboot)   return 0 ;;
    # The desk is a systemd user unit: a substrate without systemd (a hand) cannot
    # owe it — and the arm's own door already names that gap.
    mail)       return 0 ;;
  esac
  return 1
}

# surface_ok <surface> — 0 when the surface is satisfied by another door.
surface_ok() {
  case "$1" in
    # herdr is one pane backend; tmux is the other, and it is the one this platform has.
    herdr) have tmux ;;
    *) return 1 ;;
  esac
}

surface_detail_skip() {
  case "$1" in
    vault)      printf '%s\n' 'not this seat (no cryptsetup/loop devices on Android)' ;;
    shells|sessrumnir) printf '%s\n' 'not this seat (desktop shells are not built for bionic)' ;;
    autoboot)   printf '%s\n' 'not this seat (no systemd; the Pi watcher owns supervision)' ;;
    mail)       printf '%s\n' 'not this seat (no systemd: the desk is a user unit)' ;;
    *)          printf '%s\n' 'skip' ;;
  esac
}

# Each surface: `s_<name>` = healthy? (exit 0), `f_<name>` = the repair.
SURFACES=(floors seatpaths hooks packaging herdr a2abridge hermes snotra voice council sessrumnir shells graphics well memory mail mcp harness arm lock gates migrations hoard autoboot vault ward)

# ── the three surfaces the 2026-11-03 Windows audit found, and the rule they read ──────────
# A SEAT IS NOT UPDATED BY A PULL. The checkout moves; the installed hooks, the PATH a later
# shell sees, and the packaging that builds the door do not. These three ask the doors that own
# those answers, so `eir-doctor check` names the same faults the installer and Gróa heal.
seat_profile() {  # the profile this operator's shell actually reads (probed, never assumed)
  case "${SHELL##*/}" in zsh) printf '%s' "$HOME/.zprofile" ;; *) printf '%s' "$HOME/.profile" ;; esac
}
s_seatpaths() {
  local d f; f="$(seat_profile)"
  for d in "$HOME/.bun/bin" "$HOME/.local/bin"; do
    [ -d "$d" ] || continue
    grep -qF "$d" "$f" 2>/dev/null || return 1     # provisioned, but no login shell would find it
  done
  return 0
}
f_seatpaths() { "$SCRIPT_DIR/../engine/prereq-ensure.sh" --persist-path >/dev/null 2>&1; }
s_hooks() {
  local hooks; hooks="$(cd "$ROOT" && git rev-parse --git-path hooks 2>/dev/null || printf '.git/hooks')"
  case "$hooks" in /*) ;; *) hooks="$ROOT/$hooks" ;; esac
  [ -x "$hooks/pre-commit" ] && [ -x "$hooks/pre-push" ] || return 1
  # A hook that BAKES a home path dies when that tree is reclaimed, and takes every ward with it
  # (the pre-push hook was taught this on 2026-10-20; the pre-commit one still baked a path).
  ! grep -q "^\"/home/\|^\"/Users/" "$hooks/pre-commit" 2>/dev/null
}
f_hooks() {
  [ -x "$SCRIPT_DIR/../gates/guards/secret-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/secret-guard.sh" --install >/dev/null 2>&1
  [ -x "$SCRIPT_DIR/../gates/guards/fixes-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/fixes-guard.sh" --install >/dev/null 2>&1
}
# The packaged door: every path a shipped installer names must exist, and the host must be able
# to say what it can build. A broken directive is named by the ward; there is no mending here —
# it is a code change, so the fix row points at the ward.
s_packaging() { [ -x "$SCRIPT_DIR/../gates/guards/packaging-guard.sh" ] && "$SCRIPT_DIR/../gates/guards/packaging-guard.sh" check >/dev/null 2>&1; }

s_floors()    { [ -x "$SCRIPT_DIR/../engine/prereq-ensure.sh" ] && "$SCRIPT_DIR/../engine/prereq-ensure.sh" status >/dev/null 2>&1; }
f_floors()    { "$SCRIPT_DIR/../engine/prereq-ensure.sh" ensure --install >/dev/null 2>&1; }
s_herdr()     { [ -x "$SCRIPT_DIR/../seat/herdr-ensure.sh" ] && "$SCRIPT_DIR/../seat/herdr-ensure.sh" status >/dev/null 2>&1; }
f_herdr()     { "$SCRIPT_DIR/../seat/herdr-ensure.sh" ensure --install >/dev/null 2>&1; }
s_a2abridge() { [ -x "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" ] && "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" status >/dev/null 2>&1; }
f_a2abridge() { "$SCRIPT_DIR/../bridge/a2abridge-ensure.sh" ensure --install >/dev/null 2>&1; }
s_hermes()    { [ -x "$SCRIPT_DIR/../engine/hermes-ensure.sh" ] && "$SCRIPT_DIR/../engine/hermes-ensure.sh" status >/dev/null 2>&1; }
f_hermes()    { "$SCRIPT_DIR/../engine/hermes-ensure.sh" ensure --install >/dev/null 2>&1; }
# The meeting ear's engine (whisper.cpp + a model); the MCP face + unit ride
# the fleet surface below. A seat that captures but transcribes elsewhere still
# passes (voxtype counts as an engine).
s_snotra()    { [ -x "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" ] && "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" status >/dev/null 2>&1; }
# The voice engines (whisper STT + piper TTS): a machine property, adopted or installed.
s_voice()     { [ -x "$SCRIPT_DIR/../voice/voice-ensure.sh" ] && "$SCRIPT_DIR/../voice/voice-ensure.sh" status >/dev/null 2>&1; }
f_voice()     { "$SCRIPT_DIR/../voice/voice-ensure.sh" ensure --install >/dev/null 2>&1; }
# The council of models (plan 92): its roster must exist in the home, or `logretta_sit`
# is a loud skip. The surface asks the ensure door, which never overwrites a stack.
s_council()   { [ -x "$SCRIPT_DIR/../pi/logretta-ensure.sh" ] && "$SCRIPT_DIR/../pi/logretta-ensure.sh" status >/dev/null 2>&1; }
f_council()   { "$SCRIPT_DIR/../pi/logretta-ensure.sh" ensure >/dev/null 2>&1; }
f_snotra()    { "$SCRIPT_DIR/../../systems/snotra/services/ear/snotra-ensure.sh" ensure --install >/dev/null 2>&1; }
s_sessrumnir(){ [ -x "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" ] && "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" status >/dev/null 2>&1; }
f_sessrumnir(){ "$SCRIPT_DIR/../desktop/sessrumnir-ensure.sh" ensure --install >/dev/null 2>&1; }
# The boot law (2026-09-24): every role-owed program enabled and standing. The
# mend for a stopped boot IS the raise — re-materialize, re-enable, re-verify.
s_autoboot()  { [ -x "$SCRIPT_DIR/../engine/ymir-autoboot.sh" ] && "$SCRIPT_DIR/../engine/ymir-autoboot.sh" verify >/dev/null 2>&1; }
f_autoboot()  { [ -x "$SCRIPT_DIR/../fleet/fleet-ensure.sh" ] && "$SCRIPT_DIR/../fleet/fleet-ensure.sh" ensure >/dev/null 2>&1; }
# Hnitbjörg — the encrypted vault. The surface checks only that the tooling and
# the vault directory stand; a sealed vault is HEALTHY, not a fault to mend.
s_vault()     { [ -x "$SCRIPT_DIR/../vault/hnitbjorg-ensure.sh" ] && "$SCRIPT_DIR/../vault/hnitbjorg-ensure.sh" status >/dev/null 2>&1; }
# The ward (Rule 24): Vörðr's audit says whether this machine has a door above the floor.
# A green house with an open port is exactly the state that let a public tunnel answer
# 200 with no login for ten days (2026-10-18).
s_ward()      { [ -x "$SCRIPT_DIR/../ward/security-audit.sh" ] && "$SCRIPT_DIR/../ward/security-audit.sh" check --quiet >/dev/null 2>&1; }
f_ward()      { "$SCRIPT_DIR/../ward/harden.sh" apply --ssh-keys-perm >/dev/null 2>&1; }
f_vault()     { "$SCRIPT_DIR/../vault/hnitbjorg-ensure.sh" ensure --install >/dev/null 2>&1; }
# ── Gná — the mail desk (:8494, plan 193 §14) ────────────────────────────────
# Three named truths, and none of them may masquerade as another:
#   ok            the desk answers /health AND declares an account
#   unconfigured  the desk answers but has no account row — a NAMED, non-green
#                 state, because "no mail" is a claim such a desk cannot make
#   broken        the desk does not answer at all
# The fix is the installer; the ACCOUNT itself is the operator's word, never a mend.
GNA_DESK_PORT="${GNA_DESK_PORT:-8490}"
GNA_DESK_URL="${GNA_DESK_URL:-http://127.0.0.1:$GNA_DESK_PORT}"
mail_accounts_file() {  # the ONE resolver (Rule 04/07) — this file never guesses a home
  local h="${YMIR_HOME:-}"
  [ -n "$h" ] || ymir_home_root h 2>/dev/null || true
  printf '%s\n' "${h:+$h/hodd/memory/mail/accounts.yaml}"
}
mail_state() {  # prints ok | unconfigured | broken — the desk's own answer, never a guess
  local h
  h="$(curl -fsS -m 3 "$GNA_DESK_URL/health" 2>/dev/null)" || { printf 'broken'; return 0; }
  printf '%s' "$h" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("broken"); raise SystemExit
print("ok" if d.get("ok") and d.get("accounts") else "unconfigured")' 2>/dev/null || printf 'broken'
}
mail_grant_keys() {  # the vault KEY NAMES the declared account grants — never a value
  python3 - "$(mail_accounts_file)" <<'PY' 2>/dev/null
import sys, yaml
try:
    rows = (yaml.safe_load(open(sys.argv[1])) or {}).get("accounts") or []
except Exception:
    raise SystemExit(0)
for row in rows:
    if not (isinstance(row, dict) and row.get("id")):
        continue
    for k in ("grant", "client", "client_secret"):
        if row.get(k):
            print(row[k])
    break
PY
}
vault_has_key() {  # <KEY> — the NAME is asked, the value never leaves the vault
  "$ROOT/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null | grep -q "^export $1="
}
mail_detail() {
  local st; st="$(mail_state)"
  case "$st" in
    broken)       printf 'no answer at %s/health — bash bin/mail/install.sh' "$GNA_DESK_URL" ;;
    unconfigured) printf 'the desk answers, but no account row in %s — nothing to read, and "no mail" cannot be said' "$(mail_accounts_file)" ;;
    *)            local k missing="" acc
                  acc="$(curl -fsS -m 3 "$GNA_DESK_URL/health" 2>/dev/null | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
print(",".join(d.get("accounts") or []))' 2>/dev/null)"
                  for k in $(mail_grant_keys); do vault_has_key "$k" || missing="$missing $k"; done
                  if [ -n "$missing" ]; then
                    printf 'desk answers for %s at %s, but the declared grant names vault keys that are ABSENT:%s' \
                      "${acc:-no account}" "$GNA_DESK_URL" "$missing"
                  else
                    printf 'desk answers for %s at %s' "${acc:-no account}" "$GNA_DESK_URL"
                  fi ;;
  esac
}
s_mail()      { [ "$(mail_state)" = ok ]; }
f_mail()      { [ -x "$ROOT/bin/mail/install.sh" ] && "$ROOT/bin/mail/install.sh" >/dev/null 2>&1; }
# The desktop shells (P8, 2026-09-24): the RESOLVER answers — app-local,
# workspace-hoisted, or the sibling package (bin/desktop/electron-lib.sh). ABSENT for
# an app the operator has installed is a FAILURE, never healthy: a desktop
# that cannot open must be reported red, not quietly green. Only a surface
# whose app dir is not installed at all — the recorded web-only decision — is
# skipped.
shell_surfaces() { printf '%s\n' hlidskjalf odrerir sessrumnir; }
s_shells() {
  local s dir state
  while IFS= read -r s; do
    dir=""
    app_dir "$s" dir 2>/dev/null || dir=""
    [ -n "$dir" ] || continue          # not installed — a deliberate web-only install
    state="$(electron_runtime_state "$dir" "$ROOT" "$(app_pkg "$s")" 2>/dev/null)"
    [ "$state" = ok ] || return 1      # absent OR partial: the shell cannot open
  done < <(shell_surfaces)
  return 0
}
f_shells() {
  printf 'eir: the shells need mending — bin/engine/ymir-install.sh (the desktop step) mends them; or by hand:\n' >&2
  electron_remedy >&2
  return 1
}
if [ -z "${YMIR_ELECTRON_LIB_LOADED:-}" ] && [ -r "$SCRIPT_DIR/../desktop/electron-lib.sh" ]; then
  . "$SCRIPT_DIR/../desktop/electron-lib.sh"; YMIR_ELECTRON_LIB_LOADED=1
fi
# Graphics (P8): the DRM truth and the effective GPU policy. A host with a
# display but NO DRM card cannot render at all — that is a named failure, not
# a green row. On a headless box nothing renders anyway: healthy.
s_graphics() {
  if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then return 0; fi
  graphics_block --json 2>/dev/null | grep -qF '"cards":[{' || return 1
  return 0
}
f_graphics() {
  printf 'eir: a display is up but no DRM card is sensed — inspect the driver (bin/host/omarchy-sense.sh observe) and the kernel log\n' >&2
  return 1
}
if [ -z "${YMIR_GRAPHICS_LIB_LOADED:-}" ] && [ -r "$SCRIPT_DIR/../host/graphics-lib.sh" ]; then
  . "$SCRIPT_DIR/../host/graphics-lib.sh"; YMIR_GRAPHICS_LIB_LOADED=1
fi

# The well: the door answers AND the store is whole (Rule 20). A memory that
# shrank is a loss even while the bridge still serves — so the ward rides this
# surface, and the mend re-checks before rolling the checkpoint forward.
well_detail() {
  if { exec 3<>/dev/tcp/127.0.0.1/4602; } 2>/dev/null; then
    exec 3>&-
    printf 'engram :4602 answering\n'
  else
    printf 'door silent on :4602%s\n' "${ROLE:+ (role $ROLE: the well is the heart door)}"
  fi
}

s_well()      {
  # HONESTY (2026-10-21): this used to answer `ok` from the presence of two
  # scripts, never from the well itself — a green row while nothing listened on
  # :4602. Ask the port.
  { exec 3<>/dev/tcp/127.0.0.1/4602; } 2>/dev/null && { exec 3>&-; return 0; }
  return 1
}
f_well()      { "$SCRIPT_DIR/../records/mimir.sh" start >/dev/null 2>&1; "$SCRIPT_DIR/../records/well-guard.sh" record >/dev/null 2>&1; }

# MEMORY — the well's PRACTICE, not just its port (plan 136). `well` asks whether
# someone is listening; `memory` asks whether there is anything worth listening to:
# how big the store is, when it was last watered, last drunk from, last written as
# a day, and last pruned. A well that answers and is never fed is green on `well`
# and useless to the Allfather, which is exactly the failure this surface names.
# The measuring lives in bin/records/mimir.sh memory (one door, stdlib only), so a
# broken bridge still yields a report rather than a blank row.
memory_detail() {
  local out
  out="$("$SCRIPT_DIR/../records/mimir.sh" memory --line 2>/dev/null)"
  [ -n "$out" ] || { printf 'the memory door did not answer — bin/records/mimir.sh memory\n'; return 1; }
  printf '%s\n' "$out"
}
s_memory()    { "$SCRIPT_DIR/../records/mimir.sh" memory --check >/dev/null 2>&1; }
f_memory()    {
  # The mends are: raise the well, then let the grading pass run (it only annotates
  # and moves; it never lowers the count). A stale DAILY record is not something a
  # healer can write honestly — the row keeps saying so.
  "$SCRIPT_DIR/../records/mimir.sh" start >/dev/null 2>&1
  "$SCRIPT_DIR/../records/mimir.sh" grade --apply >/dev/null 2>&1
}
# MCP: both A2A servers wired into opencode + pi.
s_mcp() {
  local pi="$HOME/.pi/agent/mcp-adapter.json" oc="$ROOT/opencode.json"
  # The live MCP surfaces: the OpenCode config must still bind engram (the well),
  # and the Pi config must parse and carry the fleet servers. If the A2A mesh
  # engine (a2abridge) is seated, its bridge must be wired too — a seated engine
  # with no bridge is the silent half; the deeper connection proof lives in
  # smoke_test.sh (2026-09-23).
  [ -f "$pi" ] || [ -f "$oc" ] || return 1
  if [ -f "$oc" ]; then grep -q '"engram"' "$oc" 2>/dev/null || return 1; fi
  if [ -f "$pi" ]; then
    grep -q '"mcpServers"' "$pi" 2>/dev/null || return 1
    command -v python3 >/dev/null 2>&1 && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$pi" 2>/dev/null && return 1
    if [ -x "$HOME/.a2abridge/bin/a2abridge" ]; then
      grep -q '"a2abridge"' "$pi" 2>/dev/null || return 1
    fi
  fi
  return 0
}
f_mcp()       { [ -x "$SCRIPT_DIR/../bridge/a2a-mcp.sh" ] && "$SCRIPT_DIR/../bridge/a2a-mcp.sh" install >/dev/null 2>&1; }
# Harness: the Pi extensions are DEPLOYED away from this tree, so a copy cannot
# find bin/ by walking up — it reads the root recorded beside it (`.ymir-root`,
# written by bin/seat/valknut-load.sh, resolved by .pi/extensions/lib/ymir-home.ts).
# A record with no live root means every `${root}/bin/…` they exec is a path that
# does not exist: the Gná arm child dies at 127 before its first poll, no
# state/.watch.heartbeat is ever written, and the watch is dead while every file
# listing looks correct. Absent extensions are healthy — nothing to resolve.
PI_EXT_HOME="${PI_EXT_HOME:-$HOME/.pi/agent/extensions}"
s_harness() {
  [ -d "$PI_EXT_HOME" ] || return 0
  [ -n "$(ls "$PI_EXT_HOME"/*.ts 2>/dev/null)" ] || return 0
  [ -r "$PI_EXT_HOME/.ymir-root" ] || return 1
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ -x "$line/bin/pi/syn-watch-arm.sh" ] && return 0
  done <"$PI_EXT_HOME/.ymir-root"
  return 1
}
f_harness()   { [ -x "$SCRIPT_DIR/../seat/valknut-load.sh" ] && "$SCRIPT_DIR/../seat/valknut-load.sh" --pi >/dev/null 2>&1 && s_harness; }
# Arm: Sýn as a SERVICE (plan 58, Phase 2) — one standing watcher per home that
# idles when no session is seated, never retires with one. The surface is the
# arm's own door (bin/pi/syn-watch.sh): a live lease with a fresh heartbeat is
# healthy whether a session is up (state=up) or none is (state=idle). A missing
# or stale arm is a NAMED failure — command merges and a blind turn end are what
# a dead watch costs — and the mend is to seat the service again.
s_arm()      { [ -x "$SCRIPT_DIR/../pi/syn-watch.sh" ] && "$SCRIPT_DIR/../pi/syn-watch.sh" status >/dev/null 2>&1; }
f_arm()      { [ -x "$SCRIPT_DIR/../pi/syn-watch.sh" ] && "$SCRIPT_DIR/../pi/syn-watch.sh" start >/dev/null 2>&1 && s_arm; }
# Lock: absent, or held by a live pid.
s_lock() {
  local f="$STATE/.lock" pid
  [ -r "$f" ] || return 0
  pid="$(tr -d '[:space:]' <"$f" 2>/dev/null || true)"
  [ -n "$pid" ] || return 0
  kill -0 "$pid" 2>/dev/null
}
f_lock() {
  local f="$STATE/.lock" pid
  if [ -r "$f" ]; then
    pid="$(tr -d '[:space:]' <"$f" 2>/dev/null || true)"
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -f "$f" "$STATE/.lock-path"
      # A stale arm marker with no live session would silence the turn-end guard.
      rm -f "$STATE/.supervision-armed" "$STATE/.watch.heartbeat"
    fi
  fi
}
s_migrations(){ [ ! -x "$SCRIPT_DIR/../engine/ymir-migrate.sh" ] || "$SCRIPT_DIR/../engine/ymir-migrate.sh" status >/dev/null 2>&1; }

# Gates: the delivery hook that is INSTALLED, not the installer that is right.
# `fixes-guard.sh --install` was fixed on 2026-10-20 to judge the PUSHING worktree
# (`git rev-parse --show-toplevel`) instead of the checkout that installed it — but
# the hook already seated on this machine kept the old shape, so for four days every
# push from a Yggdrasil worktree was judged against the main tree, and a branch that
# had regenerated its register was still refused (measured 2026-10-24). A mend that
# is not re-seated is not a mend: this surface checks the artifact, not the script.
_gates_hook() {  # <result-var> — the installed pre-push hook's path
  local hooks
  hooks="$(cd "$ROOT" 2>/dev/null && git rev-parse --git-path hooks 2>/dev/null)" || return 1
  [ -n "$hooks" ] || return 1
  case "$hooks" in /*) ;; *) hooks="$ROOT/$hooks" ;; esac
  printf -v "${1:?}" '%s' "$hooks/pre-push"
}
s_gates() {
  local h
  _gates_hook h || return 1
  [ -x "$h" ] || return 1
  grep -q 'git rev-parse --show-toplevel' "$h" 2>/dev/null || return 1
  grep -q 'branch-current.sh' "$h" 2>/dev/null || return 1
}
f_gates() {
  _gates_hook h >/dev/null 2>&1 || true
  bash "$SCRIPT_DIR/../gates/guards/fixes-guard.sh" --install >/dev/null 2>&1 || return 1
  s_gates
}
f_migrations(){ [ -x "$SCRIPT_DIR/../engine/ymir-migrate.sh" ] && "$SCRIPT_DIR/../engine/ymir-migrate.sh" apply >/dev/null 2>&1; }
# Hoard: private data sits under the hoard, and .ymir-layout.yaml tells the truth.
# Two failures this catches: (1) a declared layout path that does not exist — a
# stale map is what lets private work land outside the hoard; (2) a flat
# $YMIR_HOME/{identity,data,docs,secrets,tenants} duplicate beside hodd/ — the
# drift that RULES/04-hoard.md (correction 2026-09-17) forbids.
_hoard_root() { local r; if [ -x "$SCRIPT_DIR/../vault/hoard-lib.sh" ]; then . "$SCRIPT_DIR/../vault/hoard-lib.sh"; hoard_root r; printf '%s' "$r"; else printf '%s' "${YMIR_HOARD:-$YMIR_HOME/hodd}"; fi; }
s_hoard() {
  local h; h="$(_hoard_root)"
  [ -d "$h" ] || return 1
    local lay="$YMIR_HOME/.ymir-layout.yaml" k p rp maproot
    if [ -f "$lay" ]; then
      # A path naming the SAME home under another root is not foreign: a substrate
      # THE MAP MUST DESCRIBE *THIS* MACHINE. The previous code RETRIED a foreign path
      # under this root, which made a map naming another computer pass as 'ok' —
      # masking the very fault this surface exists to catch (measured 2026-10-13:
      # .ymir-layout.yaml pointed at an absolute per-user home for every path, and this
      # surface still reported 'ok'). A foreign map is now a FAILURE.
      maproot="$(sed -nE 's/^git_repo: "([^"]+)".*/\1/p' "$lay" 2>/dev/null | head -1)"
      if [ -n "$maproot" ] && [ "$maproot" != "$YMIR_HOME" ]; then
        return 1   # the map names another machine's home — regenerate it on this one
      fi
      for k in config secrets identity workspaces memory smidja state data; do
        p="$(sed -nE "s/^  $k: \"([^\"]+)\".*/\1/p" "$lay" | head -1)"
        [ -n "$p" ] || continue
        if [ "${p#/}" != "$p" ]; then [ -d "$p" ] || return 1
        else [ -d "$YMIR_HOME/$p" ] || return 1; fi
      done
    fi
  # STATE LIVES IN THE HOME AND NOWHERE ELSE (Rule 21). Two faults measured 2026-10-13:
  # state beside the home (~/Documents/Ymir/state) and state INSIDE the public repo
  # (ymir/.agents/state, ymir/bin/state — git-ignored, so no guard could see it either).
  [ -d "$YMIR_HOME/state" ] || return 1
  local baddir
  for baddir in "$HOME/Documents/Ymir" "$HOME/hodd"; do  # allow-home-default: names the LEGACY drift paths on purpose (Rule 21)
    [ -e "$baddir" ] && return 1
  done
  if [ -n "${ROOT:-}" ]; then
    for baddir in "$ROOT/.agents/state" "$ROOT/bin/state"; do
      [ -e "$baddir" ] && return 1
    done
  fi
  # A COMPANY OR PROJECT DOCUMENT MUST NOT SIT IN THE OPERATOR'S OWN SHELF (Rule 21):
  # hodd/life is the operator's own, never a company's or a project's.
  local life="$YMIR_HOME/hodd/life"
  if [ -d "$life" ]; then
    [ -d "$life/work" ] && return 1
    local cid
    for cid in "$YMIR_HOME"/hodd/identity/companies/*/; do
      [ -d "$cid" ] || continue
      cid="$(basename "$cid")"
      [ "$cid" = '*' ] && continue
      find "$life" -maxdepth 3 -iname "*$cid*" -print -quit 2>/dev/null | grep -q . && return 1
    done
  fi
  for k in identity data docs secrets tenants; do
    [ -d "$YMIR_HOME/$k" ] && return 1
  done
  # A session-lock pointer that names another machine's home is stale drift: the
  # lock is machine-local, but the pointer lives in the synced home, so a box
  # reinstalled under a new username inherits the old one. The arm then tries to
  # mkdir a foreign home and fails with EACCES, stranding supervision (2026-09-23).
  local lp="$YMIR_HOME/state/.lock-path" rec
  if [ -f "$lp" ]; then
    rec="$(head -n1 "$lp" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$rec" ] && [ -n "${HOME:-}" ] && [ "$rec" != "$HOME" ] && [ "${rec#"$HOME"/}" = "$rec" ]; then
      return 1
    fi
  fi
  return 0
}
f_hoard() {
  local h; h="$(_hoard_root)"
  mkdir -p "$h" 2>/dev/null || return 1
  # A flat duplicate beside hodd/ is the drift: merge it in, never clobber.
  local k
  for k in identity data docs secrets tenants; do
    local src="$YMIR_HOME/$k"
    [ -d "$src" ] || continue
    mkdir -p "$h/$k" 2>/dev/null || continue
    cp -an "$src/." "$h/$k/" 2>/dev/null || true
    rm -rf "$src" 2>/dev/null || true
  done
    # A layout entry naming a nonexistent dir is repointed at the hoard.
    local lay="$YMIR_HOME/.ymir-layout.yaml" k2 p rp maproot
    if [ -f "$lay" ] && [ -d "$h" ]; then
      maproot="$(sed -nE 's/^git_repo: "([^"]+)".*/\1/p' "$lay" 2>/dev/null | head -1)"
      for k2 in identity data secrets docs tenants; do
        p="$(sed -nE "s/^  $k2: \"([^\"]+)\".*/\1/p" "$lay" | head -1)"
        [ -n "$p" ] || continue
        rp="$p"
        if [ ! -d "$rp" ] && [ -n "$maproot" ] && [ "${p#"$maproot"}" != "$p" ]; then
          rp="$YMIR_HOME/${p#"$maproot"/}"
        fi
        # Resolves under this root, or under a container's view of the same home:
        # nothing to repoint.
        if [ -d "$rp" ]; then continue; fi
        if [ "${p#/}" = "$p" ] && [ -d "$YMIR_HOME/$p" ]; then continue; fi
        sed -i "s|^  $k2: .*|  $k2: \"$h/$k2\"|" "$lay"
      done
    fi
  # A stale session-lock pointer (see s_hoard) is repointed at this machine.
  local lp="$YMIR_HOME/state/.lock-path" rec want
  if [ -f "$lp" ]; then
    rec="$(head -n1 "$lp" 2>/dev/null | tr -d '[:space:]')"
    if [ -n "$rec" ] && [ -n "${HOME:-}" ] && [ "$rec" != "$HOME" ] && [ "${rec#"$HOME"/}" = "$rec" ]; then
      want="${BROKK_MACHINE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ymir}/brokk.lock"
      printf '%s\n' "$want" >"$lp" 2>/dev/null || true
    fi
  fi
  s_hoard
}

# Each branch PRINTS the command that produces the fact; the caller evaluates it
# (the branches used to be bare command text, which is a command-not-found — a
# single quoted word, not a command — so every row's detail came out EMPTY, and
# the `arm` surface is the one the plan's proof asks to NAME the arm, 2026-09-27).
detail() { # <name> -> the command that prints one short fact
  case "$1" in
    floors)    printf '%s\n' "[ -x $SCRIPT_DIR/../engine/prereq-ensure.sh ] && echo 'tool floors'" ;;
    herdr)     printf '%s\n' "have herdr && herdr --version 2>/dev/null | head -1 || { have tmux && tmux -V | sed 's/^/tmux fallback: /' || echo 'no pane backend'; }" ;;
    a2abridge) printf '%s\n' "have a2abridge && a2abridge --version 2>/dev/null | head -1 || echo 'engine absent'" ;;
    hermes)    printf '%s\n' "have hermes && echo present || echo absent" ;;
    sessrumnir)printf '%s\n' "[ -d $APP_SESSRUMNIR/out ] && echo built || echo 'not built'" ;;
    well)      printf '%s\n' well_detail ;;
    memory)    printf '%s\n' memory_detail ;;
    mail)      printf '%s\n' mail_detail ;;
    mcp)       printf '%s\n' "echo 'a2abridge + engram'" ;;
    graphics)  printf '%s\n' "if [ -z \"\${DISPLAY:-}\${WAYLAND_DISPLAY:-}\" ]; then echo headless; else echo \"\$(graphics_block 2>/dev/null | sed -n '1p' | sed 's/.*{//;s/}//') · \$(graphics_policy 2>/dev/null)\"; fi" ;;
    harness)   printf '%s\n' "s_harness && echo 'deployed extensions resolve their bin/' || echo 'no live root recorded'" ;;
    arm)       printf '%s\n' "$SCRIPT_DIR/../pi/syn-watch.sh status --detail 2>/dev/null | head -1 || echo 'arm door missing'" ;;
    gates)     printf '%s\n' "s_gates && echo 'pre-push hook: the worktree that pushes' || echo 'installed hook is stale — bin/gates/guards/fixes-guard.sh --install'" ;;
    lock)      printf '%s\n' "cat $STATE/.lock 2>/dev/null | tr -d '[:space:]' | sed 's/^/pid /' || echo none" ;;
    migrations)printf '%s\n' "echo 'structure'" ;;
    shells)    printf '%s\n' 'shell_surfaces | while IFS= read -r s; do d=""; app_dir "$s" d 2>/dev/null || d=""; [ -n "$d" ] && printf "%s %s; " "$s" "$(electron_runtime_state "$d" "$ROOT" "$(app_pkg "$s")" 2>/dev/null)"; done' ;;
    hoard)     printf '%s\n' "printf 'hoard %s' \"\$(_hoard_root)\" ; [ -d \"\$YMIR_HOME/identity\" ] && printf ' +flat-duplicate' ; printf '\n'" ;;
    autoboot)  printf '%s\n' "$SCRIPT_DIR/../engine/ymir-autoboot.sh verify >/dev/null 2>&1 && echo 'boot proven' || echo 'boot gap — bin/engine/ymir-autoboot.sh verify'" ;;
    seatpaths) printf '%s\n' "printf '%s' \"$(seat_profile)\" ; grep -qF \"$HOME/.bun/bin\" \"$(seat_profile)\" 2>/dev/null && printf ' carries the marked block' || printf ' does not carry ~/.bun/bin — a unit or validator will not find bun'" ;;
    hooks)     printf '%s\n' "printf 'installed hooks' ; [ -x \"$(cd "$ROOT" && git rev-parse --git-path hooks 2>/dev/null || printf '.git/hooks')/pre-commit\" ] && printf ' present' || printf ' MISSING — a guarded deletion and a staged secret would both pass'" ;;
    packaging) printf '%s\n' "bash \"$SCRIPT_DIR/../gates/guards/packaging-guard.sh\" check 2>&1 | grep -o 'the File directive names a file that does not exist: [^)]*' | head -1 || printf 'every named input exists'" ;;
  esac
}

broken=0
unconfigured=0
if [ "$ACTION" = "fix" ]; then
  for s in "${SURFACES[@]}"; do
    surface_skip "$s" && continue
    if ! "s_$s" >/dev/null 2>&1; then
      "f_$s" >/dev/null 2>&1 && printf 'eir: mended %s\n' "$s" || printf 'eir: could not mend %s\n' "$s" >&2
    fi
  done
fi

rows=""
count=0
for s in "${SURFACES[@]}"; do
  if surface_skip "$s"; then
    state=skip
    d="$(surface_detail_skip "$s")"
    rows="${rows}  \"${s}\",\"${state}\",\"${d}\"\n"
    count=$((count+1))
    continue
  fi
  # A surface may NAME its own state where a yes/no would be a lie (the mail desk:
  # answering with no account is not healthy, and it is not broken either).
  named=""
  case "$s" in mail) named="$(mail_state)" ;; esac
  if [ -n "$named" ]; then
    state="$named"
    case "$state" in
      unconfigured) unconfigured=$((unconfigured+1)) ;;
      *)            broken=$((broken+1)) ;;
    esac
  elif "s_$s" >/dev/null 2>&1; then state=ok
  elif surface_ok "$s"; then state=ok; d_override="tmux fallback"
  else state=broken; broken=$((broken+1)); fi
  d="$(eval "$("detail" "$s" 2>/dev/null)" 2>/dev/null | head -1)"
  [ -n "${d_override:-}" ] && { d="$d_override"; d_override=""; }
  rows="${rows}  \"${s}\",\"${state}\",\"${d}\"\n"
  count=$((count+1))
done

printf 'eir[1]{action,root,broken}:\n  "%s","%s",%s\n' "$ACTION" "$ROOT" "$broken"
printf 'health[%d]{surface,state,detail}:\n' "$count"
printf '%b' "$rows"
# For the eye, on stderr: marks and colour; for the pipe, the TOON above.
if [ -t 2 ]; then
  printf '\n' >&2
  while IFS='|' read -r surface state detail; do
    [ -n "$surface" ] || continue
    style_line "$state" "$surface" "$detail"
  done <<<"$(printf '%b' "$rows" | sed 's/^  //; s/"//g; s/,/|/; s/,/|/')"
fi
if [ "$broken" != 0 ] || [ "$unconfigured" != 0 ]; then
  [ "$broken" != 0 ] && printf 'eir: %s surface(s) need mending — run: bin/agents/eir-doctor.sh fix\n' "$broken"
  [ "$unconfigured" != 0 ] && printf 'eir: %s surface(s) are unconfigured — a name must be DECLARED, never mended\n' "$unconfigured"
  exit 1
fi
exit 0
