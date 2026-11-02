#!/usr/bin/env bash
# learn-house.sh — give Skírnir the house's own public knowledge: the lore and the feature catalogue.
#
#   bin/assistant/learn-house.sh [--dry-run]
#
# His words, 2026-10-22: *"he needs to know a lot about ymir … we have the FEATURES.md and the lore.md"*.
# Both files are PUBLIC (they ship in this repo), so nothing private crosses into the digest. Each row
# becomes ONE approved fact, read VERBATIM — a paraphrased feature description is how a catalogue turns
# into a rumour. The lore's "Odin" is rewritten to "the Allfather": the name law binds the mouth, not
# just the prompt.
#
# Idempotent: facts are keyed by slug, so a re-run updates the claims it owns and touches nothing else.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'learn-house: the hoard is unresolved\n' >&2; exit 2; }
DEST="$HOME_R/hodd/identity/assistant/approved"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
mkdir -p "$DEST" 2>/dev/null || exit 3

ROOT_DIR="$ROOT" DEST_Q="$DEST" DRY_Q="$DRY" python3 - <<'PY'
import os, re, time

root, dest, dry = os.environ["ROOT_DIR"], os.environ["DEST_Q"], os.environ["DRY_Q"] == "1"
today = time.strftime("%Y-%m-%d")
written = []

def clean(text: str) -> str:
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)      # markdown links → their words
    text = re.sub(r"[*_`]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace("Odin's", "the Allfather's").replace("Odin", "the Allfather")
    return text

def fact(slug: str, claim: str, source: str) -> None:
    claim = claim.strip()
    if len(claim) < 12:
        return
    claim = claim[:400]
    body = ("---\n"
            "approved_by: the Allfather\n"
            f"approved_at: {today}\n"
            "class: public\naudience: public\nverbatim: true\n"
            f"source: {source}\ngenerated_by: bin/assistant/learn-house.sh\n"
            f"generated_at: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n"
            "---\n"
            f"{claim}\n")
    written.append(slug)
    if dry:
        return
    with open(os.path.join(dest, slug + ".md"), "w") as fh:
        fh.write(body)

# ── the lore: one fact per named thing ────────────────────────────────────────────────────────
lore = os.path.join(root, "docs", "lore.md")
if os.path.exists(lore):
    for line in open(lore, encoding="utf-8"):
        if not line.startswith("| **"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        name = clean(cells[0])
        what = clean(cells[1])
        if not name or not what or set(name) <= set("- "):
            continue
        # a one-word gloss ("control plane") is not a fact — the catalogue row will carry it
        if len(what) < 15 or what.lower() == name.lower():
            continue
        key = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:40]
        fact(f"lore-{key}", f"{name}: {what}", "docs/lore.md")

# ── the feature catalogue: one fact per row ───────────────────────────────────────────────────
feat = os.path.join(root, "FEATURES.md")
if os.path.exists(feat):
    for line in open(feat, encoding="utf-8"):
        if not line.startswith("| ") or line.startswith("| ---") or line.startswith("| Domain"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        domain, name, what = clean(cells[0]), clean(cells[1]), clean(cells[2])
        if not name or len(what) < 20:
            continue
        key = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:50]
        fact(f"feature-{key}", f"Ymir has a feature: {name} ({domain}). {what}", "FEATURES.md")

# the generator OWNS only what it marked: a fact it no longer produces is removed, and nothing else
# in `approved/` is ever touched (his own facts carry no `generated_by` line).
removed = []
if not dry:
    for name in os.listdir(dest):
        if not name.endswith(".md"):
            continue
        path = os.path.join(dest, name)
        try:
            head = open(path, encoding="utf-8").read(600)
        except Exception:
            continue
        if "generated_by: bin/assistant/learn-house.sh" in head and name[:-3] not in written:
            os.unlink(path)
            removed.append(name[:-3])

print(f"learn-house[1]{{facts,removed,dry}}: \"{len(written)}\",\"{len(removed)}\",\"{'yes' if dry else 'no'}\"")
PY
if [ "$DRY" -eq 0 ]; then
  bash "$SCRIPT_DIR/kb-export.sh" >/dev/null 2>&1 || true
  printf 'learn-house: digest rebuilt — %s facts\n' "$(python3 -c "
import os
p = os.path.join('$HOME_R', 'hodd', 'state', 'assistant', 'digest.jsonl')
print(sum(1 for l in open(p) if l.strip()) if os.path.exists(p) else 0)")"
fi
