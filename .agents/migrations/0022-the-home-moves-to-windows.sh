#!/usr/bin/env bash
# 0022-the-home-moves-to-windows — the operator's home leaves the WSL disk for Windows.
#
# WHY. On a Windows machine Ymir runs inside WSL2, but the home — the well, the Runes
# ledger, the plans, the daily log, the machine cards, the vault — is the operator's
# own ground. On the distro's ext4 disk he cannot open it from Explorer, cannot back
# it up with his Windows tools, and loses all of it to `wsl --unregister`. So the home
# and the projects move to the Windows filesystem; only execution stays in the distro.
#
# WHAT MAY CROSS, AND WHAT MAY NOT, is a written decision — not this script's opinion:
#   docs/fixes/hoard/2026-11-11-what-may-live-on-the-windows-mount.md
# In one line: documents, plans, memory and checkouts may live on the 9p mount; a tree
# that systemd units EXECUTE from may not, because the mount carries no real mode bits
# (measured here: `chmod 600` lands as `777`), so a ward cannot be enforced, and the
# filesystem is case-insensitive, so two modules differing only in case are one file.
# This migration therefore never moves `~/ymir-runtime`, and it says so out loud.
#
# THE SHAPE OF THE MOVE (Rule 06 — never lose one in a move):
#   1. pre-flight: the destination is a Windows mount, has room, and the source has no
#      case collision the destination could not represent;
#   2. inventory every append-only artifact BY NAME, with its sha256, before anything
#      is written;
#   3. copy (rsync, never `mv`, never `--delete`) into the destination;
#   4. verify: the same inventory, byte for byte, on the other side; the well opens and
#      its episode count does not fall (Rule 20); git on the mount keeps modes and line
#      endings (core.filemode=false, core.autocrlf=false) — proven by a real probe;
#   5. only then repoint the resolver (`~/.config/ymir/home`);
#   6. the old home is LEFT WHOLE as the backup. Nothing is deleted, ever, here.
#
# Usage:
#   .agents/migrations/0022-the-home-moves-to-windows.sh [--dry-run]
#        [--destination=<dir>]   the C:\-backed path (Linux view), e.g. /mnt/c/Users/<you>/ymirhome
#        [--heal-case-collisions]
#
# The destination is also read from $YMIR_HOME_TARGET, then from
# `~/.config/ymir/home.target` (written the first time it is given). With no
# destination the migration DEFERS — it does not choose where the operator's home
# lives, because that is his decision, not a migration's.
#
# Exit: 0 moved or already clean · 1 refused (a fault, nothing written) · 3 deferred.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=bin/vault/hoard-lib.sh
. "$ROOT/bin/vault/hoard-lib.sh"

say() { printf '0022: %s\n' "$1"; }
die() { printf '0022: REFUSED — %s\n' "$1" >&2; exit 1; }
defer() { printf '0022: DEFERRED — %s\n' "$1" >&2; exit 3; }

DRY=0; DEST=""; HEAL=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --destination=*) DEST="${a#*=}" ;;
    --heal-case-collisions) HEAL=1 ;;
    -*) die "unknown argument $a" ;;
  esac
done

ymir_home_root SRC
[ -n "${DEST:-}" ] || DEST="${YMIR_HOME_TARGET:-}"
if [ -z "$DEST" ] && [ -r "$YMIR_CONFIG_DIR/home.target" ]; then
  DEST="$(head -n1 "$YMIR_CONFIG_DIR/home.target" 2>/dev/null | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
fi

# ── the fence: this is a Windows-bridge migration, nothing else ───────────────
is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }
fs_of() { stat -f -c '%T' "$1" 2>/dev/null; }
is_windows_mount() {  # <dir> — 9p/drvfs is how WSL present a Windows drive
  case "$(fs_of "$1")" in v9fs|9p|drvfs) return 0 ;; *) return 1 ;; esac
}

if ! is_wsl; then
  say "not WSL — this migration is the Windows bridge and does nothing here"
  exit 0
fi

if is_windows_mount "$SRC"; then
  say "clean — the home is already on a Windows mount ($SRC)"
  exit 0
fi

if [ -z "$DEST" ]; then
  defer "the home is still on the WSL disk and no Windows destination is recorded.
  PREVIEW it (names every directory, writes nothing):
    YMIR_HOME_TARGET=/mnt/c/Users/<you>/ymirhome bin/engine/ymir-migrate.sh apply --dry-run
  ASK FOR IT (copies, verifies, repoints once, idempotently):
    YMIR_HOME_TARGET=/mnt/c/Users/<you>/ymirhome bin/engine/ymir-migrate.sh apply
  The destination is your choice, not this migration's, so it never guesses one."
fi

# ── what is copied, and what is not ──────────────────────────────────────────
# `.venvs` is a PYTHON VIRTUALENV: its shebangs and symlinks encode the machine that
# built it, and its interpreter is executed — runtime, not documents. It is rebuilt by
# `bin/voice/voice-ensure.sh`, never carried.
#
# `smidja/` IS carried, and this is a correction. It was excluded on the first pass as
# "factory churn", and the move then left `smidja/smidja.db` behind — which
# `bin/engine/ymir-validate.sh` requires, so a correct move reported the install as
# broken. That database is the factory's RUN RECORD (the operator's own history), not a
# rebuildable interpreter. Only the venv and bytecode are skipped.
EXCLUDES=(--exclude=/.venvs --exclude='*/__pycache__/' --exclude='*.pyc')

excluded() {  # <relpath> — mirrors EXCLUDES, so the pre-flight sees what rsync sees
  case "$1" in
    .venvs|.venvs/*|*/__pycache__/*|__pycache__/*|*.pyc) return 0 ;;
    *) return 1 ;;
  esac
}

# ── pre-flight ───────────────────────────────────────────────────────────────
[ -d "$SRC" ] || die "the home does not exist: $SRC"
case "$DEST/" in
  "$SRC/"*) die "the destination is inside the home it would replace ($DEST)" ;;
esac
case "$SRC/" in
  "$DEST/"*) die "the home is inside the destination ($SRC)" ;;
esac

# The refusal, stated every run, before anything is written: the pinned runtime stays.
RT="${YMIR_RUNTIME_ROOT:-$HOME/ymir-runtime}"
case "$DEST/" in
  "$RT/"*) die "the destination is inside the pinned runtime ($RT): a runtime tree that systemd units execute from must NOT live on the 9p mount — it carries no real mode bits (measured: chmod 600 lands as 777), so a ward cannot be enforced, and the filesystem is case-insensitive, so two modules differing only in case collide. The home may cross; the runtime may not." ;;
esac
printf '0022[1]{tree,state,why}:\n  "%s","NOT MOVED","systemd units execute from it; 9p carries no mode bits (measured chmod 600 -> 777)"\n' "$RT"

# Where the destination would land. A dry run creates nothing, so it probes the
# nearest ancestor that already exists instead of mkdir'ing one.
DEST_PROBE="$DEST"
while [ ! -d "$DEST_PROBE" ] && [ "$DEST_PROBE" != "/" ]; do DEST_PROBE="$(dirname "$DEST_PROBE")"; done
is_windows_mount "$DEST_PROBE" || die "the destination is not on a Windows mount (filesystem: $(fs_of "$DEST_PROBE")) — a home on another ext4 leaf is not the move this migration makes"
if [ "$DRY" = 0 ]; then
  mkdir -p "$DEST" 2>/dev/null || die "cannot create the destination: $DEST"
fi

# Room. The home carries the documents; `.venvs` (202M here) stays behind.
need_kb=$(du -sk --exclude=.venvs "$SRC" 2>/dev/null | awk '{print $1}')
avail_kb=$(df -Pk "$DEST_PROBE" 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "$need_kb" ] && [ -n "$avail_kb" ] && [ "$avail_kb" -lt "$need_kb" ]; then
  die "not enough room under $DEST_PROBE — need ${need_kb}K, have ${avail_kb}K"
fi

# A live well is a store being written while we copy it. Never copy a moving target.
well_busy() {  # 0 when a process holds the store or the well's port answers
  local store
  hoard_memory_store store
  [ -e "$store" ] || return 1
  if command -v fuser >/dev/null 2>&1 && fuser "$store" >/dev/null 2>&1; then return 0; fi
  if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ':4602 '; then return 0; fi
  return 1
}

# ── the one hard fault a filesystem can present: two names, one file ──────────
# ext4 is case-sensitive; the Windows mount is not. Two paths that differ only in
# case become ONE file on the destination, and a copy that does not say so is a
# silent data loss. Measured on this home: hodd/machines/DESKTOP-FRS81OR and
# hodd/machines/desktop-frs81or both exist, each with plans/README.md, different text.
case_collisions() {  # prints "GROUP<TAB>relpath" for every group with >1 member
  ( cd "$SRC" && find . -type f -printf '%P\n' 2>/dev/null ) | while IFS= read -r rel; do
    excluded "$rel" && continue
    printf '%s\t%s\n' "$(printf '%s' "$rel" | tr '[:upper:]' '[:lower:]')" "$rel"
  done | LC_ALL=C sort -t "$(printf '\t')" -k1,1 \
    | awk -F'\t' '{ c[$1]=c[$1] "\t" $2; n[$1]++ } END { for (k in c) if (n[k]>1) { split(substr(c[k],2), a, "\t"); for (i in a) print k "\t" a[i] } }' \
    | LC_ALL=C sort -u
}

COLL="$(case_collisions)"
COLL_N=0
COLL_FAULT=0
declare -a DROP=()
dropped() {  # <relpath> — the losing member of a case-collision group
  local r="$1" d
  for d in ${DROP[@]+"${DROP[@]}"}; do [ "$d" = "$r" ] && return 0; done
  return 1
}
if [ -n "$COLL" ]; then
  COLL_N=$(printf '%s\n' "$COLL" | cut -f1 | sort -u | wc -l | tr -d ' ')
  printf '0022[%s]{path,state,why}:\n' "$(printf '%s\n' "$COLL" | wc -l | tr -d ' ')"
  prev_key=""
  while IFS=$'\t' read -r key rel; do
    [ -n "${rel:-}" ] || continue
    tracked=0
    git -C "$SRC" ls-files --error-unmatch "$rel" >/dev/null 2>&1 && tracked=1
    if [ "$key" = "$prev_key" ]; then
      # A later member of the same group LOSES: the destination folds it onto the
      # first, and copying both is how the second silently overwrites the first.
      if [ "$tracked" = 1 ]; then
        printf '  "%s","TRACKED — cannot be dropped","a tracked path is part of the record; the destination cannot hold both names"\n' "$rel"
        COLL_FAULT=1
      else
        printf '  "%s","dropped from the copy","untracked; stays in the retained old home, whole"\n' "$rel"
        DROP+=("$rel")
      fi
    else
      printf '  "%s","carried","the first of its group, by C-collation"\n' "$rel"
      [ "$tracked" = 1 ] && : # a tracked winner is fine; a tracked loser is not
    fi
    prev_key="$key"
  done < <(printf '%s\n' "$COLL")
  [ "$COLL_FAULT" = 1 ] || [ "$HEAL" = 1 ] || COLL_FAULT=2
  # Without the flag nothing is dropped: the copy would fold, and the manifest
  # would catch it — but a refusal that arrives after 66M of copying is a poor
  # refusal. Say no before the first byte.
  [ "$COLL_FAULT" = 2 ] && DROP=()
fi

# ── the inventory: every append-only artifact, by name, before the write ──────
manifest() {  # <root> <outfile> — sha256 + relative path for the set that must survive
  local root="$1" out="$2" rel
  : >"$out"
  # One writer for one row: a dropped case-collision member is not in the copy, so
  # it must not be in the inventory either — otherwise the move reports a loss it
  # chose, and a real loss could hide inside that noise.
  mf() {
    local r="$1"
    dropped "$r" && return 0
    [ -f "$root/$r" ] || return 0
    printf '%s  %s\n' "$(sha256sum "$root/$r" | cut -d' ' -f1)" "$r" >>"$out"
  }
  # Named one by one, never "the whole tree": a wildcard that silently matches
  # nothing is how a move loses a directory and calls itself a success.
  for rel in \
    hodd/memory/runes_audit.md \
    hodd/docs/append-only-log.md \
    hodd/docs/masterplan.md \
    hodd/memory/kaia.engram ; do
    mf "$rel"
  done
  # The daily log, the well's episodes, the plan ledger, the vault's sealed files:
  # directories whose every entry must arrive.
  for d in hodd/memory/daily hodd/memory/well hodd/secrets ; do
    [ -d "$root/$d" ] || continue
    ( cd "$root" && find "$d" -type f -print0 2>/dev/null ) | while IFS= read -r -d '' f; do
      mf "${f#./}"
    done
  done
  # The plan ledger: every `plans/` shelf in the home, wherever the realm put it.
  ( cd "$root" && find . -type d -name plans -not -path './.git/*' \
      -not -path './.venvs/*' -print0 2>/dev/null ) \
    | while IFS= read -r -d '' pd; do
        ( cd "$root" && find "$pd" -type f -print0 2>/dev/null ) \
          | while IFS= read -r -d '' f; do
              mf "${f#./}"
            done
      done
  LC_ALL=C sort -k2 "$out" -o "$out"
}

# ── the dry run: every directory it would touch, named, and nothing written ───
if [ "$DRY" = 1 ]; then
  printf '0022[1]{action,destination,source,size_needed}:\n  "dry-run","%s","%s","%sK"\n' "$DEST" "$SRC" "${need_kb:-unknown}"
  printf '0022[%s]{directory,files,size,action}:\n' "$(find "$SRC" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | grep -vE '^(\.venvs|\.git)$' | wc -l | tr -d ' ')"
  for d in "$SRC"/*/ "$SRC"/.[a-z]*/; do
    [ -d "$d" ] || continue
    b="$(basename "$d")"
    case "$b" in .venvs|.git) continue ;; esac
    printf '  "%s/%s","%s","%s","%s"\n' "$SRC" "$b" \
      "$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')" \
      "$(du -sh "$d" 2>/dev/null | cut -f1)" "copy"
  done
  printf '  "%s/.git","%s","%s","%s"\n' "$SRC" \
    "$(find "$SRC/.git" -type f 2>/dev/null | wc -l | tr -d ' ')" \
    "$(du -sh "$SRC/.git" 2>/dev/null | cut -f1)" "copy"
  printf '  "%s/.venvs","-","%s","skip (a python venv: rebuilt, not carried)"\n' "$SRC" "$(du -sh "$SRC/.venvs" 2>/dev/null | cut -f1)"
  printf '0022[3]{touched,action}:\n'
  printf '  "%s","created, then written by rsync (no --delete, ever)"\n' "$DEST"
  printf '  "%s","git config core.filemode=false · core.autocrlf=false"\n' "$DEST/.git/config"
  printf '  "%s","repointed to %s (the recorded choice)"\n' "$YMIR_CONFIG_DIR/home" "$DEST"
  printf '  "%s","recorded as this machine s Windows destination"\n' "$YMIR_CONFIG_DIR/home.target"
  printf '0022[2]{artifact,state}:\n  "%s","LEFT WHOLE — the backup, never deleted by this migration"\n  "%s","NOT MOVED — the runtime stays in the distro"\n' "$SRC" "$RT"
  case "$COLL_FAULT" in
    1) printf '0022[1]{verdict,reason}:\n  "REFUSE","a git-tracked path collides by case — resolve the naming in the home first"\n' ;;
    2) printf '0022[1]{verdict,reason}:\n  "REFUSE unless --heal-case-collisions","%s path(s) differ only by case; the Windows filesystem folds them into one"\n' "$COLL_N" ;;
    0) [ "$COLL_N" -gt 0 ] && printf '0022[1]{verdict,reason}:\n  "PROCEED with --heal-case-collisions","%s path(s) differ only by case; the first of each group is carried and the rest stay in the retained old home"\n' "$COLL_N" ;;
  esac
  [ "$COLL_FAULT" = 0 ] || printf '0022[1]{verdict,note}:\n  "this dry run wrote nothing","not the destination, not the record, not one byte of the home"\n'
  exit 0
fi

# The hard refusal, now that the dry run has had its say: a filesystem that folds
# two names into one cannot be trusted with a record that holds both.
[ "$COLL_FAULT" = 1 ] && die "a git-tracked path collides by case with another. The destination cannot hold both, and a tracked file is part of the record — resolve the naming in the home before moving."
[ "$COLL_FAULT" = 2 ] && die "$COLL_N path(s) collide by case (listed above). The Windows filesystem cannot hold two names that differ only in case. Re-run with --heal-case-collisions to carry the first of each group and leave the rest in the retained old home — nothing is deleted either way."

# ── 1. inventory before ──────────────────────────────────────────────────────
STATE_TMP="${TMPDIR:-/tmp}/0022-$$"; mkdir -p "$STATE_TMP"
trap 'rm -rf "$STATE_TMP"' EXIT
manifest "$SRC" "$STATE_TMP/before"
BEFORE_N=$(grep -c . "$STATE_TMP/before" || true)
[ "$BEFORE_N" -gt 0 ] || die "the append-only inventory is EMPTY — refusing to move a home whose record cannot be named. That is the fault this rule exists to catch."
printf '0022[5]{artifact,files}:\n'
printf '  "the Runes ledger","%s"\n' "$(grep -c '  hodd/memory/runes_audit.md$' "$STATE_TMP/before" || true)"
printf '  "the decision log + masterplan","%s"\n' "$(grep -cE '  hodd/docs/(append-only-log|masterplan)\.md$' "$STATE_TMP/before" || true)"
printf '  "the daily logs","%s"\n' "$(grep -c '  hodd/memory/daily/' "$STATE_TMP/before" || true)"
printf '  "the well (store + episodes)","%s"\n' "$(grep -cE '  hodd/memory/(kaia\.engram|well/)' "$STATE_TMP/before" || true)"
printf '  "the plan ledger","%s"\n' "$(grep -c '/plans/' "$STATE_TMP/before" || true)"
printf '  "the sealed vault","%s"\n' "$(grep -c '  hodd/secrets/' "$STATE_TMP/before" || true)"

if well_busy; then
  defer "the well is open ($(hoard_memory_store _s 2>/dev/null; printf '%s' "$_s")) — a store being written while it is copied is a torn copy.
  stop it first, then run this again:
    bin/bridge/mimir-bridge.sh --stop"
fi

# ── 2. copy — never mv, never --delete. The old home stays whole. ────────────
if [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  say "the destination already holds files — resuming an interrupted copy (rsync is idempotent, nothing is deleted)"
fi
say "copying $SRC -> $DEST"
# A destination that already holds a folded collision file must not be left to win
# by rsync's size/mtime shortcut: clear it first, so the kept member is really the
# one on disk. Nothing of the SOURCE is touched by this.
declare -a RSYNC_ARGS=("${EXCLUDES[@]}")
if [ "${#DROP[@]}" -gt 0 ] 2>/dev/null; then
  for rel in "${DROP[@]}"; do RSYNC_ARGS+=(--exclude="$rel"); done
fi
if [ -n "$COLL" ]; then
  while IFS=$'\t' read -r key rel; do
    [ -n "${rel:-}" ] || continue
    [ -e "$DEST/$rel" ] && rm -f "$DEST/$rel"
  done < <(printf '%s\n' "$COLL")
fi
if ! rsync -rlt --no-perms --no-owner --no-group "${RSYNC_ARGS[@]}" "$SRC"/ "$DEST"/; then
  die "rsync failed; the old home is untouched and the resolver still points at it"
fi

# ── 3. verify: the inventory, byte for byte, on the other side ───────────────
manifest "$DEST" "$STATE_TMP/after"
if ! diff -q "$STATE_TMP/before" "$STATE_TMP/after" >/dev/null 2>&1; then
  printf '0022: the two inventories differ — showing the first divergence:\n' >&2
  diff "$STATE_TMP/before" "$STATE_TMP/after" 2>&1 | head -20 >&2
  die "an append-only artifact did not arrive intact. Nothing was repointed; the old home is still the home."
fi
AFTER_N=$(grep -c . "$STATE_TMP/after" || true)
say "verified: $AFTER_N/$BEFORE_N append-only artifacts, sha256 for sha256"

# ── 4. the well opens, and its count does not fall (Rule 20) ─────────────────
if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$SRC/hodd/memory/kaia.engram" "$DEST/hodd/memory/kaia.engram" <<'PY'
import sqlite3, sys, os
src, dst = sys.argv[1], sys.argv[2]
if not (os.path.exists(src) and os.path.exists(dst)):
    print("0022: the well store is absent on one side — skipped"); raise SystemExit(0)
def counts(p):
    c = sqlite3.connect("file:%s?mode=ro" % p, uri=True)
    try:
        ok = c.execute("pragma integrity_check").fetchone()[0]
        rows = {t: c.execute('select count(*) from "%s"' % t).fetchone()[0]
                for t in ("episodes", "facts", "entities", "edges", "reflections")
                if c.execute("select 1 from sqlite_master where type='table' and name=?", (t,)).fetchone()}
        return ok, rows
    finally:
        c.close()
oks, rs = counts(src); okd, rd = counts(dst)
print("0022:   source integrity=%s %s" % (oks, rs))
print("0022:   moved  integrity=%s %s" % (okd, rd))
for t, n in rs.items():
    if rd.get(t, -1) < n:
        print("0022: FAIL the well lost %s episodes on the move (%d -> %d)" % (t, n, rd.get(t, -1)))
        raise SystemExit(1)
PY
  then
    die "the well did not survive the copy intact. Nothing was repointed."
  fi
else
  say "python3 absent — the well's integrity was NOT proven (verify by hand before trusting it)"
fi

# ── 5. git on a Windows mount: modes and line endings, proven ────────────────
PROBE="$DEST/state/git-probe"
rm -rf "$PROBE"; mkdir -p "$PROBE" || die "cannot write the git probe at $PROBE"
git -C "$PROBE" init -q 2>/dev/null || die "git cannot initialise on the destination — that alone disqualifies it"
git -C "$PROBE" config core.filemode false
git -C "$PROBE" config core.autocrlf false
printf 'one\ntwo\n' >"$PROBE/a.txt"
printf '#!/bin/sh\necho x\n' >"$PROBE/b.sh"
git -C "$PROBE" add -A 2>/dev/null
git -C "$PROBE" -c user.email=probe@ymir.invalid -c user.name=probe commit -qm probe 2>/dev/null
probe_fail=0
[ -z "$(git -C "$PROBE" status --porcelain 2>/dev/null)" ] || { probe_fail=1; printf '0022:   git status is not clean on the mount\n'; }
if git -C "$PROBE" ls-files -s 2>/dev/null | grep -q '^100755'; then
  probe_fail=1; printf '0022:   a 100755 mode appeared for a plain file (filemode is not off, or the mount invents exec)\n'
fi
if git -C "$PROBE" show HEAD:a.txt 2>/dev/null | grep -q "$(printf '\r')"; then
  probe_fail=1; printf '0022:   a CR appeared in the committed blob — line endings are being translated\n'
fi
chmod 755 "$PROBE/a.txt" 2>/dev/null
[ -z "$(git -C "$PROBE" status --porcelain 2>/dev/null)" ] || { probe_fail=1; printf '0022:   a chmod on the mount dirtied the work tree (core.filemode must be false)\n'; }
git -C "$PROBE" fsck --no-progress >/dev/null 2>&1 || { probe_fail=1; printf '0022:   git fsck reports a damaged object store on the mount\n'; }
[ "$probe_fail" = 0 ] || die "git is not proven safe on the destination — refusing to make it the home"
printf '0022[3]{probe,result}:\n  "git status is clean after commit","pass"\n  "no 100755 churn on a chmod","pass"\n  "LF preserved in the blob","pass"\n'

# the home's own repo gets the same two settings; they are not inherited
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" config core.filemode false
  git -C "$DEST" config core.autocrlf false
  printf '0022[2]{setting,value}:\n  "core.filemode","false"\n  "core.autocrlf","false"\n'
fi

# ── 6. repoint — only now, after the new home has answered ───────────────────
ymir_home_record_set "$DEST" || die "the new home is sound but the resolver could not be repointed"
mkdir -p "$YMIR_CONFIG_DIR" 2>/dev/null
printf '%s\n' "$DEST" >"$YMIR_CONFIG_DIR/home.target"

# The Windows-native spelling of the same place, for the tools that speak Windows.
win_path() {  # /mnt/c/Users/x -> C:\Users\x
  local p="$1"
  case "$p" in
    /mnt/[a-zA-Z]/*) printf '%s:\\%s' "$(printf '%s' "${p#/mnt/}" | cut -c1 | tr '[:lower:]' '[:upper:]')" \
        "$(printf '%s' "${p#/mnt/?/}" | tr '/' '\\')" ;;
    *) printf '%s' "$p" ;;
  esac
}
printf '0022[1]{resolver,now}:\n  "~/.config/ymir/home","%s"\n' "$DEST"
printf '0022[1]{view,path}:\n  "linux","%s"\n  "windows","%s"\n' "$DEST" "$(win_path "$DEST")"
printf '0022[2]{path,state}:\n  "%s","retained whole as the backup — delete it yourself once the new home has been lived in"\n  "%s","not moved, and never will be by this migration"\n' "$SRC" "$RT"
# The move changes a path; a running process keeps the path it was born with.
printf '0022[3]{followup,why}:\n'
printf '  "restart the well and the model bridge","both were raised with the OLD path — bin/bridge/mimir-bridge.sh --stop|--start, bin/bridge/bifrost-bridge.sh --stop|--start"\n'
printf '  "rebuild .venvs if you use the voice","a virtualenv is not carried: its shebangs and symlinks name the machine that built it (bin/voice/voice-ensure.sh)"\n'
printf '  "run bin/engine/ymir-validate.sh","the proof that the moved home answers from every door it answered from before"\n'
