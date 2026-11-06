# The dna command.

set shell := ["zsh", "-cu"]
set positional-arguments
set working-directory := "../../apps/dna-cli"

# List cli commands
[default]
default:
    @just --list cli

# Run any dna command
run *ARGS:
    NODE_NO_WARNINGS=1 npx tsx src/main.ts "$@"

# Put dna on PATH with npm link
link:
    npm link

# Types and CLI tests
check:
    npx tsc -p .
    NODE_NO_WARNINGS=1 npx tsx --test tests/*.test.ts
