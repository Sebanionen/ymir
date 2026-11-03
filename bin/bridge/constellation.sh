#!/usr/bin/env bash
# constellation.sh — the A2A road between two Ymir fleets, as one door.
#
# Plan 172 ("two fleets, one road"). A road is not a reachability and not an
# account: it is a CARD (published by its own house), a GRANT (written in the
# receiving house's own hoard, per pair and per skill, with an expiry) and a
# short-lived EdDSA token verified against the public key already in the sender's
# card. Nothing here calls MCP, and nothing here enrols a peer in the fleet.
#
# Usage:
#   constellation.sh keygen <name> [--out DIR]
#   constellation.sh publish <name> --endpoint URL --skill id:name[,…] [--description S]
#                                    [--pub FILE] [--out DIR]
#   constellation.sh list   [--registry DIR] [--json]
#   constellation.sh show   <peer> [--registry DIR]
#   constellation.sh grant  <peer> <skill>… [--self NAME] [--operator S] [--expires ISO]
#                           [--role reader|member|writer|admin] [--namespace N] [--key FILE]
#   constellation.sh countersign <grant-id> [--sig SIG] [--pub FILE]
#   constellation.sh revoke <grant-id> | <peer>
#   constellation.sh grants [--peer NAME]
#   constellation.sh mint   --peer NAME --skill ID [--self NAME] [--minutes N] [--key FILE]
#   constellation.sh verify --token TOKEN --pub FILE [--aud NAME] [--skill ID]
#   constellation.sh doctor
#   constellation.sh --version
#
# Environment (Rule 07 — one documented default each):
#   YMIR_HOME              the operator's home (resolved by bin/vault/hoard-lib.sh)
#   CONSTELLATION_REGISTRY registry of agent cards (default: <hoard>/data/constellation/agents)
#   CONSTELLATION_SELF     this house's ymir name, as its own card declares it
#   CONSTELLATION_OPERATOR the operator this house speaks for
#   CONSTELLATION_KEY      this house's ed25519 private key (default: <hoard>/state/constellation/<self>.ed25519.key)
#
# Exit: 0 ok, 1 refused, 2 usage, 3 unavailable.
set -u
VERSION="1.0.0"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
TOOL="$HERE/constellation-tool.mjs"
GRANTS="$HERE/constellation-grants.py"
GUARD="$ROOT/bin/gates/guards/constellation-grant-guard.sh"

die() { printf '%s\n' "$2" >&2; exit "$1"; }
toon() { printf '%s\n' "$1"; }

# shellcheck source=/dev/null
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
hoard=""
if declare -F hoard_root >/dev/null 2>&1; then hoard_root hoard 2>/dev/null || true; fi
[ -n "$hoard" ] || die 3 "constellation: cannot resolve the home — bin/vault/hoard-lib.sh did not answer"

registry="${CONSTELLATION_REGISTRY:-$hoard/data/constellation/agents}"
grants_file="$hoard/identity/grants.yaml"
self_name="${CONSTELLATION_SELF:-}"
operator="${CONSTELLATION_OPERATOR:-${USER:-operator}}"
key="${CONSTELLATION_KEY:-}"

node_or_die() { command -v node >/dev/null 2>&1 || die 3 "constellation: node is required (the card contract is validated by it)"; }

card_path() { printf '%s/%s.json' "$registry" "$1"; }
have_card() { [ -f "$(card_path "$1")" ]; }

skill_of_card() { # <name> <skill>
  node -e '
    const fs=require("fs");
    const card=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const ids=(card.skills||[]).map(s=>s.id);
    process.stdout.write(ids.includes(process.argv[2]) ? "yes" : ids.join(","));
  ' "$(card_path "$1")" "$2"
}

cmd=${1:-}; shift || true

case "$cmd" in
  --version|-v) toon "constellation.sh $VERSION"; exit 0 ;;

  keygen)
    node_or_die
    name=${1:-}; shift || true
    [ -n "$name" ] || die 2 "usage: constellation.sh keygen <name> [--out DIR]"
    out=""
    while [ $# -gt 0 ]; do case "$1" in --out) out=${2:-}; shift 2 ;; *) die 2 "keygen: unknown argument $1" ;; esac; done
    out=${out:-$hoard/state/constellation}
    res=$(node "$TOOL" keygen --name "$name" --out "$out") || die 1 "keygen failed"
    toon "$res"
    ;;

  publish)
    node_or_die
    name=${1:-}; shift || true
    [ -n "$name" ] || die 2 "usage: constellation.sh publish <name> --endpoint URL --skill id:name[,…]"
    endpoint="" skills="" description="" pub=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --endpoint) endpoint=${2:-}; shift 2 ;;
        --skill) skills=${2:-}; shift 2 ;;
        --description) description=${2:-}; shift 2 ;;
        --pub) pub=${2:-}; shift 2 ;;
        *) die 2 "publish: unknown argument $1" ;;
      esac
    done
    [ -n "$endpoint" ] || die 2 "publish: --endpoint is required"
    [ -n "$skills" ] || die 2 "publish: --skill is required"
    mkdir -p "$registry" || die 1 "cannot create $registry"
    args=(build --name "$name" --endpoint "$endpoint" --skill "$skills" --out "$(card_path "$name")")
    [ -n "$description" ] && args+=(--description "$description")
    [ -n "$pub" ] && args+=(--pub "$pub")
    node "$TOOL" "${args[@]}" || die 1 "publish: the card was refused"
    toon "published[2]{name,path}:"
    toon "  \"$name\",\"$(card_path "$name")\""
    ;;

  list)
    node_or_die
    json=0
    while [ $# -gt 0 ]; do case "$1" in --registry) registry=${2:-}; shift 2 ;; --json) json=1; shift ;; *) die 2 "list: unknown argument $1" ;; esac; done
    if [ ! -d "$registry" ]; then
      toon "constellation-skip[1]{reason}:"
      toon "  \"no registry at $registry — an unconfigured mesh is UNKNOWN, not empty\""
      exit 3
    fi
    if [ "$json" = 1 ]; then
      node -e '
        const fs=require("fs"),path=require("path");
        const dir=process.argv[1];
        const out=[];
        for (const f of fs.readdirSync(dir).filter(f=>f.endsWith(".json")&&f!=="agent-card.schema.json").sort()) {
          try { const c=JSON.parse(fs.readFileSync(path.join(dir,f),"utf8")); out.push({file:f,name:c.name,url:c.url,skills:(c.skills||[]).map(s=>s.id)}); }
          catch(e){ out.push({file:f,invalid:e.message}); }
        }
        process.stdout.write(JSON.stringify(out,null,1)+"\n");
      ' "$registry"
      exit 0
    fi
    node -e '
      const fs=require("fs"),path=require("path");
      const dir=process.argv[1];
      const files=fs.readdirSync(dir).filter(f=>f.endsWith(".json")&&f!=="agent-card.schema.json").sort();
      const ok=[],bad=[];
      for (const f of files) {
        try { const c=JSON.parse(fs.readFileSync(path.join(dir,f),"utf8"));
          ok.push([c.name||f,c.url||"",(c.skills||[]).map(s=>s.id).join(","),(c.kid||"-")]); }
        catch(e){ bad.push([f,e.message.replace(/"/g,"\x27")]); }
      }
      const lines=[];
      lines.push(`peers[${ok.length}]{name,url,skills,kid}:`);
      for (const r of ok) lines.push(`  "${r[0]}","${r[1]}","${r[2]}","${r[3]}"`);
      if (bad.length) { lines.push(`invalid[${bad.length}]{file,why}:`); for (const r of bad) lines.push(`  "${r[0]}","${r[1]}"`); }
      process.stdout.write(lines.join("\n")+"\n");
    ' "$registry"
    ;;

  show)
    peer=${1:-}; shift || true
    [ -n "$peer" ] || die 2 "usage: constellation.sh show <peer>"
    while [ $# -gt 0 ]; do case "$1" in --registry) registry=${2:-}; shift 2 ;; *) die 2 "show: unknown argument $1" ;; esac; done
    have_card "$peer" || die 1 "constellation: no card for $peer in $registry"
    cat "$(card_path "$peer")"
    ;;

  grant)
    node_or_die
    peer=${1:-}; shift || true
    [ -n "$peer" ] || die 2 "usage: constellation.sh grant <peer> <skill>… [--expires ISO]"
    skills=()
    expires="" role="reader" namespace="ymir-mesh"
    while [ $# -gt 0 ]; do
      case "$1" in
        --expires) expires=${2:-}; shift 2 ;;
        --role) role=${2:-}; shift 2 ;;
        --namespace) namespace=${2:-}; shift 2 ;;
        --self) self_name=${2:-}; shift 2 ;;
        --operator) operator=${2:-}; shift 2 ;;
        --key) key=${2:-}; shift 2 ;;
        --*) die 2 "grant: unknown flag $1" ;;
        *) skills+=("$1"); shift ;;
      esac
    done
    [ ${#skills[@]} -gt 0 ] || die 2 "grant: name at least one skill"
    [ -n "$self_name" ] || die 2 "grant: --self (or CONSTELLATION_SELF) must name this house's card"
    have_card "$peer" || die 1 "constellation: no card for $peer — a grant names a peer whose card we hold"
    have_card "$self_name" || die 1 "constellation: no card for $self_name — our own card must exist before we sign a grant"
    for skill in "${skills[@]}"; do
      got=$(skill_of_card "$peer" "$skill") || die 1 "constellation: cannot read $peer's card"
      [ "$got" = "yes" ] || die 1 "constellation: $peer does not declare skill '$skill' (declared: $got) — a grant may not name a capability the card does not carry"
    done
    key=${key:-$hoard/state/constellation/$self_name.ed25519.key}
    [ -f "$key" ] || die 1 "constellation: no private key at $key — run: constellation.sh keygen $self_name"
    mkdir -p "$(dirname "$grants_file")"
    draft=$(mktemp); body=$(mktemp)
    python3 - "$(card_path "$peer")" "$(card_path "$self_name")" "$peer" "$self_name" "$operator" "$role" "$namespace" "$expires" "$draft" "$body" "${skills[@]}" <<'PY' || die 1 "constellation: cannot build the grant draft"
import json, sys, uuid, datetime
peer_card_path, self_card_path, peer, self_name, operator, role, namespace, expires, draft, body = sys.argv[1:11]
skills = sys.argv[11:]
peer_card = json.load(open(peer_card_path, encoding="utf-8"))
self_card = json.load(open(self_card_path, encoding="utf-8"))
def party(card, ymir):
    return {
        "ymir": ymir,
        "operator": card.get("operator") or (operator if ymir == self_name else ymir),
        "heimdall": card.get("kid") or f"{ymir}-unsigned",
        "card": {"protocol": "a2a/1.0", "endpoint": card.get("url", ""), "signed": bool(card.get("signed"))},
    }
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
grant = {
    "grant_id": str(uuid.uuid4()),
    "namespace": namespace,
    "role": role,
    "skills": skills,
    "state": "pending",
    "issued": now,
    "grantor": party(self_card, self_name),
    "grantee": party(peer_card, peer),
    "signatures": [],
}
if expires:
    grant["expires"] = expires
json.dump(grant, open(draft, "w", encoding="utf-8"), indent=2)
canonical = json.dumps(grant, sort_keys=True, separators=(",", ":")).encode()
open(body, "wb").write(canonical)
PY
    sig=$(node "$TOOL" signbody --key "$key" --body "$body") || die 1 "constellation: signing failed"
    kid=$(node "$TOOL" kid --pub "${key%.key}.pub" 2>/dev/null || true)
    [ -n "$kid" ] || kid=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["grantor"]["heimdall"])' "$draft")
    python3 - "$draft" "$kid" "$sig" <<'PY' || die 1 "constellation: cannot attach the signature"
import json, sys
draft, kid, sig = sys.argv[1:4]
grant = json.load(open(draft, encoding="utf-8"))
grant["signatures"].append({"signer": kid, "alg": "ed25519", "key_id": kid, "sig": sig})
json.dump(grant, open(draft, "w", encoding="utf-8"), indent=2)
PY
    python3 "$GRANTS" add "$grants_file" --json "$draft" || die 1 "constellation: the grant was refused"
    gid=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["grant_id"])' "$draft")
    cp "$body" "$(dirname "$grants_file")/../state/constellation/$gid.body" 2>/dev/null || true
    rm -f "$draft" "$body"
    "$ROOT/bin/records/runes-append.sh" constellation grant --message "grant $gid to $peer for ${skills[*]} (pending countersignature)" >/dev/null 2>&1 || true
    toon "grant[4]{grant_id,peer,skills,state}:"
    toon "  \"$gid\",\"$peer\",\"${skills[*]}\",\"pending\""
    toon "the canonical body to countersign is $(dirname "$grants_file")/../state/constellation/$gid.body"
    ;;

  countersign|activate)
    node_or_die
    gid=${1:-}; shift || true
    [ -n "$gid" ] || die 2 "usage: constellation.sh countersign <grant-id> [--sig SIG] [--pub FILE]"
    sig="" pub=""
    while [ $# -gt 0 ]; do case "$1" in --sig) sig=${2:-}; shift 2 ;; --pub) pub=${2:-}; shift 2 ;; --*) die 2 "countersign: unknown flag $1" ;; *) shift ;; esac; done
    body="$hoard/state/constellation/$gid.body"
    if [ "$cmd" = countersign ]; then
      [ -n "$sig" ] || die 2 "countersign: --sig is required"
      [ -f "$body" ] || die 1 "constellation: no canonical body for $gid at $body"
      [ -n "$pub" ] || pub="$registry/$(python3 - "$grants_file" "$gid" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
for g in doc.get("grants") or []:
    if g.get("grant_id") == sys.argv[2]:
        print(g["grantee"]["ymir"] + ".ed25519.pub")
PY
)"
      [ -f "$pub" ] || pub="$hoard/state/constellation/$(basename "$pub")"
      [ -f "$pub" ] || die 1 "constellation: no public key for the peer at $pub — pass --pub FILE"
      node "$TOOL" verifysig --pub "$pub" --body "$body" --sig "$sig" >/dev/null || die 1 "constellation: the countersignature does not verify against $pub"
      signer=$(node "$TOOL" kid --pub "$pub")
      python3 "$GRANTS" add-signature "$grants_file" --grant-id "$gid" --signer "$signer" --sig "$sig" || die 1 "constellation: cannot add the signature"
    fi
    python3 "$GRANTS" activate "$grants_file" --grant-id "$gid" || die 1 "constellation: cannot activate $gid"
    "$ROOT/bin/records/runes-append.sh" constellation activate --message "grant $gid active (both Heimdalls signed)" >/dev/null 2>&1 || true
    toon "activated[1]{grant_id}:"
    toon "  \"$gid\""
    ;;

  revoke)
    target=${1:-}
    [ -n "$target" ] || die 2 "usage: constellation.sh revoke <grant-id> | <peer>"
    if printf '%s' "$target" | grep -qE '^[0-9a-f]{8}-'; then
      python3 "$GRANTS" revoke "$grants_file" --grant-id "$target" || die 1 "constellation: cannot revoke"
    else
      python3 "$GRANTS" revoke "$grants_file" --peer "$target" || die 1 "constellation: cannot revoke"
    fi
    "$ROOT/bin/records/runes-append.sh" constellation revoke --message "revoked grants: $target" >/dev/null 2>&1 || true
    ;;

  grants)
    peer=""
    while [ $# -gt 0 ]; do case "$1" in --peer) peer=${2:-}; shift 2 ;; *) die 2 "grants: unknown argument $1" ;; esac; done
    [ -f "$grants_file" ] || { toon "grants[0]{grant_id,peer,skills,state,expires}:"; exit 0; }
    python3 "$GRANTS" list "$grants_file" ${peer:+--peer "$peer"}
    ;;

  mint)
    node_or_die
    peer="" skill="" minutes="5"
    while [ $# -gt 0 ]; do
      case "$1" in
        --peer) peer=${2:-}; shift 2 ;;
        --skill) skill=${2:-}; shift 2 ;;
        --self) self_name=${2:-}; shift 2 ;;
        --minutes) minutes=${2:-}; shift 2 ;;
        --key) key=${2:-}; shift 2 ;;
        *) die 2 "mint: unknown argument $1" ;;
      esac
    done
    [ -n "$peer" ] && [ -n "$skill" ] || die 2 "usage: constellation.sh mint --peer NAME --skill ID"
    [ -n "$self_name" ] || die 2 "mint: --self (or CONSTELLATION_SELF) must name this house"
    key=${key:-$hoard/state/constellation/$self_name.ed25519.key}
    [ -f "$key" ] || die 1 "constellation: no private key at $key"
    granted=$(python3 - "$grants_file" "$peer" "$skill" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) if __import__("os").path.exists(sys.argv[1]) else {}
peer, skill = sys.argv[2], sys.argv[3]
for g in (doc.get("grants") or []):
    if g.get("state") == "active" and skill in (g.get("skills") or []):
        if peer in {g["grantor"]["ymir"], g["grantee"]["ymir"]}:
            print("yes"); break
PY
)
    [ "$granted" = "yes" ] || die 1 "constellation: no active grant names skill '$skill' for '$peer' — the token would claim what the shelf does not"
    kid=$(node "$TOOL" kid --pub "${key%.key}.pub")
    node "$TOOL" mint --key "$key" --kid "$kid" --iss "$self_name" --aud "$peer" --skill "$skill" --minutes "$minutes" || die 1 "mint failed"
    ;;

  verify)
    node_or_die
    token="" pub="" aud="" skill=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --token) token=${2:-}; shift 2 ;;
        --pub) pub=${2:-}; shift 2 ;;
        --peer) pub="$registry/${2:-}.ed25519.pub"; shift 2 ;;
        --aud) aud=${2:-}; shift 2 ;;
        --skill) skill=${2:-}; shift 2 ;;
        *) die 2 "verify: unknown argument $1" ;;
      esac
    done
    [ -n "$token" ] && [ -n "$pub" ] || die 2 "usage: constellation.sh verify --token TOKEN --pub FILE [--aud NAME] [--skill ID]"
    [ -f "$pub" ] || die 1 "constellation: no public key at $pub"
    args=(verify --pub "$pub" --token "$token")
    [ -n "$aud" ] && args+=(--aud "$aud")
    [ -n "$skill" ] && args+=(--skill "$skill")
    node "$TOOL" "${args[@]}"
    ;;

  guard)
    [ -f "$GUARD" ] || die 3 "constellation: the grant guard is missing at $GUARD"
    exec "$GUARD" --registry "$registry" --grants "$grants_file" "$@"
    ;;

  doctor)
    node_or_die
    ok=1
    toon "constellation[6]{check,state,why}:"
    if [ -d "$registry" ]; then toon "  \"registry\",\"present\",\"$registry\""; else toon "  \"registry\",\"absent\",\"$registry — an unconfigured mesh is UNKNOWN, not empty\""; ok=0; fi
    if [ -f "$grants_file" ]; then toon "  \"grants\",\"present\",\"$grants_file\""; else toon "  \"grants\",\"absent\",\"no grant shelf yet\""; fi
    if command -v node >/dev/null 2>&1; then toon "  \"node\",\"present\",\"$(node --version)\""; else toon "  \"node\",\"absent\",\"the card contract is validated by node\""; ok=0; fi
    if [ -f "$ROOT/packages/contracts/src/agent-card.ts" ]; then toon "  \"contract\",\"present\",\"packages/contracts/src/agent-card.ts\""; else toon "  \"contract\",\"absent\",\"the shared agent-card contract\""; ok=0; fi
    if [ -n "$self_name" ]; then toon "  \"self\",\"$self_name\",\"from CONSTELLATION_SELF\""; else toon "  \"self\",\"unset\",\"set CONSTELLATION_SELF to this house's card name\""; fi
    if [ -n "${key:-}" ] || [ -f "$hoard/state/constellation/$self_name.ed25519.key" ]; then toon "  \"key\",\"present\",\"this house may sign\""; else toon "  \"key\",\"absent\",\"run: constellation.sh keygen $self_name\""; fi
    [ "$ok" = 1 ] || exit 3
    ;;

  ""|-h|--help|help)
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;

  *)
    die 2 "constellation: unknown verb '$cmd' (try: constellation.sh --help)"
    ;;
esac
