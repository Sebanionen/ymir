#!/usr/bin/env bash
# hermes-telegram.sh — seat THIS machine's Telegram bot into the Hermes gateway (the machine agent's ear).
#
#   hermes-telegram.sh status         # gateway running? which platforms attached? is the token in the vault?
#   hermes-telegram.sh seat <machine> # write that machine's channel into Hermes' gateway config, FROM THE VAULT
#   hermes-telegram.sh check          # exit 1 when a token is ready but no Telegram platform is attached
#   hermes-telegram.sh unseat         # take the token line out of Hermes' env file (the vault is untouched)
#   hermes-telegram.sh instructions   # the exact steps, including the one only the operator can take
#
# Hermes' gateway is its messaging ear. The token is NEVER typed here and NEVER printed:
# it is read from the home's vault by reference (hodd/identity/machines.yaml → telegram.token_ref)
# and written into Hermes' own env file, ~/.hermes/.env, mode 0600 — the file the gateway reads.
# If the token is absent, `seat` refuses LOUDLY and writes NOTHING: an ear with no bot is not a
# silent success, it is a named gap.
#
# Environment:
#   HERMES_HOME             Hermes' home (default ~/.hermes)
#   TELEGRAM_MACHINES_REG   the fleet registry (default <home>/hodd/identity/machines.yaml)
#
# Exit: 0 done · 1 refused or a named gap · 2 usage.
set -uo pipefail
VERSION="1.0.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
HOME_DIR="$(dirname "${hoard:-/}")"
HERMES="${HERMES_HOME:-$HOME/.hermes}"
STATE="$HERMES/gateway_state.json"
ENVFILE="$HERMES/.env"
REG="${TELEGRAM_MACHINES_REG:-$HOME_DIR/hodd/identity/machines.yaml}"
SEAT="$HOME/.pi/agent/extensions/.ymir-seat"
host="$(sed -n 's/^host=//p' "$SEAT" 2>/dev/null)"

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf 'hermes-telegram: %b\n' "$*" >&2; exit 1; }

registry_field() {  # <machine> <field>
  REG="$REG" python3 - "$1" "$2" <<'PY'
import os, sys, yaml
try:
    machines = ((yaml.safe_load(open(os.environ["REG"])) or {}).get("machines") or {})
except Exception:
    print(""); raise SystemExit
m = machines.get(sys.argv[1]) or {}
for part in sys.argv[2].split("."):
    m = (m or {}).get(part) if isinstance(m, dict) else None
print(m or "")
PY
}

emit_token() {  # <machine> -> the token on stdout, or nothing (the caller owns the refusal)
  local ref tok
  ref="$(registry_field "$1" telegram.token_ref)"
  [ -n "$ref" ] || return 1
  tok="$(bash "$ROOT/bin/vault/hodd.sh" emit "$ref" 2>/dev/null | sed -n 's/^export TELEGRAM_BOT_TOKEN=//p' | head -1)"
  tok="${tok#\'}"; tok="${tok%\'}"
  [ -n "$tok" ] || return 1
  printf '%s' "$tok"
}

token_state() {  # present | absent  — never the value
  if emit_token "${host:-none}" >/dev/null 2>&1; then printf 'present'; else printf 'absent'; fi
}

platforms() { python3 -c "import json;d=json.load(open('$STATE'));print(','.join((d.get('platforms') or {}).keys()) or 'none')" 2>/dev/null || echo 'no gateway'; }

case "${1:-status}" in
  -h|--help|help|"") usage; exit 0 ;;
  --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
  status)
    printf 'hermes-telegram[4]{what,value,note}:\n'
    printf '  "gateway","%s","the messaging ear"\n' "$(python3 -c "import json;d=json.load(open('$STATE'));print(d.get('gateway_state','absent'))" 2>/dev/null || echo absent)"
    printf '  "platforms","%s","telegram appears here once the token is seated and the gateway restarted"\n' "$(platforms)"
    printf '  "token","%s","%s in the vault at %s"\n' "$(token_state)" "$(token_state)" "$(registry_field "${host:-none}" telegram.token_ref)"
    printf '  "env","%s","%s carries TELEGRAM_BOT_TOKEN when seated"\n' "$([ -s "$ENVFILE" ] && grep -qE '^TELEGRAM_BOT_TOKEN=..' "$ENVFILE" && echo 'seated' || echo 'not seated')" "$ENVFILE" ;;
  seat)
    machine="${2:-}"; [ -n "$machine" ] || { printf 'error: seat needs a machine\nhelp: hermes-telegram.sh seat <machine>\n' >&2; exit 2; }
    [ -n "$host" ] || die "this seat has no name (no $SEAT) — an ear must know whose it is, so nothing was written"
    [ "$machine" = "$host" ] || die "this Hermes is $host's ear; $machine's ear is seated ON $machine — nothing was written here"

    # Every refusal comes before any write. Nothing below this block runs until the token is in hand.
    ref="$(registry_field "$machine" telegram.token_ref)"
    [ -n "$ref" ] || die "no registry entry for $machine (or no token_ref) in $REG — nothing was written"
    tok="$(emit_token "$machine")"
    [ -n "$tok" ] || die "no token for $machine: $ref(.age) is absent from the vault (or will not decrypt) — nothing was written\nhelp: create the bot in @BotFather, then bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN <token> $ref"
    [ -d "$HERMES" ] || die "no Hermes home at $HERMES — nothing was written (set HERMES_HOME if it lives elsewhere)"
    command -v hermes >/dev/null 2>&1 || die "hermes is not on PATH, so the platform cannot be enabled — nothing was written\nhelp: bin/engine/hermes-ensure.sh"

    TOK="$tok" python3 - "$ENVFILE" <<'PY' || exit 1
import os, sys
path, tok = sys.argv[1], os.environ["TOK"]
lines = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
out, done = [], False
for ln in lines:
    if ln.startswith("TELEGRAM_BOT_TOKEN=") and not done:
        out.append("TELEGRAM_BOT_TOKEN=" + tok); done = True
    else:
        out.append(ln)
if not done:
    out.append("TELEGRAM_BOT_TOKEN=" + tok)
tmp = path + ".new"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(out) + "\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
print("hermes-telegram: token written to %s (mode 0600, %s)" % (path, "replaced" if done else "appended"))
PY
    # Enable the channel through Hermes' OWN door — no secret ever enters its argv.
    if out="$(hermes config set platforms.telegram.enabled true 2>&1)"; then
      printf 'hermes-telegram: platform enabled (%s)\n' "$(printf '%s' "$out" | tail -1)"
    else
      die "the token is in $ENVFILE but Hermes would not enable the platform — %s\nhelp: hermes config set platforms.telegram.enabled true (then hermes gateway restart)"
    fi
    printf 'hermes-telegram[3]{what,value,note}:\n'
    printf '  "seated","%s","%s into %s"\n' "$machine" "$ref" "$ENVFILE"
    printf '  "next","hermes gateway restart","the running gateway must re-read its platforms"\n'
    printf '  "pair","send /start in the bot'"'"'s DM","the first user to pair becomes the allowed owner"\n' ;;
  unseat)
    [ -s "$ENVFILE" ] || die "no $ENVFILE to change"
    python3 - "$ENVFILE" <<'PY' || exit 1
import os, sys
path = sys.argv[1]
lines = [ln for ln in open(path, encoding="utf-8").read().splitlines() if not ln.startswith("TELEGRAM_BOT_TOKEN=")]
tmp = path + ".new"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
os.chmod(tmp, 0o600); os.replace(tmp, path)
print("hermes-telegram: token line removed from %s (the vault still holds it)" % path)
PY
    printf 'hermes-telegram: run hermes gateway restart to lower the ear\n' ;;
  check)
    p="$(platforms)"
    if [ "$p" = none ] || [ "$p" = 'no gateway' ]; then
      printf 'hermes-telegram: no platform attached (platforms=%s) — run: hermes-telegram.sh seat %s\n' "$p" "${host:-<machine>}" >&2; exit 1
    fi
    case "$p" in *telegram*) printf 'hermes-telegram: telegram is attached ✓\n' ;; *) printf 'hermes-telegram: platforms=%s — telegram is not among them\n' "$p" >&2; exit 1 ;; esac ;;
  instructions)
    printf 'Seat the ear (the token never leaves the vault, and is never printed):\n'
    printf '  1. the bot exists in @BotFather and its token is in the vault:\n'
    printf '       bin/vault/hodd-set.sh TELEGRAM_BOT_TOKEN <token> secrets/telegram-%s.env\n' "${host:-<machine>}"
    printf '  2. write the channel into Hermes from the vault:\n'
    printf '       %s/bin/seat/hermes-telegram.sh seat %s\n' "$ROOT" "${host:-<machine>}"
    printf '  3. restart the gateway:  hermes gateway restart\n'
    printf '  4. pair: open the bot in Telegram and send /start\n'
    printf '  5. prove it:            %s/bin/seat/hermes-telegram.sh check\n' "$ROOT" ;;
  *) printf 'error: unknown action %s\nhelp: hermes-telegram.sh [status|seat <machine>|unseat|check|instructions]\n' "$1" >&2; exit 2 ;;
esac
