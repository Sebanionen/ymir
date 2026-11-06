#!/usr/bin/env bash
# whose-tree.sh — whose code am I standing in?
#
# A hand must know, before its first line, whether it is working in the house's own code or in a project somebody else
# lives in. The two answer to different laws: the house's own tree is edited under the house's rules and sealed by the
# Allfather; another owner's tree is edited under THAT repository's rules, and the house's only duty there is the kit.
#
# Usage:
#   whose-tree.sh [path]         # the tree's identity, as TOON
#   whose-tree.sh --quiet [path] # one line: "house" | "project: <id>" | "guest: <owner>/<repo>" | "unknown"
#   whose-tree.sh --version
#
# Exit: 0 a verdict was reached · 1 the tree cannot be read · 2 usage.
set -u
VER="1.0.0"
quiet=0
path="."
for a in "$@"; do
  case "$a" in
    --quiet) quiet=1 ;;
    --version) printf 'whose-tree %s\n' "$VER"; exit 0 ;;
    -*) printf 'usage: whose-tree.sh [--quiet] [path]\n' >&2; exit 2 ;;
    *) path="$a" ;;
  esac
done

root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || {
  printf 'whose-tree: not a git tree: %s\n' "$path" >&2; exit 1;
}

remote=$(git -C "$root" remote get-url origin 2>/dev/null || printf '')
slug=""
if [ -n "$remote" ]; then
  slug=$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
fi
owner=${slug%%/*}; repo=${slug##*/}

# The registry is the declared truth for the house's projects. It is read, never guessed.
# The hoard is resolved, never restated (RULES/07). One resolver, and a clean skip when there is none.
ymir_home="${YMIR_HOME:-}"
# This door ships with the house, so the resolver is found beside it — not in the tree under inspection.
house_root="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
if [ -z "$ymir_home" ] && [ -r "$house_root/bin/vault/hoard-lib.sh" ]; then
  # the resolver's functions take a result variable: `ymir_home_root <var>`
  ymir_home=$(bash -c '. "$1" >/dev/null 2>&1; ymir_home_root _v; printf "%s" "$_v"' _ "$house_root/bin/vault/hoard-lib.sh" || true)
fi
reg="${ymir_home:+$ymir_home/hodd/identity/projects.yaml}"
project=""; posture=""; realm=""
if [ -n "$slug" ] && [ -n "$reg" ] && [ -f "$reg" ]; then
  block=$(awk -v want="$slug" '
    /^[[:space:]]*- id:/ { id=$0; sub(/^[[:space:]]*- id:[[:space:]]*/,"",id); inblock=1; m=""; p="" }
    inblock && /^[[:space:]]+repo:/ { r=$0; sub(/^[[:space:]]+repo:[[:space:]]*/,"",r); gsub(/"/,"",r); if (r==want || (want ~ ("/" r "$"))) { matched=1 } }
    inblock && /^[[:space:]]+posture:/ { p=$0; sub(/^[[:space:]]+posture:[[:space:]]*/,"",p) }
    inblock && /^[[:space:]]+realm:/ { m=$0; sub(/^[[:space:]]+realm:[[:space:]]*/,"",m) }
    matched && !printed { print id "|" m "|" p; printed=1 }
  ' "$reg")
  IFS='|' read -r project realm posture <<< "$block"
fi

# Who works in this tree. A repository that names its people in `.agents/identity.json` can answer it; one that does not
# says so, rather than implying the work is yours alone.
identity="$root/.agents/identity.json"
hands=""; handcount=0
if [ -f "$identity" ]; then
  hands=$(sed -nE 's/.*"github": *"([^"]+)".*/\1/p' "$identity" | grep -vE 'null|login or' | paste -sd, -)
  handcount=$(sed -nE 's/.*"github": *"([^"]+)".*/\1/p' "$identity" | grep -vE "null|login or" | grep -c .)
fi

manifest="$root/.collab-kit.json"
kit=""; kitapplied=""
if [ -f "$manifest" ]; then
  kit=$(sed -nE 's/.*"kit": *"([^"]+)".*/\1/p' "$manifest" | head -1)
  kitapplied=$(sed -nE 's/.*"applied": *"([^"]+)".*/\1/p' "$manifest" | head -1)
fi

case "$slug" in
  zerwiz/ymir|zerwiz/ymirhome) whose=house ;;
  "") whose=unknown ;;
  *)
    if [ -n "$project" ]; then whose=project
    elif [ "$owner" = "zerwiz" ]; then whose=house
    else whose=guest
    fi
    ;;
esac

case "$whose" in
  guest) law="the host repository's own law; the house's kit, and nothing else" ; skill="smidr-the-workbench" ;;
  project) law="the project's law and the house's rules where they do not disagree" ; skill="smidr-the-workbench" ;;
  house) law="the house's rules; the Allfather seals every merge" ; skill="galdr-ymirsystem" ;;
  *) law="unread — name it before you edit" ; skill="" ;;
esac

if [ "$quiet" = 1 ]; then
  case "$whose" in
    project) printf 'project: %s\n' "${project:-$slug}" ;;
    guest)   printf 'guest: %s\n' "${slug:-no-remote}" ;;
    *)       printf '%s\n' "$whose" ;;
  esac
  exit 0
fi

printf 'tree[1]{field,value}:\n'
printf '  "root","%s"\n' "$root"
printf '  "whose","%s"\n' "$whose"
printf '  "remote","%s"\n' "${slug:-none}"
printf '  "project","%s"\n' "${project:-none}"
printf '  "realm","%s"\n' "${realm:-none}"
printf '  "posture","%s"\n' "${posture:-none}"
printf '  "kit","%s"\n' "${kit:-none}"
printf '  "kit_applied","%s"\n' "${kitapplied:-none}"
printf '  "hands","%s"\n' "${hands:-unstated}"
printf '  "hand_count","%s"\n' "$handcount"
printf '  "law","%s"\n' "$law"
[ -n "$skill" ] && printf '  "skill","%s"\n' "$skill"
printf "\nA guest tree is not the house's to seal: open a pull request, say what you verified, and stop.\n"
exit 0
