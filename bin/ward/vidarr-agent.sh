#!/usr/bin/env bash
# vidarr-agent.sh — seat the DEFENDER as a live pi agent on the fast road.
#
# Víðarr is not only a persona file: he is a running agent, because a defender that wakes only when
# someone types is not a defender. This seats him in a herdr pane with `opencode-go/deepseek-v4.1-flash`
# — fast and strong enough to triage while something is happening — and gives him the room name
# `vidarr`, so an incident can also be put to him in words.
#
#   vidarr-agent.sh up       # seat him (herdr pane; ROOM_TAP_AGENT=vidarr)
#   vidarr-agent.sh status   # where he stands, and on which model
#   vidarr-agent.sh down     # lower him
#
# His powers do not change by being live: the persona allows `garmr-bite.sh` and `vidarr.sh` and
# nothing else destructive, and every action still records itself before it is taken.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERSION="1.0.0"
# Resolved for THIS seat (RULES/25): the warden names no model id of its own.
MODEL="${VIDARR_MODEL:-$(bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/model/agent-model.sh" forseti --tier strong --plain 2>/dev/null || true)}"
PERSONA="$ROOT/.agents/agents/vidarr-defender.md"
LABEL="${VIDARR_LABEL:-vidarr-defender}"

case "${1-}" in -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

jget() { python3 -c "import sys,json;d=json.load(sys.stdin);r=d.get('result',{});print(r$1)" 2>/dev/null; }

cmd_up() {
  command -v herdr >/dev/null || { printf 'vidarr_agent[1]{error}: "herdr is absent"\n' >&2; exit 1; }
  [ -r "$PERSONA" ] || { printf 'vidarr_agent[1]{error}: "no persona at %s"\n' "$PERSONA" >&2; exit 1; }
  local out pane
  out=$(herdr tab create --cwd "$ROOT" --label "$LABEL" --no-focus 2>/dev/null) || {
    printf 'vidarr_agent[1]{error}: "herdr refused the tab"\n' >&2; exit 1; }
  pane=$(printf '%s' "$out" | jget "['root_pane']['pane_id']")
  [ -n "$pane" ] || { printf 'vidarr_agent[1]{error}: "herdr returned no pane"\n' >&2; exit 1; }
  herdr pane run "$pane" env ROOM_TAP_AGENT=vidarr pi --name vidarr --model "$MODEL" \
    --append-system-prompt "$PERSONA" >/dev/null 2>&1
  printf 'vidarr_agent[3]{state,pane,model}:\n  "seated","%s","%s"\n  "room name","vidarr — address him in the room"\n' "$pane" "$MODEL"
}

cmd_status() {
  herdr pane list 2>/dev/null | python3 -c "
import sys, json
d=json.load(sys.stdin)
rows=[p for p in d.get('result',{}).get('panes',[]) if p.get('tab_id')]
found=[p for p in rows if (p.get('terminal_title') or '').endswith('vidarr') or '${LABEL}' in (p.get('terminal_title') or '')]
print('vidarr_agent[%d]{pane,state}:' % (len(found) or 1))
if found:
    for p in found: print('  \"%s\",\"%s\"' % (p.get('pane_id'), p.get('agent_status')))
else:
    print('  \"—\",\"not seated\"')
" 2>/dev/null || printf 'vidarr_agent[1]{state}:\n  "unknown","herdr did not answer"\n'
}

cmd_down() {
  herdr tab list 2>/dev/null | python3 -c "
import sys, json
d=json.load(sys.stdin)
print('\n'.join(t['tab_id'] for t in d.get('result',{}).get('tabs',[]) if t.get('label')=='${LABEL}'))
" 2>/dev/null | while read -r t; do [ -n "$t" ] && herdr tab close "$t" >/dev/null 2>&1 && printf '  closed %s\n' "$t"; done
}

CMD="${1-}"; shift || true
case "$CMD" in
  up) cmd_up ;;
  status) cmd_status ;;
  down) cmd_down ;;
  *) printf 'vidarr_agent[1]{error}: "unknown command: %s"\n' "$CMD" >&2; exit 2 ;;
esac
