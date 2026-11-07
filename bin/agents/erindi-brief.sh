#!/usr/bin/env bash
# erindi-brief.sh - scaffold an Eindri worker brief at data/<task-id>/brief.md.
#
# Erindi ("the errand") is the written errand Brokk hands an Eindri. The brief
# carries the Setup / Rules / Definition-of-done contract, a fixed machine-
# readable "Delivery contract: mode=<mode>" line, the ISOLATION DECLARATION,
# the status protocol, and the steering-inbox receive/ack section. Ported from
# the upstream distro brief scaffold for plan 29.
#
# The rule (settled 2026-09-24): herdr is the ORDINARY road — a normal deploy
# runs in a herdr workspace in the worktree, with no container. Utgard is the
# EXCEPTION, chosen for untrusted code or an outsized task, never for routine
# work and never merely because an image is present. The brief DECLARES the
# isolation on its own line so einherjar-spawn validates it against reality:
#
#   Isolation: herdr — <why>        (ordinary; the default)
#   Isolation: utgard — <why>       (the exception: untrusted code / outsized load)
#
# The scaffold emits the herdr line; a writer who needs Utgard edits the line
# and says why. The declaration is never inferred from the task text.
# The Definition of done is machine-checkable: every gate is a COMMAND the
# worker runs and whose output it records; where a gate cannot be a command,
# the brief says why.
#
# Usage:
#   erindi-brief.sh <task-id> <repo-name> --mode <no-mistakes|direct-PR|local-only>
#   erindi-brief.sh <task-id> <repo-name> --scout
#   erindi-brief.sh <task-id> --relaunch
#
# --scout writes the scout contract: the deliverable is a report at
# data/<task-id>/report.md (no branch, no push, no PR) and the worktree is
# scratch.
# --relaunch regenerates the brief from the task's recorded state/<id>.meta so
# a replacement Eindri receives the SAME delivery contract as the original; it
# refuses to invent a mode and it will not run without an existing meta record.
# The fixed "Delivery contract: mode=<mode>" line is read by
# bin/agents/einherjar-spawn.sh, which refuses to launch a ship task whose explicit
# --mode disagrees, so an adjusted brief and the recorded task cannot drift.
# --mode is refused on --scout and --relaunch: a scout delivers a report and a
# relaunch re-derives the mode from the task record, not from a flag.
# Refuses to overwrite an existing brief unless --relaunch is given.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
BROKK_HOME="${BROKK_HOME:-${BROKK_ROOT_OVERRIDE:-$ROOT}}"
DATA="${BROKK_DATA_OVERRIDE:-$BROKK_HOME/data}"
STATE="${BROKK_STATE_OVERRIDE:-$BROKK_HOME/state}"
PAUSED_VERB="${BROKK_PAUSED_VERB:-paused}"

KIND=ship
SCOUT=0
RELAUNCH=0
MODE=
MODE_SET=0
POS=()
want_value=
for a in "$@"; do
  if [ -n "$want_value" ]; then
    case "$a" in
      --*) echo "error: --$want_value requires a value" >&2; exit 1 ;;
    esac
    case "$want_value" in
      mode) MODE=$a; MODE_SET=1 ;;
      *) echo "error: internal parser state for --$want_value" >&2; exit 1 ;;
    esac
    want_value=
    continue
  fi
  case "$a" in
    --scout) SCOUT=1 ;;
    --relaunch) RELAUNCH=1 ;;
    --mode) want_value=mode ;;
    --mode=*) MODE=${a#--mode=}; MODE_SET=1 ;;
    --yolo|--yolo=*) echo "error: --yolo is not a brief input; pass it to bin/agents/einherjar-spawn.sh, which records the task's merge posture" >&2; exit 1 ;;
    *) POS+=("$a") ;;
  esac
done
[ -z "$want_value" ] || { echo "error: --$want_value requires a value" >&2; exit 1; }

if [ "$SCOUT" -eq 1 ] && [ "$RELAUNCH" -eq 1 ]; then
  echo "error: --scout and --relaunch are mutually exclusive" >&2
  exit 1
fi

ID=${POS[0]:-}
[ -n "$ID" ] || { echo "error: task-id is required" >&2; exit 2; }
case "$ID" in
  */*|.*|*' '*) echo "error: invalid task-id '$ID' (no slashes, no leading dot, no spaces)" >&2; exit 2 ;;
esac

meta_value() {  # <meta> <key>
  grep "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2- || true
}

# The isolation declaration the brief carries. Fresh scaffolds declare herdr
# (the ordinary road); a writer who needs Utgard edits the line. A relaunch
# re-derives the RECORDED isolation (state/<id>.meta) so the replacement smith
# receives the same declaration the spawn validated.
ISOLATION_WORD=herdr
ISOLATION_WHY="the ordinary road: herdr and the worktree only; Utgard is for untrusted code or an outsized task"
if [ "$RELAUNCH" -eq 1 ]; then
  iso=$(meta_value "$STATE/$ID.meta" isolation)
  iso_reason=$(meta_value "$STATE/$ID.meta" isolation_reason)
  case "$iso" in
    on) ISOLATION_WORD=utgard; [ -n "$iso_reason" ] && ISOLATION_WHY=$iso_reason ;;
    off) ISOLATION_WORD=herdr; [ -n "$iso_reason" ] && ISOLATION_WHY=$iso_reason ;;
  esac
fi
ISOLATION_DECLARATION="Isolation: $ISOLATION_WORD — $ISOLATION_WHY"

if [ "$RELAUNCH" -eq 1 ]; then
  META="$STATE/$ID.meta"
  [ -f "$META" ] || { echo "error: --relaunch requires an existing task record at $META" >&2; exit 1; }
  RECORDED_KIND=$(meta_value "$META" kind); RECORDED_KIND=${RECORDED_KIND:-ship}
  REPO=$(meta_value "$META" project)
  [ -n "$REPO" ] || REPO=$(meta_value "$META" worktree)
  [ -n "$REPO" ] || { echo "error: task record $META records no project; cannot regenerate the brief" >&2; exit 1; }
  if [ "$MODE_SET" -eq 1 ]; then
    echo "error: --mode is refused with --relaunch; the delivery mode is re-derived from $META" >&2
    exit 1
  fi
  if [ "$RECORDED_KIND" = ship ]; then
    MODE=$(meta_value "$META" mode)
    case "$MODE" in
      no-mistakes|direct-PR|local-only) ;;
      *) echo "error: task record $META records no valid mode; refusing to regenerate the brief" >&2; exit 1 ;;
    esac
  elif [ "$RECORDED_KIND" != scout ]; then
    echo "error: task record $META records kind=$RECORDED_KIND, which has no brief scaffold" >&2
    exit 1
  fi
  KIND=$RECORDED_KIND
else
  if [ "$SCOUT" -eq 1 ]; then
    KIND=scout
  else
    [ "$MODE_SET" -eq 1 ] || {
      echo "error: ship briefs require --mode <no-mistakes|direct-PR|local-only>; resolve it at intake and pass it here" >&2
      exit 1
    }
    case "$MODE" in
      no-mistakes|direct-PR|local-only) ;;
      *) echo "error: --mode must be one of no-mistakes, direct-PR, local-only (got '$MODE')" >&2; exit 1 ;;
    esac
  fi
  if [ "$MODE_SET" -eq 1 ] && [ "$SCOUT" -eq 1 ]; then
    echo "error: --mode applies only to ship briefs; a scout delivers a report" >&2
    exit 1
  fi
  REPO=${POS[1]:-}
  [ -n "$REPO" ] || { echo "error: <repo-name> is required for a fresh brief" >&2; exit 2; }
fi

BRIEF="$DATA/$ID/brief.md"
if [ -e "$BRIEF" ] && [ "$RELAUNCH" -ne 1 ]; then
  echo "error: $BRIEF already exists (use --relaunch to regenerate from the task record)" >&2
  exit 1
fi
mkdir -p "$DATA/$ID"

shell_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

STATUS_FILE=$(shell_quote "$STATE/$ID.status")
REPORT_SHELF=$(shell_quote "$STATE/eindri-reports/$ID.md")

# THE HANDOFF DOOR (2026-11-01). The shelf above is where a report goes; this is the door that writes it,
# and the brief names it so the worker does not have to remember a path. A link with no door is a hope.
HANDOFF_CMD="bin/agents/report.sh write $ID --state done|blocked|needs-decision --changed \"<files>\" --verified \"<command → result>\" --not-verified \"<what and why>\" --next \"<one sentence>\" --pointers \"plan:<N> · card:<id>\""
WAKE_QUEUE=$(shell_quote "$STATE/.wake-queue")
INBOX_DIR=$(shell_quote "$STATE/$ID.inbox")
REPORT_FILE="$DATA/$ID/report.md"

INBOX_SECTION=$(cat <<EOF
# Brokk instruction inbox
Brokk steers you through durable message files in $INBOX_DIR.
When a terminal message says an instruction is waiting there - and at any natural checkpoint when you are unsure - list $INBOX_DIR/*.msg, read and act on each message in numeric order, then acknowledge each handled message by moving it: \`mv $INBOX_DIR/NNN.msg $INBOX_DIR/handled/\`.
The move IS the acknowledgement: without it Brokk rings again and eventually treats you as stuck. An empty or absent inbox needs no action.
EOF
)

STATUS_SECTION=$(cat <<EOF
Report status by appending one line:
   \`echo "{state}: {one short line}" >> $STATUS_FILE\`
   States: working, needs-decision, blocked, $PAUSED_VERB, done, failed.
   Each append wakes Brokk, so report sparingly: only phase changes a supervisor
   would act on and the needs-decision/blocked/$PAUSED_VERB/done/failed states.
   A TERMINAL state (done:, failed:, needs-decision:) is ALSO a report. Make the
   terminal act ONE command — it writes the status line, files the report shelf the

**Checkpoint at every boundary.** Before you move from one phase to the next, and before any long step:
`bin/agents/eindri-checkpoint.sh save $ID --step "<what just finished>" --next "<what is next>"`.
The pane is a view; the checkpoint is the record. A restart reads the checkpoint, never your scrollback.
   handoff failsafe sweeps (bin/agents/eindri-handoff.sh), and appends the DURABLE wake
   (state/.wake-queue) so Brokk is woken even with no arm and no sweep running:
      \`bin/agents/eindri-acclaim.sh $ID --terminal done --line "<what shipped and where: PR, path, proof>"\`
   Use \`--terminal failed\` or \`--terminal needs-decision\` as the state; a
   needs-decision files the question shelf ($STATE/eindri-questions/$ID.md) instead.
   Never defer the wake: a report that is not in the queue is a report Brokk may
   never see.
   Use \`$PAUSED_VERB: {why}\` - distinct from \`blocked:\` - ONLY when you are deliberately
   idling on a known external wait you expect to clear on its own (an upstream release,
   a rate-limit reset); use \`blocked:\` when you are stuck and need Brokk to act.
   A mid-task \`working:\` line is nonterminal: do not end the turn after it; continue
   until a defined \`done:\` gate under Definition of done.
   A decision or blocker stays open until a \`resolved\` line carrying its exact key
   lands; a later \`done:\` or \`working:\` line never closes it.
   Silence is distinguished from thinking: a worker that stops appending inside
   the window is reported as SUSPECT (bin/agents/eindri-heartbeat.sh) — keep a line
   moving whenever you make progress.
EOF
)

# The isolation/verification preamble, shared by every brief. herdr is the
# ordinary road; Utgard is named only as the exception with its trigger.
ISOLATION_SETUP=$(cat <<EOF
**herdr is the ordinary road.** Your workspace is created in this worktree; no
container runs. Utgard is the EXCEPTION, chosen only for \`untrusted code\` or an
\`outsized task\` — this errand declares:

$ISOLATION_DECLARATION

(The declaration is not inferred from the task text. A \`utgard\` declaration is
validated by bin/agents/einherjar-spawn.sh against the Utgard image — a declared utgard
with no image is a refusal to launch, never a silent fallback.)

**Verify isolation before anything else.** Run \`pwd -P\` and
\`git rev-parse --show-toplevel\`; both must resolve to this disposable task
worktree (host path .yggdrasil/$ID; under Utgard it appears at /sandbox/workspace),
never the primary checkout Brokk operates from.
The path check is authoritative. If the top-level path is the primary checkout or
not the worktree you were launched in, STOP - do not branch or commit here - append
\`blocked: launched in primary checkout, not an isolated worktree\` to the status
file and stop.
EOF
)

if [ "$KIND" = scout ]; then
  cat > "$BRIEF" <<EOF
You are an Eindri: an autonomous worker agent managed by Brokk. Work on your own; do not wait for the Allfather.

# Task
{TASK}

# Delivery contract
Delivery contract: mode=scout

# Setup
You are in a disposable git worktree of $REPO at .yggdrasil/$ID, at a detached HEAD on a clean default branch.

$ISOLATION_SETUP

This is a SCOUT task: the deliverable is a written report, not a PR.
The worktree is your laboratory - install, run, edit, and make scratch commits freely; all of it is discarded at teardown.
The report is the only thing that survives, so anything worth keeping must be in it.

1. First action: confirm where you stand with \`pwd -P\` and \`git rev-parse --show-toplevel\`.

# Rules
1. Never push to any remote and never open a PR.
2. Stay inside this worktree; the only files you may write outside it are the report and the status file below.
3. $STATUS_SECTION
4. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; Brokk will help.
5. If a decision belongs to the Allfather (product choices, destructive actions), append \`needs-decision: {summary of options}\` and stop. Brokk will reply with the decision.

$INBOX_SECTION

# Definition of done — every gate is a COMMAND; run it and record its output
- \`test -s $REPORT_FILE\` exits 0 (the report exists and is non-empty). Record its size with \`wc -c $REPORT_FILE\`.
- \`grep -E '^(done|recommend|conclusion|findings):' $REPORT_FILE\` finds the stand-alone conclusion — what you did, what you found, the evidence (commands, output, file:line), and what you recommend.
   (A prose judgment "reads well" cannot be a command — read it yourself and say so in the report.)
- Run the terminal act — one command; it files your report shelf and appends the durable wake: \`bin/agents/eindri-acclaim.sh $ID --terminal done --line "{one-line conclusion}"\`.
- \`grep -c "$ID" $WAKE_QUEUE\` prints at least 1 (your wake is in the durable queue).
- Stop.
EOF
  if [ "$RELAUNCH" -eq 1 ]; then
    printf 'scaffolded: %s (scout, relaunch; replace {TASK})\n' "$BRIEF"
  else
    printf 'scaffolded: %s (scout; replace {TASK})\n' "$BRIEF"
  fi
  exit 0
fi

case "$MODE" in
  direct-PR)
    RULE1='Never push to the default branch (push only your `eindri/'"$ID"'` branch). Never merge a PR; the Glitnir human gate owns the merge.'
    DOD_BODY=$(cat <<EOF
# Definition of done — every gate is a COMMAND; run it and record its output
- \`git diff --quiet\` exits 0 (no uncommitted tracked change beyond the scratch you intend to keep).
- \`git push -u origin eindri/$ID\` succeeds — your branch reaches the remote.
- \`gh pr create --fill\` opens the pull request and prints its URL.
- \`gh pr view --json url -q .url\` prints the same URL; record it as the evidence.
   (A prose PR description that "reads well" cannot be a command — read it yourself and say so.)
- Run the terminal act — one command; it writes the status line, files the report shelf, and appends the durable wake:
     \`bin/agents/eindri-acclaim.sh $ID --terminal done --line "opened PR <url>"\`
- \`grep -c "$ID" $WAKE_QUEUE\` prints at least 1 (your wake is in the durable queue; Brokk is woken with no arm and no sweep).
- Stop. Brokk routes the PR to the Glitnir human gate; you never merge.
EOF
)
    ;;
  local-only)
    RULE1="Never push to any remote and never open a PR. Work only on your \`eindri/$ID\` branch; Brokk merges into local \`main\` after the Allfather approves."
    DOD_BODY=$(cat <<EOF
# Definition of done — every gate is a COMMAND; run it and record its output
- \`git branch --show-current\` prints \`eindri/$ID\` (you are on the right branch).
- \`git diff --quiet\` exits 0 (everything committed).
- \`git status --porcelain\` lists only the scratch files you intend to leave; record the list.
- Run the terminal act — one command; it writes the status line, files the report shelf, and appends the durable wake:
     \`bin/agents/eindri-acclaim.sh $ID --terminal done --line "ready in branch eindri/$ID"\`
- \`grep -c "$ID" $WAKE_QUEUE\` prints at least 1 (your wake is in the durable queue).
- Stop. Brokk merges into local \`main\` after the Allfather approves.
EOF
)
    ;;
  *)  # no-mistakes
    RULE1='Never push to the default branch. Never merge a PR; the Glitnir human gate owns the merge.'
    DOD_BODY=$(cat <<EOF
# Definition of done — every gate is a COMMAND; run it and record its output
- \`no-mistakes doctor\` reports the repo is initialized here (run \`no-mistakes init\` first if not).
- \`git push -u origin eindri/$ID\` succeeds — the pipeline branch reaches the remote.
- The \`no-mistakes\` pipeline run prints its PR URL and a status; record both.
- Run the terminal act — one command; it writes the status line, files the report shelf, and appends the durable wake:
     \`bin/agents/eindri-acclaim.sh $ID --terminal done --line "<PR url> (pipeline <status>)"\`
- \`grep -c "$ID" $WAKE_QUEUE\` prints at least 1 (your wake is in the durable queue).
- Stop. Brokk routes the PR to the Glitnir human gate; you never merge.
EOF
)
    ;;
esac

if [ "$MODE" = no-mistakes ]; then
  SETUP_STEP2='
2. Run `no-mistakes doctor`; if it reports the repo is not initialized here, run `no-mistakes init`.'
else
  SETUP_STEP2=""
fi

cat > "$BRIEF" <<EOF
You are an Eindri: an autonomous worker agent managed by Brokk. Work on your own; do not wait for the Allfather.

# Task
{TASK}

# Delivery contract
Delivery contract: mode=$MODE

# Setup
You are in a disposable git worktree of $REPO at .yggdrasil/$ID, at a detached HEAD on a clean default branch.

$ISOLATION_SETUP

1. First action: create your branch: \`git checkout -b eindri/$ID\`$SETUP_STEP2

# Rules
1. $RULE1
2. Stay inside this worktree; modify nothing outside it.
3. $STATUS_SECTION
4. If you hit the same obstacle twice, append \`blocked: {why}\` and stop; Brokk will help.
5. If a decision belongs to the Allfather (product choices, destructive actions), append \`needs-decision: {summary of options}\` and stop. Brokk will reply with the decision.

$INBOX_SECTION

$DOD_BODY
EOF
if [ "$RELAUNCH" -eq 1 ]; then
  printf 'scaffolded: %s (ship, mode=%s, relaunch; replace {TASK})\n' "$BRIEF" "$MODE"
else
  printf 'scaffolded: %s (ship, mode=%s; replace {TASK})\n' "$BRIEF" "$MODE"
fi