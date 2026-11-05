# Terminal client for one device.

set shell := ["zsh", "-cu"]
set positional-arguments
set working-directory := "../../apps/dna-client-tui"

# List tui commands
[default]
default:
    @just --list tui

# Attach to a device's agent
attach DEVICE="local":
    DNA_TARGET="$1" NODE_NO_WARNINGS=1 npx tsx src/main.ts

# Types and render tests
check:
    npx tsc -p .
    NODE_NO_WARNINGS=1 npx tsx --test tests/*.test.ts

# tmux smoke: faux, or a device id
smoke TARGET="faux":
    tests/smoke.sh "$1"
