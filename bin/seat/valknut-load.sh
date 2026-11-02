#!/usr/bin/env bash
# valknut-load.sh — Valknut, the knot that binds the repo distro into each tool's
# load path. Galdr-style: TOON output, structured errors, no prompts, idempotent.
#
# The repo is the source of truth: agents live in `.agents/agents/`, skills in
# `.agents/skills/`, Pi extensions in `.pi/extensions/`, the backend in
# `bin/` + `.agents/backend/`. This command binds them where each harness looks.
#
# Usage:
#   bin/seat/valknut-load.sh [--opencode] [--pi] [--global] [--status] [--all]
#   bin/seat/valknut-load.sh --check        # is the extension home ONE home? (exit 1 if not)
#   bin/seat/valknut-load.sh --ext-home     # which extension tree serves THIS tree?
#   bin/seat/valknut-load.sh --install      # seat the post-merge hook (bind on merge)
#   bin/seat/valknut-load.sh --version | -v
#
# Exit: 0 ok, 1 error, 2 usage.
set -u

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do
  [ "$PWD" = / ] && break; cd ..; done; pwd)"
AGENTS="$ROOT/.agents/agents"
PI_LOCAL="$ROOT/.pi/agents"
PI_GLOBAL="${HOME}/.pi/agent/agents"
# Pi extensions have ONE home: the repo's `.pi/extensions/` tree (RULES/13;
# commit ac5fd8ad, 2026-10-04). Pi loads BOTH that project tree and the global
# ${HOME}/.pi/agent/extensions/ and does not de-duplicate, so an extension in both
# registers its tools twice and pi exits with a tool-name conflict — no agent can be
# seated. This loader therefore DEPLOYS NOTHING: it keeps the global home free of any
# extension that also stands in the project tree, and writes the root record the
# extensions read back.
# A pinned runtime wins over the working tree (RULES/02 §7): the extensions a harness loads must be the ones
# a deployment proved, never whatever branch an agent left checked out. $YMIR_HOME/config/runtime.env names it.
_pin=""
_hoard="${YMIR_HOME:-}"
if [ -z "$_hoard" ] && [ -r "$ROOT/bin/vault/hoard-lib.sh" ]; then
  . "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
  command -v ymir_home_root >/dev/null 2>&1 && ymir_home_root _hoard 2>/dev/null || true
fi
if [ -n "$_hoard" ] && [ -r "$_hoard/config/runtime.env" ]; then
  _pin=$(sed -n 's/^YMIR_RUNTIME_DIR="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$_hoard/config/runtime.env" | head -1)
fi
unset _hoard
[ -n "$_pin" ] && [ -d "$_pin/.pi/extensions" ] && PI_EXT_SRC="${PI_EXT_SRC:-$_pin/.pi/extensions}"
PI_EXT_SRC="${PI_EXT_SRC:-$ROOT/.pi/extensions}"
unset _pin
PI_EXT_HOME="${PI_EXT_HOME:-${HOME}/.pi/agent/extensions}"
PI_SETTINGS="${PI_SETTINGS:-${HOME}/.pi/agent/settings.json}"
OC_LOCAL="$ROOT/.opencode/agents"
SKILLS="$ROOT/.agents/skills"

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

for a in "$@"; do
  case "$a" in
    -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
  esac
done

MODE_OPENCODE=0; MODE_PI=0; MODE_GLOBAL=0; MODE_INSTALL=0; MODE_STATUS=0; MODE_CHECK=0; MODE_EXT_HOME=0
for a in "$@"; do
  case "$a" in
    --opencode) MODE_OPENCODE=1 ;;
    --pi|--agents) MODE_PI=1 ;;
    --global) MODE_GLOBAL=1 ;;
    --status) MODE_STATUS=1 ;;
    --check) MODE_CHECK=1 ;;
    --ext-home) MODE_EXT_HOME=1 ;;
    --all) MODE_OPENCODE=1; MODE_PI=1 ;;
    --install) MODE_INSTALL=1 ;;
    *) printf 'error: unknown flag %s\nhelp: bin/seat/valknut-load.sh [--opencode|--pi|--global|--status|--check|--ext-home|--all]\n' "$a" >&2; exit 2 ;;
  esac
done

# ── ONE HOME ACROSS A WORKTREE (2026-10-24) ─────────────────────────────────
# A Yggdrasil worktree is the SAME repository as the seat root, so its
# `.pi/extensions/` is one home seen twice, never two homes. It used to be checked
# out like any other file, so a pi seat inside it loaded eighteen extensions twice,
# every tool name collided, pi exited, and the dispatcher typed the brief into the
# bare shell that was left (docs/fixes/agents/2026-10-24-the-errand-that-looked-alive.md).
# `bin/forge/yggdrasil.sh create` now excludes that path by a per-worktree
# sparse-checkout. This resolver is how every mode sees the difference:
#
#   own          this tree carries the extension home (the normal case)
#   absent       this tree carries none, and is NOT a worktree of the seated tree
#   shared       a worktree of the seated tree with no copy of its own — ONE home,
#                served by the seated tree
#   shared-link  that worktree points at the seated tree by symlink (works, but the
#                shipped shape is the sparse exclusion: a symlink shows as deleted
#                tracked files)
#   shared-copy  that worktree carries its OWN `.pi/extensions` — a genuine second
#                home, and exactly the fault
#
# A tree of a DIFFERENT repository is never "shared": it is its own home and must
# pass on its own terms.
git_common_dir() {  # <dir> -> absolute shared git dir, or nothing
  local d
  d="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$d" ] || return 0
  case "$d" in /*) ;; *) d="$1/$d" ;; esac
  ( cd "$d" 2>/dev/null && pwd -P )
}

pi_ext_seat_root() {  # the recorded seat root that still holds a live bin/, or nothing
  local pointer="$PI_EXT_HOME/.ymir-root" line
  [ -r "$pointer" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ -x "$line/bin/pi/syn-watch-arm.sh" ] && { printf '%s' "$line"; return 0; }
  done <"$pointer"
}

# Sets PI_EXT_SEAT, PI_EXT_STATE and PI_EXT_SERVING (the tree pi really loads).
pi_ext_resolve() {
  PI_EXT_SEAT="$(pi_ext_seat_root)"
  PI_EXT_SERVING="$PI_EXT_SRC"
  if [ -e "$PI_EXT_SRC" ] || [ -L "$PI_EXT_SRC" ]; then PI_EXT_STATE=own; else PI_EXT_STATE=absent; fi
  [ -n "$PI_EXT_SEAT" ] || return 0
  [ "$PI_EXT_SEAT" = "$ROOT" ] && return 0
  local here seat
  here="$(git_common_dir "$ROOT")"; seat="$(git_common_dir "$PI_EXT_SEAT")"
  [ -n "$here" ] && [ "$here" = "$seat" ] || return 0   # a different repository: not shared
  if [ "$PI_EXT_STATE" = absent ]; then
    PI_EXT_STATE=shared
    PI_EXT_SERVING="$PI_EXT_SEAT/.pi/extensions"
  elif [ -L "$PI_EXT_SRC" ]; then
    PI_EXT_STATE=shared-link
    PI_EXT_SERVING="$(cd "$PI_EXT_SRC" 2>/dev/null && pwd -P)"
    [ -n "$PI_EXT_SERVING" ] || PI_EXT_SERVING="$PI_EXT_SRC"
  else
    PI_EXT_STATE=shared-copy
  fi
}

pi_ext_resolve

if [ "$MODE_EXT_HOME" = "1" ]; then
  printf 'ext-home[1]{tree,state,seat_root,serving}:\n  "%s","%s","%s","%s"\n' \
    "$PI_EXT_SRC" "$PI_EXT_STATE" "${PI_EXT_SEAT:-}" "$PI_EXT_SERVING"
  exit 0
fi

# --check: is the DEPLOYED extension tree what the repo says it is?
#
# This gate exists because of four defects that every other check missed (2026-10-04):
#   1. the deployed ymir-subagents.ts was 12,991 B against a 13,748 B source, so the
#      RUNNING harness was missing the fix that stops a figure being seated with an
#      unfilled brief — and every file listing looked correct
#   2. `constellation-load.test.ts` and `constellation-registry.test.ts` were copied
#      into the live tree on every deploy, because nothing excluded them
#   3. an extension present in BOTH `~/.pi/agent/extensions/` and the project
#      `.pi/extensions/` registers its tools twice; pi refuses the duplicate and no
#      agent can be seated. The no-op stubs exist to prevent exactly this
#   4. the governing doc pointed at both paths at once, so a grep for a module's
#      home returned two answers
#
# A deploy is a COPY. Nothing re-runs the loader on its own, so the only thing that
# can catch a stale deploy is a check that asks. Exit 1 on any failure, so it can sit
# in CI and in the post-merge hook rather than in someone's memory.
# Make Ymir's extensions GLOBAL — loaded in every pi session, from any cwd.
#
# Measured against pi's own loader
# (`dist/core/extensions/loader.js: discoverAndLoadExtensions`): pi's discovery is
#   1. <cwd>/.pi/extensions   2. ~/.pi/agent/extensions   3. settings `extensions[]`
# and `addPaths` skips a path already `seen`, keyed on `path.resolve(p)`. Both (1)
# and (3) yield ABSOLUTE paths for the same files, so the same directory listed in
# user settings is de-duplicated when a session sits inside the repo — one home,
# no double registration. That is what makes this safe where a COPY or a SYMLINK
# would not be (a symlink resolves to a different string and would double-register,
# which is the failure Rule 13 exists to prevent).
#
# Prints `added`, `unchanged`, or `ERROR`.
pi_settings_extension_root() {
  [ -d "$PI_EXT_SRC" ] || return 0
  command -v python3 >/dev/null 2>&1 || { printf 'ERROR'; return 0; }
  [ -d "${HOME}/.pi/agent" ] || mkdir -p "${HOME}/.pi/agent" 2>/dev/null || { printf 'ERROR'; return 0; }

  PI_SETTINGS="$PI_SETTINGS" PI_EXT_SRC="$PI_EXT_SRC" python3 - <<'PY'
import json, os, shutil, sys

settings = os.environ["PI_SETTINGS"]
src = os.environ["PI_EXT_SRC"]

data = {}
if os.path.exists(settings):
    try:
        with open(settings) as handle:
            data = json.load(handle)
    except Exception:
        print("ERROR")
        sys.exit(0)
    if not isinstance(data, dict):
        print("ERROR")
        sys.exit(0)

extensions = data.get("extensions")
if not isinstance(extensions, list):
    extensions = []

# Drop any path entry into some OTHER checkout's extensions tree, then add ours.
# Flags such as `-builtin:mcp` are left exactly as they are.
def is_other_ymir_extensions(entry):
    if not isinstance(entry, str):
        return False
    if entry.startswith("-") or entry.startswith("+"):
        entry = entry[1:]
    if not entry.endswith(".pi/extensions"):
        return False
    expanded = os.path.expanduser(entry)
    return expanded != src and os.path.isdir(expanded)

# De-duplicate the whole array, preserving first-seen order. `kept.append(src)`
# without this guard added a NEW copy on every run: six runs put six identical
# entries in the list, and pi does not de-duplicate its `extensions[]` — so the
# entire extension tree loaded six times, every tool registered six times and
# every extension's console warning printed six times into the TUI.
kept = []
for entry in extensions:
    if is_other_ymir_extensions(entry):
        continue
    if entry in kept:
        continue
    kept.append(entry)
if src not in kept:
    kept.append(src)

if kept == extensions:
    print("unchanged")
    sys.exit(0)

data["extensions"] = kept
if os.path.exists(settings):
    shutil.copy2(settings, settings + ".bak-ymir")
with open(settings, "w") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
print("added")
PY
}

# Does the user settings `extensions` array already name THIS checkout?
pi_settings_extension_root_present() {
  [ -r "$PI_SETTINGS" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  PI_SETTINGS="$PI_SETTINGS" PI_EXT_SRC="$PI_EXT_SRC" python3 - <<'PY' >/dev/null 2>&1
import json, os, sys
try:
    with open(os.environ["PI_SETTINGS"]) as handle:
        data = json.load(handle)
except Exception:
    sys.exit(1)
entries = data.get("extensions") if isinstance(data, dict) else None
if not isinstance(entries, list):
    sys.exit(1)
src = os.environ["PI_EXT_SRC"]
# Exactly one entry for THIS tree: present, and no duplicate of it. A repeated
# entry loads the whole tree again (pi does not de-duplicate), which multiplies
# every extension warning into UI-breaking noise.
sys.exit(0 if entries.count(src) == 1 and len(entries) == len(set(map(str, entries))) else 1)
PY
}

if [ "$MODE_CHECK" = "1" ]; then
  fails=0
  printf 'check{pi-extensions-one-home}:
'
  # THE WORKTREE CASE (2026-10-24). A worktree of the SEATED repository is one
  # home, not two — but only while it carries no copy of its own. A copy is the
  # fault itself (`pi --list-models` inside such a worktree lists eighteen tool
  # conflicts and exits), so it is a FAIL with the exact repair.
  case "$PI_EXT_STATE" in
    shared)
      printf '  %-46s %s\n' "worktree of the seat's repository" "ONE HOME -> $PI_EXT_SERVING"
      printf '  %-46s %s\n' "the worktree carries no second tree" "PASS (sparse: .pi/extensions not checked out)" ;;
    shared-link)
      printf '  %-46s %s\n' "worktree of the seat's repository" "ONE HOME -> $PI_EXT_SERVING"
      printf '  %-46s %s\n' "the worktree carries no second tree" "PASS (symlink — sparse is the shipped shape)" ;;
    shared-copy)
      printf '  %-46s %s\n' "worktree of the seat's repository" "FAIL — it carries its OWN $PI_EXT_SRC"
      printf '  %-46s %s\n' "two load paths, so no seat" "FAIL — git -C $ROOT sparse-checkout set --no-cone '/*' '!/.pi/extensions/'"
      fails=$((fails+2)) ;;
    absent)
      printf '  %-46s %s\n' "project home holds extensions" "FAIL — $PI_EXT_SRC is absent and this is no worktree of the seat"
      fails=$((fails+1)) ;;
  esac
  # From here on, the tree that SERVES this session: the seated tree when the
  # worktree is sparse, else this tree's own.
  n_src=0
  for f in "$PI_EXT_SERVING"/*.ts "$PI_EXT_SERVING"/*.js; do [ -e "$f" ] && n_src=$((n_src+1)); done
  { [ "$n_src" -gt 0 ] && printf '  %-46s %s\n' "the serving home holds extensions ($n_src)" "PASS"; } \
    || { [ "$PI_EXT_STATE" = absent ] || { printf '  %-46s %s\n' "the serving home holds extensions" "FAIL"; fails=$((fails+1)); }; }
  dupes=0
  for ext in "$PI_EXT_SERVING"/*; do
    [ -e "$ext" ] || continue
    b=$(basename "$ext")
    case "$b" in node_modules|lib) continue ;; esac
    if [ -e "$PI_EXT_HOME/$b" ]; then
      printf '  %-46s %s\n' "$b" "DUPLICATE — also in the global home; pi would double-register it"
      dupes=$((dupes+1))
    fi
  done
  [ "$dupes" -eq 0 ] && printf '  %-46s %s\n' "no extension in two load paths" "PASS" \
                     || { printf '  %-46s %s\n' "double-registered extensions" "FAIL ($dupes)"; fails=$((fails+1)); }
  pointer="$PI_EXT_HOME/.ymir-root"; vroot=""
  if [ -r "$pointer" ]; then while IFS= read -r line; do [ -n "$line" ] || continue; [ -d "$line/bin" ] && { vroot="$line"; break; }; done <"$pointer"; fi
  if [ -n "$vroot" ]; then printf '  %-46s %s\n' ".ymir-root record" "PASS -> $vroot"
  else printf '  %-46s %s\n' ".ymir-root record" "FAIL — run: bin/seat/valknut-load.sh --pi"; fails=$((fails+1)); fi
  # Global reach: the user settings must name the tree that serves this session, or
  # the extensions load only when a session happens to sit inside the repo.
  if PI_EXT_SRC="$PI_EXT_SERVING" pi_settings_extension_root_present; then
    printf '  %-46s %s\n' "pi settings name the extensions tree" "PASS -> $PI_EXT_SERVING"
  else
    printf '  %-46s %s\n' "pi settings name the extensions tree" "FAIL — run: bin/seat/valknut-load.sh --pi"; fails=$((fails+1))
  fi
  printf 'check{pi-extension-check}:
'
  if [ "$fails" -eq 0 ]; then
    printf '  %-46s %s\n' "valknut-load --check" "PASS"
    exit 0
  fi
  printf '  %-46s %s\n' "valknut-load --check" "FAIL ($fails) — run: bin/seat/valknut-load.sh --pi"
  exit 1
fi

# --install: seat the post-merge hook, so a MERGE rebinds the surfaces. A merged
# extension fix otherwise sits in the repo while the RUNNING harness keeps the
# code it loaded — which is exactly how a hand-copy became necessary 2026-09-23.
if [ "$MODE_INSTALL" = "1" ]; then
  # Ask git for the hooks dir: in a worktree `.git` is a FILE, and the shared
  # hooks live in the MAIN repo — the same reason a fix must be installed from
  # wherever git says, not from the caller's tree.
  hooksdir="$(git -C "$ROOT" rev-parse --git-path hooks 2>/dev/null)"
  case "$hooksdir" in /*) ;; "") hooksdir="" ;; *) hooksdir="$ROOT/$hooksdir" ;; esac
  if [ -n "$hooksdir" ] && [ -d "$hooksdir" ]; then
    h="$hooksdir/post-merge"
    main_root="$(cd "$(dirname "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)")" 2>/dev/null && pwd)"
    [ -n "$main_root" ] || main_root="$ROOT"
    cat >"$h" <<HOOK
#!/usr/bin/env bash
# post-merge — rebind the harness surfaces after a merge. Installed by
# bin/seat/valknut-load.sh --install. A merge pulls new agents, skills and Pi
# extensions into the tree; the harnesses load them from their OWN homes, so the
# bind must run or a merged fix stays invisible to the running session.
set -u
[ -x "$main_root/bin/seat/valknut-load.sh" ] && "$main_root/bin/seat/valknut-load.sh" --all --global >/dev/null 2>&1 || true
HOOK
    chmod +x "$h"
    printf 'valknut-load[1]{hook,path,state}:\n  "post-merge","%s","installed"\n' "$h"
  else
    printf 'valknut-load[1]{hook,state}:\n  "post-merge","skipped — no hooks dir (not a git checkout)"\n'
  fi
  exit 0
fi

[ $((MODE_OPENCODE + MODE_PI + MODE_STATUS)) -eq 0 ] && { MODE_OPENCODE=1; MODE_PI=1; }

if [ ! -d "$AGENTS" ]; then
  printf 'error: agents dir not found: %s\nhelp: expected .agents/agents/ inside %s\n' "$AGENTS" "$ROOT"
  exit 1
fi

# ── machine config, rendered from its example ────────────────────────────────
# opencode.json and .pi/mcp-adapter.json must contain ABSOLUTE paths, so they cannot be
# tracked — a tracked copy would hand every operator the previous one's home.
# They are rendered from the shipped *.example with the real $HOME and root.
#
# TWO WRITERS touch opencode.json: this loader, and `bin/fleet/agents-config.sh apply`
# (which owns the ROSTER — providers and per-agent models, from
# config/agents.yaml). A blind render here DELETED the roster's work: the Apodex
# provider lived only in the live file and vanished on the next loader run. So
# this merges and never overwrites: missing keys are added, existing ones are
# left alone, and the skills tree is ensured. A live value is never lost, from
# either writer. Seeding happens only when the target is absent.
#
# Returns one of: seeded | merged(<what>) | unchanged | kept | absent.
config_out() {  # <rendered-json-or-text> <target>
  local ex=$1 out=$2
  [ -r "$ex" ] || { printf 'absent'; return 0; }
  python3 - "$ex" "$out" "$HOME" "$ROOT" <<'PY'
import json, os, sys

ex, out, home, root = sys.argv[1:5]
raw = open(ex).read().replace("__YMIR_HOME__", home).replace("__YMIR_ROOT__", root)

def write(text):
    with open(out, "w") as fh:
        fh.write(text)

try:
    want = json.loads(raw)
except Exception:
    # Not JSON (or not yet): seed a missing file, but never overwrite a live one.
    if os.path.exists(out):
        print("kept")
    else:
        write(raw); print("seeded")
    raise SystemExit

if not os.path.exists(out):
    write(json.dumps(want, indent=2) + "\n"); print("seeded"); raise SystemExit

cur = json.load(open(out))
added = []

def merge(cur, want, path=""):
    for k, v in want.items():
        if k not in cur:
            cur[k] = v; added.append(path + k)
        elif isinstance(v, dict) and isinstance(cur[k], dict):
            merge(cur[k], v, path + k + ".")

merge(cur, want)

# This loader's own contract: the ONE skills tree must stay reachable.
paths = cur.setdefault("skills", {}).setdefault("paths", [])
if ".agents/skills" not in paths:
    paths.append(".agents/skills"); added.append("skills.paths")

if not added:
    print("unchanged"); raise SystemExit
write(json.dumps(cur, indent=2) + "\n")
print("merged(%s)" % ",".join(added[:4]))
PY
}

declare -a T P S
add() { T+=("$1"); P+=("$2"); S+=("$3"); }

# ── the deployed-extension root record ───────────────────────────────────────
# The extensions are DEPLOYED into ${HOME}/.pi/agent/extensions/, and walking up
# from there reaches ${HOME}/.pi — a directory that holds no bin/. So a deployed
# copy that exec'd `${root}/bin/…` exec'd a path that does not exist, and the
# failure was silent: the Gná arm child died with 127 before its first poll, no
# state/.watch.heartbeat was ever written, and the watch was dead while every
# file listing looked correct. The root is therefore RECORDED beside the deployed
# files and read back by .pi/extensions/lib/ymir-home.ts.
#
# One absolute root per line, most recent first, deduped, capped. A root that no
# longer exists (a merged-and-removed Yggdrasil worktree, an uninstalled npm
# prefix) is skipped by the reader, so deploying from a worktree never strands a
# machine on a dead path. Prints `recorded` when the file changed, `unchanged`
# when it did not.
ymir_root_record() {
  local pointer="$PI_EXT_HOME/.ymir-root" tmp line
  [ -d "$PI_EXT_HOME" ] || return 0
  tmp="$(mktemp 2>/dev/null)" || return 0
  printf '%s\n' "$ROOT" >"$tmp"
  # PRUNE DEAD ROOTS. Measured 2026-10-04: `.ymir-root` carried FOUR roots and TWO of them were
  # `.yggdrasil/` worktrees that no longer exist. Every resolver that reads this file asks "the
  # first recorded root that really holds bin/pi/syn-watch-arm.sh", so a worktree that survives here
  # after it is deleted from disk will eventually be picked — and every door an extension calls
  # through it fails at 127. This list is a cache of places that USED to be real; a cache of dead
  # places is worse than no cache.
  if [ -r "$pointer" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      [ "$line" = "$ROOT" ] && continue
      grep -qxF -- "$line" "$tmp" 2>/dev/null && continue
      # keep a root only while it still IS a root
      [ -x "$line/bin/pi/syn-watch-arm.sh" ] || continue
      printf '%s\n' "$line" >>"$tmp"
    done <"$pointer"
  fi
  if [ "$(wc -l <"$tmp" | tr -d ' ')" -gt 8 ]; then
    head -n 8 "$tmp" >"$tmp.cap" && mv "$tmp.cap" "$tmp"
  fi
  if [ -r "$pointer" ] && cmp -s "$tmp" "$pointer"; then
    rm -f "$tmp"; printf 'unchanged'; return 0
  fi
  mv "$tmp" "$pointer" && printf 'recorded'
}

# The first recorded root that really holds bin/pi/syn-watch-arm.sh, or nothing.
ymir_root_verified() {
  local pointer="$PI_EXT_HOME/.ymir-root" line
  [ -r "$pointer" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ -x "$line/bin/pi/syn-watch-arm.sh" ] && { printf '%s' "$line"; return 0; }
  done <"$pointer"
}

link_agent_dir() {  # <target-dir> <rel-prefix>
  local target=$1 prefix=$2 made=0
  mkdir -p "$target" || return 1
  local f base
  for f in "$AGENTS"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    ln -sfn "${prefix}/${base}" "$target/$base" 2>/dev/null || return 1
    made=$((made + 1))
  done
  printf '%s' "$made"
}

# Skills are ONE tree (`.agents/skills/`). Each harness reaches it its own way:
#   opencode — `skills.paths: [".agents/skills"]` in opencode.json (rendered below)
#   pi       — discovery, natively: it walks up from the cwd looking for
#              `.agents/skills` (and `~/.agents/skills`), so it needs NO link,
#              and a second root under `.pi/` would only invite double-loading
#   claude · codex · cursor — project skills live under the harness dir, so each
#              gets `<harness>/skills -> ../.agents/skills`
link_skills() {  # <harness-dir>  → binds <harness-dir>/skills
  local dir=$1
  [ -d "$dir" ] || return 1
  ln -sfn ../.agents/skills "$dir/skills" 2>/dev/null || return 1
  printf 'bound'
}

if [ "$MODE_STATUS" = 1 ]; then
  [ -d "$OC_LOCAL" ] && add opencode "$OC_LOCAL" "$(ls "$OC_LOCAL"/*.md 2>/dev/null | wc -l | tr -d ' ') files" || add opencode "$OC_LOCAL" absent
  [ -d "$PI_LOCAL" ] && add pi-local "$PI_LOCAL" "$(ls "$PI_LOCAL"/*.md 2>/dev/null | wc -l | tr -d ' ') links" || add pi-local "$PI_LOCAL" absent
  [ -d "$PI_GLOBAL" ] && add pi-global "$PI_GLOBAL" "$(ls "$PI_GLOBAL"/*.md 2>/dev/null | wc -l | tr -d ' ') links" || add pi-global "$PI_GLOBAL" absent
  add agents-source "$AGENTS" "$(ls "$AGENTS"/*.md 2>/dev/null | wc -l | tr -d ' ') files"
  add opencode-skills "$SKILLS" "$(grep -q '\.agents/skills' "$ROOT/opencode.json" 2>/dev/null && printf 'via skills.paths' || printf 'absent')"
  add pi-skills "$SKILLS" "native discovery (walks up to .agents/skills)"
  # The root the DEPLOYED extensions read (`.ymir-root`). A stale or absent record
  # means every `${root}/bin/…` they exec is a path that does not exist: the arm
  # dies at 127 and the watch is silently dead, so this is a checked row.
  vroot="$(ymir_root_verified)"
  if [ -n "$vroot" ]; then
    add pi-ext-root "$PI_EXT_HOME/.ymir-root" "deployed extensions resolve to $vroot"
  else
    add pi-ext-root "$PI_EXT_HOME/.ymir-root" "ERROR no recorded root holds bin/pi/syn-watch-arm.sh — deployed extensions cannot find their bin/ (run: bin/seat/valknut-load.sh --pi)"
  fi
  for hd in .claude .codex .cursor; do
    [ -d "$ROOT/$hd" ] || continue
    [ -L "$ROOT/$hd/skills" ] && add "$hd-skills" "$ROOT/$hd/skills" linked || add "$hd-skills" "$ROOT/$hd/skills" absent
  done
fi

if [ "$MODE_OPENCODE" = 1 ]; then
  add opencode-config "$ROOT/opencode.json" "$(config_out "$ROOT/opencode.json.example" "$ROOT/opencode.json")"
  # OpenCode reads `.opencode/agents/` (PLURAL). The singular `.opencode/agent/`
  # was never read by the harness at all — twenty correct symlinks in a directory
  # no loader opens, which is why only the agents declared by hand in
  # opencode.json ever appeared. Migrate a legacy singular dir forward so an old
  # home heals instead of silently keeping its agents invisible.
  if [ -d "$ROOT/.opencode/agent" ] && [ ! -e "$ROOT/.opencode/agents" ]; then
    mv "$ROOT/.opencode/agent" "$ROOT/.opencode/agents" 2>/dev/null \
      && add opencode-migrate "$ROOT/.opencode/agents" "legacy .opencode/agent/ moved to .opencode/agents/" \
      || add opencode-migrate "$ROOT/.opencode/agents" "ERROR could not migrate"
  fi
  # Count what is bound here; the binding itself happens further down, after
  # `link_agents` is defined (this block runs before that definition).
  if [ -d "$OC_LOCAL" ]; then
    n=$(ls "$OC_LOCAL"/*.md 2>/dev/null | wc -l | tr -d ' ')
    add opencode "$OC_LOCAL" "native ($n agents)"
  else
    add opencode "$OC_LOCAL" "ERROR absent"
  fi
  # The skills tree reaches opencode through its config, not a link.
  if [ -f "$ROOT/opencode.json" ] && grep -q '\.agents/skills' "$ROOT/opencode.json"; then
    add opencode-skills "$SKILLS" "via skills.paths"
  else
    add opencode-skills "$SKILLS" "ERROR not in opencode.json"
  fi
fi

if [ "$MODE_PI" = 1 ]; then
  add pi-mcp "$ROOT/.pi/mcp-adapter.json" "$(config_out "$ROOT/.pi/mcp-adapter.json.example" "$ROOT/.pi/mcp-adapter.json")"
  n=$(link_agent_dir "$PI_LOCAL" "../../.agents/agents") && add pi-local "$PI_LOCAL" "bound ($n links)" || add pi-local "$PI_LOCAL" "ERROR"
  if [ "$MODE_GLOBAL" = 1 ]; then
    g=$(link_agent_dir "$PI_GLOBAL" "$AGENTS") && add pi-global "$PI_GLOBAL" "bound ($g links)" || add pi-global "$PI_GLOBAL" "ERROR"
  fi
  # Deploy the shared extensions into their single home. Copy, not link: a
  # broken link would silently disable a tool, and pi reads the file directly.
  # Idempotent — identical files are left untouched.
  # The CONTRACT, deployed globally: pi reads an AGENTS.md from its agent home in
  # every session, whatever the workspace. Without this, Sessrumnir (or any pi
  # session) started in another project loads THAT project's rules and knows
  # nothing of Ymir - no Brokk, no laws, no lore. Symlink, so the tree stays the
  # single source and an update is picked up with no re-install.
  #
  # A Yggdrasil worktree is REMOVED by `yggdrasil.sh cleanup`, so a contract
  # symlink into one leaves every later session with no AGENTS.md at all — the
  # same transient-root failure the `.ymir-root` record exists to avoid. A deploy
  # from a worktree therefore repoints the contract only when the current target
  # is already gone.
  if [ -d "$HOME/.pi/agent" ]; then
    contract="$HOME/.pi/agent/AGENTS.md"
    if [ -e "$contract" ]; then
      case "$ROOT" in
        */.yggdrasil/*) add pi-global-contract "$contract" "kept — a worktree deploy never repoints a live contract" ;;
        *) ln -sfn "$ROOT/AGENTS.md" "$contract" 2>/dev/null \
             && add pi-global-contract "$contract" "the Ymir contract, loaded in every pi session" \
             || add pi-global-contract "$contract" "ERROR" ;;
      esac
    else
      ln -sfn "$ROOT/AGENTS.md" "$contract" 2>/dev/null \
        && add pi-global-contract "$contract" "the Ymir contract, loaded in every pi session" \
        || add pi-global-contract "$contract" "ERROR"
    fi
  fi

  if [ -d "$PI_EXT_SRC" ]; then
    mkdir -p "$PI_EXT_HOME" 2>/dev/null
    # ONE home. The project tree IS the home; the global tree must hold NO Ymir
    # extension, or pi loads each one twice and refuses to seat. Remove any global
    # file or folder that shares a name with a project extension (a flat `ro.ts`
    # beside a project `ro/` counts), keeping the .ymir-root record beside them.
    pruned=0
    for ext in "$PI_EXT_SRC"/*; do
      [ -e "$ext" ] || continue
      b=$(basename "$ext")
      [ "$b" = "node_modules" ] && continue
      if [ -e "$PI_EXT_HOME/$b" ]; then rm -rf "$PI_EXT_HOME/$b" && pruned=$((pruned+1)); fi
    done
    for stale in "$PI_EXT_HOME"/*.ts "$PI_EXT_HOME"/*.js "$PI_EXT_HOME"/*.mjs; do
      [ -e "$stale" ] || continue
      b=$(basename "$stale"); stem="${b%.*}"
      if [ -e "$PI_EXT_SRC/$b" ] || [ -e "$PI_EXT_SRC/$stem" ]; then rm -f "$stale" && pruned=$((pruned+1)); fi
    done
    for d in "$PI_EXT_HOME"/*/; do
      [ -d "$d" ] || continue
      b=$(basename "$d"); stem="${b%.*}"
      if [ -e "$PI_EXT_SRC/$b" ] || [ -e "$PI_EXT_SRC/$stem" ]; then rm -rf "$d" && pruned=$((pruned+1)); fi
    done
    [ "$pruned" -gt 0 ] && add pi-ext-prune "$PI_EXT_HOME" "$pruned removed (one home — a duplicate would double-register)"
    add pi-extensions "$PI_EXT_SRC" "one tree — the project home (nothing deployed)"
    add pi-ext-root "$PI_EXT_HOME/.ymir-root" "$(ymir_root_record) -> $ROOT"
    # The seat's own name. One source (hodd/identity/seats.yaml), one artefact per
    # seat; a host with no identity line fails loudly rather than inherit "Brokk".
    if [ -x "$ROOT/bin/agents/seat-identity.sh" ]; then
      add seat-identity "$PI_EXT_HOME/.ymir-seat" "$("$ROOT/bin/agents/seat-identity.sh" --install "${YMIR_HOST:-$(hostname -s)}" 2>&1 | tail -1)"
    fi

    # GLOBAL REACH, ONE HOME. The project tree is still the only home; the user
    # settings `extensions` array names it so pi loads it from ANY cwd. Pi
    # de-duplicates on the resolved path, so a session inside the repo loads it
    # once (see pi_settings_extension_root above for the measured evidence).
    case "$(pi_settings_extension_root)" in
      added)     add pi-ext-global "$PI_SETTINGS" "extensions[] += $PI_EXT_SRC (loaded in every pi session)" ;;
      unchanged) add pi-ext-global "$PI_SETTINGS" "already names $PI_EXT_SRC" ;;
      *)         add pi-ext-global "$PI_SETTINGS" "ERROR could not be written" ;;
    esac
  fi
fi

# Agents for every harness: `.agents/agents/` is canonical, and each harness dir
# is a directory of symlinks into it (Rule 02). Pi and opencode have their own
# bindings above; claude, codex and cursor are bound here, so no harness is left
# holding a hand-made subset. opencode names an agent by its `name:` frontmatter
# (bragi.md -> bragi-marketer.md), the others by the profile file name.
agent_name_of() {  # <profile> -> the frontmatter `name:`
  sed -n 's/^name:[[:space:]]*//p' "$1" 2>/dev/null | head -1 | tr -d '[:space:]'
}
link_agents() {  # <harness-dir> [short]
  local dir=$1 short=${2:-} made=0 f base want
  [ -d "$(dirname "$dir")" ] || return 1
  mkdir -p "$dir" || return 1
  for f in "$AGENTS"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if [ "$short" = "short" ]; then
      want="$(agent_name_of "$f")"; [ -n "$want" ] || continue; want="$want.md"
    else
      want="$base"
    fi
    ln -sfn "../../.agents/agents/$base" "$dir/$want" 2>/dev/null || return 1
    made=$((made + 1))
  done
  printf '%s' "$made"
}
if [ "$MODE_STATUS" = 0 ]; then
  # Skills for the CLIs whose project scope is their own directory. Pi needs no
  # link (it discovers `.agents/skills` by walking up); opencode reaches that
  # tree through `skills.paths`. claude, codex and cursor each get one link, so
  # all of them read the ONE skills tree.
  linked=""
  for hd in .claude .codex .cursor; do
    [ -d "$ROOT/$hd" ] || continue
    link_skills "$ROOT/$hd" >/dev/null 2>&1 && linked="$linked $hd"
  done
  [ -n "$linked" ] && add harness-skills "$SKILLS" "linked into:$linked"

  # …and AGENTS for the same harnesses, plus opencode, so every tool loads every
  # agent — never a hand-made subset.
  for hd in .claude .codex .cursor; do
    [ -d "$ROOT/$hd" ] || continue
    n=$(link_agents "$ROOT/$hd/agents") || n=0
    add "${hd#.}-agents" "$ROOT/$hd/agents" "bound ($n)"
  done
  if [ -d "$ROOT/.opencode" ]; then
    n=$(link_agents "$OC_LOCAL" short) || n=0
    add opencode-agents "$OC_LOCAL" "bound ($n)"
  fi
fi

printf 'loaders[%s]{tool,path,status}:\n' "${#T[@]}"
for i in "${!T[@]}"; do
  printf '  "%s","%s","%s"\n' "${T[$i]}" "${P[$i]}" "${S[$i]}"
done
printf 'help[1]: run `bin/seat/valknut-load.sh --status` to inspect bindings\n'
