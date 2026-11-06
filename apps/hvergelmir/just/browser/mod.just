# Web client: a hub on 127.0.0.1 that holds the client token, plus the Vue app.
# Each device's hub runs on its hub_port from dna-network.yaml (DNA_HUB_PORT or 4851 without one).

set shell := ["zsh", "-cu"]
set positional-arguments
set working-directory := "../../apps/dna-client-browser"

# List browser commands
[default]
default:
    @just --list browser

# Hub with Vite hot reload
dev DEVICE="local":
    DNA_TARGET="$1" NODE_NO_WARNINGS=1 npx tsx hub/src/main.ts --dev

# Build the Vue app
build:
    npm run build

# Serve the built app against a device
start DEVICE="local":
    DNA_TARGET="$1" NODE_NO_WARNINGS=1 npx tsx hub/src/main.ts

# Serve every device in the background and print the links
all:
    npm run build
    NODE_NO_WARNINGS=1 npx tsx hub/src/all.ts

# Stop every hub
stop:
    @pkill -f "hub/src/main.ts" && echo "stopped the hubs" || echo "no hub running"

# Types and lint
check:
    npm run check
    npx oxlint fe hub tests
