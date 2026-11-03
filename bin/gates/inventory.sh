#!/usr/bin/env bash
# inventory.sh — the honest index of the two shelves nobody can read.
#
# WHY (2026-10-02): the Allfather asked *"do we have a readme in the bin folder and backend
# folder over what every file are doing?"* — one existed, and it was worthless:
#
#   files in bin/            389
#   entries in bin/README.md 105     ← 284 files with no entry at all
#   entries ending mid-sentence  6     ← truncated headers
#   a generator                    none  ← it was hand-written once
#   a checker                      none  ← so it silently rotted
#
# This writes BOTH inventories from the files themselves, and `--check` fails when the
# shelf and the index disagree — so the index cannot rot again.
#
# Per file it reports, all measured rather than judged:
#   does        the file's own header, first COMPLETE sentence
#   kind        door · lib · tool · provenance(fm-*) · module
#   verdict     tested · wired · internal · orphan        (liveness, strongest first)
#   disposition keep · migrate → src/ymir_runtime/<mod> · retire · provenance
#   called-by   the doors that invoke it
#
#   bin/gates/inventory.sh            # write bin/README.md and .agents/backend/README.md
#   bin/gates/inventory.sh --check    # fail if either index is stale (for CI)
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
MODE="${1:-write}"

python3 - "$ROOT" "$MODE" <<'PY'
import os, re, subprocess, sys, json
from pathlib import Path

ROOT, MODE = Path(sys.argv[1]), sys.argv[2]
BIN = ROOT / "bin"
BACKEND = ROOT / ".agents" / "backend"
SRC = ROOT / "src" / "ymir_runtime"

def read(p, n=200000):
    try: return p.read_text(errors="ignore")[:n]
    except Exception: return ""

def first_sentence(text, limit=140):
    """The file's own header, first COMPLETE sentence (never a truncated line)."""
    lines = text.splitlines()
    for i, ln in enumerate(lines[:40]):
        s = ln.strip()
        if not s or s.startswith("#!") or s.startswith("set "):
            continue
        s = re.sub(r"^#+\s*", "", s).strip()
        s = re.sub(r"\s+", " ", s)
        if len(s) < 3:
            continue
        m = re.match(r"^(.{10,}?[.!?])(\s|$)", s)
        s = m.group(1) if m else s
        return (s[:limit - 1].rstrip() + "…") if len(s) > limit else s
    return "(no header)"

# ---- corpus: everything that can prove a file is alive -----------------------
# TWO bugs lived here (2026-10-02), and CI caught the second:
#
#   1. The roots were `agents` and `pi` — DIRECTORIES THAT DO NOT EXIST. The real shelves
#      are `.agents` (723 tracked files) and `.pi` (57), so the single largest body of
#      proof-of-alive evidence in the house was silently excluded from every verdict.
#   2. A `find`/`os.walk` corpus includes gitIGNORED files, so a machine with local state
#      (`.agents/state/`, `.agents/skills-local/`, `.opencode/node_modules/`) renders a
#      DIFFERENT index than a fresh checkout. CI then reads the committed index, finds it
#      stale, and fails — correctly — for a difference no reviewer can see in the diff.
#
# So the corpus is now `git ls-files`: TRACKED files only. A generated index must be
# reproducible from a clean checkout by construction, or its `--check` is a lottery.
TEXTY = (".sh", ".md", ".ts", ".tsx", ".py", ".yaml", ".yml", ".json", ".toml", ".mjs", ".js")
# Index modes are portable; os.access(X_OK) reports ordinary files executable on
# Windows/DrvFS. NUL-delimited stage records preserve whitespace in tracked paths.
index = subprocess.run(["git", "ls-files", "--stage", "-z"], cwd=ROOT,
                       capture_output=True, check=True).stdout
tracked_modes = {}
for record in index.split(b"\0"):
    if not record:
        continue
    metadata, filename = record.split(b"\t", 1)
    mode, _object, stage = metadata.split()
    if stage == b"0":
        tracked_modes[os.fsdecode(filename)] = mode
tracked = list(tracked_modes)
tracked_set = set(tracked)
corpus_paths = [ROOT / p for p in tracked if p.endswith(TEXTY)]
corpus = []
for p in corpus_paths:
    corpus.append(read(p))
for f in ("AGENTS.md", "README.md", "opencode.json", "package.json"):
    corpus.append(read(ROOT / f))
CORPUS = "\n".join(corpus)

# A test is a test wherever it lives. This used to read ONLY `.agents/tests/`, so 73 doors
# that `src/ymir_runtime/tests/` and the `.agents/backend/fm-*.test.sh` suites really do
# exercise were reported untested — which is how a second register could claim 64 of them
# were undecided while the first said they were fine.
TEST_ROOTS = (".agents/tests", "src", "tools", ".agents/backend", "apps", "packages")
TESTS = "\n".join(
    read(p)
    for root in TEST_ROOTS
    for p in (ROOT / root).rglob("*")
    if p.is_file() and (".test." in p.name or "/tests/" in p.as_posix() or p.name.endswith("_test.py"))
) or ""

PY_MODULES = {p.stem for p in SRC.rglob("*.py")} if SRC.exists() else set()
PY_MODULE_PATHS = {p.stem: p.relative_to(ROOT).as_posix() for p in SRC.rglob("*.py")} if SRC.exists() else {}

def counterpart(stem):
    """A python module with the same name, if the runtime already owns this."""
    s = re.sub(r"^(fm|brokk|ymir|agent)-", "", stem)
    s = re.sub(r"-(lib|sh)$", "", s).replace("-", "_")
    for cand in (stem.replace("-", "_"), s):
        if cand in PY_MODULES:
            return PY_MODULE_PATHS.get(cand)
    return None

# The doors that may call a door: TRACKED bin files only, computed ONCE.
# This was `BIN.rglob("*")` INSIDE analyse() — a filesystem walk per file (quadratic)
# that also counted untracked scripts, so a seat's `called-by` totals ran higher than a
# clean checkout's and the committed index could never match CI.
# A VIEW IS NOT A CALLER (2026-10-23). This scan included `bin/README.md` — the file it
# renders — so every door gained one caller the moment the index listed it, and the next
# render counted one more. Measured: render 1 changed 97 lines, render 2 changed 26, and
# only a third render matched. A markdown page that NAMES a door does not CALL it, so no
# README.md is a caller: the register stays derived AND reproducible, and `--check` stops
# being the lottery this file warns about (`bin/gates/guards/inventory-guard.sh` proves it).
BIN_TRACKED = (
    [p for p in sorted(BIN.rglob("*"), key=lambda p: p.relative_to(ROOT).as_posix())
     if p.is_file() and p.name != "README.md" and p.relative_to(ROOT).as_posix() in tracked_set]
    if BIN.exists() else []
)


def analyse(path: Path, shelf: str):
    name = path.name
    # README.md is the inventory's OWN output: emitting its line count makes the
    # file change every generation, so --check could never pass. A dash is
    # honest ('this is the index itself') and idempotent.
    self_indexed = name in ('README.md',)
    stem = re.sub(r"\.(sh|py|bash)$", "", name)
    text = read(path)
    is_exec = tracked_modes.get(path.relative_to(ROOT).as_posix()) == b"100755"

    # callers: which other doors invoke it
    called_by = []
    # RECURSIVE: bin/ now has SYSTEM FOLDERS, and a root-only scan indexes 148 of 398 doors and
    # calls it current — the same blindness that hid four doors in the first move.
    # The index is its OWN input if it is read here: every door's name appears in `README.md`, so each
    # generation added one to every `called-by` count and `--check` could NEVER pass (measured
    # 2026-10-23: two consecutive runs differed in 48 lines — `2 → 3`, `3 → 4`). A generator that reads
    # its own output is not a generator, it is a feedback loop. Skip every index file by name.
    for other in BIN_TRACKED:
        if other == path or other.name in ("README.md", "CAPABILITIES.md"):
            continue
        if name in read(other, 200000): called_by.append(other.name)
    outside = name in CORPUS
    tested = name in TESTS

    # A NAME is not a verdict. This shelf was `if name.startswith("fm-"): provenance`,
    # which overrode every piece of evidence: 174 files were filed as inert vendored
    # reference when 162 of them are exercised by a test and 11 more are called by a door,
    # and NOT ONE was unreferenced. Evidence first, provenance last — provenance then means
    # what it says: inert, and only because nothing exercises it.
    if tested:
        verdict, disp = "tested", "keep"
    elif called_by:
        verdict, disp = "wired", "keep"
    elif name.startswith("fm-"):
        verdict = "provenance"
        disp = "provenance"
    elif tested:
        verdict, disp = "tested", "keep"
    elif outside:
        verdict, disp = "wired", "keep"
    elif called_by:
        verdict, disp = "internal", "keep"
    else:
        verdict, disp = "orphan", "retire"

    cp = counterpart(stem)
    if disp == "keep" and cp and shelf == "bin":
        disp = f"migrate → {cp}"

    kind = "provenance" if name.startswith("fm-") else (
        "lib" if "-lib" in name else "tool" if is_exec else "data")
    return dict(file=name, does=first_sentence(text), kind=kind, verdict=verdict,
                disposition=disp, callers=len(called_by),
                lines=("-" if self_indexed else text.count("\n") + 1))

def table(rows, title_cols):
    out = [f'{title_cols}[{len(rows)}]{{file,does,kind,verdict,disposition,callers,lines}}:']
    for r in sorted(rows, key=lambda x: x["file"]):
        esc = lambda s: str(s).replace('"', "'").replace("\n", " ").strip()
        out.append('  "%s","%s","%s","%s","%s",%s,%s' % (
            esc(r["file"]), esc(r["does"]), esc(r["kind"]), esc(r["verdict"]),
            esc(r["disposition"]), r["callers"], r["lines"]))
    return "\n".join(out)

def tally(rows, key):
    d = {}
    for r in rows: d[r[key]] = d.get(r[key], 0) + 1
    return ", ".join(f"{k}={v}" for k, v in sorted(d.items(), key=lambda kv: -kv[1]))

shelves = {}
# TRACKED files only, as the header above promises. This walked the filesystem
# (`rglob`), so untracked live state — bin/state/cron.log, .session-start-complete —
# was counted, its "called-by" totals moved as the machine ran, and the committed
# index could not match a clean checkout: `--check` was the lottery this file warns
# about. A generated index must be a function of the tree, not of the seat.
tracked_set = set(tracked)
for shelf, d in (("bin", BIN), (".agents/backend", BACKEND)):
    if d.exists():
        shelves[shelf] = [
            analyse(p, shelf)
            for p in sorted(d.rglob("*"), key=lambda p: p.relative_to(ROOT).as_posix())
            if p.is_file() and p.relative_to(ROOT).as_posix() in tracked_set
        ]

fail = False
for shelf, rows in shelves.items():
    target = ROOT / ("bin/README.md" if shelf == "bin" else ".agents/backend/README.md")
    gen = []
    if shelf == "bin":
        gen.append("# `bin/` — every file, what it does, and whether it is alive\n")
        gen.append("**Generated by `bin/gates/inventory.sh`. Do not hand-edit; run `bin/gates/inventory.sh` and")
        gen.append("commit the result.** `bin/gates/inventory.sh --check` fails when this file and the")
        gen.append("shelf disagree, so the index cannot rot the way the hand-written one did.\n")
        gen.append("**Read the columns.** `verdict` is measured, not judged: `tested` = a test")
        gen.append("exercises it · `wired` = a skill, doc or gate names it · `internal` = only other")
        gen.append("doors call it · `orphan` = nothing outside `bin/` names it · `provenance` = a")
        gen.append("vendored `fm-*` script kept byte-comparable to upstream on purpose.")
        gen.append("`disposition` says what happens to it: `keep`, `migrate → src/…` where the")
        gen.append("Python runtime already has the module, `retire` for orphans, `provenance`.")
        gen.append("")
        gen.append(table(rows, "bin"))
        gen.append("")
        gen.append(f"**Tally.** verdict: {tally(rows,'verdict')}")
        gen.append("")
        gen.append(f"**Tally.** disposition: {tally(rows,'disposition')}")
    else:
        gen.append("# `.agents/backend/` — the backend layer, file by file\n")
        gen.append("**Generated by `bin/gates/inventory.sh`. Do not hand-edit.**\n")
        gen.append("**What this folder is.** Two things that share one job — *make work happen")
        gen.append("and report it truthfully*:\n")
        gen.append("1. **The vendored firstmate runtime** (`fm-*`) — the validated upstream Ymir")
        gen.append("   ported its dispatch from. It is the reference implementation of")
        gen.append("   spawn → send → peek → watch → teardown, and it stays byte-comparable to")
        gen.append("   upstream so a port can be checked against it. **Provenance, not Ymir's own.**")
        gen.append("2. **The model bridges** — Ymir's own files. They are why this index exists:\n")
        gen.append(table(rows, "backend"))
        gen.append("")
        gen.append(f"**Tally.** verdict: {tally(rows,'verdict')}")
    body = "\n".join(gen) + "\n"

    if MODE == "--check":
        cur = read(target)
        if cur.strip() != body.strip():
            print(f"inventory --check: {target.relative_to(ROOT)} is STALE — run bin/gates/inventory.sh", file=sys.stderr)
            fail = True
        else:
            print(f"inventory --check: {target.relative_to(ROOT)} is current ({len(rows)} files)")
    else:
        target.write_text(body, encoding="utf-8", newline="\n")
        print(f"wrote {target.relative_to(ROOT)} — {len(rows)} files · verdict: {tally(rows,'verdict')} · disposition: {tally(rows,'disposition')}")

sys.exit(1 if fail else 0)
PY
rc=$?
[ "$MODE" = "--check" ] && exit $rc
exit 0