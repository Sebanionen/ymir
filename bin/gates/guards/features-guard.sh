#!/usr/bin/env bash
# features-guard.sh — every feature page is catalogued (Rule 14).
#
# The user's front door is FEATURES.md (the master catalogue) + docs/features/
# (the how-tos). A page that is not listed in the catalogue is a page no user will
# find — so this ward refuses a `docs/features/*.md` that FEATURES.md does not
# name. It does not require a feature to HAVE a page (that is a debt Rule 14 names);
# it requires that any page which exists be reachable.
#
#   features-guard.sh            # check
#   features-guard.sh --all      # same
#
# Exit: 0 every page is catalogued · 1 one is not · 2 usage.
set -u
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  # `check` is the DEFAULT: a bare invocation must judge, never print help and pass
  # vacuously (measured 2026-11-04: no argument matched this branch first and exited 0).
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  check|--all|"") ;;
  *) printf 'error: unknown action %s\nhelp: features-guard.sh [check|--all]\n' "${1-}" >&2; exit 2 ;;
esac

CATALOGUE="$ROOT/FEATURES.md"
printf 'features-guard[3]{finding,page,catalogue}:\n'
if [ ! -f "$CATALOGUE" ]; then
  printf '  "the catalogue is missing","FEATURES.md","%s"\n' "$CATALOGUE"
  printf 'features-guard: FEATURES.md does not exist\nhelp: the master catalogue is required (Rule 14)\n' >&2
  exit 1
fi

missing=0
for f in "$ROOT"/docs/features/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "README.md" ] && continue
  if ! grep -q "docs/features/$base" "$CATALOGUE"; then
    printf '  "a feature page is not in the catalogue","docs/features/%s","FEATURES.md"\n' "$base"
    missing=$((missing + 1))
  fi
done

# The catalogue is WOVEN (Þættir, plan 174): the file must equal its fragments, and the
# merge driver must be seated so a conflict is answered by weaving, not by hand.
stale=0
if ! bash "$ROOT/bin/records/weave-features.sh" --check >/dev/null 2>&1; then
  printf '  "the woven catalogue is stale","FEATURES.md","run bin/records/weave-features.sh (fragments live in docs/features/_catalogue/)"\n'
  stale=$((stale + 1))
fi
# The driver is DECLARED in .gitattributes (tracked, so every clone and CI carry it);
# the per-clone `git config` is only the convenience `--install` seats. Judging the
# local config made every fresh clone — CI included — fail a ward about a merge that
# never happens there, and turned four collaborators' PRs red for nothing.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
<<<<<<< ours
  driver="$(git -C "$ROOT" config --get merge.regenerate.driver 2>/dev/null || true)"
  [ -n "$driver" ] || {
    printf '  "the merge driver is not seated","FEATURES.md · bin/README.md · capabilities.md","run bin/records/weave-features.sh --install (a woven document without its driver conflicts by hand, on every merge)"\n'
=======
  declared="$(git -C "$ROOT" check-attr merge -- FEATURES.md 2>/dev/null | sed 's/.*: merge: //' || true)"
  script_ok=1
  [ -f "$ROOT/bin/records/regenerate-on-merge.sh" ] || script_ok=0
  if [ "$declared" != "regenerate" ] || [ "$script_ok" -ne 1 ]; then
    printf '  "the merge driver is not declared","FEATURES.md","FEATURES.md needs merge=regenerate in .gitattributes and bin/records/regenerate-on-merge.sh in the tree (a woven document without its driver conflicts by hand)"\n'
>>>>>>> theirs
    stale=$((stale + 1))
  elif [ -z "$(git -C "$ROOT" config --get merge.regenerate.driver 2>/dev/null || true)" ]; then
    printf '  "the merge driver is declared but not seated in this clone","FEATURES.md","run bin/records/weave-features.sh --install for this clone (CI does not merge, so it is a note here, not a fault)"\n'
  fi
fi
if [ "$missing" -eq 0 ] && [ "$stale" -eq 0 ]; then
  printf '  "none","","every feature page is catalogued, and the woven catalogue is current"\n'
  exit 0
fi
printf 'features-guard: %s finding(s) — %s page(s) uncatalogued, %s stale/driver fault(s)\nhelp: add the row to its section fragment in docs/features/_catalogue/, then run bin/records/weave-features.sh (Rule 14 · Þættir)\n' "$((missing + stale))" "$missing" "$stale" >&2
exit 1
