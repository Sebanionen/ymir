#!/usr/bin/env bash
# pr-seal.sh — the seat's own PR is sealed by the seat, and the word arrives through Gná.
#
# The Allfather's word (plan 190 §1): *"The arm holder ALWAYS NEED TO GET A
# NOTIFICATION IN THRU THE ARM on when a PR are done. And merge that PR directly.
# Otherwise main will move and merge will have conflicts."*
#
# The reversal is narrow, and the narrowness is the safety. A PR is sealed by THIS
# seat only when all six conditions hold (RULES/08, its 2026-11-05 amendment):
#
#   1 whose PR     the SEAT'S OWN — opened by this seat or an Eindri it dispatched.
#                  Another hand's PR is NEVER merged here.
#   2 what state   CI green, and no conflicts
#   3 who          the seat's agent (Sindri on nidavellir, Hœnir on heimdall) —
#                  never a worker, never a timer alone: the arm wakes the seat
#   4 one open PR  this seat has exactly ONE open PR, and it is this one
#   5 the record   one Runes entry naming PR, head and merge commit
#   6 the brake    state/.seal-hold absent
#
# Usage:
#   pr-seal.sh watch [--quiet]   judge every open PR by this credential; for each
#                                PR that holds 1–4 and 6, raise ONE wake line into
#                                state/.wake-queue naming the PR, its head, its
#                                checks and the exact merge command
#   pr-seal.sh seal <n>          re-check all six IMMEDIATELY, then
#                                gh pr merge <n> --squash --delete-branch,
#                                carve one Runes entry, print the merge commit
#
# Exit: 0 judged / sealed · 1 a condition failed or gh failed (the finding is
# printed and named) · 2 usage · 3 something is ready and the seat must act.
#
# It never retries blindly: a refusal names the failing condition and stops. The
# wake is idempotent per (PR, head sha) — the flood brake this house already paid
# for — so a second `watch` in the same minute raises nothing new.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  for _c in "$SCRIPT_DIR/../vault/hoard-lib.sh" "$SCRIPT_DIR/hoard-lib.sh"; do
    [ -r "$_c" ] && { . "$_c"; YMIR_HOARD_LIB_LOADED=1; break; }
  done
  unset _c
fi
hoard_state_dir YMIR_STATE_DIR
# The brake, the wake queue and the seat's own records are the HOUSE's, never the
# harness's private machine-state: BROKK_STATE_OVERRIDE points at pi's continuity
# dir, where no `.seal-hold` could ever be found (and no wake ever drained).
STATE="$YMIR_STATE_DIR"
ROOT="${BROKK_ROOT_OVERRIDE:-$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)}"
HOLD="$STATE/.seal-hold"
QUEUE="$STATE/.wake-queue"
SEEN_DIR="$STATE/pr-seal-seen"
RUNES="$SCRIPT_DIR/../records/runes-append.sh"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help|"") sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
ACTION="${1:-watch}"; shift || true

# --- who is this seat? -------------------------------------------------------
# The roster renders it at install and every update; it is read, never guessed.
seat_identity() {  # fills SEAT_PRIMARY and SEAT_HOST
  local f="$HOME/.pi/agent/extensions/.ymir-seat"
  SEAT_PRIMARY=""; SEAT_HOST="${YMIR_HOST:-$(hostname -s 2>/dev/null || echo unknown)}"
  if [ -r "$f" ]; then
    SEAT_PRIMARY="$(sed -n 's/^primary=//p' "$f" | head -1)"
    SEAT_HOST="$(sed -n 's/^host=//p' "$f" | head -1)"
  fi
  [ -n "$SEAT_PRIMARY" ] || SEAT_PRIMARY=unnamed
  [ -n "$SEAT_HOST" ] || SEAT_HOST=unnamed
}
seat_identity

# --- the judgement, in one reader -------------------------------------------
# Input: the JSON of one `gh pr list|view --json …` record. Output, one line:
#   <number>\t<head>\t<sha>\t<own|other:reason>\t<green|red:names>\t<mergeable>\t<url>
# The rules are here and nowhere else, so `watch` and `seal` cannot disagree
# about whether a PR may be sealed.
judge_py() {  # <json-file> — the gh record, read from a file so stdin stays free
  python3 - "$SEAT_HOST" "$SEAT_PRIMARY" "$STATE" "$1" "$ROOT" <<'PY'
import json, os, re, subprocess, sys

host, primary, state, path, root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
with open(path) as fh:
    raw = json.load(fh)
prs = raw if isinstance(raw, list) else [raw]
OK = {"SUCCESS", "NEUTRAL", "SKIPPED"}

def own(pr):
    body = pr.get("body") or ""
    pats = [rf"^\s*Arm:\s*{re.escape(host)}\s*$", rf"^\s*Arm:\s*{re.escape(primary)}@{re.escape(host)}\s*$"]
    for line in body.splitlines():
        for p in pats:
            if re.match(p, line, re.I):
                return True, f"marked Arm: {host}"
    head = pr.get("headRefName") or ""
    if head.startswith("eindri/"):
        eid = head[len("eindri/"):].split("/")[0]
        if eid and os.path.exists(os.path.join(state, eid + ".meta")):
            return True, f"an errand this seat dispatched ({head})"
    # Every agent shares the operator's GitHub login, so authorship cannot decide
    # ownership: a branch that exists in THIS clone is this seat's own work; one
    # that arrived only as a peer's remote ref is not. Cheap, and it fails closed.
    if head:
        try:
            rc = subprocess.run(["git", "-C", root, "show-ref", "--verify", "--quiet", "refs/heads/" + head],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
            if rc == 0:
                return True, f"a branch of this clone ({head})"
        except Exception:
            pass
    return False, "no Arm marker, no errand of this seat, and no local branch — another hand's PR"

def checks(pr):
    roll = pr.get("statusCheckRollup") or []
    if not roll:
        return False, "no checks reported"
    bad, names = False, []
    for c in roll:
        kind = c.get("__typename")
        if kind == "StatusContext":
            st = (c.get("state") or "").upper()
            if st not in ("SUCCESS",):
                bad = True; names.append(f"{c.get('context') or '?'}={st.lower()}")
        else:
            st = (c.get("status") or "").upper()
            con = (c.get("conclusion") or "").upper()
            if st != "COMPLETED" or con not in OK:
                bad = True; names.append(f"{c.get('name') or '?'}={con.lower() or st.lower()}")
    if bad:
        return False, ", ".join(names)
    return True, ", ".join((c.get("name") or c.get("context") or "?") for c in roll)

def merge(pr):
    """No CONFLICT is the condition; drought of nothing else is invented here.

    CONFLICTING/DIRTY is a conflict. BLOCKED (branch protection), DRAFT and an
    UNKNOWN mergeable are refusals too — a merge GitHub will reject is not a seal.
    BEHIND is NOT a conflict: the base moving is the very reason this law exists,
    and refusing it would make the seal impossible in a busy repo.
    """
    m = pr.get("mergeable") or "UNKNOWN"
    s = pr.get("mergeStateStatus") or "UNKNOWN"
    if m in ("CONFLICTING",):
        return False, f"mergeable={m}"
    if s in ("DIRTY", "BLOCKED", "DRAFT"):
        return False, f"mergeStateStatus={s}"
    if m == "UNKNOWN" or s == "UNKNOWN":
        return False, f"mergeable={m}/mergeStateStatus={s} (GitHub has not decided yet)"
    return True, f"{m}/{s}"

for pr in prs:
    is_own, why_own = own(pr)
    green, why_ci = checks(pr)
    ok_merge, why_merge = merge(pr)
    print("\t".join([
        str(pr.get("number") or "?"),
        pr.get("headRefName") or "?",
        (pr.get("headRefOid") or "")[:12] or "?",
        ("own:" + why_own) if is_own else ("other:" + why_own),
        ("green:" + why_ci) if green else ("red:" + why_ci),
        ("clean:" + why_merge) if ok_merge else ("conflict:" + why_merge),
        pr.get("url") or "",
    ]))
PY
}

hold_reason() {  # 0 when held (prints why), 1 when the brake is clear
  [ -e "$HOLD" ] || return 1
  printf '%s' "$(head -3 "$HOLD" 2>/dev/null | tr '\n' ' ')"
  return 0
}

# --- the Runes entry, carved once per seal ----------------------------------
carve_runes() {  # <n> <head> <sha> <merge-commit>
  if [ ! -x "$RUNES" ]; then
    printf 'error: the ledger door %s is missing — a seal with no Runes entry is not a seal\n' "$RUNES" >&2
    return 1
  fi
  "$RUNES" "$SEAT_PRIMARY@$SEAT_HOST" pr-seal --message \
    "sealed PR #$1 (head $2 at $3) -> merge commit $4, through the arm: eyes pr-seal.sh seal" >/dev/null
}

# --- watch ------------------------------------------------------------------
watch() {
  local quiet=0 rows row num head sha own_v ci_v merge_v url own_ok ci_ok merge_ok tmp
  local own_count=0 ready=0 hold=""
  for a in "$@"; do [ "$a" = "--quiet" ] && quiet=1; done
  command -v gh >/dev/null 2>&1 || { printf 'error: gh is not installed — the PR list cannot be read\n' >&2; return 1; }
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  if ! (cd "$ROOT" && gh pr list --author @me --state open \
      --json number,headRefName,headRefOid,title,url,mergeable,mergeStateStatus,statusCheckRollup,body >"$tmp" 2>/dev/null); then
    printf 'error: could not read the open PRs (gh pr list failed)\n' >&2
    return 1
  fi
  rows="$(judge_py "$tmp")"
  rows="$(printf '%s\n' "$rows" | grep -v '^[[:space:]]*$' || true)"
  if [ -z "$rows" ]; then
    [ "$quiet" = 1 ] || printf 'pr-seal[1]{finding,detail}:\n  "no open PR","this credential authors none — nothing to seal"\n'
    return 0
  fi
  hold="$(hold_reason || true)"
  # the one-open-PR count is measured ONCE, before any verdict is printed
  while IFS=$'\t' read -r num head sha own_v ci_v merge_v url; do
    case "$own_v" in own:*) own_count=$((own_count + 1)) ;; esac
  done <<<"$rows"

  printf 'pr-seal[%s]{pr,head,ci,merge,verdict}\n' "$(printf '%s\n' "$rows" | grep -c .)"
  while IFS=$'\t' read -r num head sha own_v ci_v merge_v url; do
    [ -n "$num" ] || continue
    own_ok=0; ci_ok=0; merge_ok=0
    case "$own_v" in own:*) own_ok=1 ;; esac
    case "$ci_v" in green:*) ci_ok=1 ;; esac
    case "$merge_v" in clean:*) merge_ok=1 ;; esac
    local verdict why
    if [ "$own_ok" = 0 ]; then
      verdict="NOT OURS"; why="${own_v#other:}"
    elif [ -n "$hold" ]; then
      verdict="HELD"; why="state/.seal-hold: $hold"
    elif [ "$ci_ok" = 0 ]; then
      verdict="RED"; why="${ci_v#red:}"
    elif [ "$merge_ok" = 0 ]; then
      verdict="CONFLICTED"; why="${merge_v#conflict:}"
    elif [ "$own_count" -gt 1 ]; then
      verdict="QUEUE"; why="this seat has $own_count open PRs — the one-open-PR rule refuses a second seal"
    else
      verdict="SEAL"; why="all six conditions hold — the seat merges now"
    fi
    printf '  "%s","%s","%s","%s","%s"\n' "#$num" "$head" "${ci_v%%:*}" "${merge_v%%:*}" "$verdict"
    if [ "$verdict" = "SEAL" ]; then
      local marker="$SEEN_DIR/$num.$sha"
      if [ -e "$marker" ]; then
        [ "$quiet" = 1 ] || printf '  wake: already raised for #%s at %s — one wake per head\n' "$num" "$sha"
      else
        mkdir -p "$SEEN_DIR" 2>/dev/null || true
        printf 'PR #%s (%s at %s) is green and conflict-free — the seat seals it now: bin/agents/pr-seal.sh seal %s\n' \
          "$num" "$head" "$sha" "$num" >>"$QUEUE"
        printf 'pr-seal-wake: PR #%s head %s checks %s merge %s cmd "bin/agents/pr-seal.sh seal %s"\n' \
          "$num" "$head" "${ci_v#green:}" "${merge_v#clean:}" "$num" >>"$SEEN_DIR/$num.$sha"
        ready=$((ready + 1))
      fi
    else
      [ "$quiet" = 1 ] || printf '  why: #%s %s\n' "$num" "$why"
    fi
  done <<<"$rows"
  [ "$ready" -gt 0 ] && return 3
  return 0
}

# --- seal -------------------------------------------------------------------
seal() {
  local n=${1-} json rows own_v ci_v merge_v num head sha url hold own_count tmp own_tmp
  [ -n "$n" ] || { printf 'error: seal needs a PR number\nhelp: pr-seal.sh seal <n>\n' >&2; return 2; }
  case "$n" in ''|*[!0-9]*) printf 'error: <%s> is not a PR number\n' "$n" >&2; return 2 ;; esac
  command -v gh >/dev/null 2>&1 || { printf 'error: gh is not installed\n' >&2; return 1; }

  if hold="$(hold_reason)"; then
    printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","the brake","state/.seal-hold is present: %s"\n' "$n" "$hold"
    printf 'seal-refused: the seat merges nothing while state/.seal-hold exists — remove it only by the Allfather'"'"'s word\n' >&2
    return 1
  fi

  tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  if ! (cd "$ROOT" && gh pr view "$n" \
      --json number,headRefName,headRefOid,title,url,mergeable,mergeStateStatus,statusCheckRollup,body >"$tmp" 2>/dev/null); then
    printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","unknown PR","gh pr view failed — nothing was merged"\n' "$n"
    return 1
  fi
  rows="$(judge_py "$tmp")" || { printf 'error: the PR record could not be judged\n' >&2; return 1; }
  IFS=$'\t' read -r num head sha own_v ci_v merge_v url <<<"$rows"

  case "$own_v" in
    own:*) ;;
    *) printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","not ours","%s"\n' "$n" "${own_v#other:}"
       printf 'seal-refused: another hand'"'"'s PR is that hand'"'"'s to tend — this seat never merges it\n' >&2
       return 1 ;;
  esac

  # the one-open-PR rule, counted at the same instant as the seal
  own_tmp="$(mktemp)"
  (cd "$ROOT" && gh pr list --author @me --state open --json number,headRefName,body >"$own_tmp" 2>/dev/null) || true
  own_count="$(judge_py "$own_tmp" | awk -F'\t' '$4 ~ /^own:/ {n++} END{print n+0}')"
  rm -f "$own_tmp"
  if [ "${own_count:-0}" -gt 1 ]; then
    printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","one-open-PR","this seat has %s open PRs — seal or clear the others first"\n' "$n" "$own_count"
    return 1
  fi

  case "$ci_v" in
    green:*) ;;
    *) printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","CI not green","%s"\n' "$n" "${ci_v#red:}"
       printf 'seal-refused: a red PR is never merged, under any flag\n' >&2
       return 1 ;;
  esac
  case "$merge_v" in
    clean:*) ;;
    *) printf 'seal-refused[1]{pr,condition,detail}:\n  "#%s","conflicts","%s"\n' "$n" "${merge_v#conflict:}"
       printf 'seal-refused: a conflicted PR is never merged — rebase it first\n' >&2
       return 1 ;;
  esac

  printf 'sealing[1]{pr,head,sha,checks}:\n  "#%s","%s","%s","%s"\n' "$n" "$head" "$sha" "${ci_v#green:}"
  if ! (cd "$ROOT" && gh pr merge "$n" --squash --delete-branch >/dev/null 2>&1); then
    printf 'seal-failed[1]{pr,detail}:\n  "#%s","gh pr merge did not succeed — nothing was claimed; read the PR and retry by hand"\n' "$n" >&2
    return 1
  fi
  local merge_commit=""
  merge_commit="$(cd "$ROOT" && gh pr view "$n" --json mergeCommit -q '.mergeCommit.oid' 2>/dev/null | tr -d '[:space:]')"
  [ -n "$merge_commit" ] || merge_commit=unknown
  carve_runes "$n" "$head" "$sha" "$merge_commit" || printf 'warn: PR #%s merged, but the Runes entry could not be carved — record it by hand\n' "$n" >&2
  printf 'sealed[1]{pr,head,merge_commit}:\n  "#%s","%s","%s"\n' "$n" "$head" "$merge_commit"
  printf '%s\n' "$merge_commit"
  return 0
}

case "$ACTION" in
  watch) watch "$@" ;;
  seal) seal "${1-}" ;;
  *) printf 'error: unknown action %s (watch|seal)\nhelp: pr-seal.sh watch | pr-seal.sh seal <n>\n' "$ACTION" >&2; exit 2 ;;
esac
exit $?
