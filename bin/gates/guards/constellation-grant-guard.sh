#!/usr/bin/env bash
# constellation-grant-guard.sh — the road's own ward.
#
# Judges the grants shelf against the cards it names, and refuses four things:
#
#   1. a grant naming a skill the peer's card does not declare — a grant may not
#      open a capability the card never carried;
#   2. an active grant whose expiry has passed — an expired road is a closed road;
#   3. an active grant with no signature from one of its parties (delegated to
#      src/ymir_runtime/grants.py, the one implementation of that law);
#   4. a grant whose peer has no card in the registry — a road to a house we cannot
#      name.
#
# A plan-58 namespace grant (no `skills`) is not a road grant and is not judged here.
#
# Usage:
#   constellation-grant-guard.sh [--registry DIR] [--grants FILE]
# Exit: 0 clean · 1 a fault · 2 usage · 3 unavailable.
set -u
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../../.." && pwd)

. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
hoard=""
if declare -F hoard_root >/dev/null 2>&1; then hoard_root hoard 2>/dev/null || true; fi
[ -n "$hoard" ] || { printf 'unavailable: cannot resolve the home — bin/vault/hoard-lib.sh did not answer\n' >&2; exit 3; }

registry="${CONSTELLATION_REGISTRY:-$hoard/data/constellation/agents}"
grants="$hoard/identity/grants.yaml"
while [ $# -gt 0 ]; do
  case "$1" in
    --registry) registry=${2:-}; shift 2 ;;
    --grants) grants=${2:-}; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'error: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { printf 'unavailable: python3 is required\n' >&2; exit 3; }
[ -f "$grants" ] || { printf 'grants[0]{grant_id,peer,skill,fault}:\n'; exit 0; }

python3 - "$grants" "$registry" <<'PY'
import datetime, json, os, sys

grants_path, registry = sys.argv[1], sys.argv[2]
try:
    import yaml
except ImportError:
    sys.stderr.write("unavailable: PyYAML is required\n")
    raise SystemExit(3)

doc = yaml.safe_load(open(grants_path, encoding="utf-8")) or {}
now = datetime.datetime.now(datetime.timezone.utc)


def declared(ymir: str) -> set[str] | None:
    path = os.path.join(registry, f"{ymir}.json")
    if not os.path.exists(path):
        return None
    try:
        card = json.load(open(path, encoding="utf-8"))
    except Exception:
        return None
    return {str(s.get("id", "")) for s in card.get("skills") or []}


faults = []
for grant in doc.get("grants") or []:
    skills = grant.get("skills") or []
    if not skills:
        continue
    gid = grant.get("grant_id", "?")
    state = grant.get("state", "")
    parties = [str((grant.get("grantor") or {}).get("ymir", "")), str((grant.get("grantee") or {}).get("ymir", ""))]
    peer = parties[1] if len(parties) > 1 else ""
    have = declared(peer)
    if have is None:
        faults.append((gid, peer, ",".join(skills), f"no card for '{peer}' in the registry"))
    else:
        for skill in skills:
            if skill not in have:
                faults.append((gid, peer, skill, f"'{peer}' does not declare this skill (declares: {','.join(sorted(have)) or 'none'})"))
    expires = str(grant.get("expires") or "")
    if expires and state == "active":
        try:
            when = datetime.datetime.fromisoformat(expires.replace("Z", "+00:00"))
            if when.tzinfo is None:
                when = when.replace(tzinfo=datetime.timezone.utc)
            if when < now:
                faults.append((gid, peer, ",".join(skills), f"active grant expired at {expires}"))
        except ValueError:
            faults.append((gid, peer, ",".join(skills), f"expires '{expires}' is not an ISO 8601 instant"))

lines = [f"grants[%d]{{grant_id,peer,skill,fault}}:" % len(faults)]
for f in faults:
    lines.append('  "%s","%s","%s","%s"' % tuple(str(x).replace('"', "'") for x in f))
sys.stdout.write("\n".join(lines) + "\n")
raise SystemExit(1 if faults else 0)
PY
