#!/usr/bin/env bash
# hermes-session-hook.sh — Hermes' session side of the Gná arm: the Sága digest, and its delivery.
#
#   (installed by) bin/pi/arm.sh hook hermes --install
#   bin/pi/arm.sh hook hermes --check      # is it installed, and is it consented?
#
# WHY (plan 177 H4, the Allfather 2026-11-03: *"can they all run the gna arm?"*). The watch LOOP is
# harness-agnostic (the ymir-syn-watch unit); the SESSION SIDE — waking a live session with what the
# house knows — was owned only by Pi and OpenCode extensions. Hermes has no extension API for that,
# but it has a real shell-hook surface (`hooks:` in ~/.hermes/config.yaml, `hermes hooks`), and this
# script is what an entry in it runs. Two entries, one command:
#
#   on_session_start  run bin/time/saga-session-start.sh ONCE, stash its digest, bind the session id.
#                     Hermes IGNORES this event's return, so the digest is recorded here, not injected.
#   pre_llm_call      on the FIRST turn of that session, and only when the working directory is inside
#                     the house, return {"context": <digest>} — the documented injection shape — so the
#                     model actually receives the bearings. Every later turn answers {} (no-op).
#
# The wire is Hermes' own: a JSON payload on stdin, an OPTIONAL JSON directive on stdout. This door
# therefore NEVER fails the harness: every path prints a valid no-op `{}` and exits 0, and a harness
# that is missing, a house that is not found, or a digest that fails is a named skip, never a crash.
#
# Honest limit, stated here because a later reader will meet it: this is delivery of the digest into a
# turn and a recorded session binding — it is NOT the live wake relay Pi's extension performs (a shell
# hook is a subprocess that outlives nothing). A wake raised while no Hermes turn is running waits in
# the durable wake queue, exactly as it does for every harness without an extension.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIGEST_DOOR="$ROOT/bin/time/saga-session-start.sh"
STATE="${YMIR_HERMES_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ymir/hermes}"
CAP="${YMIR_HERMES_DIGEST_CAP:-12000}"

noop() { printf '{}\n'; exit 0; }

# ── the envelope: Hermes' payload → five fields, absent ones as "-" (never a shifted field) ──
# `python3 -c`, never a heredoc: a heredoc REPLACES stdin, and stdin is the payload.
envelope() {
  python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("-\t-\t-\t0"); raise SystemExit(0)
extra = d.get("extra") or {}
first = extra.get("is_first_turn", str(d.get("hook_event_name")) == "on_session_start")
print("\t".join([
    str(d.get("hook_event_name") or "-"),
    str(d.get("session_id") or "-"),
    str(d.get("cwd") or "-"),
    "1" if first else "0",
]))
' 2>/dev/null || printf '-\t-\t-\t0\n'
}

# ── is this working directory home? ──────────────────────────────────────────────────────────
# The house is this tree, the recorded seat root and the private home — never "any directory", so a
# Hermes session in another project is not handed Ymir's bearings.
in_house() {
  local cwd="$1" r roots=""
  [ "$cwd" = "-" ] && return 1
  roots="$ROOT"
  r="$(cat "$HOME/.pi/agent/extensions/.ymir-root" 2>/dev/null || true)"
  [ -n "$r" ] && roots="$roots $r"
  r="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
  [ -n "$r" ] && roots="$roots $(dirname "$r")"
  for r in $roots; do
    case "$cwd" in "$r"|"$r"/*) return 0 ;; esac
  done
  return 1
}

# ── the digest, stashed per session (stdout of the door, never the model's context yet) ──────
run_digest() {  # <session>
  local session="$1" out rc
  [ -x "$DIGEST_DOOR" ] || return 1
  mkdir -p "$STATE" 2>/dev/null || return 1
  out="$(cd "$ROOT" && timeout 180 bash "$DIGEST_DOOR" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && [ -n "$out" ] || return 1
  printf '%s\n' "$out" > "$STATE/digest.$session.md" || return 1
  printf '%s\n' "$out" > "$STATE/digest.latest.md" 2>/dev/null || true
  printf 'harness=hermes\nsession=%s\nroot=%s\nat=%s\n' "$session" "$ROOT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$STATE/session" 2>/dev/null || true
  return 0
}

main() {
  local event session cwd first
  IFS=$'\t' read -r event session cwd first <<<"$(envelope)"
  [ -n "${event:-}" ] || noop

  case "$event" in
    on_session_start)
      [ "$session" = "-" ] && noop
      if run_digest "$session"; then
        printf 'hermes-session-hook: digest stashed for %s (%s lines) — injected on the first turn\n' \
          "$session" "$(wc -l < "$STATE/digest.$session.md" 2>/dev/null | tr -d ' ')" >&2
      else
        printf 'hermes-session-hook: no digest (saga-session-start.sh absent or failed) — skip, named\n' >&2
      fi
      noop ;;
    pre_llm_call)
      # Only the first turn of the session, only inside the house, only if the digest is there and
      # not yet delivered: a second injection would be noise, and noise is what the digest is for.
      [ "$first" = "1" ] || noop
      [ "$session" = "-" ] && noop
      in_house "$cwd" || noop
      [ -s "$STATE/digest.$session.md" ] || noop
      [ -e "$STATE/injected.$session" ] && noop
      CAP="$CAP" SESSION="$session" python3 - "$STATE" <<'PY' 2>/dev/null || noop
import json, os, sys
state = sys.argv[1]
session = os.environ["SESSION"]
cap = int(os.environ.get("CAP") or 12000)
try:
    body = open(os.path.join(state, "digest.%s.md" % session)).read()
except OSError:
    print("{}"); raise SystemExit(0)
if len(body) > cap:
    body = body[:cap] + ("\n\n[digest truncated at %d characters — the whole of it is "
                         "$XDG_STATE_HOME/ymir/hermes/digest.%s.md]" % (cap, session))
print(json.dumps({"context": "=== YMIR SESSION START (Sága) ===\n" + body}))
try:
    open(os.path.join(state, "injected.%s" % session), "w").write("1\n")
except OSError:
    pass
PY
      exit 0 ;;
    *) noop ;;
  esac
}

main
