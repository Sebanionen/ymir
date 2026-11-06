# The every minute tick (the API schedule picks which ticks sweep). `tick` is the exact program the crontab runs.

set shell := ["zsh", "-cu"]
set positional-arguments
set working-directory := "../../apps/dna-server-cron"

# List cron commands
[default]
default:
    @just --list cron

# Run one tick now (the cron code path)
tick:
    NODE_NO_WARNINGS=1 npx tsx src/main.ts tick

# Install the crontab line
install:
    NODE_NO_WARNINGS=1 npx tsx src/main.ts install

# Remove the crontab line
uninstall:
    NODE_NO_WARNINGS=1 npx tsx src/main.ts uninstall

# Show the crontab line and recent ticks
status:
    NODE_NO_WARNINGS=1 npx tsx src/main.ts status

# Tail the cron log
logs LINES="20":
    tail -n "$1" ../../logs/cron.jsonl
