#!/usr/bin/env bash
# fixes-guard.sh — the delivery gate reads, and it checks the RECORD.
#
# What it replaces, and why: `changelog-guard` passed if a push range merely
# *touched* CHANGELOG.md — a stray line satisfied it, so it never verified that
# anything was recorded. And the hook in front of it FOLDED fragments into the
# monolith, mutating the tree mid-push and then demanding a commit for the edit it
# had just made.
#
# This gate only READS. A push must carry at least one new fix note
# (`docs/fixes/<component>/<version>-<slug>.md`), and it says which of the push's
# touched paths that note's component covers — a mismatch is reported, never
# silently accepted.
#
#   fixes-guard.sh --install     # seat it as the pre-push hook (replacing the old one)
#   fixes-guard.sh --check       # judge the current branch against its base, by hand
#   git push                     # the hook runs it with the refs on stdin
#
# Override, loudly: YMIR_SKIP_FIXES_GUARD=1
#
# Exit: 0 the record is there, 1 it is not, 2 usage.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
cd "$ROOT" || exit 1

[ "${YMIR_SKIP_FIXES_GUARD:-0}" = 1 ] && { printf 'fixes-guard[1]{gate,result}:\n  "push","skipped (YMIR_SKIP_FIXES_GUARD=1)"\n'; exit 0; }

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --install)
    H="$(git rev-parse --git-path hooks)/pre-push"
    mkdir -p "$(dirname "$H")"
    cat >"$H" <<EOF
#!/usr/bin/env bash
# pre-push — the delivery gate. Installed by bin/gates/guards/fixes-guard.sh --install.
#   1. guards       — the TREE wards: the tree is not a runtime, and one place knows where
#                     things live. First, because it is fast and a dirty tree should fail
#                     before anything else is argued about.
#   2. branch-guard — never push a protected branch.
#   3. fixes-guard  — every push carries a fix note for what it changed.
#   4. branch-current — the branch is based on CURRENT main before it is offered
#                     (a branch six commits behind main arrives with conflicts and
#                     stale rule numbers; caught 2026-10-18 by asking "did you pull")
set -u
# Judge the checkout the push comes FROM, not the one that installed the hook. Git runs a
# pre-push hook with cwd at the pushing worktree's root, and this hook used to bake in the
# installing checkout's absolute path: when that worktree was reclaimed, the hook pointed at
# a directory that no longer existed and every push died with "No such file or directory"
# (measured 2026-10-20). A hook that names a path a cleanup can remove is a gate that can
# be deleted by housekeeping.
ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
refs="\$(mktemp)"; trap 'rm -f "\$refs"' EXIT
cat >"\$refs"
"\$ROOT/bin/gates/guards.sh" || exit 1
"\$ROOT/bin/gates/guards/branch-guard.sh" <"\$refs" || exit 1
"\$ROOT/bin/gates/guards/fixes-guard.sh" <"\$refs" || exit 1
"\$ROOT/bin/gates/branch-current.sh" check || exit 1
EOF
    chmod +x "$H"
    printf 'fixes-guard[1]{gate,result}:\n  "hook","installed at %s"\n' "${H#"$ROOT"/}"
    exit 0 ;;
  --check) ;;
  "") ;;
  *) printf 'error: unknown flag %s\nhelp: bin/gates/guards/fixes-guard.sh [--install|--check]\n' "$1" >&2; exit 2 ;;
esac

# ── the judgement ────────────────────────────────────────────────────────────
# Judge each outgoing branch independently; a later ref cannot hide an earlier one.
judge_range() {
  local head_sha="${1:-}" remote_sha="${2:-}" require_record="${3:-0}" base="" range notes touched covered count n c f
[ -n "$head_sha" ] || head_sha="$(git rev-parse HEAD)"

base=""
if [ -n "$remote_sha" ] && [ "$remote_sha" != 0000000000000000000000000000000000000000 ]; then
  base="$remote_sha"
else
  for cand in origin/main main master; do
    git rev-parse --verify -q "$cand" >/dev/null 2>&1 || continue
    base="$(git merge-base "$head_sha" "$cand" 2>/dev/null || true)"
    [ -n "$base" ] && break
  done
fi
if [ -z "$base" ] && [ "$require_record" = 1 ]; then
  base="$(git hash-object -t tree --stdin </dev/null)" || return 1
fi
[ -n "$base" ] || { printf 'fixes-guard[1]{gate,result}:\n  "push","no base to compare — first push of a branch is judged on its own"\n'; return 0; }

range="${base}..${head_sha}"
# The note's name is <version>-<slug>.md, and a version is whatever bin/gates/fixes.sh was
# TOLD it is: `--version=unversioned` is legitimate, and 158 of the repo's notes use
# it. Accepting only a digit-first version made the gate blind to those notes and
# refused every push that carried one (2026-09-25) — the guard demanded a format its
# own writer does not require. A note the gate cannot SEE is a note it cannot judge.
notes="$(git diff --name-only --diff-filter=A "$range" 2>/dev/null | grep -E '^docs/fixes/[a-z]+/([0-9]|unversioned-)[^/]*\.md$' || true)"
touched="$(git diff --name-only "$range" 2>/dev/null | grep -v '^docs/fixes/' | grep -v '^CHANGELOG' || true)"

if [ -z "$notes" ]; then
  printf 'fixes-guard[1]{gate,result}:\n  "push","refused — no fix note in this range"\n' >&2
  printf 'help: bin/gates/fixes.sh record --component=<%s> --version=<v> --title="what changed"\n' \
    "install|runtime|snotra|skills|agents|hlidskjalf|odrerir|sessrumnir|smidja|hoard|gate" >&2
  printf 'note: a note is a file under docs/fixes/<component>/ — write one, commit it, push again.\n' >&2
  return 1
fi

# The record is there: now say whether it speaks to what the push changed.
# WHAT A PATH IS, so the note that describes it can be recognised.
#
# Until 2026-10-01 this matcher only knew three shapes: a path containing the component's own
# name, a short list of files that happen to spell one, and `.agents/skills/*`. So a note under
# `runtime/` describing `bin/seat/verify-seat.sh` counted as covering NOTHING — and every push that
# carried a correct note still had to be pushed with the loud YMIR_SKIP_FIXES_GUARD=1 override.
# **A gate that must be routinely overridden is a gate nobody trusts**, so the map is explicit now
# rather than clever: a path that names no component is mapped by WHAT IT IS.
path_component() {  # <path> -> the component it belongs to, or empty
  case "$1" in
    systems/snotra/*) echo snotra ;;
    src/ymir_runtime/*|bin/mimir*|bin/records/mimir.sh|bin/seat/verify-seat.sh|bin/time/saga-wake-drain.sh) echo runtime ;;
    tools/mcp-gateway/*|bin/bridge/mcp-gateway.sh|bin/records/journal-*.sh) echo runtime ;;
    bin/bridge/a2a-mcp.sh|bin/bridge/ratatoskr.sh) echo runtime ;;
    bin/engine/ymir-install.sh|bin/agents/groa-update.sh|bin/seat/valknut-load.sh|bin/engine/ymir-migrate.sh) echo install ;;
    .pi/*|.agents/skills/*|bin/agents/skill-find.sh|bin/gates/fixes.sh|bin/gates/guards/fixes-guard.sh) echo agents ;;
    bin/gates/capabilities.sh|bin/gates/inventory.sh|bin/gates/queue.sh|bin/gates/ci-verify.sh|bin/gates/checks/*|bin/no-delete-guard.sh) echo gate ;;
    # The unit templates and the renderer that seats them: the seat's services, so a fix
    # here is a runtime fix. Before this row tools/{mill,web}/systemd/* mapped to NO
    # component — a correct runtime note covered nothing and the gate passed on a
    # technicality while saying it could not tell. Same defect as the bin/skuld/* row
    # above, found again on 2026-10-12 by the StartLimit mend.
    tools/mill/systemd/*|tools/web/systemd/*|bin/fleet/fleet-ensure.sh|bin/engine/autoboot-lib.sh) echo runtime ;;
    # The registry readers: a fix here is a runtime fix, and before this row
    # bin/skuld/* mapped to NO component — so a correct note under runtime/ covered
    # nothing and the gate passed on a technicality while saying it could not tell.
    bin/skuld/*|bin/agents/project-git.sh) echo runtime ;;
    .agents/skills/galdr-ymirsystem/assets/hlidskjalf-ui.md|apps/hlidskjalf/*) echo hlidskjalf ;;
    .agents/skills/galdr-ymirsystem/assets/smidja.md|.agents/skills/smidja-factory/*) echo smidja ;;
    .agents/skills/galdr-ymirsystem/assets/snotra-meeting-ear.md|bin/snotra*|tools/snotra/*) echo snotra ;;
    tools/tickets-mcp/*|bin/desktop/odrerir*|apps/odrerir/*) echo odrerir ;;
  esac
}
covered=0
for n in $notes; do
  c="$(printf '%s' "${n#docs/fixes/}" | cut -d/ -f1)"
  case "$touched" in
    *"$c"*) covered=$((covered+1)) ;;
    *bin/fixes*|*install*) [ "$c" = install ] && covered=$((covered+1)) ;;
    *bin/ymir*|*bin/sessrumnir*|*bin/smidja*|*bin/npm-publish*|*.agents/skills/*) covered=$((covered+1)) ;;
  esac
  # and: does the note's component own any path this push touched?
  while IFS= read -r f; do
    [ "$(path_component "$f")" = "$c" ] && covered=$((covered+1))
  done <<EOF2
$(printf '%s\n' "$touched" | grep -v '^docs/fixes/')
EOF2
done

count="$(printf '%s\n' "$notes" | grep -c . || true)"
if [ "$covered" -gt 0 ]; then
  printf 'fixes-guard[1]{gate,result}:\n  "push","ok — %s note(s), and the record speaks to the change"\n' "$count"
else
  printf 'fixes-guard[1]{gate,result}:\n  "push","ok — %s note(s); none names a path this range touched"\n' "$count"
  printf 'note: a note for another component is still a record — but say what THIS push changed.\n' >&2
  printf '      components touched: %s\n' "$(printf '%s' "$touched" | head -4 | tr '\n' ' ')" >&2
fi
return 0
}

# Manual --check keeps its original branch/base judgment, even for published tips.
if [ "${1-}" = --check ]; then judge_range "" ""; exit $?; fi
refs="$(cat 2>/dev/null || true)"
if [ -z "$refs" ]; then judge_range "" ""; exit $?; fi
failed=0
while read -r _local local_sha remote_ref remote_sha; do
  [ -n "${local_sha:-}" ] || continue
  case "$remote_ref" in refs/tags/*)
    printf 'fixes-guard: ok — tag pointer %s carries no branch content\n' "$remote_ref"; continue ;;
  esac
  case "$local_sha" in 000000*)
    printf 'fixes-guard: ok — deletion %s carries no content\n' "$remote_ref"; continue ;;
  esac
  # Public commits may be named by another branch without inventing a new fix note.
  # Only already-fetched origin refs establish publication; outgoing siblings do not.
  if unpublished="$(git rev-list -n1 "$local_sha" --not --remotes=origin 2>/dev/null)"; then
    if [ -z "$unpublished" ]; then
      printf 'fixes-guard: ok — %s names only already published commits\n' "$remote_ref"
      continue
    fi
  else
    printf 'fixes-guard: refused — cannot inspect outgoing ref %s\n' "$remote_ref" >&2
    failed=1; continue
  fi
  printf 'fixes-guard: judging outgoing branch %s\n' "$remote_ref"
  judge_range "$local_sha" "${remote_sha:-}" 1 || failed=1
done <<<"$refs"
exit "$failed"
