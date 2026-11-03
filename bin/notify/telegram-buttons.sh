#!/usr/bin/env bash
# telegram-buttons.sh — make a Telegram button that actually renders.
#
# The bridge parses exactly two wrappers and SILENTLY DROPS anything else, so a
# reply whose controls are almost-right arrives as a wall of prose with no error
# anywhere. This door is the one place the grammar is written down as code:
#
#   telegram-buttons.sh emit --button "label|prompt" [--button …] [--in-body]
#   telegram-buttons.sh check [FILE|-]      # validate a draft reply before sending
#   telegram-buttons.sh --version
#
# `emit` prints the canonical wrapper (footer comment by default, an in-body
# ```telegram_button fence with --in-body) and refuses a button that could not
# work: no prompt, an unknown style, a label past Telegram's limit, more than six
# in a reply, more than eight in a row.
#
# `check` reads a draft reply and names every wrapper it finds, every fault with
# its line, and the one mistake that looks right: the legacy colon form
# `<!--telegram_button: label|prompt-->`, which the bridge ignores completely.
#
# Exit: 0 clean · 1 a finding · 2 usage.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TOOL="$HERE/telegram-buttons.mjs"
VERSION="1.0.0"

command -v node >/dev/null 2>&1 || { printf 'unavailable: node is required for the button grammar\n' >&2; exit 3; }

cmd=${1:-}
case "$cmd" in
  emit|check)
    shift
    exec node "$TOOL" "$cmd" "$@"
    ;;
  --version|-v)
    printf 'telegram-buttons.sh %s\n' "$VERSION"
    ;;
  -h|--help|"")
    sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    printf 'error: unknown verb %s\nhelp: telegram-buttons.sh [emit|check|--version]\n' "$cmd" >&2
    exit 2
    ;;
esac
