#!/usr/bin/env bash
# telegram-roster.sh — who speaks in a chat, remembered (thin door over the tool).
#
# Telegram will not list a group's members and the bridge does not hand over the
# sender, so the only complete member list a bot can build is a roster built from
# who speaks. This door records, reads and reconciles it.
#
#   telegram-roster.sh record --chat ID --user ID --name S [--username U] [--message ID]
#   telegram-roster.sh list   --chat ID
#   telegram-roster.sh show   --chat ID --user ID
#   telegram-roster.sh chats
#   telegram-roster.sh sync-admins --chat ID --admins-json '<getChatAdministrators result>'
#   telegram-roster.sh --version
#
# The store is <hoard>/data/telegram-rosters/<chat-id>.yaml — private data, hoard only.
# A roster row is a RECORD of who spoke, never a grant of anything.
#
# Exit: 0 ok · 1 refused · 2 usage · 3 unavailable.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
VERSION="1.0.0"
case "${1:-}" in
  --version|-v) printf 'telegram-roster.sh %s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
command -v python3 >/dev/null 2>&1 || { printf 'unavailable: python3 is required\n' >&2; exit 3; }
exec python3 "$HERE/telegram-roster.py" "$@"
