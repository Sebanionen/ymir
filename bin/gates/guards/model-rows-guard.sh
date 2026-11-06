#!/usr/bin/env bash
# model-rows-guard.sh — every agent row names a model THIS machine can actually serve.
#
# WHY (2026-11-06, measured on two seats in one night): `config/agents.yaml` named
# `llama-swap/qwen3.6-35b-a3b@q4_k_xl-mtp` for eleven agent rows, and `bin/model/catalog.sh --has`
# says that id is not in the catalogue. Every agent that fell through to its default died at model
# resolution — and the error stayed invisible because a house-split refusal failed first and took the
# blame. The same fault was on the heart, with a DIFFERENT right answer: the id is per seat, the fault
# was shared. So the question a ward must ask is not "is this a good model" but "is this model in
# THIS machine's catalogue".
#
# WHAT IT JUDGES: every `model:` value in `$YMIR_HOME/config/agents.yaml` (resolved through
# bin/vault/hoard-lib.sh, never guessed), against the catalogue's own list — one call, not one per row.
#
# WHAT IT DOES NOT JUDGE: whether the model is a good choice. That is the Allfather's, and a ward
# that has opinions about taste is a ward that gets switched off.
#
# A clean skip names its reason (RULES/25): no home, no agent file, no catalogue door.
#
# Usage: model-rows-guard.sh check   (guards.sh calls exactly this)
# Exit: 0 every row resolves (or a clean skip) · 1 a row names a model this machine cannot serve.
set -u

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="${YMIR_GUARD_ROOT:-$(_root)}"
cd "$ROOT" 2>/dev/null || { printf 'model-rows-guard: cannot enter %s\n' "$ROOT" >&2; exit 2; }

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$ROOT/bin/vault/hoard-lib.sh" "$ROOT/../vault/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
HOME_DIR=""
ymir_home_root HOME_DIR 2>/dev/null || true
[ -n "$HOME_DIR" ] || HOME_DIR="${YMIR_HOME:-}"
AGENTS="$HOME_DIR/config/agents.yaml"

skip() { printf 'model-rows-guard[1]{gate,result,note}:\n  "model rows","SKIP","%s"\n' "$1"; exit 0; }

[ -n "$HOME_DIR" ] || skip "no home resolved — nothing to judge on this machine"
[ -r "$AGENTS" ] || skip "no $AGENTS — this machine declares no agent rows"
CATALOG="$ROOT/bin/model/catalog.sh"
[ -x "$CATALOG" ] || skip "bin/model/catalog.sh is absent — cannot ask what this machine serves"

# ONE catalogue call, then compare. `--has` per row would be one process per agent.
servable="$(timeout 180 "$CATALOG" 2>/dev/null | sed -n 's/^  "\([^"]*\)","\([^"]*\)".*/\1\/\2/p')"
[ -n "$servable" ] || skip "the catalogue returned nothing (the rail may be down) — not judging blind"

# Every `model:` value in the file, with the agent row it belongs to. Two shapes are in use:
#   brokk:   { model: provider/model }
#   hnoss:   { model: "provider/model", primary: true }
models="$(grep -nE '(^|[[:space:]])model:[[:space:]]*"?[^"}]*"?' "$AGENTS" 2>/dev/null \
  | sed -E 's/^[0-9]+:[[:space:]]*([A-Za-z0-9_.-]+):.*model:[[:space:]]*"?([^",}]*)"?.*/\1\t\2/' \
  | awk -F'\t' 'NF==2 {gsub(/"/,"",$2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2);
                  if ($2!="" && tolower($2)!="default") print $1"\t"$2}' | sort -u)"

[ -n "$models" ] || skip "the agent file declares no model rows"

faults=0
total=0
report=""
while IFS="$(printf '\t')" read -r agent id; do
  [ -n "${agent:-}" ] || continue
  total=$((total + 1))
  case "$id" in */*) : ;; *) faults=$((faults + 1)); report+="  \"$agent\",\"$id\",\"not provider/model — the harness cannot resolve it\""$'\n'; continue ;; esac
  if printf '%s\n' "$servable" | grep -Fxq -- "$id"; then : ; else
    faults=$((faults + 1))
    report+="  \"$agent\",\"$id\",\"not in this machine's catalogue — bin/model/catalog.sh --has says no\""$'\n'
  fi
done <<EOF
$models
EOF

if [ "$faults" -gt 0 ]; then
  printf 'model-rows-guard[%s]{agent,model,finding}:\n' "$faults"
  printf '%s' "$report"
  printf 'error: %s of %s agent row(s) name a model this machine cannot serve\n' "$faults" "$total" >&2
  printf 'help: pick an id this seat lists — bin/model/catalog.sh --has <provider/model>; the id is per seat, never portable\n' >&2
  exit 1
fi

printf 'model-rows-guard[1]{gate,result,rows}:\n  "model rows","ok","%s"\n' "$total"
exit 0
