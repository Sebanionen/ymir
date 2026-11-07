#!/usr/bin/env bash
# agent-model.sh — WHICH MODEL, ON THIS SEAT. One resolver, and a refusal when the answer is not
# in the catalogue.
#
# WHY (the Allfather, 2026-11-06): *"this model choosing logic don't make sense. all users and
# computers have different models and capabilities.. are we shipping hardcoded models?"* — yes,
# we were. Nine shipped scripts named a model id (`opencode-go/deepseek-v4.1-flash`,
# `llamacpp-3050-big/…`), and an id that is true on one machine is a promise another cannot keep:
# `llamacpp-3050-big` exists on nidavellir and nowhere else. The house already had the truth —
# `bin/model/catalog.sh` — and the shipped code went around it.
#
# THE ORDER OF AUTHORITY, stated once, resolved here and nowhere else:
#   1 · an EXPLICIT model (`--model`)              — the operator's word for this run
#   2 · `YMIR_<AGENT>_MODEL` in the environment    — a deliberate per-invocation override
#   3 · `config/agents.<host>.yaml`                — THIS machine's overlay (private home)
#   4 · `config/agents.yaml`                       — the fleet's declared choice (private home)
#   5 · the agent's `tier:` row resolved here      — fast · balanced · strong · local
#   6 · the fleet's `default_model`
#   7 · REFUSAL                                    — never a guess, never a silent fallback
#
# AND ONE LAW OVER ALL OF THEM: **a model this seat's catalogue does not list is refused by name.**
# A row that names an unservable model is not a preference, it is a broken promise, and the refusal
# says which row and which catalogue (`RULES/25` — probe, never assume).
#
# A seat that cannot serve the fleet's choice says so; it does not quietly pick a different one.
# The overlay exists so the choice can be corrected per machine, deliberately and on the record.
#
# Usage:
#   agent-model.sh <agent>                    # provider/model for that agent on this seat
#   agent-model.sh <agent> --tier fast        # resolve by capability instead of a named model
#   agent-model.sh <agent> --json             # machine-readable, with the source it came from
#   agent-model.sh --check [<agent> …]        # every row this seat would use, or the row that fails
#   agent-model.sh <agent> --plain             # just the id, for a script that spawns
#   agent-model.sh --explain <agent>          # the whole chain, step by step, and why each step lost
#
# Exit: 0 resolved · 1 a fault · 2 usage · 3 refused (a model this seat cannot serve).
set -u
VERSION="1.0.0"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$SCRIPT_DIR/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
SETTINGS=""; hoard_settings_dir SETTINGS 2>/dev/null || true
[ -n "$SETTINGS" ] || { printf 'agent-model: the settings dir is unresolved\n' >&2; exit 1; }

CATALOG="$ROOT/bin/model/catalog.sh"
HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"

die()    { printf 'agent-model: %s\n' "$*" >&2; exit 1; }
usage()  { printf 'agent-model: %s\n' "$*" >&2; exit 2; }
refuse() { printf 'agent-model: REFUSED — %s\n' "$*" >&2; exit 3; }

# The catalogue, read ONCE per run and kept in a temp file: every question below asks the same
# answer, so two steps of the chain cannot disagree about what this machine can serve.
CATFILE="$(mktemp)"
trap 'rm -f "$CATFILE"' EXIT
listed() {  # <provider/model> → 0 when this seat lists it
  local want=$1 p m
  p="${want%%/*}"; m="${want#*/}"
  [ "$p" != "$want" ] || return 1
  awk -F'","' -v p="$p" -v m="$m" '
    NR > 1 { prov=$1; sub(/^  "/, "", prov); mod=$2
             if (prov == p && mod == m) { found = 1 } }
    END { exit(found ? 0 : 1) }' "$CATFILE"
}
refresh_catalog() {
  [ -s "$CATFILE" ] && return 0
  [ -x "$CATALOG" ] || return 1
  "$CATALOG" >"$CATFILE" 2>/dev/null || return 1
  [ -s "$CATFILE" ]
}
providers_of() { awk -F'","' 'NR > 1 { p=$1; sub(/^  "/, "", p); print p }' "$CATFILE" | sort -u; }

# ── the config readers (the private home, never the tree) ─────────────────────────────────────
row_value() {  # <file> <agent> <key> — agents.<agent>.<key> from a YAML the operator owns
  local f=$1 agent=$2 key=$3
  [ -r "$f" ] || return 1
  python3 - "$f" "$agent" "$key" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except Exception:
    sys.exit(1)
f, agent, key = sys.argv[1:4]
try:
    cfg = yaml.safe_load(open(f)) or {}
except Exception:
    sys.exit(1)
row = (cfg.get("agents") or {}).get(agent)
if isinstance(row, dict):
    v = row.get(key)
elif isinstance(row, str) and key == "model":
    v = row
else:
    v = None
if v is None:
    sys.exit(1)
print(v)
PY
}
fleet_value() {  # <key> — a top-level key of the fleet file
  local f=$1 key=$2
  [ -r "$f" ] || return 1
  python3 - "$f" "$key" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except Exception:
    sys.exit(1)
f, key = sys.argv[1:3]
try:
    cfg = yaml.safe_load(open(f)) or {}
except Exception:
    sys.exit(1)
v = cfg.get(key)
if v is None:
    sys.exit(1)
print(v)
PY
}
agent_rows() {  # <file> — every agent name in it
  local f=$1
  [ -r "$f" ] || return 1
  python3 - "$f" <<'PY' 2>/dev/null
import sys
try:
    import yaml
except Exception:
    sys.exit(1)
cfg = yaml.safe_load(open(sys.argv[1])) or {}
for a in (cfg.get("agents") or {}):
    print(a)
PY
}

FLEET="$SETTINGS/agents.yaml"
OVERLAY="$SETTINGS/agents.$HOST.yaml"

# ── tiers: a capability, resolved against what THIS seat lists ───────────────────────────────
tier_pick() {  # <tier>
  local tier=$1 p m best
  refresh_catalog || return 1
  case "$tier" in
    local)
      # the strongest local model this seat lists: the longest context name wins, providers that
      # start with `llamacpp-` are the local rail by the catalogue's own naming.
      awk -F'","' 'NR > 1 { p=$1; sub(/^  "/, "", p); if (p ~ /^llamacpp-/) { print p "/" $2 } }' "$CATFILE" | head -1
      ;;
    fast)
      # a small online model first (cheap, quick), then any *flash/*mini, then anything online
      for pat in 'opencode-go/deepseek.*flash' 'opencode-go/.*flash' '.*flash' '.*mini' 'opencode-go/.*' 'openrouter/.*'; do
        best="$(awk -F'","' -v pat="$pat" 'NR > 1 { p=$1; sub(/^  "/, "", p); full=p "/" $2; if (full ~ pat) { print full; exit } }' "$CATFILE")"
        [ -n "$best" ] && { printf '%s' "$best"; return 0; }
      done
      return 1 ;;
    strong)
      for pat in 'opencode-go/.*pro' 'opencode-go/.*max' 'openrouter/.*sonnet' 'openrouter/.*gpt-5' 'opencode-go/.*' '.*'; do
        best="$(awk -F'","' -v pat="$pat" 'NR > 1 { p=$1; sub(/^  "/, "", p); full=p "/" $2; if (full ~ pat) { print full; exit } }' "$CATFILE")"
        [ -n "$best" ] && { printf '%s' "$best"; return 0; }
      done
      return 1 ;;
    balanced)
      best="$(fleet_value "$FLEET" default_model || true)"
      if [ -n "$best" ] && listed "$best"; then printf '%s' "$best"; return 0; fi
      tier_pick fast
      return $? ;;
    *) return 1 ;;
  esac
}

# ── the chain ────────────────────────────────────────────────────────────────────────────────
AGENT=""; TIER=""; EXPLICIT=""; JSON=0; EXPLAIN=0; CHECK=0; PLAIN=0
while [ $# -gt 0 ]; do case "$1" in
  --tier) TIER="${2:-}"; shift 2 ;;
  --tier=*) TIER="${1#--tier=}"; shift ;;
  --model) EXPLICIT="${2:-}"; shift 2 ;;
  --model=*) EXPLICIT="${1#--model=}"; shift ;;
  --json) JSON=1; shift ;;
  --plain) PLAIN=1; shift ;;
  --explain) EXPLAIN=1; shift ;;
  --check) CHECK=1; shift ;;
  -*) usage "unknown flag $1" ;;
  *) [ -z "$AGENT" ] && AGENT="$1" || usage "one agent at a time"; shift ;;
esac; done

refresh_catalog || die "the catalogue cannot be read on this seat (bin/model/catalog.sh --check) — without it every model id is a guess, and this door refuses to guess"

resolve_one() {  # <agent> → prints "model<TAB>source<TAB>why"; exit 3 when refused
  local agent=$1 model="" source="" why="" envkey envval
  envkey="YMIR_$(printf '%s' "$agent" | tr '[:lower:]-' '[:upper:]_')_MODEL"
  envval="$(printenv "$envkey" 2>/dev/null || true)"

  if [ -n "$EXPLICIT" ]; then
    listed "$EXPLICIT" || refuse "the model '$EXPLICIT' is NOT in this seat's catalogue — a model a machine does not list is not a preference, it is a promise it cannot keep"
    printf '%s\t%s\t%s' "$EXPLICIT" "explicit --model" "the operator named it for this run"
    return 0
  fi
  if [ -n "$envval" ]; then
    if listed "$envval"; then printf '%s\t%s\t%s' "$envval" "$envkey" "an environment override, honoured because this seat lists it"
    else refuse "$envkey names '$envval', which this seat's catalogue does NOT list — correct the override or name a listed model"; fi
    return 0
  fi
  if [ -n "$TIER" ]; then
    model="$(tier_pick "$TIER" || true)"
    [ -n "$model" ] || refuse "no model on this seat matches tier '$TIER' — the catalogue lists: $(providers_of | tr '\n' ' ')"
    printf '%s\t%s\t%s' "$model" "tier:$TIER" "capability resolved against this seat's catalogue"
    return 0
  fi

  # the overlay, then the fleet row: a row is honoured ONLY when this seat lists it
  local f label
  for f in "$OVERLAY" "$FLEET"; do
    case "$f" in "$OVERLAY") label="overlay agents.$HOST.yaml" ;; *) label="fleet agents.yaml" ;; esac
    local row; row="$(row_value "$f" "$agent" model || true)"
    [ -n "$row" ] || continue
    if listed "$row"; then
      printf '%s\t%s\t%s' "$row" "$label" "declared there, and listed here"
      return 0
    fi
    # an unservable row is not silently skipped: it is a finding, reported with the resolution
    printf 'agent-model: FINDING — %s names %s for '%s', which THIS seat does not list; falling through\n' \
      "$label" "$row" "$agent" >&2
  done

  # the agent's own tier row, then the fleet default
  local trow; trow="$(row_value "$OVERLAY" "$agent" tier || true)"; [ -n "$trow" ] || trow="$(row_value "$FLEET" "$agent" tier || true)"
  if [ -n "$trow" ]; then
    model="$(tier_pick "$trow" || true)"
    [ -n "$model" ] || refuse "agent '$agent' declares tier '$trow' and this seat has no model for it — the catalogue lists: $(providers_of | tr '\n' ' ')"
    printf '%s\t%s\t%s' "$model" "tier:$trow (row)" "the row asks for a capability; this seat answered with a listed model"
    return 0
  fi

  model="$(fleet_value "$FLEET" default_model || true)"
  if [ -n "$model" ] && listed "$model"; then
    printf '%s\t%s\t%s' "$model" "fleet default_model" "no row for '$agent'; the fleet's declared default, listed here"
    return 0
  fi

  refuse "no model for agent '$agent' on seat '$HOST' — no explicit --model, no $envkey, no overlay row, no fleet row that this seat lists, and no default_model it can serve. Name one: agent-model.sh $agent --model <provider/model> (catalogue: bin/model/catalog.sh)"
}

if [ "$CHECK" = 1 ]; then
  agents=()
  if [ $# -gt 0 ]; then agents=("$@"); else
    while IFS= read -r a; do [ -n "$a" ] && agents+=("$a"); done < <( { agent_rows "$OVERLAY" 2>/dev/null; agent_rows "$FLEET" 2>/dev/null; } | sort -u )
  fi
  [ "${#agents[@]}" -gt 0 ] || { printf 'agent-model: no agent rows to check\n' >&2; exit 1; }
  ok=0; bad=0
  for a in "${agents[@]}"; do
    if out="$(resolve_one "$a" 2>/dev/null)"; then
      ok=$((ok + 1)); printf 'ok   %-10s %s  (%s)\n' "$a" "${out%%$'\t'*}" "$(printf '%s' "$out" | cut -f2)"
    else
      bad=$((bad + 1)); printf 'FAIL %-10s\n' "$a"
    fi
  done
  printf 'agent-model: %s ok / %s fail on %s\n' "$ok" "$bad" "$HOST"
  [ "$bad" = 0 ]
  exit
fi

[ -n "$AGENT" ] || usage "an agent is required: agent-model.sh <agent> [--tier fast] [--model id]"

if [ "$EXPLAIN" = 1 ]; then
  printf 'explain[6]{seat,agent,tier,explicit,overlay,fleet}:\n'
  printf '  "%s","%s","%s","%s","%s","%s"\n' "$HOST" "$AGENT" "${TIER:-none}" "${EXPLICIT:-none}" \
    "$([ -r "$OVERLAY" ] && echo present || echo absent)" "$([ -r "$FLEET" ] && echo present || echo absent)"
fi

OUT="$(resolve_one "$AGENT")" || exit $?
MODEL="${OUT%%$'\t'*}"; REST="${OUT#*$'\t'}"; SRC="${REST%%$'\t'*}"; WHY="${REST#*$'\t'}"

if [ "$PLAIN" = 1 ]; then
  printf '%s\n' "$MODEL"
elif [ "$JSON" = 1 ]; then
  printf '{"seat":"%s","agent":"%s","model":"%s","source":"%s","why":"%s"}\n' "$HOST" "$AGENT" "$MODEL" "$SRC" "$WHY"
else
  printf 'agent-model[4]{seat,agent,model,source}:\n  "%s","%s","%s","%s"\n' "$HOST" "$AGENT" "$MODEL" "$SRC"
  printf 'why[1]{reason}:\n  "%s"\n' "$WHY"
fi
