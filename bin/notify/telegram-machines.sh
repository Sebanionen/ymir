#!/usr/bin/env bash
# telegram-machines.sh — Telegram across the FLEET: each machine's own bot, and the road between them.
#
#   telegram-machines.sh list                     # machines, their bot id and chat, their token_ref (names only)
#   telegram-machines.sh all                      # the machine names, one per line
#   telegram-machines.sh me <machine>             # which bot answers — that machine's token, asked getMe
#   telegram-machines.sh count <machine> --chat C  # how many are in chat C, asked with THAT machine's bot
#   telegram-machines.sh admins <machine> --chat C # chat C's administrators, same way
#   telegram-machines.sh relay <to> "<text>"      # send through THIS machine's bot into <to>'s chat; a Rune is carved
#
# THE LIMIT, and it is Telegram's not ours: a bot cannot ENUMERATE ordinary members. It is given
# the chat, the count, the administrators and one known user at a time — `bin/notify/telegram-members.sh`
# answers those, and `bin/notify/telegram-roster.sh` remembers who SPOKE. This door only chooses
# WHICH MACHINE'S BOT asks; the member answers are the member door's to give.
# THE TOKEN NEVER PRINTS (Rule 24). It is read from the home's vault by reference:
#   hodd/identity/machines.yaml → telegram.token_ref (e.g. secrets/telegram-<machine>.env)
#   and emitted only into the environment of the child process.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"; [ -n "$hoard" ] || { echo "telegram-machines: no home" >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
REG="$HOME_DIR/hodd/identity/machines.yaml"
MEMBERS="$ROOT/bin/notify/telegram-members.sh"
[ -r "$REG" ] || { printf 'telegram-machines: no registry at %s\nhelp: create it (see hodd/identity/machines.yaml.example)\n' "$REG" >&2; exit 1; }

py() { python3 - "$REG" "$@" <<'PY2'
import sys, yaml
reg = yaml.safe_load(open(sys.argv[1])) or {}
cmd = sys.argv[2]
machines = reg.get('machines') or {}
if cmd == 'list':
    for name, m in machines.items():
        tg = m.get('telegram') or {}
        print(f"{name}\tbot={tg.get('bot_id','-')}\tchat={tg.get('chat','-')}\ttoken_ref={tg.get('token_ref','-')}")
elif cmd in ('field',):
    name, field = sys.argv[3], sys.argv[4]
    m = machines.get(name) or {}
    for part in field.split('.'):
        m = (m or {}).get(part) if isinstance(m, dict) else None
    print(m or '')
elif cmd == 'all':
    print('\n'.join(machines.keys()))
PY2
}

emit_token() {  # <machine> -> env-only token, EMPTY (never a silent exit) when the vault has none
  local name="$1" ref out
  ref="$(py field "$name" telegram.token_ref 2>/dev/null)"
  [ -n "$ref" ] || { printf 'telegram-machines: %s has no token_ref in the registry\n' "$name" >&2; return 1; }
  # `|| true`: under pipefail a missing vault file must not abort the caller with no message
  out="$(YMIR_HOST="$name" bash -c 'bash "$0" emit "$1"' "$ROOT/bin/vault/hodd.sh" "$ref" 2>/dev/null || true)"
  printf '%s\n' "$out" | sed -n 's/^TELEGRAM_BOT_TOKEN=//p' | head -1
  return 0
}

case "${1:-}" in
  -h|--help|"") sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  list) py list ;;
  all) py all ;;
  me)
    m="${2:?machine}"; tok="$(emit_token "$m")" || exit 1
    [ -n "$tok" ] || { printf 'telegram-machines: no TELEGRAM_BOT_TOKEN in %s'\''s vault ref\n' "$m" >&2; exit 1; }
    TELEGRAM_BOT_TOKEN="$tok" bash "$MEMBERS" me ;;
  count|admins|chat|who)
    # the member door owns the answer; this door only decides WHICH MACHINE'S BOT asks it
    act="$1"; m="${2:?machine}"; shift 2
    tok="$(emit_token "$m")" || exit 1
    [ -n "$tok" ] || { printf 'telegram-machines: no TELEGRAM_BOT_TOKEN in %s'\''s vault ref\n' "$m" >&2; exit 1; }
    TELEGRAM_BOT_TOKEN="$tok" bash "$MEMBERS" "$act" "$@" ;;
  relay)
    to="${2:?target machine}"; text="${3:?text}"
    me_name="$(sed -n 's/^host=//p' "$HOME/.pi/agent/extensions/.ymir-seat" 2>/dev/null)"
    chat="$(py field "$to" telegram.chat 2>/dev/null)"; tok="$(emit_token "$me_name")" || exit 1
    [ -n "$chat" ] && [ -n "$tok" ] || { printf 'telegram-machines: %s needs telegram.chat and %s needs its token\n' "$to" "$me_name" >&2; exit 1; }
    curl -s --max-time 20 -X POST "https://api.telegram.org/bot$tok/sendMessage" \
      --data-urlencode "chat_id=$chat" --data-urlencode "text=[$me_name] $text" | python3 -c 'import sys,json;d=json.load(sys.stdin);print("sent" if d.get("ok") else d)' 2>/dev/null
    bash "$ROOT/bin/records/runes-append.sh" --actor "$me_name" --event telegram.relay --message "relay $me_name -> $to" >/dev/null 2>&1 || true ;;
  *) printf 'error: unknown action %s\nhelp: telegram-machines.sh [list|all|me <m>|count <m> --chat C|admins <m> --chat C|relay <to> <text>]\n' "$1" >&2; exit 2 ;;
esac
