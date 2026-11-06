#!/usr/bin/env bash
# standardise.sh — put the collaboration kit into a repository, or say what is missing.
#
#   bin/collab/standardise.sh --check <repo>    # a report; changes nothing
#   bin/collab/standardise.sh --apply <repo>    # copy what is missing, seat the hooks, write the manifest
#
# Never overwrites a rule that already exists; never touches code. Idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$HERE/kit"
VERSION="1.1.0"

mode=""; repo=""
for a in "$@"; do
  case "$a" in --check) mode=check ;; --apply) mode=apply ;; -*) printf 'unknown option: %s\n' "$a" >&2; exit 2 ;; *) repo="$a" ;; esac
done
[ -n "$mode" ] && [ -n "$repo" ] || { printf 'usage: standardise.sh --check|--apply <repo>\n' >&2; exit 2; }
[ -d "$repo/.git" ] || [ -f "$repo/.git" ] || { printf 'not a git repository: %s\n' "$repo" >&2; exit 2; }

missing=(); present=(); differ=()
while IFS= read -r rel; do
  target="$repo/$rel"
  if [ ! -e "$target" ]; then missing+=("$rel")
  elif ! cmp -s "$KIT/$rel" "$target"; then differ+=("$rel")
  else present+=("$rel"); fi
done < <(cd "$KIT" && find . -type f ! -name README.md | sed 's|^\./||' | sort)

# the baton is not the kit's business: `init.sh` already owns it, and two doors to one shelf is how they drift
if [ -x "$HERE/init.sh" ]; then
  bash "$HERE/init.sh" "$repo" --check >/dev/null 2>&1 || printf '  note: the baton shelf is not installed — `bin/collab/collab.sh init %s`\n' "$repo"
fi

printf '[%s] kit %s\n' "$repo" "$VERSION"
printf '  present: %s\n' "${#present[@]}"
printf '  missing: %s\n' "${#missing[@]}"
[ "${#missing[@]}" -gt 0 ] && printf '    %s\n' "${missing[@]}"
printf '  different (a local rule wins; it is reported, never replaced): %s\n' "${#differ[@]}"
[ "${#differ[@]}" -gt 0 ] && printf '    %s\n' "${differ[@]}"

if [ "$mode" = apply ]; then
  for rel in "${missing[@]:-}"; do
    [ -n "$rel" ] || continue
    mkdir -p "$repo/$(dirname "$rel")"
    cp "$KIT/$rel" "$repo/$rel"
    chmod +x "$repo/$rel" 2>/dev/null || true
  done
  # a manifest so the next run knows what it installed and when
  # what the kit CARRIES and what this run ADDED — a manifest that says "files: 0" on a refresh reads as an
  # empty kit. Appended 2026-11-06, after the first install that had nothing missing said exactly that.
  carried="$(cd "$KIT" && find . -type f ! -name README.md | grep -c . | tr -d ' ')"
  printf '{\n  "kit": "%s",\n  "applied": "%s",\n  "files": %s,\n  "installed_this_run": %s\n}\n' \
    "$VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$carried" \
    "$(printf '%s\n' "${missing[@]:-}" | grep -c . | tr -d ' ')" > "$repo/.collab-kit.json"
  # the hooks only run if git is told where they are
  git -C "$repo" config core.hooksPath .githooks
  chmod +x "$repo"/.githooks/* 2>/dev/null || true
  printf '  applied %s file(s); hooks seated at .githooks\n' "${#missing[@]}"
fi

# a repository with no baton is not standardised, whatever else it has
[ -e "$repo/handoff/CURRENT.md" ] || printf '  note: no handoff/CURRENT.md yet — copy handoff/TEMPLATE.md and write the first baton\n'
