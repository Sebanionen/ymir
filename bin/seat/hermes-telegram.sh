#!/usr/bin/env bash
# hermes-telegram.sh — seat THIS machine's Telegram bot into the Hermes gateway (the machine agent's ear).
#
#   hermes-telegram.sh status       # is the gateway running, and which platforms are attached?
#   hermes-telegram.sh check        # exit 1 when a token is ready but no Telegram platform is attached
#   hermes-telegram.sh instructions # the exact step (the setup is interactive — the operator pastes the token)
#
# Hermes' gateway is its messaging ear (Telegram, Discord, WhatsApp…). The token comes from the home's
# vault by reference; `hermes gateway setup` is interactive by design, so Ymir points at it and proves it.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; HOME_DIR="$(dirname "${hoard:-/}")"
STATE="$HOME/.hermes/gateway_state.json"
host="$(sed -n 's/^host=//p' "$HOME/.pi/agent/extensions/.ymir-seat" 2>/dev/null)"

platforms() { python3 -c "import json;d=json.load(open('$STATE'));print(','.join((d.get('platforms') or {}).keys()) or 'none')" 2>/dev/null || echo 'no gateway'; }
case "${1:-status}" in
  -h|--help|"") sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  status)
    printf 'hermes-telegram[3]{what,value,note}:\n'
    printf '  "gateway","%s","the messaging ear"\n' "$(python3 -c "import json;d=json.load(open('$STATE'));print(d.get('gateway_state','absent'))" 2>/dev/null || echo absent)"
    printf '  "platforms","%s","telegram appears here once gateway setup has the token"\n' "$(platforms)"
    printf '  "token_ref","%s","%s"\n' "$(python3 -c "import yaml;d=yaml.safe_load(open('$HOME_DIR/hodd/identity/machines.yaml'));print(((d.get('machines') or {}).get('$host') or {}).get('telegram',{}).get('token_ref','-'))" 2>/dev/null || echo '-')" "the vault path, never the token" ;;
  check)
    p="$(platforms)"
    if [ "$p" = none ] || [ "$p" = 'no gateway' ]; then
      printf 'hermes-telegram: no platform attached (platforms=%s) — run: hermes gateway setup\n' "$p" >&2; exit 1
    fi
    case "$p" in *telegram*) printf 'hermes-telegram: telegram is attached ✓\n' ;; *) printf 'hermes-telegram: platforms=%s — telegram is not among them\n' "$p" >&2; exit 1 ;; esac ;;
  instructions)
    printf 'Seat the ear (the operator pastes the token; Ymir never prints it):\n'
    printf '  1. create the bot in @BotFather and store the token: hodd/secrets/telegram-%s.env\n' "${host:-<host>}"
    printf '  2. export TELEGRAM_BOT_TOKEN="$(bash %s/bin/vault/hodd.sh emit secrets/telegram-%s.env | sed -n s/^TELEGRAM_BOT_TOKEN=//p)"\n' "$ROOT" "${host:-<host>}"
    printf '  3. hermes gateway setup      # choose Telegram, paste the token\n'
    printf '  4. %s/bin/seat/hermes-telegram.sh check\n' "$ROOT" ;;
  *) printf 'error: unknown action %s\nhelp: hermes-telegram.sh [status|check|instructions]\n' "$1" >&2; exit 2 ;;
esac
