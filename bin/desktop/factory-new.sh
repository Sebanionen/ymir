#!/usr/bin/env bash
# factory-new.sh — copy the empty factory, give it a name, and say what to fill in.
#
#   bin/desktop/factory-new.sh <name> [--out DIR]
#
# A factory is a preset: one problem, one chain, one roster, one trigger, one scope.
# This door never guesses a model, a path or a schedule — it copies the shape and prints
# the five lines a human must fill before the factory may run (plan 199 §5).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TPL="$ROOT/.agents/templates/factory/factory.yaml.example"
NAME="${1-}"; shift || true
OUT="${YMIR_HOME:-$HOME/Documents/ymirhome}/hodd/factories"
while [ $# -gt 0 ]; do case "$1" in --out) OUT="${2-}"; shift 2 ;; *) shift ;; esac; done

[ -n "$NAME" ] || { printf 'usage: factory-new.sh <name> [--out DIR]\n' >&2; exit 2; }
case "$NAME" in [a-z0-9]*) ;; *) printf 'factory-new: a name is kebab-case: lower letters, digits, hyphens\n' >&2; exit 2 ;; esac
[ -r "$TPL" ] || { printf 'factory-new: the template is missing at %s\n' "$TPL" >&2; exit 3; }
mkdir -p "$OUT"
dest="$OUT/$NAME.yaml"
[ -e "$dest" ] && { printf 'factory-new: %s already exists — edit it, do not overwrite a factory\n' "$dest" >&2; exit 1; }
sed "s/name: <one-problem-in-kebab-case>/name: $NAME/" "$TPL" > "$dest"
printf 'factory[1]{name,file,state}:\n  "%s","%s","copied — five lines to fill"\n' "$NAME" "$dest"
printf 'fill: problem · chain · roster (role→model) · trigger · scope\n'
printf 'then: bin/seat/pending.sh shows what it asks you; bin/agents/eir-doctor.sh check before the first run\n'
