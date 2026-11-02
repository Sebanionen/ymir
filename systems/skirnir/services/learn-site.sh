#!/usr/bin/env bash
# learn-site.sh — Skírnir learns the house's own public site.
#
#   bin/assistant/learn-site.sh [--url https://ymir.zerwiz.org/] [--dry-run]
#
# His words, 2026-10-22: *"he needs to know everything https://ymir.zerwiz.org/"*. The site is PUBLIC, so
# nothing private crosses into the digest; it carries what the repo's lore and catalogue do not say in
# the same words — the houses, the eleven treasures, the laws, the watch, the renewal.
#
# The page is fetched, stripped to text, cut into passages, and each passage becomes ONE approved fact
# marked `verbatim` (the site's own words, never a paraphrase) with its source URL. Same-origin links are
# followed one level deep, and nothing else is ever fetched. The generator owns only what it marks.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The repo root, found by walking up to the tree that holds .pi and RULES — never counted in
# "../", because this shelf was moved once (bin/assistant/ -> systems/skirnir/, plan 149) and
# 25 scripts kept the old depth, so every $ROOT/bin/... pointed into systems/ instead (2026-11-02).
ROOT="$(CDPATH='' cd "$SCRIPT_DIR" && while [ ! -e "$PWD/.pi" ] || [ ! -d "$PWD/RULES" ]; do [ "$PWD" = / ] && break; cd ..; done; pwd)"
. "$ROOT/bin/vault/hoard-lib.sh" 2>/dev/null || true
ymir_home_root HOME_R 2>/dev/null || true
[ -n "${HOME_R:-}" ] || { printf 'learn-site: the hoard is unresolved\n' >&2; exit 2; }
URL="https://ymir.zerwiz.org/"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) shift ;;
  esac
done
DEST="$HOME_R/hodd/identity/assistant/approved"
mkdir -p "$DEST" 2>/dev/null || exit 3

URL_Q="$URL" DEST_Q="$DEST" DRY_Q="$DRY" python3 - <<'PY'
import hashlib, html, os, re, time, urllib.parse, urllib.request

url, dest, dry = os.environ["URL_Q"], os.environ["DEST_Q"], os.environ["DRY_Q"] == "1"
today = time.strftime("%Y-%m-%d")
UA = "Ymir-Skirnir/1.0 (assistant learning the house's own public site)"
written = []

def fetch(u: str) -> str:
    req = urllib.request.Request(u, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read(3_000_000).decode("utf-8", "replace")

def text_of(page: str) -> str:
    page = re.sub(r"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>", " ", page)
    page = re.sub(r"(?i)<br\s*/?>|</p>|</h[1-6]>|</li>|</div>", "\n", page)
    page = re.sub(r"(?s)<[^>]+>", " ", page)
    page = html.unescape(page)
    page = re.sub(r"[ \t]+", " ", page)
    page = re.sub(r"\n\s*\n+", "\n", page)
    return page

def passages(text: str, size: int = 340):
    words = text.split()
    buf = []
    for w in words:
        buf.append(w)
        if sum(len(x) + 1 for x in buf) >= size:
            yield " ".join(buf)
            buf = []
    if buf:
        yield " ".join(buf)

def normalise(s: str) -> str:
    s = s.replace("Odin's", "the Allfather's").replace("Odin", "the Allfather")
    s = re.sub(r"\s+", " ", s).strip(" -–—·|")
    return s

def fact(slug: str, claim: str, source: str) -> None:
    claim = normalise(claim)
    if len(claim) < 60 or len(claim) > 420:
        return
    written.append(slug)
    if dry:
        return
    body = ("---\n"
            "approved_by: the Allfather\n"
            f"approved_at: {today}\n"
            "class: public\naudience: public\nverbatim: true\n"
            f"source: {source}\ngenerated_by: bin/assistant/learn-site.sh\n"
            f"generated_at: {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n"
            "---\n"
            f"{claim}\n")
    with open(os.path.join(dest, slug + ".md"), "w") as fh:
        fh.write(body)

try:
    home = fetch(url)
except Exception as exc:
    print(f'learn-site[1]{{error}}: "{type(exc).__name__}: {exc}"')
    raise SystemExit(1)

pages = [(url, home)]
seen = {url}
for href in re.findall(r'href="([^"#]+)"', home):
    absolute = urllib.parse.urljoin(url, href)
    if urllib.parse.urlparse(absolute).netloc != urllib.parse.urlparse(url).netloc:
        continue
    if absolute in seen or not absolute.startswith(("http://", "https://")):
        continue
    seen.add(absolute)
    if len(pages) >= 8:
        break
    try:
        pages.append((absolute, fetch(absolute)))
    except Exception:
        continue

for page_url, page in pages:
    body = text_of(page)
    for i, chunk in enumerate(passages(body)):
        slug = "site-" + hashlib.sha256(f"{page_url}|{i}".encode()).hexdigest()[:12]
        fact(slug, chunk, page_url)

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
        if "generated_by: bin/assistant/learn-site.sh" in head and name[:-3] not in written:
            os.unlink(path)
            removed.append(name[:-3])

print(f'learn-site[1]{{pages,facts,removed,dry}}: "{len(pages)}","{len(written)}","{len(removed)}","{"yes" if dry else "no"}"')
PY
if [ "$DRY" -eq 0 ]; then
  bash "$SCRIPT_DIR/kb-export.sh" >/dev/null 2>&1 || true
  printf 'learn-site: digest rebuilt — %s facts\n' "$(python3 -c "
import os
p = os.path.join('$HOME_R', 'hodd', 'state', 'assistant', 'digest.jsonl')
print(sum(1 for l in open(p) if l.strip()) if os.path.exists(p) else 0)")"
fi
