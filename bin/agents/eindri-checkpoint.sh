#!/usr/bin/env bash
# eindri-checkpoint.sh — a herdr worker's durable checkpoint, so a dead pane resumes.
#
#   eindri-checkpoint.sh save <id> --step "<what finished>" [--next "<what is next>"] [--state working|blocked|done]
#   eindri-checkpoint.sh show <id> [--json]
#   eindri-checkpoint.sh list
#   eindri-checkpoint.sh resume <id>     # re-seat from the checkpoint, or refuse and say why
#
# Why: a herdr pane is a VIEW. The durable facts are the branch, the worktree and this
# checkpoint record. pi persists the conversation; nothing persisted "where the work
# stands". When a pane dies (crash, 429, closed terminal) the operator had to reconstruct
# it from the pane's scrollback — which dies with the pane.
#
# The record: <state>/<id>.checkpoint.jsonl, one JSON line per boundary, append-only.
# Never rewritten: a checkpoint is a fact about a moment, and the newest one is the truth.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
hoard_state_dir STATE 2>/dev/null || STATE="${YMIR_HOME:-$HOME/Documents/ymirhome}/state"
mkdir -p "$STATE/checkpoints" 2>/dev/null || true

cmd="${1-}"; shift || true
case "$cmd" in
  -h|--help|"") sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
ID="${1-}"; shift || true
[ -n "$ID" ] || { printf 'eindri-checkpoint: an errand id is required\n' >&2; exit 2; }
FILE="$STATE/checkpoints/$ID.jsonl"
META="$STATE/$ID.meta"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "$cmd" in
  save)
    STEP=""; NEXT=""; CSTATE=working
    while [ $# -gt 0 ]; do case "$1" in
      --step) STEP="${2-}"; shift 2 ;;
      --next) NEXT="${2-}"; shift 2 ;;
      --state) CSTATE="${2-}"; shift 2 ;;
      *) shift ;;
    esac; done
    [ -n "$STEP" ] || { printf 'eindri-checkpoint: --step is required — a checkpoint names what finished\n' >&2; exit 2; }
    WT="$(sed -n 's/^worktree=//p' "$META" 2>/dev/null | head -1)"
    COMMITS=0; BRANCH=""
    [ -n "$WT" ] && [ -d "$WT" ] && {
      COMMITS="$(git -C "$WT" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)"
      BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    }
    python3 - "$FILE" "$ID" "$STEP" "$NEXT" "$CSTATE" "${WT:-}" "$COMMITS" "${BRANCH:-}" "$(now)" <<'PY'
import json, sys
path, ident, step, nxt, state, wt, commits, branch, ts = sys.argv[1:10]
rec = {"id": ident, "at": ts, "step": step, "next": nxt, "state": state,
       "worktree": wt, "branch": branch, "commits": int(commits or 0)}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
print(json.dumps(rec, ensure_ascii=False))
PY
    ;;
  show)
    [ -s "$FILE" ] || { printf 'eindri-checkpoint: %s has no checkpoint yet — it never saved one, and that is the fault to fix\n' "$ID" >&2; exit 1; }
    tail -1 "$FILE"
    ;;
  list)
    printf 'checkpoints[%s]{id,at,state,step}:\n' "$(ls "$STATE"/checkpoints/*.jsonl 2>/dev/null | wc -l | tr -d ' ')"
    for f in "$STATE"/checkpoints/*.jsonl; do
      [ -s "$f" ] || continue
      id="$(basename "$f" .jsonl)"
      last="$(tail -1 "$f")"
      printf '  "%s"' "$id"
      printf '%s' "$last" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(f",\"{d[chr(34)+chr(97)+chr(116)+chr(34)]}\",\"{d[chr(34)+chr(115)+chr(116)+chr(97)+chr(116)+chr(101)+chr(34)]}\",\"{d[chr(34)+chr(115)+chr(116)+chr(101)+chr(112)+chr(34)][:70]}\"")'
    done
    ;;
  resume)
    [ -s "$FILE" ] || { printf 'eindri-checkpoint: %s has no checkpoint — refuse to resume into a guess\n' "$ID" >&2; exit 1; }
    LAST="$(tail -1 "$FILE")"
    WT="$(sed -n 's/^worktree=//p' "$META" 2>/dev/null | head -1)"
    # the three refusals, each named
    [ -n "$WT" ] && [ -d "$WT" ] || { printf 'refused: the worktree is gone (%s) — nothing durable is left to resume\n' "${WT:-unset}" >&2; exit 3; }
    BR="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [ "$BR" != "HEAD" ] || { printf 'refused: the worktree is on a detached HEAD — commits cannot be found after a restart\n' >&2; exit 3; }
    printf '%s' "$LAST" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(f"resume_plan[5]{{id,step,next,worktree,commits}}:")
print(f\"  \\\"{d[chr(34)+chr(105)+chr(100)+chr(34)]}\\\",\\\"{d[chr(34)+chr(115)+chr(116)+chr(101)+chr(112)+chr(34)]}\\\",\\\"{d[chr(34)+chr(110)+chr(101)+chr(120)+chr(116)+chr(34)]}\\\",\\\"{d[chr(34)+chr(119)+chr(111)+chr(114)+chr(107)+chr(116)+chr(114)+chr(101)+chr(101)+chr(34)]}\\\",\\\"{d[chr(34)+chr(99)+chr(111)+chr(109)+chr(109)+chr(105)+chr(116)+chr(115)+chr(34)]}\\\")\")'
    printf 'next: sudo -u %s true; then re-seat with the checkpoint as the brief seed:\n' "$(id -un)"
    printf '  bin/agents/einherjar-spawn.sh %s %s --mode local-only --harness pi --model opencode-go/deepseek-v4.1-flash\n' "$ID" "$ROOT"
    ;;
  *) printf 'eindri-checkpoint: unknown action %s\nhelp: save · show · list · resume\n' "$cmd" >&2; exit 2 ;;
esac
