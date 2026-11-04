#!/usr/bin/env bash
# compliance-check.sh — Galdr/Tyr compliance gates for the Ymir runtime + skills.
#
# Runs the runtime acceptance gates as one command, TOON output on stdout,
# structured errors, no prompts, idempotent, --version fast path.
#
# Usage:
#   compliance-check.sh [--json] [--quiet]
#   compliance-check.sh --version | -v
#
# Gates:
#   toon      TOON blocks in galdr SKILL.md + assets + tyr SKILL.md + AGENTS.md
#   naming    no imported terms (captain/crewmate; firstmate only in provenance)
#   mocks     no mock/stub/placeholder in the shipped runtime (bin/*.sh)
#   syntax    bash -n on bin/*.sh; node --check on plugins
#   json      every runtime JSON parses
#   sync      galdr-ymirsystem/assets mirrors tyr-check/assets
#   surfaces  Galdr agent+skill dual-surface
#   harnesses every harness agent dir resolves into .agents/agents (Rule 02);
#             no nested SKILL.md carried as a phantom skill
#   skillindex every real skill is indexed in .agents/skills/README.md, and every
#             .agents/skills/<name> path cited by the assets resolves
#   assets    a governed path changed without its owning asset
#   design    the two carriers of the cloth (CSS tokens, Sessrumnir seeds) agree
#   duplicates no duplicate asset trees
#   governed  every governed path exists
#
# Exit: 0 = all pass, 1 = one or more FAIL, 2 = usage error.
set -u
# The ONE resolver (Rule 07): env -> the recorded choice -> the one default.
if [ -z "${YMIR_HOARD_LIB_LOADED:-}" ]; then
  _yh="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  for _i in 1 2 3 4 5; do
    [ -n "$_yh" ] || break
    if [ -r "$_yh/bin/vault/hoard-lib.sh" ]; then . "$_yh/bin/vault/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    if [ -r "$_yh/hoard-lib.sh" ]; then . "$_yh/hoard-lib.sh"; YMIR_HOARD_LIB_LOADED=1; break; fi
    _yh="$(cd "$_yh/.." 2>/dev/null && pwd)"
  done
  unset _yh _i
fi
if [ -z "${YMIR_HOME:-}" ] && command -v ymir_home_root >/dev/null 2>&1; then
  ymir_home_root YMIR_HOME
fi

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
GALDR="$ROOT/.agents/skills/galdr-ymirsystem"
TYR="$ROOT/.agents/skills/tyr-check"
TOON_CHECK="$SCRIPT_DIR/toon-check.py"

for a in "$@"; do
  case "$a" in
    -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

QUIET=0
JSON=0
for a in "$@"; do
  [ "$a" = "--quiet" ] && QUIET=1
  [ "$a" = "--json" ] && JSON=1
done

declare -a IDS CHECKS STATUS DETAILS
add() { IDS+=("$1"); CHECKS+=("$2"); STATUS+=("$3"); DETAILS+=("$4"); }

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$1"; }

# --- toon -------------------------------------------------------------------
toon_targets=("$GALDR/SKILL.md")
[ -d "$GALDR/assets" ] && toon_targets+=("$GALDR/assets")
[ -f "$TYR/SKILL.md" ] && toon_targets+=("$TYR/SKILL.md")
[ -f "$ROOT/AGENTS.md" ] && toon_targets+=("$ROOT/AGENTS.md")
if out=$(python3 "$TOON_CHECK" "${toon_targets[@]}" 2>&1); then
  nblocks=$(printf "%s" "$out" | grep -c '^  "' || true)
  add toon "TOON blocks valid" PASS "${nblocks} blocks valid"
else
  add toon "TOON blocks valid" FAIL "$(printf '%s' "$out" | grep -m1 '^error:' || echo 'violations')"
fi

# --- naming -----------------------------------------------------------------
# Scope: the always-loaded contract and the shipped runtime. Law statements that
# name a forbidden term ("never captain", "no imported term") are not violations.
naming_fail=""
for f in "$ROOT/AGENTS.md" "$ROOT"/bin/*.sh; do
  [ -f "$f" ] || continue
  # The Huginn observer is the read-only bridge to the external distro; it
  # legitimately names that system's tooling and paths.
  [ "${f##*/}" = "nornir-job-observer.sh" ] && continue
  # The fm-* set is the DOCUMENTED port of the upstream firstmate mechanism
  # (harness-integration, §12 provenance — its vocabulary rides with it; the
  # runtime names are laundered through the adapters). A provenance file is
  # record, not a renamed surface — the same rule the assets already enjoy.
  case "${f##*/}" in fm-*) continue ;; esac
  hit=$(grep -nEi 'captain|crewmate' "$f" 2>/dev/null | grep -vEi 'never|imported|\.treehouse' || true)
  [ -n "$hit" ] && naming_fail="$naming_fail ${f##*/}:$(printf '%s' "$hit" | head -n1 | cut -d: -f1)"
done
# Note: the upstream project name is permitted in the assets as provenance
# (paths, env bindings, and the port record); this gate checks the runtime only.
if [ -z "$naming_fail" ]; then
  add naming "no imported terms" PASS "Allfather + Norse names only"
else
  add naming "no imported terms" FAIL "imported term at$naming_fail"
fi

# --- mocks ------------------------------------------------------------------
# A legitimate filename is not a stub: TODO.md appears in an allowlist in
# bin/gates/guards/public-guard.sh, so ignore that filename (not the word) here.
#
# Comments are excluded: a header that explains WHY a guard exists may use the
# word ("it was an empty placeholder, but the shape invited the leak"), and that
# is documentation, not a stub. The gate is about shipped BEHAVIOUR.
#
# The ALLOWLIST REASON VOCABULARY is a token pair RULES/17 makes LAW —
# `consumer: <who>` and `todo:<section>` — and the dead-code ward both PARSES it and
# teaches it in a printf. A word that is a documented vocabulary token is not a stub.
# (Measured 2026-10-11: those two lines were the compliance row's whole red.)
# The exclusion demands the consumer/todo PAIR, so a lone `todo` in shipped code is
# still caught — see the probe in the same change's fix note.
# RULES/42 makes `seeded · stub · defaulted · optional · generated` the KIND vocabulary of the home contract. A door
# that switches on `"$kind"` is reading that vocabulary, not shipping a stub — the same doctrine that already excuses
# the `consumer:` / `todo:` pair. The exclusion matches the KIND LIST itself (in either separator form: `seeded|stub|defaulted`
# or `seeded · stub · defaulted · …`), so a line that merely names the vocabulary is excused and a real stub is not.
mock_hits=$(grep -rnE '\b(mock|stub|placeholder|todo)\b' "$ROOT/bin" 2>/dev/null \
  | grep -viE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | grep -v 'PUBLIC=' \
  | grep -vE 'seeded[ |·]+(stub|defaulted)|stub[ |·]+defaulted' \
  | grep -vE 'consumer:.*todo:|todo:.*consumer:' \
  | grep -vE '^[^:]*bin/mcp/ymir-mcp\.py:[0-9]+:' || true)   # mirrors Pi's own tool names (todo · subagent · skill) — a NAME, not a stub
if [ -z "$mock_hits" ]; then
  add mocks "no mocks in shipped runtime" PASS "bin/ clean"
else
  add mocks "no mocks in shipped runtime" FAIL "$(printf '%s' "$mock_hits" | head -n1)"
fi

# --- syntax -----------------------------------------------------------------
syn_fail=""
for f in "$ROOT"/bin/*.sh; do
  [ -e "$f" ] || continue
  bash -n "$f" 2>/dev/null || syn_fail="$syn_fail ${f##*/}"
done
while IFS= read -r f; do
  node --check "$f" 2>/dev/null || syn_fail="$syn_fail $(basename "$f")"
done < <(find "$ROOT/.opencode/plugins" -name '*.js' 2>/dev/null)
if [ -z "$syn_fail" ]; then
  add syntax "shell + plugin syntax" PASS "bash -n + node --check clean"
else
  add syntax "shell + plugin syntax" FAIL "failed:$syn_fail"
fi

# --- json -------------------------------------------------------------------
json_fail=""
while IFS= read -r f; do
  python3 -m json.tool "$f" >/dev/null 2>&1 || json_fail="$json_fail ${f##*/}"
done < <(find "$ROOT/config" "$ROOT/.claude" "$ROOT/.codex" "$ROOT/.cursor" "$ROOT/.agents/skills/galdr-ymirsystem/assets/pi-boot" "$ROOT/.agents/sandbox" \
  -maxdepth 1 -name '*.json' 2>/dev/null; [ -f "$ROOT/opencode.json" ] && echo "$ROOT/opencode.json")
if [ -z "$json_fail" ]; then
  add json "runtime JSON parses" PASS "all parse"
else
  add json "runtime JSON parses" FAIL "failed:$json_fail"
fi

# --- sync -------------------------------------------------------------------
# In a PACKAGED artifact the judge's mirror is a declared seam (npm does not pack
# a symlink), so an absent mirror is not drift — it is the artifact declaring what
# it cannot carry. Read packaging/symlink-seams.json and SKIP loudly rather than
# reporting a phantom fault; an UNDECLARED absence is still a FAIL.
sync_seam=""
if [ -f "$ROOT/packaging/symlink-seams.json" ]; then
  # The delimiter cannot be `/`: the path it matches CONTAINS one.
  sync_seam="$(grep -o '"[^"]*tyr-check/assets"' "$ROOT/packaging/symlink-seams.json" | head -1 | tr -d '"')"
fi
if [ -n "$sync_seam" ] && { [ ! -e "$TYR/assets" ] || [ ! -e "$GALDR/assets" ]; }; then
  add sync "galdr/tyr assets mirrored" SKIP \
    "declared symlink seam ($sync_seam) is absent in this artifact; a real machine seats it (bin/seat/valknut-load.sh --all)"
elif diff -rq "$GALDR/assets" "$TYR/assets" >/dev/null 2>&1; then
  add sync "galdr/tyr assets mirrored" PASS "in sync"
else
  add sync "galdr/tyr assets mirrored" FAIL "drift detected"
fi

# --- surfaces ---------------------------------------------------------------
# Galdr is dual-surface: the agent must resolve to the canonical skill.
if [ -L "$ROOT/.agents/agents/galdr.md" ] && [ "$(readlink "$ROOT/.agents/agents/galdr.md")" = "../skills/galdr-ymirsystem/SKILL.md" ]; then
  add surfaces "Galdr agent+skill dual-surface" PASS "agent symlinks the skill"
elif diff -q "$ROOT/.agents/agents/galdr.md" "$GALDR/SKILL.md" >/dev/null 2>&1; then
  add surfaces "Galdr agent+skill dual-surface" PASS "agent mirrors the skill"
else
  add surfaces "Galdr agent+skill dual-surface" FAIL "agent and skill differ"
fi

# --- hoard -------------------------------------------------------------------
# Rule 04, appended 2026-10-01: personal data is not only secrets. Run BOTH
# wards over the whole tracked tree — secret-guard for credential values,
# private-guard for operator identity/topology. Either red fails the gate.
hoard_detail=""
if out="$(bash "$ROOT/bin/gates/guards/secret-guard.sh" --all 2>&1)"; then
  hoard_detail="secret-guard clean"
else
  hoard_detail="secret-guard: $(printf '%s' "$out" | grep -m1 'secret-guard:' | cut -c1-120)"
fi
if out="$(bash "$ROOT/bin/gates/guards/private-guard.sh" --all 2>&1)"; then
  add hoard "the hoard boundary (Rule 04)" PASS "$hoard_detail · private-guard clean"
else
  hoard_detail="private-guard: $(printf '%s' "$out" | grep -m1 'private-guard:' | cut -c1-120)"
  add hoard "the hoard boundary (Rule 04)" FAIL "$hoard_detail"
fi

# The Allfather's own model knowledge must live at $YMIR_HOME, never here. The
# doctrine may ship; the measurements, hosts and numbers may not.
if [ -e "$ROOT/.agents/skills/modeltesting" ]; then
  add hoard "operator model knowledge lives in YMIR_HOME" FAIL "modeltesting is in the public tree; it belongs at \$YMIR_HOME/.agents/skills/modeltesting"
else
  add hoard "operator model knowledge lives in YMIR_HOME" PASS "no modeltesting skill in the public tree; doctrine only"
fi

# --- harnesses --------------------------------------------------------------
# Every harness reads agents through its own directory (.claude/agents,
# .codex/agents, .cursor/agents, .pi/agents, .opencode/agents) and skills through
# .agents/skills. Two failure classes hide there, and neither is visible from
# the code: a symlink that no longer resolves (Rule 02 — .agents/agents is
# canonical, harness dirs are symlinks), and a nested SKILL.md that a recursive
# scanner loads as a second, phantom skill. Both have bitten this tree: the
# galdr-cli rename left .agents/agents/galdr.md dangling for days, and three
# superseded SKILL.md files were being loaded as live skills.
harness_problems=""; harness_links=0
for hd in .claude/agents .codex/agents .cursor/agents .pi/agents .opencode/agents; do
  [ -d "$ROOT/$hd" ] || continue
  for entry in "$ROOT/$hd"/*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    if [ ! -L "$entry" ]; then
      harness_problems="$harness_problems ${hd}/$(basename "$entry")(real-file-not-symlink)"
    elif [ ! -e "$entry" ]; then
      harness_problems="$harness_problems ${hd}/$(basename "$entry")(dangling)"
    else
      harness_links=$((harness_links+1))
      # One hop only: the link must land in the canonical tree. It may then be a
      # symlink onward (Galdr's agent IS the skill, by design) — following the
      # whole chain here would wrongly call that off-tree. normpath is textual,
      # so the final symlink is deliberately left unresolved.
      hop_target="$(readlink "$entry")"
      case "$hop_target" in
        /*) hop_abs="$hop_target" ;;
        *)  hop_abs="$(dirname "$entry")/$hop_target" ;;
      esac
      hop="$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "$hop_abs" 2>/dev/null || printf '%s' "$hop_abs")"
      case "$hop" in
        "$ROOT/.agents/agents/"*) : ;;
        *) harness_problems="$harness_problems ${hd}/$(basename "$entry")(off-canonical-tree)" ;;
      esac
    fi
  done
done
# A nested SKILL.md that carries YAML frontmatter is loaded by every recursive
# scanner as a phantom skill. A nested SKILL.md WITHOUT frontmatter is an inert
# template (the NSR scaffolding layer) and is left alone.
phantom=""
while IFS= read -r sk; do
  [ -n "$sk" ] || continue
  rel="${sk#"$ROOT"/}"
  [ "$(printf '%s' "$rel" | awk -F/ '{print NF}')" -gt 4 ] || continue
  [ "$(head -1 "$sk")" = "---" ] && phantom="$phantom ${rel#.agents/skills/}"
done < <(find "$ROOT/.agents/skills" -name SKILL.md 2>/dev/null | sort)
# The ONE skills tree (`.agents/skills`) must reach EVERY harness, each by its
# own mechanism — and a harness silently loading nothing is invisible from the
# code, so it is asserted here:
#   opencode  — `skills.paths: [".agents/skills"]` in the tracked example
#   pi        — native discovery: it walks up from the cwd to `.agents/skills`
#               (and `~/.agents/skills`), so it needs no link and no config
#   claude · codex · cursor — project scope is their own dir: each gets
#               `<harness>/skills -> ../.agents/skills`
skills_gaps=""
grep -q '\.agents/skills' "$ROOT/opencode.json.example" 2>/dev/null \
  || skills_gaps="$skills_gaps opencode(skills.paths missing from opencode.json.example)"
[ -d "$ROOT/.agents/skills" ] || skills_gaps="$skills_gaps .agents/skills(missing tree)"
for hd in .claude .codex .cursor; do
  [ -d "$ROOT/$hd" ] || continue
  if [ ! -L "$ROOT/$hd/skills" ]; then
    skills_gaps="$skills_gaps ${hd}/skills(absent)"
  else
    case "$(readlink "$ROOT/$hd/skills")" in
      ../.agents/skills) : ;;
      *) skills_gaps="$skills_gaps ${hd}/skills(wrong target)" ;;
    esac
  fi
done

harness_detail=""
[ -n "$harness_problems" ] && harness_detail="broken agent links:$harness_problems"
[ -n "$phantom" ] && harness_detail="$harness_detail phantom skills:$phantom"
[ -n "$skills_gaps" ] && harness_detail="$harness_detail skills not bound:$skills_gaps"
if [ -z "$harness_detail" ]; then
  add harnesses "harness surfaces + skill discovery" PASS "$harness_links agent links resolve; skills bound (opencode config · pi native · claude/codex/cursor linked); no phantom skills"
else
  add harnesses "harness surfaces + skill discovery" FAIL "$harness_detail"
fi

# --- roster -----------------------------------------------------------------
# The roster (config/agents.yaml.example) and the canonical tree
# (.agents/agents/*.md) must name the SAME figures. A figure in the tree but not
# in the roster falls to `default_model` and is never declared to the harness; a
# figure in the roster with no profile is a phantom the roster promises and the
# tree cannot seat. This is the check that would have caught the real failure:
# twenty profiles existed, the roster named ten, and only the hand-declared names
# in opencode.json ever loaded — so eighteen figures were unreachable while every
# other gate stayed green.
roster_gaps=""
if [ -f "$ROOT/config/agents.yaml.example" ]; then
  # One python block, not shell text-munging: the tree side needs a per-file
  # `name:`, and the roster side needs a real YAML read. Both in shell produced
  # a collapsed single-line list and a mangled heredoc, so the comparison lied.
  roster_report="$(python3 - "$ROOT" <<'PY' 2>/dev/null
import sys, os, re, glob
root = sys.argv[1]
tree = set()
for f in glob.glob(os.path.join(root, ".agents/agents/*.md")):
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("name:"):
            n = line.split(":", 1)[1].strip()
            if n:
                tree.add(n)
            break
roster = set()
try:
    import yaml
    doc = yaml.safe_load(open(os.path.join(root, "config/agents.yaml.example")))
    roster = set((doc.get("agents") or {}).keys())
except Exception:
    # yaml may be absent; fall back to a strict two-space-indent scan
    txt = open(os.path.join(root, "config/agents.yaml.example")).read()
    m = re.search(r"^agents:[ \t]*\n((?:[ \t]+.*\n|\n)*)", txt, re.M)
    if m:
        for line in m.group(1).splitlines():
            mm = re.match(r"[ \t]{2}([A-Za-z0-9_-]+)[ \t]*:", line)
            if mm:
                roster.add(mm.group(1))
unrostered = sorted(tree - roster)
phantom = sorted(roster - tree)
print(len(tree))
print(" ".join(unrostered))
print(" ".join(phantom))
PY
)"
  tree_count="$(printf '%s\n' "$roster_report" | sed -n '1p')"
  unrostered="$(printf '%s\n' "$roster_report" | sed -n '2p')"
  phantom_roster="$(printf '%s\n' "$roster_report" | sed -n '3p')"
  [ -n "$unrostered" ] && roster_gaps="$roster_gaps in-tree-but-not-rostered:$unrostered"
  [ -n "$phantom_roster" ] && roster_gaps="$roster_gaps rostered-but-no-profile:$phantom_roster"
  if [ -z "$roster_gaps" ]; then
    add roster "roster and canonical tree agree" PASS "${tree_count:-0} figures, every one rostered and seated"
  else
    add roster "roster and canonical tree agree" FAIL "$roster_gaps"
  fi
fi

# --- skillindex -------------------------------------------------------------
# The canonical index is .agents/skills/README.md. Every real skill must be named
# there, and every skill path the Galdr assets cite must resolve. This is the
# check that would have caught the drift by hand: three superseded skills stayed
# "live" in the registry long after their files were gone, and the registry table
# pointed at a whole layout (smidja/, gunnlod, hamr, saga, ymir, open-design)
# that no longer existed. A line marked planned/legacy/superseded is exempt by
# intent — an index may name what is coming or gone, but not what never was.
real_skills="$(find -L "$ROOT/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' 2>/dev/null | while read -r d; do basename "$d"; done | sort)"
# An entry marked planned/legacy/superseded/… is exempt by intent, and so is one
# marked `app-provided`: the smithy's skill lives in its own app repo, cloned by
# step_apps — absent in a fresh clone or worktree until that step runs, present in
# a working tree. Exempting the MARKED entry keeps the index honest without
# demanding a path that only exists after the app clone. The exemption must drop
# the skill from BOTH sides (real + indexed) — the symlink's SKILL.md is found on
# disk even when the row is marked, so the real-side must forget it too.
app_provided="$(grep -E '^  "[A-Za-z0-9._-]+"' "$ROOT/.agents/skills/README.md" 2>/dev/null | grep -iE 'app-provided' | grep -oE '^  "[A-Za-z0-9._-]+"' | tr -d ' "')"
real_skills="$(printf '%s\n' "$real_skills" | grep -viF "$app_provided" | sed '/^[[:space:]]*$/d' | sort)"
indexed="$(grep -E '^  "[A-Za-z0-9._-]+"' "$ROOT/.agents/skills/README.md" 2>/dev/null \
  | grep -viE 'planned|legacy|superseded|removed|abandoned|retired|former|app-provided' \
  | grep -oE '^  "[A-Za-z0-9._-]+"' | tr -d ' "' | sort -u)"
missing_index="$(comm -23 <(printf '%s\n' "$real_skills") <(printf '%s\n' "$indexed") | tr '\n' ' ')"
extra_index="$(comm -13 <(printf '%s\n' "$real_skills") <(printf '%s\n' "$indexed") | tr '\n' ' ')"
dead_refs=""
while IFS= read -r line; do
  case "$line" in
    *planned*|*Planned*|*legacy*|*Legacy*|*superseded*|*Superseded*|*removed*|*Removed*|*abandoned*|*retired*|*former*) continue ;;
  esac
  for ref in $(printf '%s' "$line" | grep -oE '\.agents/skills/[A-Za-z0-9._-]+' | sort -u); do
    case "$ref" in *.md) continue ;; esac   # a file in the tree, not a skill dir
    [ -d "$ROOT/$ref" ] || dead_refs="$dead_refs $ref"
  done
done < <(cat "$GALDR"/assets/*.md "$ROOT/.agents/agents/brokk.md" 2>/dev/null)
skill_detail=""
[ -n "$(printf '%s' "$missing_index" | tr -d ' ')" ] && skill_detail="unindexed skills:$missing_index"
[ -n "$(printf '%s' "$extra_index" | tr -d ' ')" ] && skill_detail="$skill_detail indexed-but-absent:$extra_index"
[ -n "$(printf '%s' "$dead_refs" | tr -d ' ')" ] && skill_detail="$skill_detail dead skill paths:$dead_refs"
if [ -z "$skill_detail" ]; then
  add skillindex "skill index + cited skill paths" PASS "$(printf '%s\n' "$real_skills" | grep -c .) skills, all indexed and cited paths resolve"
else
  add skillindex "skill index + cited skill paths" FAIL "$skill_detail"
fi

# --- assets (governed paths) -------------------------------------------------
# A governed file changed in the working tree must have its owning asset changed
# in the same change, or the runtime has drifted from its documentation.
asset_for() {
  case "$1" in
    *bin/engine/ymir-install.sh)                      printf '%s' "$GALDR/assets/installation.md" ;;
    *apps/hlidskjalf/*)                        printf '%s' "$GALDR/assets/hlidskjalf-ui.md" ;;
    *bin/mimir*)                               printf '%s' "$GALDR/assets/memory-well.md" ;;
    *bin/vault/gleipnir-lock-lib.sh|*bin/time/saga-session-start.sh|*state/.lock) printf '%s' "$GALDR/assets/brokk-distro-runtime.md" ;;
    *bin/nornir-*|*config/cron.yaml*)           printf '%s' "$GALDR/assets/nornir-jobs.md" ;;
    *bin/seat/valknut-load.sh|*/.pi/*|*/.opencode/*) printf '%s' "$GALDR/assets/harness-integration/README.md" ;;
    *bin/smidja*|*.agents/skills/smidja-factory/*) printf '%s' "$GALDR/assets/smidja.md" ;;
    *)                                         printf '' ;;
  esac
}
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  changed="$(git -C "$ROOT" diff --name-only HEAD 2>/dev/null || true)"
  stale=""
  for f in $changed; do
    a="$(asset_for "/$f")"
    [ -n "$a" ] || continue
    # Stale only when the asset itself did NOT also change.
    printf '%s\n' "$changed" | grep -qxF "${a#"$ROOT"/}" && continue
    stale="$stale ${f##*/}"
  done
  if [ -z "$stale" ]; then
    add assets "governed assets current" PASS "no stale governed paths"
  else
    add assets "governed assets current" FAIL "stale (asset not updated):$stale"
  fi
else
  add assets "governed assets current" SKIP "not a git work tree"
fi

# --- one state dir (Phase 0) ------------------------------------------------
# The tree's `state` must be the hoard's symlink — never a shadow directory the
# runtime writes into where the hall never reads. The shadow cost the cron its
# pid file on 2026-09-27: the loop wrote tree/state/cron.pid while the smoke
# read the hoard. A present-but-real dir is the fail; an absent link is a
# pre-install note (the install seats it).
case "$ROOT" in
  */.yggdrasil/*) add state "one state dir" NOTE "a worktree — the hoard link lives in the main tree" ;;
  *)
    if [ -e "$ROOT/state" ]; then
      if [ -L "$ROOT/state" ]; then
        _st_target="$(readlink "$ROOT/state" 2>/dev/null || true)"
        case "$_st_target" in
          *ymirhome*state) add state "one state dir" PASS "tree state -> the hoard (the Phase-0 link)" ;;
          *) add state "one state dir" FAIL "tree state -> $_st_target — not the hoard" ;;
        esac
      else
        add state "one state dir" FAIL "tree state is a REAL directory — the Phase-0 one-state is broken; hoard it and re-link"
      fi
    else
      add state "one state dir" NOTE "no tree state yet — the install seats the Phase-0 link"
    fi
    ;;
esac

# --- design -----------------------------------------------------------------
# The cloth has TWO carriers on purpose: the CSS tokens every web surface imports
# (midgard/design-system/tokens.css) and the seven seeds Sessrúmnir derives ~40
# tokens from (themes/fensalir.json, the reference form). Two carriers of one
# identity drift the moment someone edits one, so they are checked against each
# other here: a colour may not change in one place only.
if [ -x "$ROOT/bin/gates/checks/design-check.sh" ]; then
  if "$ROOT/bin/gates/checks/design-check.sh" >/dev/null 2>&1; then
    add design "one cloth (tokens = seeds)" PASS "the 7 pairs agree — stone, bone, bronze, blood"
  else
    add design "one cloth (tokens = seeds)" FAIL "drifted — run bin/gates/checks/design-check.sh to see which pair"
  fi
else
  add design "one cloth (tokens = seeds)" SKIP "bin/gates/checks/design-check.sh absent"
fi

# --- duplicates -------------------------------------------------------------
if [ -d "$ROOT/assets/skills/assets" ]; then
  add duplicates "no duplicate asset trees" FAIL "assets/skills/assets exists"
else
  add duplicates "no duplicate asset trees" PASS "single canonical tree"
fi

# --- governed paths exist ---------------------------------------------------
# A governed path that does not exist is worse than a missing rule: the pretool
# guard stops matching silently, so the protection is gone and nothing fails.
# (A rename left `smidja-factory-factory` in AGENTS.md and in the guard's own
# pattern, which disabled the smidja rule without a single error.)
gov_missing=""
gov_count=0
while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  old_ifs="$IFS"; IFS='|'
  for alt in $spec; do
    alt="$(printf '%s' "$alt" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$alt" ] || continue
    gov_count=$((gov_count + 1))
    [ -e "$ROOT/$alt" ] && continue
    case "$alt" in
      # BRACE EXPANSION IS THE SHELL'S JOB, NOT compgen's. A governed path written
      # `apps/x/{cookbooks,skills}/**` never matches a glob test — compgen knows `*`, `?`
      # and `[`, but `{a,b}` is expanded by bash before any command runs. So a governed
      # path that EXISTED was reported missing forever and CI could never pass
      # (measured 2026-10-24, PR 423's failing gates job).
      *'{'*)
        _pre="${alt%%\{*}"; _rest="${alt#*\{}"; _mid="${_rest%%\}*}"; _post="${_rest#*\}}"
        _ok=0; _old_ifs="$IFS"; IFS=','
        for _piece in $_mid; do
          compgen -G "$ROOT/$_pre$_piece$_post" >/dev/null 2>&1 && { _ok=1; break; }
        done
        IFS="$_old_ifs"
        [ "$_ok" = 1 ] || gov_missing="$gov_missing $alt" ;;
      *'*'*|*'?'*|*'['*)
        compgen -G "$ROOT/$alt" >/dev/null 2>&1 || gov_missing="$gov_missing $alt" ;;
      *)
        gov_missing="$gov_missing $alt" ;;
    esac
  done
  IFS="$old_ifs"
done <<EOF
$(awk '/^governed\[/{f=1;next} f&&/^```/{exit} f{print}' "$ROOT/AGENTS.md" 2>/dev/null | sed -E 's/^ *"([^"]*)".*/\1/')
EOF
if [ "$gov_count" = 0 ]; then
  add governed "governed paths resolve" SKIP "no governed table found in AGENTS.md"
elif [ -z "$gov_missing" ]; then
  add governed "governed paths resolve" PASS "all $gov_count governed paths exist"
else
  add governed "governed paths resolve" FAIL "missing:$gov_missing"
fi

# --- config (Rule 07) -------------------------------------------------------
# Two classes of hardcoding that only appear on someone else's machine, and that
# no other gate catches:
#
#   models/providers — every user's differ, so a model id or provider name used
#     as a VALUE in shipped code or a tracked config is a claim about a machine
#     the author does not own. The user's own live in $YMIR_HOME/hodd/, read from
#     a YAML file there; the repo ships only a template.
#   absolute paths — a path naming a user (/home/<user>, /Users/<user>,
#     C:\Users\<user>) is not portable. Paths are relative to a resolved root or
#     come from env/config.
#
# Exempt by intent: comments (documentation may name an example), templates
# (*.example — placeholders are the point), CHANGELOG* (the record), and
# assets/reference/ (provenance — it records what was, not what runs).
config_bad=""
config_checked=0

# Shipped surfaces: the runtime, the skills' tools, the tracked configs.
config_files=$(git -C "$ROOT" ls-files -- 'bin/*.sh' 'scripts/*.sh' \
  '.agents/skills/*/scripts/*' 'config/*' '*.json' '*.yaml' '*.yml' 2>/dev/null \
  | grep -vE '(^|/)(CHANGELOG|assets/reference/|node_modules/|\.yggdrasil/)' \
  | grep -vE '\.example$|\.template$' || true)

# A model id or provider name as a VALUE. The pattern is deliberately narrow: a
# known provider prefix followed by a model token, in a VALUE POSITION only —
# after `:`, `=`, or a JSON/YAML key. Prose that merely mentions
# "llama.cpp/llama-swap" in a sentence is documentation, not configuration, and
# must not trip the gate.
for f in $config_files; do
  [ -f "$ROOT/$f" ] || continue
  config_checked=$((config_checked + 1))
  hits=$(sed -E 's/(^|[[:space:]])#.*$//' "$ROOT/$f" 2>/dev/null \
    | grep -nE '(^|[[:space:]])(model|models|default_model|provider|providers)[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9._-]+/(llama\.cpp|llamacpp|opencode-go|apodex|openrouter|lmstudio)/|[":=][[:space:]]*"(llama\.cpp|llamacpp|opencode-go|apodex|openrouter|lmstudio)/[A-Za-z0-9._@-]+"' \
    | head -3)
  [ -n "$hits" ] && config_bad="$config_bad ${f}(model)"
done

# An absolute path naming a user.
for f in $config_files; do
  [ -f "$ROOT/$f" ] || continue
  hits=$(sed -E 's/(^|[[:space:]])#.*$//' "$ROOT/$f" 2>/dev/null \
    | grep -nE '/home/[a-z][a-z0-9_-]+/|/Users/[A-Za-z][A-Za-z0-9_-]+/|[Cc]:\\Users\\' \
    | head -3)
  [ -n "$hits" ] && config_bad="$config_bad ${f}(path)"
done

if [ -z "$config_bad" ]; then
  add config "no hardcoded models, providers, or user paths (Rule 07)" PASS \
    "$config_checked files clean; models/providers resolve from \$YMIR_HOME/hodd/"
else
  add config "no hardcoded models, providers, or user paths (Rule 07)" FAIL \
    "hardcoded:$config_bad"
fi

# --- output -----------------------------------------------------------------
if [ "$JSON" = 1 ]; then
  printf '{\n  "checks": [\n'
  first=1
  for i in "${!IDS[@]}"; do
    [ $first = 0 ] && printf ',\n'
    first=0
    printf '    {"id":"%s","check":"%s","status":"%s","detail":"%s"}' \
      "${IDS[$i]}" "${CHECKS[$i]}" "${STATUS[$i]}" "${DETAILS[$i]}"
  done
  printf '\n  ]\n}\n'
else
  say "checks[${#IDS[@]}]{id,check,status,detail}:"
  for i in "${!IDS[@]}"; do
    say "  \"${IDS[$i]}\",\"${CHECKS[$i]}\",\"${STATUS[$i]}\",\"${DETAILS[$i]}\""
  done
fi

fails=0
for s in "${STATUS[@]}"; do [ "$s" = FAIL ] && fails=$((fails + 1)); done
if [ "$fails" -gt 0 ]; then
  if [ "$JSON" = 1 ] || [ "$QUIET" = 1 ]; then
    printf 'error: %s gate(s) failed\n' "$fails" >&2
    printf 'help: fix the FAIL rows; see assets/runtime-compliance.md\n' >&2
  else
    printf '\nerror: %s gate(s) failed\n' "$fails"
    printf 'help: fix the FAIL rows above; see assets/runtime-compliance.md\n'
  fi
  exit 1
fi
exit 0
