#!/usr/bin/env bash
# housewatch.sh — the quiet parts of the house, checked on a timer so they cannot go quiet.
#
# Four surfaces that fail silently today: the model rail, the MCP gateway, the well bridge, and
# the hound's own heartbeat. None of them has a listener; each has a port. A failure is a HIGH
# through Hófvarpnir, keyed per surface per hour, so a flapping service says one thing, not sixty.
#
# The fifth (2026-10-23) is the VOICE: kokoro is idle-lowered on purpose, so being down is not a
# fault by itself — being down while the TTS lease is held is. That distinction is the whole reason
# a voice note came back as text for seven hours while every unit looked healthy.
#
#   bin/time/housewatch.sh [--dry-run] [--quiet]
#
# Exit: 0 every surface answered (or was deliberately skipped) · 1 one did not.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'error: the home is unresolved\n' >&2; exit 1; }

DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
  esac
done

DOOR="$ROOT/bin/notify/send.sh"
fails=0; checked=0
printf 'housewatch{surface,state,note}:\n'

say() {  # <surface> <severity> <message>
  [ "$DRY" = 1 ] && { printf '  "%s","would-say %s","%s"\n' "$1" "$2" "$3"; return; }
  bash "$DOOR" --source ward --severity "$2" --message "$3" \
    --key "housewatch:$1:$(date +%Y%m%d%H)" >/dev/null 2>&1 || true
}

# ── the rail: does it answer its own catalogue? ────────────────────────────────
KEY="$(python3 -c "
import json,os
try: print(json.load(open(os.path.expanduser('~/.pi/agent/auth.json')))['llama-swap']['key'])
except Exception: print('')" 2>/dev/null)"
checked=$((checked + 1))
if [ -z "$KEY" ]; then
  printf '  "rail","SKIP","no llama-swap key in the pi registry"\n'
elif curl -s -m 8 -o /dev/null -H "Authorization: Bearer $KEY" http://127.0.0.1:8080/v1/models; then
  printf '  "rail","ok","answers"\n'
else
  printf '  "rail","FAIL","no answer on :8080"\n'; fails=$((fails + 1))
  say rail HIGH "the model rail is not answering on :8080"
fi

# ── the MCP gateway (the body's one record door) ──────────────────────────────
checked=$((checked + 1))
if curl -s -m 5 -o /dev/null http://127.0.0.1:8316/mcp/well 2>/dev/null \
   || (exec 3<>/dev/tcp/127.0.0.1/8316) 2>/dev/null; then
  printf '  "mcp-gateway","ok","listening on :8316"\n'
else
  printf '  "mcp-gateway","FAIL","nothing on :8316"\n'; fails=$((fails + 1))
  say mcp HIGH "the MCP gateway is dark on :8316 — every record door is shut"
fi

# ── the well bridge ───────────────────────────────────────────────────────────
checked=$((checked + 1))
if curl -s -m 5 -o /dev/null http://127.0.0.1:4602/health 2>/dev/null \
   || (exec 3<>/dev/tcp/127.0.0.1/4602) 2>/dev/null; then
  printf '  "well","ok","the bridge answers on :4602"\n'
else
  printf '  "well","FAIL","nothing on :4602"\n'; fails=$((fails + 1))
  say well HIGH "the well bridge is down on :4602 — recall and observation are blind"
fi

# ── the voice: idle-lowered is by design; dark under a fresh lease is a fault ────────────────
checked=$((checked + 1))
LEASE="$HOME/.local/share/skirnir/tts.lease"
LEASE_TTL="${SKIRNIR_TTS_LEASE_TTL:-900}"
if (exec 3<>/dev/tcp/127.0.0.1/8765) 2>/dev/null; then
  printf '  "voice","ok","kokoro answers on :8765"\n'
elif [ -f "$LEASE" ] && [ $(( $(date +%s) - $(date -r "$LEASE" +%s) )) -lt "$LEASE_TTL" ]; then
  printf '  "voice","FAIL","dark under a fresh TTS lease — a voice note would come back as text"\n'
  fails=$((fails + 1))
  say voice HIGH "kokoro is down while the TTS lease is held — the mouth cannot speak"
else
  printf '  "voice","ok","idle-lowered, as designed (no fresh lease)"\n'
fi

# ── Skírnir: a mouth that stopped answering must be visible, not discovered ───
checked=$((checked + 1))
ABEAT="$HOME_R/hodd/state/assistant/telegram.heartbeat"
# The heartbeat lives in the SHARED home, so it is not a local fact (plan 203 §19): a seat
# where the assistant does not run reads another seat's beat as its own, or an absent beat as
# "not yet", and both are wrong. Measured 2026-11-06: no skirnir unit on this seat, none on the
# heart, no beat in the home — and the alarm still repeated in the ledger. Ask first whether the
# mouth is OURS: a local unit or a local process is the only evidence of that.
# A unit file is the evidence; `pgrep -f skirnir` was no good here, because the shell that runs
# this check carries the word in its own command line and matched itself.
if ! systemctl --user list-unit-files 2>/dev/null | grep -q '^skirnir[.]service'; then
  printf '  "assistant","SKIP","the assistant does not run on this seat - a beat in the shared home is another seat'"'"'s fact"\n'
elif [ ! -f "$ABEAT" ]; then
  printf '  "assistant","SKIP","no heartbeat file yet — the service has not run here"\n'
else
  aage=$(( $(date +%s) - $(date -r "$ABEAT" +%s) ))
  if [ "$aage" -lt 600 ]; then
    printf '  "assistant","ok","last poll %ss ago"\n' "$aage"
  else
    printf '  "assistant","FAIL","silent for %ss"\n' "$aage"; fails=$((fails + 1))
    say assistant HIGH "Skírnir has not polled Telegram for ${aage}s — he may be deaf"
  fi
fi

# ── the hound's heartbeat: a silent watcher is a finding ──────────────────────
# the hound runs as root: its state lives beside its findings, not in the user's home
BEAT="/var/log/ymir/garmr/state/hound.heartbeat"
[ -f "$BEAT" ] || BEAT="$HOME_R/hodd/state/garmr/hound.heartbeat"
checked=$((checked + 1))
if [ -f "$BEAT" ]; then
  age=$(( $(date +%s) - $(date -r "$BEAT" +%s) ))
  if [ "$age" -le 600 ]; then
    printf '  "hound","ok","heartbeat %ss old"\n' "$age"
  elif [ -f "$HOME_R/hodd/state/garmr/PAUSED" ]; then
    printf '  "hound","SKIP","paused by root"\n'
  else
    printf '  "hound","FAIL","heartbeat %ss old"\n' "$age"; fails=$((fails + 1))
    say hound CRITICAL "the hound is silent (heartbeat ${age}s old) — the guardian is not guarding"
  fi
else
  printf '  "hound","SKIP","no heartbeat yet"\n'
fi

printf 'housewatch{checked,failed}:"%s","%s"\n' "$checked" "$fails"
[ "$fails" -eq 0 ] || exit 1
