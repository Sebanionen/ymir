#!/usr/bin/env bash
# kb-export.sh — build Skírnir's digest from facts the Allfather APPROVED, and nothing else.
#
# The digest is not a filtered copy of the house; it is a set of separately approved facts, one
# file each, in $YMIR_HOME/hodd/state/assistant/approved/. A fact without an approval header is
# refused. The vault is never read, never mounted, never indexed.
#
#   bin/assistant/kb-export.sh           # rebuild digest.jsonl
#   bin/assistant/kb-export.sh --list    # what is approved right now
#
# Exit: 0 ok · 1 a file is unapprovable · 2 usage.
set -u
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
# shellcheck disable=SC1091
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'error: the home is unresolved\n' >&2; exit 1; }
APPROVED="$HOME_R/hodd/identity/assistant/approved"
DIGEST="$HOME_R/hodd/state/assistant/digest.jsonl"
IDENTITY="$HOME_R/hodd/identity/assistant"

[ "${1:-}" = "--list" ] && { ls -1 "$APPROVED"/*.md 2>/dev/null | sed 's|.*/||;s|\.md$||'; exit 0; }

ROOT_DIR="$ROOT" HOME_DIR_Q="$HOME_R" IDENTITY_Q="$IDENTITY" APPROVED_Q="$APPROVED" DIGEST_Q="$DIGEST" python3 - <<'PY'
import hashlib, json, os, re, subprocess, sys, time

approved = os.environ["APPROVED_Q"]
digest = os.environ["DIGEST_Q"]
rows, refused = [], []
for name in sorted(os.listdir(approved) if os.path.isdir(approved) else []):
    if not name.endswith(".md"):
        continue
    path = os.path.join(approved, name)
    text = open(path, encoding="utf8").read()
    if not text.startswith("---"):
        refused.append((name, "no approval header"))
        continue
    try:
        _, header, body = text.split("---", 2)
    except ValueError:
        refused.append((name, "malformed header"))
        continue
    meta = {}
    for line in header.strip().splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    # Approval is a person's signature — with ONE documentary exception: an `internal` fact (the
    # owner's own map of his home, written by bin/assistant/learn-home.sh) is proved by the document
    # it cites, so it carries `approved_by: document`. That word buys nothing anywhere else: a public
    # claim signed by a machine is exactly the forgery this refusal exists to stop.
    approver = meta.get("approved_by", "").lower()
    klass_raw = str(meta.get("class", "public")).lower()
    documentary = approver == "document" and klass_raw == "internal"
    if approver not in ("the allfather", "allfather") and not documentary:
        refused.append((name, "not approved by the Allfather (only an internal fact may be "
                              "approved by its document)"))
        continue
    if "expires" in meta and meta["expires"] < "2026-10-21":
        refused.append((name, "expired"))
        continue
    claim = re.sub(r"\s+", " ", body).strip()
    rows.append({"slug": name[:-3], "class": meta.get("class", "public"),
                 "verbatim": str(meta.get("verbatim", "")).strip().lower() in ("true", "yes", "1"),
                 "audience_declared": meta.get("audience", ""),
                 "approved_by": meta.get("approved_by"), "approved_at": meta.get("approved_at", ""),
                 "expires": meta.get("expires", ""), "claim": claim,
                 "hash": hashlib.sha256(claim.encode()).hexdigest()[:16],
                 "source": os.path.basename(path)})

# ── the directory: who the Allfather works with, from the collaborators registry ──────────
# Names, organisations and roles are facts he asked Skírnir to know. Addresses are NOT exported:
# they are personal data, and the engine never needs them to say who someone is.
reg = os.path.join(os.environ["HOME_DIR_Q"], "hodd", "identity", "collaborators.yaml")
try:
    import yaml
    with open(reg) as fh:
        people = (yaml.safe_load(fh) or {}).get("people", []) or []
except Exception:
    people = []
for person in people:
    name = (person.get("name") or "").strip()
    if not name:
        continue
    kind = person.get("kind", "contact")
    org = (person.get("org") or "").strip()
    project = (person.get("project") or "").strip()
    claim = f"{name} is a {kind}" + (f" at {org}" if org else "") + \
            (f", working on {project}" if project else "") + "."
    slug = "contact-" + re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    rows.append({"slug": slug, "class": "contacts", "approved_by": "the Allfather",
                 "approved_at": "2026-10-21", "expires": "",
                 "claim": claim, "hash": hashlib.sha256(claim.encode()).hexdigest()[:16],
                 "source": "collaborators.yaml"})

# ── the canaries, DERIVED: plan titles, the vault's markers, and the secret KEY names ──────────
# Hand-maintaining a canary list means a new plan is born unguarded. So they are collected:
# every plan title in the ledger, every marker word from the base list, and every secret KEY name
# (never a value) — the strings that must never appear in anything Skírnir says.
import glob
canary_path = os.path.join(os.path.dirname(digest), "canaries.derived.txt")
canaries = set()
ledger = os.path.join(os.environ.get("HOME_DIR_Q", ""), "svartalfaheim")
for plan in glob.glob(os.path.join(ledger, "**", "plans", "*.md"), recursive=True):
    try:
        with open(plan, encoding="utf8") as fh:
            first = fh.readline().strip()
    except OSError:
        continue
    m = re.match(r"^#\s*Plan\s+\d+\s*[—-]\s*(.+)$", first)
    if m:
        title = re.sub(r"\s*\(.*?\)\s*$", "", m.group(1)).strip()
        if 8 <= len(title) <= 60:
            canaries.add(title)
    canaries.add(os.path.basename(plan)[:-3])
# specific markers only: a common noun like "vault" turns every honest sentence into a refusal
for token in ("Hnitbjörg", "age.key", "platform.env.age", "runes_audit.md", "kaia.engram"):
    canaries.add(token)
env = os.path.join(os.environ.get("HOME_DIR_Q", ""), "hodd", "secrets", "platform.env")
try:
    out = subprocess.run(["bash", os.path.join(os.environ.get("ROOT_DIR", ""), "bin", "vault", "hodd.sh"),
                          "emit", "secrets/platform.env"], capture_output=True, text=True, timeout=30).stdout
    for line in out.splitlines():
        m = re.match(r"^export ([A-Z_]+)=", line)
        if m:
            canaries.add(m.group(1))
except Exception:
    pass
# A canary must be DISTINCTIVE, or the wall mutes him on ordinary prose. Measured 2026-10-22: the
# derived list carried bare words ('queue', 'register', 'questions'), so an honest answer containing
# the word "questions" was refused by his own gate. Keep only tokens with the shape of an identifier:
# ten characters or more, AND a digit, a separator, an inner capital, or a non-ASCII letter.
import re as _re
def _distinctive(token: str) -> bool:
    if _re.search(r"[./]", token):                       # a path or a vault marker: age.key, 102-…md
        return len(token) >= 5
    if _re.match(r"^[A-Z0-9_]{6,}$", token):             # a secret KEY name: NPM_TOKEN, GITHUB_APP_ID
        return True
    if _re.search(r"[^\x00-\x7F]", token):               # Hnitbjörg
        return len(token) >= 6
    if _re.search(r"[0-9]", token) and _re.search(r"[-_]", token):   # a plan title: 101-the-assistant
        return True
    return False                                          # 'questions', 'queue', 'register' — prose

with open(canary_path, "w") as fh:
    for token in sorted(c for c in canaries if c and _distinctive(c)):
        fh.write(token + "\n")

def audience_for(row):
    if row.get("audience_declared"):
        return row["audience_declared"]
    klass = str(row.get("class", "public")).lower()
    if klass == "public":
        return "public"
    if klass in ("logistics", "role"):
        return "public,owner"
    if klass == "contacts":
        return "owner"
    if klass in ("nda", "contracted", "restricted"):
        parties = [p.strip() for p in str(row.get("parties", "")).split(",") if p.strip()]
        return "owner," + ",".join(f"person:{p}" for p in parties) if parties else "owner"
    return "owner"


for row in rows:
    row["audience"] = audience_for(row)

os.makedirs(os.path.dirname(digest), exist_ok=True)
with open(digest, "w") as fh:
    for row in rows:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")

# ── the DATABASE: the same rows, in a shape a query door can enforce ───────────────────────
# He is given a database, not a filesystem. Every read goes through a fixed query with the class
# and the tier applied, and every read is audited. No SQL ever comes from the model.
import sqlite3
db = os.path.join(os.path.dirname(digest), "kb.db")
con = sqlite3.connect(db)
con.executescript("""
CREATE TABLE IF NOT EXISTS schema_version (version INTEGER, applied TEXT);
DROP TABLE IF EXISTS facts;
CREATE TABLE facts (
  slug TEXT PRIMARY KEY, class TEXT NOT NULL, claim TEXT NOT NULL,
  hash TEXT, source TEXT, approved_at TEXT, expires TEXT, parties TEXT,
  audience TEXT DEFAULT 'public'
);
CREATE TABLE IF NOT EXISTS people (
  id TEXT PRIMARY KEY, name TEXT, kind TEXT, status TEXT, org TEXT,
  project TEXT, nda TEXT, emails TEXT, telegram_ids TEXT
);
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY, name TEXT, status TEXT, classification TEXT
);
CREATE TABLE IF NOT EXISTS read_audit (
  ts TEXT, tier TEXT, channel TEXT, query TEXT, hits INTEGER
);
""")
if not con.execute("SELECT 1 FROM schema_version LIMIT 1").fetchone():
    con.execute("INSERT INTO schema_version VALUES (1, ?)", (time.strftime("%Y-%m-%dT%H:%M:%S%z"),))

# ── people and projects, from the operator's own registries ───────────────────────────────────
ident = {}
try:
    import yaml as _yaml
    gpath = os.path.join(os.environ.get("IDENTITY_Q", ""), "grants.yaml")
    grants = _yaml.safe_load(open(gpath)) or {}
    ident = {str(k): str(v) for k, v in (grants.get("identities") or {}).items()}
except Exception:
    pass
for person in people:
    pid = person.get("id", "")
    tids = ",".join(k for k, v in ident.items() if v == pid)
    con.execute("INSERT OR REPLACE INTO people VALUES (?,?,?,?,?,?,?,?,?)",
                (pid, person.get("name", ""), person.get("kind", ""), person.get("status", ""),
                 person.get("org", ""), person.get("project", ""), str(person.get("nda", "")),
                 ",".join(person.get("emails") or []), tids))
    if person.get("project"):
        con.execute("INSERT OR REPLACE INTO projects VALUES (?,?,?,?)",
                    (person["project"], person["project"], person.get("status", ""), "business"))
# the AUDIENCE a fact carries: who may hear it. A class is a kind; an audience is a door.
def audience_for(row):
    if row.get("audience_declared"):
        return row["audience_declared"]
    klass = str(row.get("class", "public")).lower()
    slug = row.get("slug", "")
    if klass == "public":
        return "public"
    if klass in ("logistics", "role"):
        return "public,owner"
    if klass == "contacts":
        return "owner"
    if klass in ("nda", "contracted", "restricted"):
        parties = [p.strip() for p in str(row.get("parties", "")).split(",") if p.strip()]
        return "owner," + ",".join(f"person:{p}" for p in parties) if parties else "owner"
    return "owner"

for row in rows:
    row["audience"] = audience_for(row)
    con.execute("INSERT OR REPLACE INTO facts VALUES (?,?,?,?,?,?,?,?,?)",
                (row["slug"], row.get("class", "public"), row["claim"], row.get("hash", ""),
                 row.get("source", ""), row.get("approved_at", ""), row.get("expires", ""),
                 row.get("parties", ""), row["audience"]))
con.commit(); con.close()
print(f'kb-export[1]{{approved,refused,digest}}:"{len(rows)}","{len(refused)}","{digest}"')
for name, why in refused:
    print(f'  "refused {name}: {why}"')
PY
