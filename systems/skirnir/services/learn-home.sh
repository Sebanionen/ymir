#!/usr/bin/env bash
# learn-home.sh — give Skírnir the SHAPE of the house: its shelves, its law, its plans.
#
#   bin/assistant/learn-home.sh [--dry-run]
#
# The Allfather, 2026-10-23: *"why can't I see my full ymir home in Skírnir … he's talking about
# the wrong things."* Both halves were true and both had the same cause: his book held 308 approved
# CLAIMS (95 of them feature rows) and not one fact about the home itself, so a question about the
# home could only match a feature's words — and every feature claim opens "Ymir has a feature: …",
# so "ymir" counted as the subject of all of them.
#
# This door writes the missing half: ONE fact per document the home is made of —
#
#   hodd/docs/INDEX.md            every indexed page (its own one-line description)
#   RULES/*.md                    the house law, by title
#   plans/*.md (the canonical ledger)  every plan, by number · title · status
#   hodd/bin/DOORS.md             the home's own tools, by file
#
# The facts are class `internal`, audience `owner` and `approved_by: document` — NOT the Allfather's
# signature: a document proves its own claim, and a machine must never sign for him. kb-export
# accepts that approver for `internal` only, and refuses it everywhere else.
#
# Idempotent by slug: a re-run updates what it owns, and a document that disappears removes its fact.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'learn-home: the hoard is unresolved\n' >&2; exit 2; }
DEST="$HOME_R/hodd/identity/assistant/approved"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
mkdir -p "$DEST" 2>/dev/null || exit 3

ROOT_DIR="$ROOT" HOME_Q="$HOME_R" DEST_Q="$DEST" DRY_Q="$DRY" python3 - <<'PY'
import glob, os, re, time

root, home, dest = (os.environ[k] for k in ("ROOT_DIR", "HOME_Q", "DEST_Q"))
dry = os.environ["DRY_Q"] == "1"
today = time.strftime("%Y-%m-%d")
STAMP = "generated_by: bin/assistant/learn-home.sh"
written: list[str] = []


def clean(text: str) -> str:
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"[*_`|]", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:90]


def fact(title: str, claim: str, source: str) -> None:
    claim = clean(claim)[:400]
    if len(claim) < 12:
        return
    name = slug(f"home-{title}")
    written.append(name)
    if dry:
        return
    body = ("---\n"
            "approved_by: document\n"
            f"approved_at: {today}\n"
            "class: internal\naudience: owner\nverbatim: true\n"
            f"source: {source}\n{STAMP}\n"
            f"generated_at: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n"
            "---\n"
            f"{claim}\n")
    with open(os.path.join(dest, name + ".md"), "w") as fh:
        fh.write(body)


def rel(path: str) -> str:
    """Provenance, never spoken: the home's own path if it is in the home, else the repo's."""
    if not path.startswith(home):
        return os.path.relpath(path, root)
    try:
        return os.path.relpath(path, home)
    except ValueError:
        return os.path.basename(path)


# ── the home's documents: ONE fact per document, from its own heading ─────────────────────────
# Not from INDEX.md's prose. The first attempt parsed that page with a regex and produced facts
# like "The Allfather's home holds Last updated — 2026-09-20" — noise that would make him talk
# about the wrong things while looking thorough. A document proves its own title; that is all a
# shelf fact needs, and it cannot rot the way a hand-written index line does.
def doc_fact(path: str, prefix: str = "home") -> None:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            head_text = fh.read(4000)
    except OSError:
        return
    title, status = "", ""
    for line in head_text.splitlines():
        if not title and line.startswith("# "):
            title = line[2:].strip()
        m = re.search(r"\*\*Status:\*\*\s*([a-z][a-z ,-]{2,40})", line, re.I)
        if m and not status:
            status = m.group(1).strip().rstrip(".")
        if title and status:
            break
    if not title or len(title) < 4:
        return
    title = re.sub(r"^plan\s+\d+\s*[—–:-]\s*", "", title, flags=re.I)
    fact(f"doc {rel(path)}", f"{clean(title)}" + (f" — status {status}" if status else "") + ".",
         rel(path))


docs = []
for base in (os.path.join(home, "hodd"),):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in ("node_modules", ".git", "__pycache__")]
        for name in filenames:
            if name.endswith(".md") and name != "INDEX.md":
                docs.append(os.path.join(dirpath, name))
for path in sorted(docs)[:400]:
    doc_fact(path)

# ── the house law, by title ───────────────────────────────────────────────────────────────────
for path in sorted(glob.glob(os.path.join(root, "RULES", "[0-9]*.md"))):
    title = ""
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("# "):
            title = line[2:].strip()
            break
    if title:
        fact(f"rule {os.path.basename(path)[:2]}", f"House law: {title}.", rel(path))

# ── the plan ledger: number · title · status ────────────────────────────────────────────────
plans = glob.glob(os.path.join(home, "svartalfaheim", "*", "projects", "*", "plans", "[0-9]*.md"))
plans += glob.glob(os.path.join(home, "svartalfaheim", "*", "workspace", "*", "plans", "[0-9]*.md"))
for path in sorted(plans):
    head_text = open(path, encoding="utf-8", errors="replace").read(2500)
    title = ""
    for line in head_text.splitlines():
        if line.startswith("# "):
            title = line[2:].strip()
            break
    status = ""
    m = re.search(r"\*\*Status:\*\*\s*([a-z][a-z -]{2,30})", head_text, re.I)
    if m:
        status = m.group(1).strip().lower()
    number = re.match(r"(\d+)", os.path.basename(path))
    if title and number:
        spoken = re.sub(r"^plan\s+\d+\s*[—–:-]\s*", "", title, flags=re.I)
        fact(f"plan {number.group(1)}",
             f"Plan {number.group(1)}: {spoken}" + (f" — status {status}" if status else "") + ".",
             rel(path))

# ── the home's own tools ────────────────────────────────────────────────────────────────────
doors = os.path.join(home, "hodd", "bin", "DOORS.md")
if os.path.exists(doors):
    for line in open(doors, encoding="utf-8"):
        m = re.match(r'^\s*"([^"]+)","([^"]+)"', line.strip())
        if m:
            fact(f"tool {m.group(1)}", f"The home's own tool {m.group(1)}: {m.group(2)}.",
                 rel(doors))

# ── a shelf fact per top-level home folder, so "what is in my home" has an answer ────────────
hodd = os.path.join(home, "hodd")
shelves = sorted(d for d in os.listdir(hodd) if os.path.isdir(os.path.join(hodd, d))
                 and not d.startswith(".")) if os.path.isdir(hodd) else []
if shelves:
    fact("the home",
         "The Allfather's home (YMIR_HOME) holds these shelves under hodd/: " + ", ".join(shelves) + ".",
         "hodd/")

# ── retire facts this pass no longer produces (the same discipline learn-house uses) ─────────
removed = []
for path in glob.glob(os.path.join(dest, "home-*.md")):
    name = os.path.basename(path)[:-3]
    if name in written:
        continue
    body = open(path, encoding="utf-8", errors="replace").read()
    if STAMP in body:
        removed.append(name)
        if not dry:
            os.remove(path)

print(f'learn-home{{written,removed,dest,dry}}:"{len(written)}","{len(removed)}","{dest}","{int(dry)}"')
for name in removed:
    print(f'  removed "{name}"')
PY
