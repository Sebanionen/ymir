#!/usr/bin/env bash
# telegram-members.sh — who is actually in a Telegram chat, as far as the Bot API will say.
#
# The bridge that carries this house's Telegram turns exposes no member list at all, so an
# agent cannot see who else is in the room — it sees only the words that arrive. This door asks
# Telegram directly, and states the limit rather than papering over it:
#
#   · getChat                 the chat itself — type, title, id
#   · getChatMemberCount      how many are in it
#   · getChatAdministrators   the administrators, by name and username
#   · getChatMember           ONE known user, if you have their id
#
# **A bot cannot enumerate ordinary members.** Telegram gives a bot the count and the
# administrators; everyone else must be learned from messages that arrive. A door that promised
# "all participants" would be lying, so this one says what it can and refuses what it cannot.
#
# Usage:
#   telegram-members.sh me
#   telegram-members.sh chat   --chat <id|@username>
#   telegram-members.sh count  --chat <id|@username>
#   telegram-members.sh admins --chat <id|@username>
#   telegram-members.sh who    --chat <id|@username> --user <id>
#   telegram-members.sh --version
#
# Token: TELEGRAM_BOT_TOKEN, else the bot token in the harness's telegram profile
# ($PI_TELEGRAM_CONFIG, default ~/.pi/agent/telegram.json). Never printed, never logged.
# Exit: 0 ok · 1 refused by Telegram · 2 usage · 3 unavailable (no token, no curl).
set -u
VERSION="1.0.0"
CONFIG="${PI_TELEGRAM_CONFIG:-$HOME/.pi/agent/telegram.json}"
API="https://api.telegram.org"

die() { printf '%s\n' "$2" >&2; exit "$1"; }

command -v curl >/dev/null 2>&1 || die 3 "unavailable: curl is required"
command -v python3 >/dev/null 2>&1 || die 3 "unavailable: python3 is required"

token="${TELEGRAM_BOT_TOKEN:-}"
if [ -z "$token" ]; then
  [ -f "$CONFIG" ] || die 3 "unavailable: no TELEGRAM_BOT_TOKEN and no profile at $CONFIG"
  token="$(python3 - "$CONFIG" <<'PY'
import json, sys
try:
    doc = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
profiles = doc.get("profiles") or {}
default = profiles.get("default") or {}
tok = default.get("botToken") or ""
if not tok:
    for value in profiles.values():
        if isinstance(value, dict) and value.get("botToken"):
            tok = value["botToken"]
            break
sys.stdout.write(tok)
PY
)"
  [ -n "$token" ] || die 3 "unavailable: the telegram profile carries no bot token"
fi

call() { # <method> [query]
  local method=$1 query=${2:-}
  curl -sS --max-time 20 "$API/bot$token/$method${query:+?$query}"
}

chat=""; user=""
cmd=${1:-}; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --chat) chat=${2:-}; shift 2 ;;
    --user) user=${2:-}; shift 2 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

need_chat() {
  [ -n "$chat" ] || die 2 "this verb needs --chat <id|@username> (the Bot API cannot guess which room you mean)"
}

show() { # <json> <python-expression-name>
  python3 - "$1" "$2" <<'PY'
import json, sys
raw, kind = sys.argv[1], sys.argv[2]
try:
    doc = json.loads(raw)
except Exception:
    sys.stderr.write("refused: Telegram answered with something that is not JSON\n")
    raise SystemExit(1)
if not doc.get("ok"):
    desc = doc.get("description") or "no description"
    code = doc.get("error_code") or "?"
    sys.stderr.write(f"refused by Telegram ({code}): {desc}\n")
    raise SystemExit(1)
res = doc.get("result")
def name(m):
    parts = [m.get("first_name") or "", m.get("last_name") or ""]
    full = " ".join(p for p in parts if p).strip()
    return full or m.get("title") or "(no name)"
if kind == "me":
    print('bot[3]{id,username,name}:')
    print(f'  "{res.get("id")}","{res.get("username") or ""}","{name(res)}"')
elif kind == "chat":
    print('chat[4]{id,type,title,username}:')
    print(f'  "{res.get("id")}","{res.get("type")}","{(res.get("title") or name(res))}","{res.get("username") or ""}"')
elif kind == "count":
    print('count[1]{members}:')
    print(f'  "{res}"')
elif kind == "admins":
    rows = res if isinstance(res, list) else []
    print(f'admins[{len(rows)}]{{id,name,username,status}}:')
    for m in rows:
        u = m.get("user") or {}
        print(f'  "{u.get("id")}","{name(u)}","{u.get("username") or ""}","{m.get("status") or ""}"')
elif kind == "who":
    u = (res or {}).get("user") or {}
    print('member[3]{id,name,username}:')
    print(f'  "{u.get("id")}","{name(u)}","{u.get("username") or ""}"')
PY
}

case "$cmd" in
  me)
    out=$(call getMe) || die 1 "the Bot API did not answer"
    show "$out" me
    ;;
  chat)
    need_chat; out=$(call getChat "chat_id=$chat") || die 1 "the Bot API did not answer"
    show "$out" chat
    ;;
  count)
    need_chat; out=$(call getChatMemberCount "chat_id=$chat") || die 1 "the Bot API did not answer"
    show "$out" count
    ;;
  admins)
    need_chat; out=$(call getChatAdministrators "chat_id=$chat") || die 1 "the Bot API did not answer"
    show "$out" admins
    ;;
  who)
    need_chat; [ -n "$user" ] || die 2 "who needs --user <id> (a bot cannot list members, only look one up)"
    out=$(call getChatMember "chat_id=$chat&user_id=$user") || die 1 "the Bot API did not answer"
    show "$out" who
    ;;
  --version|-v) printf 'telegram-members.sh %s\n' "$VERSION" ;;
  -h|--help|"")
    sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    die 2 "unknown verb '$cmd' (try: telegram-members.sh --help)"
    ;;
esac
