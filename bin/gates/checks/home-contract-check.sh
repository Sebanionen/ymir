#!/usr/bin/env bash
# home-contract-check.sh — the contract that raises a home is itself checked.
#
# WHY (RULES/42). The contract is how a user's home receives the files the runtime reads.
# It can rot in five ways, and each is silent: a row naming a template that was moved or
# never shipped; a row naming a door that does not exist; a required file with no shape
# anywhere; a TEMPLATE NOBODY RECEIVES, a shape that ships to every user and is copied into
# no home because no row names it; and — the widest, at ten thousand downloads — a template
# the npm package does not carry, so the install most users take cannot raise the home.
#
#   home-contract-check.sh            # judge the contract
#   home-contract-check.sh --list     # print the rows, tab-separated
#
# There is ONE parser of the contract and it lives in bin/engine/home-seed.sh: this door
# calls it, so a shape that reads well here cannot read differently when a file is seeded
# (two parsers is two truths).
#
# Exit: 0 clean · 1 a finding · 2 usage.
set -uo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
CONTRACT="$ROOT/.agents/home-contract.yaml"
SEEDER="$ROOT/bin/engine/home-seed.sh"

case "${1-}" in
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  ""|check) ;;
  --version) printf 'home-contract-check %s\n' "$VERSION"; exit 0 ;;
  *) printf 'error: unknown flag %s\nhelp: home-contract-check.sh [check|--list]\n' "$1" >&2; exit 2 ;;
esac

[ -r "$CONTRACT" ] || { printf 'home-contract-check[1]{finding,detail}:\n  "no contract","%s — the list of home files the runtime reads"\n' "$CONTRACT" >&2; exit 1; }
[ -r "$SEEDER" ] || { printf 'home-contract-check[1]{finding,detail}:\n  "no seeder","%s — the one parser and the door that copies the shapes"\n' "$SEEDER" >&2; exit 1; }

parsed="$(bash "$SEEDER" --list 2>/dev/null)" || true
[ -n "$parsed" ] || { printf 'home-contract-check[1]{finding,detail}:\n  "the contract lists no rows","%s"\n' "$CONTRACT" >&2; exit 1; }
[ "${1-}" = "--list" ] && { printf '%s\n' "$parsed"; exit 0; }

findings=0
say() { printf '  "%s","%s","%s"\n' "$1" "$2" "$3"; findings=$((findings+1)); }
printf 'home_contract[3]{rows,findings,state}:\n'

# ── the shape is strict: a line the parser cannot read is a file nobody seeds ──
bad_shape="$(awk '
  BEGIN { inblock = 0 }
  /^contract:/ { inblock = 1; next }
  /^[^ \t#]/   { inblock = 0 }
  inblock && /^[ \t]*$/ { next }
  inblock && /^[ \t]*#/ { next }
  inblock && /^  - path:/ { next }
  inblock && /^    (kind|template|door|required|why):/ { next }
  inblock { print NR ": " $0 }
' "$CONTRACT")"
while IFS= read -r l; do
  [ -n "$l" ] && say "a line the parser cannot read" "$l" "the shape is strict: path · kind · template · door · required · why"
done <<<"$bad_shape"

rows=0
declare -A SEEN=()
named_templates=" "
row_templates=""
while IFS="$(printf '\t')" read -r path kind template door required; do
  [ -n "$path" ] || continue
  rows=$((rows+1))

  # 1 · a path is home-relative, unique, and carries no substitution but {realm}
  case "$path" in
    /*)  say "path is absolute" "$path" "a contract path is relative to the home" ;;
    *..*) say "path escapes the home" "$path" "no .. in a contract path" ;;
  esac
  case "$path" in *"{"*) case "$path" in *"{realm}"*) ;; *) say "unknown substitution" "$path" "only {realm} is resolved" ;; esac ;; esac
  if [ -n "${SEEN[$path]:-}" ]; then say "the same home file is claimed twice" "$path" "one file, one row"; fi
  SEEN[$path]=1

  # 2 · the kind decides what the row owes
  case "$kind" in
    seeded|stub|defaulted|optional|generated) ;;
    "") say "kind missing" "$path" "seeded · stub · defaulted · optional · generated"; continue ;;
    *)  say "kind not a contract kind" "$path:$kind" "seeded · stub · defaulted · optional · generated"; continue ;;
  esac
  case "$required" in
    true|false) ;;
    *) say "required is not true|false" "$path:${required:-<empty>}" "state whether the house runs without it" ;;
  esac

  # 3 · the template the row names must exist, and a required file must HAVE one
  if [ -n "$template" ] && [ "$template" != "-" ]; then
    [ -f "$ROOT/$template" ] || say "the template does not exist" "$path → $template" "the shape a user receives must ship in this tree"
    named_templates="$named_templates$template "
    row_templates="$row_templates$template
"
  else
    case "$kind" in
      seeded|stub|defaulted) say "no template for a file that must be raised" "$path:$kind" "ship its shape, or make it optional and say why" ;;
    esac
    [ "$required" = "true" ] && say "a required file with no shape" "$path" "a required row the user can never receive is a wish"
  fi

  # 4 · the door that writes it must exist — and a generated file must name one
  if [ -n "$door" ] && [ "$door" != "-" ]; then
    [ -f "$ROOT/$door" ] || say "the door does not exist" "$path → $door" "a door named in the contract is how the file arrives"
  else
    case "$kind" in
      generated) say "a generated file with no generator" "$path" "name the door that writes it, never a hand" ;;
    esac
  fi
done <<<"$parsed"

# 5 · a template NOBODY RECEIVES is a shape that ships to every user and lands in no home
for shelf in registry hodd .agents/config svartalfaheim/examples; do
  [ -d "$ROOT/$shelf" ] || continue
  while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    case "$named_templates" in *" $rel "*) ;; *) say "a template no home receives" "$rel" "add its row to .agents/home-contract.yaml, or stop shipping it" ;; esac
  done < <(find "$ROOT/$shelf" -name '*.example*' -type f 2>/dev/null)
done

# 6 · THE PACKAGE MUST CARRY THE SHAPES. At ten thousand downloads most installs are the npm
# package, and `package.json`'s `files[]` decides what a package CONTAINS. A template the
# contract names that the tarball omits is a home that cannot be raised on the road most
# users take — measured 2026-11-02: `hodd/`, `registry/` and `svartalfaheim/` were absent
# from `files[]`, so nine of the twelve seeds were impossible from a package install.
PKG="$ROOT/package.json"
if [ -f "$PKG" ]; then
  included="$(python3 -c '
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: raise SystemExit(0)
for e in (d.get("files") or []):
    if not e.startswith("!"): print(e.rstrip("/"))
' "$PKG" 2>/dev/null)"
  if [ -z "$included" ]; then
    say "the package file list cannot be read" "package.json → files[]" "an unreadable list is an unproven package"
  else
    while IFS= read -r tpl; do
      [ -n "$tpl" ] || continue
      top="${tpl%%/*}"
      hit=""
      while IFS= read -r inc; do
        [ -n "$inc" ] || continue
        case "$tpl" in "$inc"|"$inc"/*) hit="$inc"; break ;; esac
      done <<<"$included"
      [ -n "$hit" ] || say "the package omits a template the contract names" "$tpl" "add $top/ to package.json files[], or a package install cannot raise this file"
    done <<<"$row_templates"
  fi
fi

if [ "$findings" -eq 0 ]; then
  printf '  "%s","0","clean"\n' "$rows"
  printf 'home-contract-check: clean — %s row(s), every template shipped, every door standing, the package carrying them\n' "$rows"
  exit 0
fi
printf '  "%s","%s","findings"\n' "$rows" "$findings"
printf 'home-contract-check: %s finding(s) — this contract would leave a home incomplete\n' "$findings" >&2
printf 'help: .agents/home-contract.yaml · RULES/42 · the seed door is bin/engine/home-seed.sh\n' >&2
exit 1
