#!/bin/bash
# What the crontab runs. Cron's PATH is bare, so every path here is absolute: Node 24 from DNA_NODE_DIR (pinned by
# `install`) or the newest nvm v24, then Homebrew and the system. bash, not zsh: the exe.dev image has no zsh.
set -u
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$APP_DIR/../.." && pwd)"
NODE_DIR="${DNA_NODE_DIR:-}"
if [ -z "$NODE_DIR" ]; then
  for d in "$HOME"/.nvm/versions/node/v24*/bin; do [ -d "$d" ] && NODE_DIR="$d"; done
fi
export PATH="$NODE_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
mkdir -p "$ROOT/logs"
cd "$APP_DIR" || exit 1
exec node --import tsx src/main.ts tick >> "$ROOT/logs/cron.out" 2>&1
