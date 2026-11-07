#!/usr/bin/env bash
# seat-identity.sh — print a seat's primary agent and its role file.
#
# Usage:
#   seat-identity.sh <host>                # the primary agent name
#   seat-identity.sh <host> --file         # the role file path
#   seat-identity.sh <host> --json         # machine-readable
#   seat-identity.sh --list                # every seat and its primary
#
# The roster lives in $YMIR_HOME/config/agents.yaml (single source of truth).
# This door reads it; it does not hardcode a name (Rule 07).
set -euo pipefail
VERSION="1.0.0"
case "${1-}" in -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh"; do [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }; done; unset _c
fi
ymir_home_root YMIR_HOME 2>/dev/null || true
YMIR_HOME="${YMIR_HOME:?YMIR_HOME unresolved}"
ROSTER="${SEAT_ROSTER:-$YMIR_HOME/hodd/identity/seats.yaml}"
[ -r "$ROSTER" ] || { printf 'error: roster not readable: %s\n' "$ROSTER" >&2; exit 1; }

SELF="${YMIR_HOST:-$(hostname -s)}"
HOST="${1-}"; MODE="name"
case "$HOST" in
  --list) MODE="list"; HOST="" ;;
  --file|--json|--install|--check|--render|--ensure) MODE="${HOST#--}"; HOST="${2:-$SELF}" ;;
  set) MODE="set"; HOST="${2:-$SELF}"; NEWNAME="${3-}"; NEWROLE="${4-}" ;;
  names|--names) MODE="names"; HOST="" ;;
esac

role_file(){
  case "$1" in
    brokk) printf 'brokk.md' ;;
    sindri) printf 'sindri-developer.md' ;;
    muninn) printf 'muninn-stow.md' ;;
    mimir) printf 'mimir-planner.md' ;;
    *) printf '%s.md' "$1" ;;
  esac
}

if [ "$MODE" = names ]; then
  # The naming law is the source: a seat's primary must be a figure with a role file.
  for f in "$ROOT"/.agents/agents/*.md; do
    n="$(basename "$f" .md)"
    case "$n" in *-*) n="${n%%-*}" ;; esac
    printf '%s\n' "$n"
  done | sort -u
  exit 0
fi

if [ "$MODE" = set ]; then
  [ -n "${NEWNAME:-}" ] || { printf 'error: set needs <host> <name> [role]\n' >&2; exit 2; }
  # Collisions belong to the registry, not to this door: it knows every name
  # across subsystems, hosts, agents, skills and extensions.
  if [ -x "$ROOT/bin/agents/name-registry.sh" ] && [ -r "$YMIR_HOME/hodd/identity/names.yaml" ]; then
    if ! bash "$ROOT/bin/agents/name-registry.sh" check "$NEWNAME" --as seat-persona; then
      printf 'help: name-registry.sh list --kind agent\n' >&2; exit 3
    fi
  fi
  if ! bash "$0" --names | grep -qxF "$NEWNAME"; then
    if [ "${YMIR_ALLOW_UNKNOWN_NAME:-0}" != 1 ]; then
      printf 'refused\t"%s" is not a name in the naming law\n' "$NEWNAME" >&2
      printf 'help: seat-identity.sh --names   (or YMIR_ALLOW_UNKNOWN_NAME=1 to override)\n' >&2
      exit 3
    fi
  fi
  python3 - "$ROSTER" "$HOST" "$NEWNAME" "${NEWROLE:-}" <<'PY'
import sys
try: import yaml
except Exception: raise SystemExit("error: PyYAML is required")
roster,host,name,role=sys.argv[1:]
d=yaml.safe_load(open(roster)) or {}
seats=d.setdefault("seats",{})
cur=seats.get(host,{})
seats[host]={"primary":name,"role":role or cur.get("role",""),"status":"sealed",
             "why":cur.get("why","chosen by the operator")}
open(roster,'w').write(yaml.safe_dump(d,sort_keys=False))
print(f"sealed\t{host}\t{name}")
PY
  CARD="$YMIR_HOME/hodd/data/agent-cards/$HOST.json"
  if [ -f "$CARD" ]; then python3 - "$CARD" "$HOST" "$NEWNAME" <<'PY'
import json,sys
p,host,name=sys.argv[1:]
d=json.load(open(p)); d["name"]=f"{name}-{host}"; d["seat_primary"]=name
json.dump(d,open(p,"w"),indent=2)
PY
  fi
  bash "$0" --install "$HOST"; exit 0
fi

if [ "$MODE" = ensure ]; then
  if bash "$0" "$HOST" >/dev/null 2>&1; then bash "$0" --install "$HOST"; exit 0; fi
  if [ -n "${YMIR_SEAT_NAME:-}" ]; then
    python3 - "$ROSTER" "$HOST" "$YMIR_SEAT_NAME" <<'PY'
import sys,yaml
roster,host,name=sys.argv[1:]
try: d=yaml.safe_load(open(roster)) or {}
except Exception: d={}
d.setdefault("seats",{})[host]={"primary":name,"role":"","status":"sealed","why":"chosen at install"}
open(roster,'w').write(yaml.safe_dump(d,sort_keys=False))
PY
    bash "$0" --install "$HOST"; exit 0
  fi
  if [ -t 0 ]; then
    printf 'This host is %s. Name its primary agent: ' "$HOST" >&2
    read -r nm
    [ -n "$nm" ] || { printf 'error: no name given\n' >&2; exit 1; }
    exec bash "$0" set "$HOST" "$nm"
  fi
  printf 'error: no primary recorded for %s — run: seat-identity.sh set %s <name>\n' "$HOST" "$HOST" >&2
  exit 1
fi

if [ "$MODE" = install ] && [ "$HOST" != "$SELF" ]; then
  printf 'skipped\t%s is not this host\n' "$HOST"; exit 0
fi
if [ "$MODE" = install ] || [ "$MODE" = check ] || [ "$MODE" = render ]; then
  NAME="$(bash "$0" "$HOST" 2>/dev/null)" || { printf 'error: %s has no seat identity\n' "$HOST" >&2; exit 1; }
  ROLE="$(python3 -c "import yaml,sys;d=yaml.safe_load(open('$ROSTER'));print(d['seats']['$HOST'].get('role',''))" 2>/dev/null)"
  STATUS="$(python3 -c "import yaml;d=yaml.safe_load(open('$ROSTER'));print(d['seats']['$HOST'].get('status','proposed'))" 2>/dev/null)"
  RF="$ROOT/.agents/agents/$(role_file "$NAME")"
  SEAT_FILE="$HOME/.pi/agent/extensions/.ymir-seat"
  RENDER="$HOME/.pi/agent/AGENTS.seat.md"
  case "$MODE" in
    install)
      mkdir -p "$(dirname "$SEAT_FILE")"
      printf 'host=%s\nprimary=%s\nrole=%s\nstatus=%s\nrole_file=%s\nroster=%s\n' "$HOST" "$NAME" "$ROLE" "$STATUS" "$RF" "$ROSTER" > "$SEAT_FILE"
      printf 'installed\t%s\t%s\t%s\n' "$SEAT_FILE" "$HOST" "$NAME" ;;
    render)
      OPERATOR="$(python3 -c "import yaml;d=yaml.safe_load(open('$YMIR_HOME/hodd/identity/operator.yaml'));print((d.get('allfather') or {}).get('display') or 'Allfather')" 2>/dev/null || echo 'Allfather')"
      cat > "$RENDER" <<EOF
<!-- generated by bin/agents/seat-identity.sh — do not edit -->
# This seat: $HOST

You are **$NAME** on **$HOST** — $ROLE. Your role file is \`$RF\`.
Seat names are proposed until the Allfather seals them in
\`hodd/identity/seats.md\`; the roster is \`$ROSTER\`.

**Your name is $NAME.** The shared contract below is written in the counsellor's
voice and names **Brokk** — that is the counsellor's craft, not your name. Where it
says Brokk, read the role being described; you answer as **$NAME**, and a seat never
calls itself Brokk unless the roster seals Brokk for it.

**The operator of this fleet is $OPERATOR.** Address him as *$OPERATOR* — in a
federated hall (Brimir, plan 74) a bare "Allfather" names nobody; every fleet's
operator is named in its own home (\`hodd/identity/operator.yaml\`).

# The shared contract

EOF
      cat "$ROOT/AGENTS.md" >> "$RENDER"
      printf 'rendered\t%s\n' "$RENDER" ;;
    check)
      [ -r "$SEAT_FILE" ] || { printf 'missing\t%s\n' "$SEAT_FILE"; exit 1; }
      want="$(printf 'host=%s\nprimary=%s\n' "$HOST" "$NAME")"
      have="$(printf 'host=%s\nprimary=%s\n' "$(sed -n 's/^host=//p' "$SEAT_FILE")" "$(sed -n 's/^primary=//p' "$SEAT_FILE")")"
      if [ "$want" = "$have" ]; then printf 'ok\t%s\t%s\n' "$HOST" "$NAME"; else printf 'mismatch\t%s\t%s\n' "$SEAT_FILE" "$have"; exit 1; fi ;;
  esac
  exit 0
fi

python3 - "$ROSTER" "$HOST" "$MODE" <<'PY'
import sys, json, os
try: import yaml
except Exception: yaml=None
roster,host,mode=sys.argv[1],sys.argv[2],sys.argv[3]
cfg=yaml.safe_load(open(roster).read()) if yaml else {}
seats=cfg.get("seats",{}) if isinstance(cfg,dict) else {}
if mode=="list":
    for s in sorted(seats):
        i=seats[s]; print(f"{s}\t{i.get('primary')}\t{i.get('status','proposed')}")
    sys.exit(0)
if host not in seats:
    print(f"error: no seat named {host!r} in {roster}", file=sys.stderr)
    sys.exit(1)
name=seats[host].get("primary")
if mode=="name": print(name)
elif mode=="file": print(os.path.join(os.path.dirname(roster),"..","..",".agents","agents",name+".md"))
elif mode=="json":
    print(json.dumps({"host":host, **seats[host]}, indent=2))
PY
