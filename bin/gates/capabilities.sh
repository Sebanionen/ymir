#!/usr/bin/env bash

# A GENERATED FILE MUST BE A FUNCTION OF CONTENT ALONE (0.1.94/0.1.95/0.1.97 — three
# reproducibility bugs, all ordering or collation). LC_ALL=C pins the collation of git's
# output, of `sort`, and of grep's character classes; under a UTF-8 locale the same tree
# rendered a different register, which is why CI kept calling a current file stale.
export LC_ALL=C
# capabilities.sh — THE register: what Ymir can do, and the door a caller should use.
#
# WHY (2026-10-01): *"an agent with no tool for a job goes and grabs a random script"*, and of 390
# doors **207** are named where an agent reads them and **185** are exercised by a test — while
# NOTHING maps a JOB to a DOOR. This is the map, and it is GENERATED from what exists, so it
# cannot drift from the tree the way a hand-written register did (twice, in one evening).
#
#   bin/gates/capabilities.sh            # write .agents/assets/agents/capabilities.md
#   bin/gates/capabilities.sh --check    # fail when the register is stale (wired into ci-verify)
set -uo pipefail

# Walk UP until we find the repo, rather than assuming one level. `bin/gates/capabilities.sh` and
# `bin/gates/capabilities.sh` BOTH have to work, and the difference is depth — a fixed `..`
# made the nested copy resolve ROOT to `bin/`, so it looked for `bin/*.sh` inside `bin/`,
# found nothing, and rendered a 2-row register over a 400-door house. Nesting must not be able
# to blind the index. (2026-10-04)
_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}
ROOT="$(_root)"
cd "$ROOT" || exit 2
OUT=".agents/assets/agents/capabilities.md"
MODE="${1:-write}"

# The live signals, taken from the surfaces themselves — never asserted.
shells=$(find bin \( -name '*.sh' -o -name '*.py' \) -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')
pys=$(find src/ymir_runtime -name '*.py' 2>/dev/null | wc -l | tr -d ' ')
skills=$(git -c safe.directory='*' ls-files '.agents/skills/*/SKILL.md' | cut -d/ -f3 | LC_ALL=C sort -u | wc -l | tr -d ' ')
# Enumerate the extension tree the way PI enumerates it (Rule 13 §3): a direct `.ts`,
# or a directory whose entry point is `index.ts`. A flat glob of `*.ts` stopped seeing
# ro/, constellation/ and skuld-branch-supervision/ the moment they became folders,
# and the register silently UNDERCOUNTED by eight tools — which is worse than being
# stale, because a stale register fails a gate and a wrong one does not.
tools=$(find .pi/shared/extensions -type f -name '*.ts' -not -name '*.test.ts' 2>/dev/null \
          | xargs -r grep -hoE 'pi\.registerTool\(\{|name: "[a-z_]+"' 2>/dev/null \
          | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u | wc -l | tr -d ' ')

# Resolved ONCE, from TRACKED files only, for the same reason as bin/gates/inventory.sh: a
# verdict computed from the working tree is a verdict about THIS MACHINE. The untracked
# skill directory `.agents/skills/skillopt-staging/` exists here and not in git, and it
# alone flipped `named=no` to `named=yes` for test_paths and test_grants — so CI read a
# different register than the machine that generated it, and correctly called it stale.
# file <TAB> verdict, read out of the inventory's TOON rows (quoted fields).
INVENTORY_MAP="$(mktemp)"; trap 'rm -f "$INVENTORY_MAP"' EXIT
if [ -r bin/README.md ]; then
  python3 - bin/README.md >"$INVENTORY_MAP" <<'PYVERDICT'
import csv, sys
for row in csv.reader(open(sys.argv[1])):
    if len(row) < 4:
        continue
    # Rows are INDENTED, so csv hands back '  "a2a-serve.sh"' — which ends with a quote, not
    # with ".sh". An unguarded endswith() therefore matched NOTHING and every door read as
    # untested: 178 false "undecided" rows from one missing strip(). Strip first, ask second.
    name = row[0].strip().strip('"')
    if name.endswith((".sh", ".py")):
        print(f"{name}\t{row[3].strip().strip(chr(34))}")
PYVERDICT
fi

NAMING_FILES=$(git -c safe.directory='*' ls-files '.agents/skills/*/SKILL.md' '.agents/skills/*/assets/*.md' AGENTS.md | tr '\n' ' ')

# TRACKED, once. A verdict read out of the working tree is a verdict about THIS MACHINE:
# `__pycache__/test_grants.cpython-314.pyc` CONTAINS the string 'test_grants', so a local
# run of the suite made `tested=yes` for a module whose tracked tests never mention it —
# and CI, which has no bytecode, read `no` and correctly called the register stale.
# Compiled artefacts are not evidence. Everything a verdict rests on must be in the commit.
AGENT_TEST_FILES=$(git -c safe.directory='*' ls-files '.agents/tests/*' | tr '\n' ' ')
PY_TEST_FILES=$(git -c safe.directory='*' ls-files 'src/ymir_runtime/tests/*' | tr '\n' ' ')

# An empty tracked list is not a normal state — it means git refused the listing (CI
# checkouts are often owned by another user) and every verdict below would silently
# become `no`. Say so, once, loudly.
if [ -z "${AGENT_TEST_FILES:-}" ]; then
  echo "capabilities: git ls-files returned NOTHING — verdicts would all read 'no'." >&2
  echo "  (on CI this is usually git's dubious-ownership refusal; safe.directory is set, so check git works here)" >&2
fi

emit() {
# The heredoc is QUOTED. Unquoted, its own ``` fence and inline backticks paired ACROSS lines, so
# bash ran the register's own text as a command substitution ("capabilities[5]surface:: command not
# found" on stderr for years), leaving an EMPTY block in the written file — and under CI's `bash -e`
# it could end the script before its verdict, reporting a current register as a failed gate.
# Nothing inside expands now; every value the header needs is printed by the printf below.
cat <<'EOM'
# What Ymir can do — the capability register

**GENERATED by `bin/gates/capabilities.sh`. Do not hand-edit: run it, and commit the result.**
`bin/gates/capabilities.sh --check` fails when this file and the tree disagree.

**The law this exists to enforce:** *if a job is not a row here, no agent may improvise a script
for it* — an unlisted job is an **open row**, not a new `bin/whatever.sh`. That is the answer to
the register becoming a to-do list twice, and to 390 doors with no name for the work.

## 1 · The doors, by the job they serve

EOM

printf 'capabilities[5]{surface,count}:\n  "shell doors (bin/*.sh)",%s\n  "runtime modules (src/ymir_runtime/*.py)",%s\n  "skills (.agents/skills/*)",%s\n  "Pi extension tools",%s\n  "generated","%s"\n\n' "$shells" "$pys" "$skills" "$tools" "$(date -u +%Y-%m-%d)"
printf '| door | the job | verdict | tech decision |\n|---|---|---|---|\n'
# READDIR ORDER IS NOT AN ORDER. `for f in bin/*.sh` yields whatever the filesystem
# returns first — ext4 hashes it, overlayfs in CI does not — so two machines built the
# SAME register with the SAME rows in a DIFFERENT order, and the staleness check (rightly)
# called it stale. Sorting makes the register a function of CONTENT alone.
# A TEMPLATE IS CONTENT, NOT A DOOR. `bin/collab/kit/` holds the collaboration kit — fifteen files
# COPIED into other repositories (the gates, hooks and tools a repository is given). Registering them
# here claimed Ymir runs them and, worse, invited the register to "move or retire" a shipped template
# (Rule 11) — every row read `keep (a human or a cron row must run it)` about a file Ymir never runs.
# They are indexed by bin/README.md as what they are; the capacity register answers "what can Ymir do".
for f in $(find bin -name '*.sh' -not -path '*/.git/*' -not -path 'bin/collab/kit/*' 2>/dev/null | LC_ALL=C sort); do
  n=$(basename "$f")
  case "$n" in inventory.sh|capabilities.sh|queue.sh|update-notes.sh|verify-seat.sh) continue ;; esac
  # the first sentence of its own header is the job, from the door itself
  job=$(sed -n '2,12p' "$f" | grep -m1 -E '^#' | sed 's/^# \{0,1\}//' | cut -c1-72)
  [ -z "$job" ] && job="(no header line)"
  # `tested` is NOT recomputed here. Two generators each deciding the same question is how one
  # register reported 188 doors tested while the other reported 115 and declared 64
  # "undecided" — a disagreement dressed as a fact. bin/gates/inventory.sh OWNS the verdict; this
  # register reads it, and owns only what inventory cannot know: whether a SKILL names it.
  # USED, not merely tested. The inventory's `wired` means something CALLS this file, which is
  # use by definition — the house's two honest answers (name it, or move it) only apply to a
  # file that nothing exercises and nothing names. A door called by another door is alive.
  tested=no
  grep -qE "^${n}$(printf "\t")(tested|wired)$" "$INVENTORY_MAP" 2>/dev/null && tested=yes
  named=no
  for _nf in $NAMING_FILES; do
    [ -f "$_nf" ] || continue
    grep -qlF "$n" "$_nf" 2>/dev/null && { named=yes; break; }
  done
  v="uncalled"; [ "$tested" = yes ] && v="tested"; [ "$named" = yes ] && v="${v}+named"
  d="keep (a human or a cron row must run it)"
  [ "$tested" = no ] && [ "$named" = no ] && d="**decide** — unnamed and untested: move it to src/ or hodd/reference/ (Rule 11), never delete"
  printf '| %s | %s | %s | %s |\n' "$n" "$job" "$v" "$d"
done

printf '\n## 1b · The engine — src/ymir_runtime/*.py (the part a bin-only register skipped)\n\n'
printf '| module | what it owns | tested | reachable from a door |\n|---|---|---|---|\n'
for f in $(find src/ymir_runtime -name '*.py' ! -name '__init__.py' | LC_ALL=C sort); do
  m=$(basename "$f" .py)
  # the first docstring line is what the module says it owns — read, not asserted
  owns=$(python3 - "$f" <<'PYD' 2>/dev/null || true
import ast,sys
try:
    t=ast.parse(open(sys.argv[1]).read())
    d=ast.get_docstring(t) or ""
    print(" ".join(d.strip().splitlines()[:1])[:70] if d else "(no docstring)")
except Exception:
    print("(unreadable)")
PYD
)
  # The inventory's map covers bin/ and the backend shelf; it does NOT list runtime modules,
  # so pointing this lookup at it reported every module untested (16 rows, all `no`, while
  # src/ymir_runtime/tests/ holds 21 files). A python module is tested when a python test
  # names it — that question belongs to the python tests, not to the shell door index.
  # A TEST FILE IS THE TEST. The lookup asked only whether some OTHER test names this module,
  # so the eleven `test_*.py` files were reported untested — the eleven files whose entire
  # job is to test. Ask the cheap question first: is this file itself a test?
  tested=no
  case "$f" in
    */test_*.py|*/*_test.py|*/tests/*) tested=yes ;;
  esac
  if [ "$tested" = no ]; then
    for _tf in $PY_TEST_FILES; do
      [ -f "$_tf" ] || continue
      grep -qlF "$m" "$_tf" 2>/dev/null && { tested=yes; break; }
    done
  fi
  reach=no;   grep -qlr "ymir_runtime" bin/ 2>/dev/null && reach="yes (bin/ imports the engine)"
  printf '| `%s` | %s | %s | %s |\n' "$m" "$owns" "$tested" "$reach"
done

# THE INSIDE OF A HEREDOC IS NOT A SCRIPT. This block used to run a command
# substitution INSIDE an unquoted heredoc, whose escaping of backticks is then re-parsed
# by the outer shell — bash answered `bad substitution: no closing "\`"` on line 178 and
# the whole capability register could not be generated, so `capabilities --check` failed
# forever and CI could not pass (measured 2026-10-24, PR 423's failing gates job).
# Compute the list here, in real code, and interpolate the result.
ext_tools="$(grep -rhoE 'name: "[a-z_]+"' .pi/shared/extensions/ymirhome.ts 2>/dev/null \
  | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u | while read -r t; do printf -- '- `%s`\n' "$t"; done)"

printf "\n## 2 · The extension's own tools (registered once, by the door)\n\n%s\n" "$ext_tools"
cat <<'EOM'

## 2 · The extension's own tools (registered once, by the door)



**One tool, ONE registration.** Another extension imports the shared lib; it never re-registers
a tool another already registers (plan 66 Part 8, register §12).

## 3 · The uncovered jobs — where a new script would otherwise appear

Anything **uncalled** in §1 is a job with no door an agent can find. Two honest answers, never a
third:
1. **it is a real capability** → add a row here with its door and its tech decision, or
2. **it is retired** → move the file to `hodd/reference/` and say why (Rule 11).

## 4 · The rule for new work

```
one_capability[4]{rule,means}:
  "one name","a capability has ONE name and ONE door; two doors is a bug the seat check names"
  "thin doors","the door calls bin/ so a human and a cron row run the same thing"
  "state before content","a door may be 1 line; anything with parsing or state moves to src/"
  "no unlisted scripts","a new bin/*.sh needs a row here, or it does not ship"
```
EOM
}

TMP="$(mktemp)"
# The header is an UNQUOTED heredoc, so its own body is interpreted and a few of its lines
# exit non-zero ("capabilities[5]surface:: command not found" — visible on stderr for years).
# Under CI's `bash -e` that made THIS LINE the last one to run: the script died here and
# never reached its own verdict, so a CURRENT register reported as a FAILED gate. So do not
# inherit the incidental status — assert the postcondition instead: a register was written,
# and it has rows. (Quoting the heredoc is the proper fix and is still owed.)
emit > "$TMP" || true
if [ ! -s "$TMP" ]; then
  echo "capabilities: emit produced NOTHING — the register cannot be built" >&2
  rm -f "$TMP"; exit 1
fi
if [ "$MODE" = "--check" ]; then
  if [ ! -f "$OUT" ] || ! diff -q "$OUT" "$TMP" >/dev/null 2>&1; then
    echo "capabilities --check: $OUT is STALE — run bin/gates/capabilities.sh" >&2
    echo "capabilities_check[2]{diff,first_lines}:" >&2
    diff "$OUT" "$TMP" 2>/dev/null | head -12 | sed "s/^/  /" >&2 || true
    echo "  (if the diff is only counts or verdicts, the cause is usually an input CI does not have — a vault file, an untracked skill, a .pyc)" >&2
    rm -f "$TMP"; exit 1
  fi
  echo "capabilities --check: current ($(grep -c '^| ' "$OUT") door rows)"
  rm -f "$TMP"; exit 0
fi
mkdir -p "$(dirname "$OUT")"; cp "$TMP" "$OUT"; rm -f "$TMP"
echo "wrote $OUT — $(grep -c '^| ' "$OUT") door rows"
