#!/usr/bin/env bash
# collab.sh — Vingólf, the assembly hall: who collaborates with the house, on which surface, and at which rung.
#
#   collab.sh who [--json] [--strict] [--from FILE]   the roll: every declared person, measured
#   collab.sh ladder                                  the register: rungs, what each person owes, which
#                                                     projects carry the shelf
#   collab.sh init <repo> [--from NAME] [--check]     put the baton shelf into a repository, or check it
#   collab.sh standardise <repo> [--check|--apply]    the baton PLUS the gates, hooks, fix notes and review shelf
#   collab.sh letter --to <addr> --person "<name>"    render the collaboration letter as a DRAFT (never sent)
#   collab.sh ship --repo P --branch B --message M --path X ...   branch, commit named paths, merge, push
#   collab.sh publish <repo> [--project NAME] [--yes]             the baton's next and blocked bullets as
#                                                                 Board cards, idempotent by title
#
# The declared truth is `$YMIR_HOME/hodd/data/collaboration.yaml`: no name is hardcoded here. A surface that
# cannot be read is reported as `unread`, never as zero.
#
# Exit: 0 fine · 1 a check failed / a drift under --strict · 2 usage.
set -euo pipefail
_d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

_root="$(cd "$_d/../.." && pwd)"
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then . "$_root/bin/vault/hoard-lib.sh" 2>/dev/null || true; fi
home="${YMIR_HOME:-}"
[ -n "$home" ] || ymir_home_root home 2>/dev/null || true
[ -n "$home" ] || { printf 'collab: no hoard — run bin/engine/ymir-install.sh, or set YMIR_HOME\n' >&2; exit 1; }
register="$home/hodd/data/collaboration.yaml"

ladder() {
  [ -f "$register" ] || { printf 'collab: no register at %s\n' "$register" >&2; exit 1; }
  python3 - "$register" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    register = yaml.safe_load(handle)
print("rungs[%d]{rung,what}:" % len(register.get("rungs") or {}))
for rung, what in (register.get("rungs") or {}).items():
    print('  "%s","%s"' % (rung, what))
people = register.get("people") or []
print("people[%d]{person,kind,rung,since,owes}:" % len(people))
for person in people:
    owed = "; ".join(person.get("owed") or []) or "—"
    print('  "%s","%s","%s","%s","%s"' % (person.get("name"), person.get("kind"),
                                          person.get("rung"), person.get("since"), owed))
projects = register.get("projects") or []
print("projects[%d]{project,rung,shelf,note}:" % len(projects))
for project in projects:
    print('  "%s","%s","%s","%s"' % (project.get("id"), project.get("rung"),
                                     project.get("shelf"), project.get("note") or ""))
PY
}

cmd="${1:-}"; shift || true
case "$cmd" in
  who)    exec python3 "$_d/who.py" --register "$register" "$@" ;;
  ladder) ladder ;;
  init)   exec bash "$_d/init.sh" "$@" ;;
  standardise) exec bash "$_d/standardise.sh" "$@" ;;
  letter) exec bash "$_d/letter.sh" "$@" ;;
  ship)   exec bash "$_d/ship.sh" "$@" ;;
  publish) exec python3 "$_d/publish.py" "$@" ;;
  -h|--help|"") usage ;;
  *) printf 'collab: unknown command %s\n\n' "$cmd" >&2; usage >&2; exit 2 ;;
esac
