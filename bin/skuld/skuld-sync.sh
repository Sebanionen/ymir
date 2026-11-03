#!/usr/bin/env bash
# skuld-sync.sh — the fleet mirror: the instances pull the heart's whole book.
# The heart (whynot) is the primary store; each seat keeps a local snapshot for
# the offline law and the cold glance. Seated by fleet-ensure / the nornir list.
set -u
HEART="${SKULD_HEART:-http://192.0.2.111:8320}"
MIRROR="${SKULD_MIRROR:-$HOME/.fleet/skuld-snapshot.json}"
SID=$(curl -s -m 10 -D /tmp/ss.txt -X POST "$HEART" -H "content-type: application/json" -H "accept: application/json, text/event-stream" -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"fleet-sync","version":"1"}}}' >/dev/null 2>&1; grep -i "^mcp-session-id" /tmp/ss.txt 2>/dev/null | tr -d '\r' | awk '{print $2}' | head -1)
[ -z "$SID" ] && { echo "skuld-sync: no session (the heart's wire)" >&2; exit 1; }
curl -s -m 60 -X POST "$HEART" -H "content-type: application/json" -H "accept: application/json, text/event-stream" -H "mcp-session-id: $SID" -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sync_snapshot","arguments":{}}}' > "$MIRROR.tmp" 2>/dev/null
[ -s "$MIRROR.tmp" ] && mv "$MIRROR.tmp" "$MIRROR" && echo "mirror: $(wc -c < "$MIRROR") bytes"
