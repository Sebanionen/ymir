#!/usr/bin/env bash
# fixes.sh — the fix notes. ONE FILE PER FIX, and nothing to fold.
#
# There is no changelog here and no fold step: a note IS a file, at
#   docs/fixes/<component>/<date>-<slug>.md
# Two branches never write the same path, so a collision is impossible, and the history of a component is its directory.
#
#   scripts/fixes.sh record --component=<name> --title="what changed" [--why="…"] [--files="a,b"]
#   scripts/fixes.sh list [<component>]
#   scripts/fixes.sh show <file|component>
#   scripts/fixes.sh components
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXES="$ROOT/docs/fixes"
COMPONENTS="${FIXES_COMPONENTS:-}"   # a repo may extend this below

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-56; }
known() { case " $COMPONENTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

action="${1-}"; shift || true
case "$action" in -h|--help|"") usage; exit 0 ;; esac

component=""; title=""; why=""; files=""; date="$(date +%Y-%m-%d)"; pos=""
for a in "$@"; do
  case "$a" in
    --component=*) component="${a#*=}" ;;
    --title=*)     title="${a#*=}" ;;
    --why=*)       why="${a#*=}" ;;
    --files=*)     files="${a#*=}" ;;
    --date=*)      date="${a#*=}" ;;
    -*) die "unknown argument $a" ;;
    *) pos="$a" ;;
  esac
done

command -v "$ROOT/scripts/fixes-components.sh" >/dev/null 2>&1 || true
[ -x "$ROOT/scripts/fixes-components.sh" ] && COMPONENTS="$("$ROOT/scripts/fixes-components.sh" | tr '\n' ' ')"

case "$action" in
  components)
    printf 'components[%d]{name}:\n' "$(printf '%s\n' $COMPONENTS | wc -l | tr -d ' ')"
    for c in $COMPONENTS; do printf '  "%s"\n' "$c"; done ;;

  list)
    c="${pos:-${component:-}}"
    if [ -n "$c" ]; then
      known "$c" || die "unknown component $c (one of: $COMPONENTS)"
      ls -1 "$FIXES/$c"/*.md 2>/dev/null | sort -r | while IFS= read -r f; do printf '  "%s","%s"\n' "$c" "$(basename "$f")"; done
    else
      for c in $COMPONENTS; do n=$(ls -1 "$FIXES/$c"/*.md 2>/dev/null | wc -l | tr -d ' '); printf '  "%s","%s"\n' "$c" "$n"; done
    fi ;;

  show)
    [ -n "$pos" ] || die "show needs a file or a component"
    if [ -f "$pos" ]; then cat "$pos"; else
      known "$pos" || die "unknown component $pos"
      newest="$(ls -1 "$FIXES/$pos"/*.md 2>/dev/null | sort -r | head -1)"
      [ -n "$newest" ] || die "$pos has no notes yet"
      cat "$newest"
    fi ;;

  record)
    [ -n "$component" ] && [ -n "$title" ] || die "record needs --component and --title"
    known "$component" || die "unknown component $component (one of: $COMPONENTS)"
    mkdir -p "$FIXES/$component"
    path="$FIXES/$component/$date-$(slugify "$title").md"
    [ -e "$path" ] && die "a note with that name already exists: $path"
    {
      printf '## %s · %s · %s\n\n' "$component" "$date" "$title"
      printf '### What\n\n%s\n\n' "$title"
      [ -n "$why" ] && printf '### Why\n\n%s\n\n' "$why"
      [ -n "$files" ] && { printf '### Files\n\n'; printf '%s' "$files" | tr ',' '\n' | sed '/^$/d; s/^/- `&`\n/' | sed 's/- ``/- /'; printf '\n'; }
      printf '### Verified\n\nDescribe what was run and what it printed. A fix note without evidence is a rumour.\n'
    } > "$path"
    printf 'recorded\t%s\n' "$path" ;;

  *) usage; exit 2 ;;
esac
