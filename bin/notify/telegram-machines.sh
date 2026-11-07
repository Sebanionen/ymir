#!/usr/bin/env bash
# telegram-machines.sh — Telegram across the FLEET: each machine's own bot, and the two roads between them.
#
#   telegram-machines.sh list                    # machines, bot id, chat, token_ref (names only, never values)
#   telegram-machines.sh all                     # just the machine names, one per line
#   telegram-machines.sh me <machine>            # which bot answers for that machine (getMe)
#   telegram-machines.sh count <machine> --chat C   # the number Telegram will count for C — and no names
#   telegram-machines.sh relay <to> "<text>"     # speak into <to>'s chat through THIS machine's own bot
#
# THE TWO ROADS BETWEEN THE MACHINES, and they are different roads:
#   1. relay — MACHINE-TO-MACHINE. This machine's own bot speaks into the peer's chat, so the
#      message arrives stamped with the sending machine's name. It is an order or a handover,
#      not a conversation. ONE Runes entry is carved per hop, naming the sender's house, fleet
#      and machine, the receiving machine, and the fact that no token travelled in it — the hop
#      is carried by the sender's own bot, whose token never leaves the vault. A relay that
#      cannot be made refuses LOUDLY and carves nothing.
#   2. shared room — CONVERSATION. One operator group both bots are members of; each answers its
#      own agent's turns and reads the other as a participant. Telegram will never list the
#      members of that room, for any bot, ever — so the only honest member list is the roster
#      built from WHO HAS SPOKEN: bin/notify/telegram-roster.sh list --chat <id>.
#
# THE TOKEN NEVER PRINTS (Rule 24). It is read from the home's vault by reference —
#   hodd/identity/machines.yaml → telegram.token_ref  (e.g. secrets/telegram-<machine>.env[.age])
# — and handed to curl through a 0600 config file, never through its argv, so it is not visible
# in a process listing either.
#
# Environment:
#   TELEGRAM_MACHINES_REG   registry path (default <home>/hodd/identity/machines.yaml)
#
# Exit: 0 done · 1 refused (nothing sent, nothing carved) · 2 usage.
set -uo pipefail
VERSION="1.0.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hoard="$(bash "$ROOT/bin/vault/hodd.sh" path 2>/dev/null || true)"
[ -n "$hoard" ] || { printf 'telegram-machines: no home — run bin/vault/hodd.sh path and see why\n' >&2; exit 1; }
HOME_DIR="$(dirname "$hoard")"
REG="${TELEGRAM_MACHINES_REG:-$HOME_DIR/hodd/identity/machines.yaml}"
SEAT="$HOME/.pi/agent/extensions/.ymir-seat"
ROSTER="$ROOT/bin/notify/telegram-roster.sh"
RUNES="$ROOT/bin/records/runes-append.sh"
[ -r "$REG" ] || { printf 'telegram-machines: no registry at %s\nhelp: create it (see hodd/identity/machines.example.yaml in the ymir repo)\n' "$REG" >&2; exit 1; }

usage() { sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf 'telegram-machines: %b\n' "$*" >&2; exit 1; }

py() { REG="$REG" python3 - "$@" <<'PY2'
import os, sys, yaml
reg = yaml.safe_load(open(os.environ["REG"])) or {}
cmd = sys.argv[1]
machines = reg.get('machines') or {}
if cmd == 'list':
    for name, m in machines.items():
        tg = (m or {}).get('telegram') or {}
        print(f"{name}\tbot={tg.get('bot_id') or '-'}\tchat={tg.get('chat') or '-'}\ttoken_ref={tg.get('token_ref') or '-'}")
elif cmd == 'all':
    print('\n'.join(machines.keys()))
elif cmd == 'has':
    sys.exit(0 if sys.argv[2] in machines else 1)
elif cmd == 'field':
    name, field = sys.argv[2], sys.argv[3]
    m = machines.get(name) or {}
    for part in field.split('.'):
        m = (m or {}).get(part) if isinstance(m, dict) else None
    print(m or '')
PY2
}

emit_token() {  # <machine> -> the token on stdout, or nothing (never a message: callers own the refusal)
  local name="$1" ref tok
  ref="$(py field "$name" telegram.token_ref 2>/dev/null)"
  [ -n "$ref" ] || return 1
  tok="$(bash "$ROOT/bin/vault/hodd.sh" emit "$ref" 2>/dev/null | sed -n 's/^export TELEGRAM_BOT_TOKEN=//p' | head -1)"
  # hodd.sh emits shell-quoted values; undo that one layer so the value is the token.
  tok="${tok#\'}"; tok="${tok%\'}"
  [ -n "$tok" ] || return 1
  printf '%s' "$tok"
}

api() {  # <method> <token> [curl args...] — the token goes in a 0600 config, never in argv
  local method="$1" tok="$2" cfg rc; shift 2
  cfg="$(mktemp)"; chmod 600 "$cfg"
  printf 'url = "https://api.telegram.org/bot%s/%s"\n' "$tok" "$method" >"$cfg"
  curl -s --max-time 25 --config "$cfg" "$@"
  rc=$?
  rm -f "$cfg"
  return "$rc"
}

self_name() { sed -n 's/^host=//p' "$SEAT" 2>/dev/null; }

identity() {  # house|fleet, from the home's seats.yaml — never a table in this script
  SEATS="$HOME_DIR/hodd/identity/seats.yaml" python3 - <<'PY2'
import os
try:
    import yaml
    fleet = (yaml.safe_load(open(os.environ["SEATS"])) or {}).get("fleet") or {}
except Exception:
    fleet = {}
print("%s|%s" % (fleet.get("house") or "unknown", fleet.get("name") or "unknown"))
PY2
}

case "${1:-}" in
  -h|--help|help|"") usage; exit 0 ;;
  --version|-v) printf '%s\n' "$VERSION"; exit 0 ;;
  list) py list ;;
  all) py all ;;
  me)
    m="${2:-}"; [ -n "$m" ] || { printf 'error: me needs a machine\nhelp: telegram-machines.sh me <machine>\n' >&2; exit 2; }
    py has "$m" || die "no registry entry for $m in $REG — nothing asked, nothing answered"
    tok="$(emit_token "$m")" || die "$m has no token: its token_ref does not resolve in the vault — nothing asked"
    api getMe "$tok" | python3 -c 'import sys,json
d=json.load(sys.stdin); r=d.get("result") or {}
if d.get("ok"): print("telegram-machines[1]{machine,bot,id}:\n  \"%s\",\"@%s\",\"%s\"" % (sys.argv[1], r.get("username"), r.get("id")))
else: print("telegram-machines: Telegram refused: %s" % (d.get("description") or "unknown"), file=sys.stderr); sys.exit(1)' "$m" ;;
  count)
    m="${2:-}"; chat=""
    shift 2 || true
    while [ $# -gt 0 ]; do case "$1" in --chat) chat="${2:-}"; shift 2 ;; *) printf 'error: unknown argument %s\n' "$1" >&2; exit 2 ;; esac; done
    [ -n "$m" ] && [ -n "$chat" ] || { printf 'error: count needs a machine and --chat\nhelp: telegram-machines.sh count <machine> --chat <id|@name>\n' >&2; exit 2; }
    py has "$m" || die "no registry entry for $m in $REG — nothing asked, nothing answered"
    tok="$(emit_token "$m")" || die "$m has no token: its token_ref does not resolve in the vault — nothing asked"
    api getChatMemberCount "$tok" --data-urlencode "chat_id=$chat" | python3 -c 'import sys,json
d=json.load(sys.stdin)
if d.get("ok"): print("telegram-machines[2]{machine,chat,count,names}:\n  \"%s\",\"%s\",\"%s\",\"0\"\n  \"note\",\"the Bot API counts members and names none of them\",\"\"\n  \"roster\",\"bin/notify/telegram-roster.sh list --chat %s\",\"who has actually spoken\"" % (sys.argv[1], sys.argv[2], d["result"], sys.argv[2]))
else: print("telegram-machines: Telegram refused: %s" % (d.get("description") or "unknown"), file=sys.stderr); sys.exit(1)' "$m" "$chat" ;;
  relay)
    to="${2:-}"; text="${3:-}"
    [ -n "$to" ] || { printf 'error: relay needs a target machine\nhelp: telegram-machines.sh relay <to> "<text>"\n' >&2; exit 2; }
    [ -n "$text" ] || { printf 'error: relay needs the text to send\nhelp: telegram-machines.sh relay <to> "<text>"\n' >&2; exit 2; }

    me_name="$(self_name)"
    [ -n "$me_name" ] || die "this seat has no name (no $SEAT) — a hop must say which machine spoke, so nothing was sent and no Rune was carved"

    # 1. the registry must know the RECEIVING machine — an unknown peer is a refusal, not a guess.
    py has "$to" >/dev/null 2>&1 || die "no registry entry for $to in $REG — nothing was sent and no Rune was carved (add machines.$to.telegram.{bot_id,chat,token_ref})"

    # 2. the receiving machine must name its chat — the door never guesses the room.
    chat="$(py field "$to" telegram.chat 2>/dev/null)"
    [ -n "$chat" ] || die "$to has no telegram.chat in $REG (its rooms are not this door's to guess) — nothing was sent and no Rune was carved"

    # 3. the SENDER's own token carries the hop. The peer's token cannot send in this machine's
    #    name, and no token travels inside the message.
    ref="$(py field "$me_name" telegram.token_ref 2>/dev/null)"
    tok="$(emit_token "$me_name")"
    [ -n "$tok" ] || die "the sending machine $me_name has no token — ${ref:-its token_ref} is absent from the vault or will not decrypt. The hop is carried by THIS machine's own bot, so nothing was sent and no Rune was carved\nhelp: store it with bin/vault/hodd-set.sh (never in a file, a log or a plan)"

    # 4. send. A refused send is not a hop: nothing is carved.
    resp="$(api sendMessage "$tok" -X POST --data-urlencode "chat_id=$chat" --data-urlencode "text=[$me_name] $text")" \
      || die "the Bot API could not be reached — nothing was sent and no Rune was carved"
    parsed="$(printf '%s' "$resp" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("ERR:cannot read the Bot API answer"); raise SystemExit
if d.get("ok"): print("OK:%s" % ((d.get("result") or {}).get("message_id") or ""))
else: print("ERR:%s" % (d.get("description") or "unknown"))')"
    case "$parsed" in
      OK:*) msg_id="${parsed#OK:}" ;;
      *) die "Telegram refused the hop — ${parsed#ERR:} — nothing was sent and no Rune was carved" ;;
    esac

    # 5. one Runes entry per hop, through the ledger's own door (never a hand-written line).
    IFS='|' read -r house fleet <<<"$(identity)"
    rune_msg="relay hop · machine=$me_name · house=$house · fleet=$fleet · to=$to · token-in-payload=none · message-id=$msg_id"
    if bash "$RUNES" "$me_name" telegram.relay --message "$rune_msg" >/dev/null 2>&1; then
      rune="carved"
    else
      rune="NOT CARVED (the ledger refused — see bin/records/runes-append.sh)"
    fi

    # 6. the receiving chat's roster gains the speaker — the only honest member list there is.
    #    The roster is a person's record keyed by a Telegram id, so a hop is filed under the
    #    sending machine's OWN bot id from the registry; with no bot id, nothing is invented.
    bot_id="$(py field "$me_name" telegram.bot_id 2>/dev/null)"
    if [ ! -r "$ROSTER" ]; then
      roster="not recorded (bin/notify/telegram-roster.sh is missing)"
    elif [ -z "$bot_id" ]; then
      roster="not recorded ($me_name has no telegram.bot_id in the registry — a roster row is keyed by an id, never by a guess)"
    elif bash "$ROSTER" record --chat "$chat" --user "$bot_id" --name "$me_name" --message "$msg_id" >/dev/null 2>&1; then
      roster="recorded"
    else
      roster="not recorded (the roster refused)"
    fi

    printf 'telegram-relay[4]{what,value,note}:\n'
    printf '  "sent","%s → %s","message-id %s"\n' "$me_name" "$to" "$msg_id"
    printf '  "runes","%s","one entry per hop, chained by the ledger"\n' "$rune"
    printf '  "roster","%s","chat %s, speaker %s"\n' "$roster" "$chat" "$me_name"
    printf '  "token","not sent","carried by %s own bot from the vault; never in the payload"\n' "$me_name" ;;
  *) printf 'error: unknown action %s\nhelp: telegram-machines.sh [list|all|me <m>|count <m> --chat C|relay <to> "<text>"]\n' "$1" >&2; exit 2 ;;
esac
