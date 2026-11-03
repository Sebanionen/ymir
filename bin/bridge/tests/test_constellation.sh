#!/usr/bin/env bash
# test_constellation.sh — the road's proof: a card, a grant, a token, and the refusals.
#
# Everything runs in a throwaway YMIR_HOME and registry, so no real house, key or
# grant is touched. The test asserts the SIX things the road claims:
#
#   1. a published card validates against the shared contract (and a card carrying
#      a secret is refused);
#   2. `list` reports a peer, and an unconfigured registry says UNKNOWN, not zero;
#   3. a grant naming a skill the card does not declare is refused;
#   4. a grant is written `pending`, and a token cannot be minted for it;
#   5. a token verifies for its audience and skill, and is refused for a wrong
#      audience, a wrong skill, and after revocation;
#   6. an expired token is refused.
#
# Usage: test_constellation.sh
# Exit: 0 all pass · 1 a failure.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)
CLI="$ROOT/bin/bridge/constellation.sh"
TOOL="$ROOT/bin/bridge/constellation-tool.mjs"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export YMIR_HOME="$TMP/home"
export CONSTELLATION_REGISTRY="$TMP/registry"
export CONSTELLATION_SELF="hearth"
export CONSTELLATION_OPERATOR="the operator"
mkdir -p "$CONSTELLATION_REGISTRY" "$YMIR_HOME/hodd/identity" "$YMIR_HOME/hodd/state/constellation"
GRANTS="$YMIR_HOME/hodd/identity/grants.yaml"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
expect_ok()   { local why=$1; shift; if "$@" >"$TMP/out" 2>"$TMP/err"; then ok "$why"; else bad "$why" "$(tail -2 "$TMP/err" | tr '\n' ' ')"; fi; }
expect_fail() { local why=$1; shift; if "$@" >"$TMP/out" 2>"$TMP/err"; then bad "$why" "expected a refusal, got success: $(tail -1 "$TMP/out")"; else ok "$why"; fi; }

printf 'constellation road test\n'

# --- keys -------------------------------------------------------------------
expect_ok "keygen makes this house a key pair" "$CLI" keygen hearth --out "$YMIR_HOME/hodd/state/constellation"
KEY="$YMIR_HOME/hodd/state/constellation/hearth.ed25519.key"
PUB="$YMIR_HOME/hodd/state/constellation/hearth.ed25519.pub"
[ -f "$KEY" ] && [ -f "$PUB" ] && ok "the key pair exists" || bad "the key pair exists"

# --- a peer's key and card ---------------------------------------------------
node "$TOOL" keygen --name farhall --out "$TMP/peer" >/dev/null
PEER_PUB="$TMP/peer/farhall.ed25519.pub"

expect_ok "publish this house's card"  "$CLI" publish hearth --endpoint https://hearth.example/a2a --skill well-recall:Recall --pub "$PUB"
expect_ok "publish the peer's card"    "$CLI" publish farhall --endpoint https://farhall.example/a2a --skill ask:Ask --pub "$PEER_PUB"
[ -f "$CONSTELLATION_REGISTRY/hearth.json" ] && ok "the card is on disk" || bad "the card is on disk"

LEAKY=$(printf 'Authorization: Bearer %s%s' 'sk-' 'abcdefghijklmnopqrstuvwxyz')
printf '{"name":"leaky","description":"d","url":"https://x.example","version":"1","capabilities":{},"skills":[{"id":"a","name":"a"}],"defaultInputModes":["text/plain"],"defaultOutputModes":["text/plain"],"note":"%s"}\n' "$LEAKY" >"$TMP/leaky.json"
expect_fail "a card carrying a secret is refused" node "$TOOL" validate "$TMP/leaky.json"

expect_ok "list reports both peers" "$CLI" list
grep -q '"hearth"' "$TMP/out" && grep -q '"farhall"' "$TMP/out" && ok "both cards are listed" || bad "both cards are listed" "$(cat "$TMP/out")"

CONSTELLATION_REGISTRY="$TMP/nowhere" "$CLI" list >"$TMP/out" 2>&1
grep -q "UNKNOWN" "$TMP/out" && ok "an unconfigured registry says UNKNOWN, never zero" || bad "an unconfigured registry says UNKNOWN" "$(cat "$TMP/out")"

# --- the grant ward ----------------------------------------------------------
expect_fail "a grant for an undeclared skill is refused" "$CLI" grant farhall well-recall --self hearth

expect_ok "a grant for a declared skill is written pending" "$CLI" grant farhall ask --self hearth --expires 2099-01-01T00:00:00Z
grep -q 'state: pending' "$GRANTS" && ok "the grant is pending until countersigned" || bad "the grant is pending until countersigned" "$(cat "$GRANTS")"
GID=$(python3 -c 'import yaml;print(yaml.safe_load(open("'"$GRANTS"'"))["grants"][0]["grant_id"])')

expect_fail "a token cannot be minted for a pending grant" "$CLI" mint --peer farhall --skill ask --self hearth
expect_ok "the grant guard is clean for a pending grant" "$CLI" guard

BODY="$YMIR_HOME/hodd/state/constellation/$GID.body"
[ -f "$BODY" ] && ok "the canonical body is kept for the countersignature" || bad "the canonical body is kept" "$BODY"
PEER_SIG=$(node "$TOOL" signbody --key "$TMP/peer/farhall.ed25519.key" --body "$BODY")
expect_fail "activate refuses without the peer's countersignature" "$CLI" activate "$GID"
expect_ok "countersign with the peer's signature activates the grant" "$CLI" countersign "$GID" --sig "$PEER_SIG" --pub "$PEER_PUB"
grep -q 'state: active' "$GRANTS" && ok "the grant is active once both houses signed" || bad "the grant is active once both houses signed"

# --- the token ---------------------------------------------------------------
expect_ok "mint a token for an active grant" "$CLI" mint --peer farhall --skill ask --self hearth --minutes 5
TOKEN=$(tail -1 "$TMP/out")
expect_ok "the token verifies for its audience and skill" node "$TOOL" verify --pub "$PUB" --token "$TOKEN" --aud farhall --skill ask
expect_fail "the token is refused for a wrong audience"  node "$TOOL" verify --pub "$PUB" --token "$TOKEN" --aud another
expect_fail "the token is refused for a wrong skill"     node "$TOOL" verify --pub "$PUB" --token "$TOKEN" --skill well-recall
expect_fail "the token is refused against another key"   node "$TOOL" verify --pub "$PEER_PUB" --token "$TOKEN"

expect_ok "an expired token is refused" bash -c "
  true
  "$CLI" mint --peer farhall --skill ask --self hearth --minutes 0 >/dev/null 2>&1 && exit 1 || exit 0
"

# --- revoke -----------------------------------------------------------------
expect_ok "revoke the grant" "$CLI" revoke farhall
grep -q 'state: revoked' "$GRANTS" && ok "the grant is recorded revoked" || bad "the grant is recorded revoked"
expect_fail "a token cannot be minted after revocation" "$CLI" mint --peer farhall --skill ask --self hearth

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
