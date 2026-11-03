#!/usr/bin/env bash
# language-guard.sh — two tongues: English for the work, Old Norse for the names.
#
# RULE 43. The house writes in English. Old Norse is the ONE other tongue allowed, because it
# is what the house is NAMED in — the figures, the shelves, the halls, and the runic script
# those names are carved in. Everything else is refused: Chinese, Swedish, German, Spanish,
# Japanese, Russian — a user must be able to read the house they run.
#
# WHAT IT JUDGES, exactly — and what it honestly cannot:
#
#   1  A LETTER THAT IS NOT ENGLISH, OLD NORSE, OR RUNIC IS REFUSED. That single test catches
#      every foreign script (Han, Kana, Hangul, Cyrillic, Greek, Arabic, Hebrew, Thai,
#      Devanagari) and every foreign Latin letter (ä · å · ü · ß · ç · ñ · ø · š · į · ł).
#      Allowed Latin is ASCII plus the Old Norse/Icelandic set á é í ó ú ý þ ð æ ö ǫ ę œ (and
#      their capitals); allowed non-Latin is the Runic block (U+16A0–U+16FF) — the house's own
#      carvings.
#   2  A DIACRITIC-FREE FOREIGN PROSE IS CAUGHT BY ITS FUNCTION WORDS — Dutch, Danish,
#      Norwegian, Indonesian, Tagalog, and a Swedish paragraph that carries no ä. Only PROSE
#      lines are read (≥6 words, code punctuation absent), so a regex, an identifier or a CSS
#      class cannot be mistaken for a sentence.
#
# Three exceptions are LEGAL, and each must be declared in `language.allow` with its reason:
#
#   fixture    a test that proves unicode handling — the foreign text is the assertion
#   detector   code that RECOGNISES a foreign language — the foreign words are matching DATA;
#              recognising a language is not writing in it (the assistant's Swedish hints)
#   quotation  a real person's actual words, or a program's own output, kept as it came
#   table      a table of LETTERS — a transliteration, an alphabet, a character map — where the
#              characters are the subject and not prose
#   specimen   the rule, or a record of it, that NAMES the characters it refuses — a gate has to
#              be able to say "this letter" without becoming a violation of itself
#
# A guard that cannot fail is not a guard: `--self-test` plants a Chinese line, a Swedish
# paragraph, a German sentence and an Old Norse line in a throwaway root, and requires the
# first three to be refused and the fourth to pass.
#
#   language-guard.sh [check]      # judge the tree
#   language-guard.sh --list       # the allow list as it is read
#   language-guard.sh --self-test  # prove the ward bites
#
# Exit: 0 clean · 1 a finding · 2 usage.
set -uo pipefail
VERSION="1.0.0"

_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.pi" ] && [ -d "$d/RULES" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
}
ROOT="$(_root)"

case "${1-}" in
  -v|-V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
  -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  ""|check|--all) MODE=check ;;
  --list) grep -vE '^\s*(#|$)' "$ROOT/language.allow" 2>/dev/null; exit $? ;;
  --self-test) MODE=selftest ;;
  *) printf 'error: unknown action %s\nhelp: language-guard.sh [check|--list|--self-test]\n' "${1-}" >&2; exit 2 ;;
esac

judge() {  # <root> <git|dir>
  python3 - "$1" "$2" <<'PY'
import fnmatch, os, re, subprocess, sys, unicodedata

ROOT, MODE = sys.argv[1], sys.argv[2]

ON = set("áéíóúýþðæöǫęœÁÉÍÓÚÝÞÐÆÖǪĘŒ")
RUNIC = (0x16A0, 0x16FF)

SCRIPT_NAMES = ("CJK", "HIRAGANA", "KATAKANA", "HANGUL", "CYRILLIC", "GREEK", "ARABIC",
                "HEBREW", "THAI", "DEVANAGARI", "ARMENIAN", "GEORGIAN", "BENGALI", "TAMIL",
                "TELUGU", "KANNADA", "MALAYALAM", "GUJARATI", "GURMUKHI", "ORIYA", "SINHALA",
                "KHMER", "LAO", "MYANMAR", "TIBETAN", "ETHIOPIC", "CHEROKEE", "MONGOLIAN")

def script_of(ch):
    try:
        n = unicodedata.name(ch)
    except ValueError:
        return "?"
    for s in SCRIPT_NAMES:
        if s in n:
            return s
    return "LATIN" if "LATIN" in n else "?"

ALLOW, bad_allow = {}, []
p = os.path.join(ROOT, "language.allow")
if not os.path.exists(p):
    print("language_guard[1]{finding,path,detail}:")
    print('  "no allow list","language.allow","the three legal exceptions must be written down"')
    sys.exit(1)
for i, line in enumerate(open(p), 1):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    parts = [x.strip() for x in s.split("|")]
    if len(parts) != 3:
        bad_allow.append((i, "expected: path | class | reason")); continue
    path, cls, why = parts
    if cls not in ("fixture", "detector", "quotation", "table", "specimen"):
        bad_allow.append((i, f"class {cls!r} is not fixture · detector · quotation · table · specimen")); continue
    if len(why) < 12:
        bad_allow.append((i, f"{path}: a reason is required, and it must say something")); continue
    if not os.path.exists(os.path.join(ROOT, path)) and not any(c in path for c in "*?["):
        bad_allow.append((i, f"{path}: the path does not exist — a rotten allow line is a lie")); continue
    ALLOW[path] = cls

def allowed_path(rel):
    if rel in ALLOW:
        return True
    return any(fnmatch.fnmatch(rel, pat) for pat in ALLOW if any(c in pat for c in "*?["))

STOP = {
    "Swedish":    "och att är inte för med det som på av till från eller också bara detta denna den jag vi kan vad hur när vilken",
    "Danish":     "og ikke er det som til fra eller også bare denne jeg kan hvad hvordan hvornår hvilken",
    "Norwegian":  "og ikke er det som til fra eller også bare denne jeg kan hva hvordan når hvilken",
    "Dutch":      "het een van niet zijn voor met dat deze ook maar wij kan wat hoe wanneer welke",
    "German":     "und der nicht mit für ein eine ist auch sich werden wird diese aber wenn",
    "French":     "les des est que pour avec dans une sur pas plus sont cette mais nous quand",
    "Spanish":    "los las para pero con una este esta como más muy cuando porque nosotros",
    "Portuguese": "uma com para isso mais quando porque nós também muito esta este",
    "Italian":    "che non per con una sono questo questa degli anche quando perché noi",
    "Finnish":    "ja on ei että mutta joka myös kun mitä miten milloin tämä",
    "Polish":     "nie się jest oraz przez także kiedy ponieważ który która",
    "Turkish":    "bir bu için ile değil olarak daha çok zaman eğer veya",
    "Indonesian": "dan yang untuk dengan tidak dari ini itu juga akan sudah karena",
    "Tagalog":    "ang mga ng sa ay hindi para ito iyon din rin kung",
    "Vietnamese": "của không được người những trong này cho với",
}
STOP = {k: set(v.split()) for k, v in STOP.items()}
PROSE_PUNCT = set("{}[]<>/=;\\|$@#`~^")
SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".icns", ".pdf", ".zip", ".gz",
            ".tgz", ".woff", ".woff2", ".ttf", ".otf", ".mp4", ".wav", ".mp3", ".onnx", ".jar",
            ".lock", ".wasm", ".so", ".dylib", ".dll", ".exe", ".pak", ".pk3", ".bin")
SKIP_NAME = ("package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Cargo.lock", "poetry.lock")

def is_prose(line):
    toks = line.split()
    if len(toks) < 6:
        return False
    if sum(1 for c in line if c in PROSE_PUNCT) > max(2, len(line) // 12):
        return False
    return any(len(t) >= 4 and t.islower() for t in toks)

if MODE == "git":
    files = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
else:
    files = []
    for base, _, names in os.walk(ROOT):
        for n in names:
            files.append(os.path.relpath(os.path.join(base, n), ROOT))

findings = 0
def say(kind, path, detail):
    global findings
    findings += 1
    print(f'  "{kind}","{path}","{detail}"')

print("language_guard[3]{finding,path,detail}:")
for i, why in bad_allow:
    say("a bad allow line", f"language.allow:{i}", why)

for rel in sorted(files):
    if rel.endswith(SKIP_EXT) or os.path.basename(rel) in SKIP_NAME or rel == "language.allow":
        continue
    if allowed_path(rel):
        continue
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="ignore").read()
    except Exception:
        continue
    if "\x00" in text[:4096]:
        continue

    hits = {}
    for ch in text:
        o = ord(ch)
        if o < 128 or ch in ON:
            continue
        cat = unicodedata.category(ch)
        if cat[0] != "L" or cat == "Lm":      # letters only; a modifier letter is an apostrophe, not a word
            continue
        if RUNIC[0] <= o <= RUNIC[1]:
            continue
        if "GREEK" in unicodedata.name(ch, ""):   # pi and beta are mathematics, not a language
            continue
        hits[ch] = hits.get(ch, 0) + 1
    if hits:
        ch, n = max(hits.items(), key=lambda kv: kv[1])
        say("a letter that is not English, Old Norse or runic", rel,
            f"{ch!r} ({script_of(ch)}) x{n} — write it in English, or name it in Old Norse")

    lang_hits = {}
    for line in text.splitlines():
        if not is_prose(line):
            continue
        low = re.findall(r"[^\W\d_]+", line.lower())
        for lang, words in STOP.items():
            c = sum(1 for t in low if t in words)
            if c:
                entry = lang_hits.setdefault(lang, [0, set()])
                entry[0] += c
                entry[1] |= {t for t in low if t in words}
    for lang, (total, distinct) in sorted(lang_hits.items(), key=lambda kv: -kv[1][0]):
        if total >= 6 and len(distinct) >= 4:
            say(f"prose in {lang}", rel,
                f"{total} function words ({', '.join(sorted(distinct)[:4])} …) — the house writes in English")
            break

if findings == 0:
    print('  "none","","two tongues: English for the work, Old Norse for the names"')
    sys.exit(0)
sys.stderr.write(f"language-guard: {findings} finding(s) — the house writes in English, and Old Norse for its names\n")
sys.stderr.write("help: write it in English; a name may be Old Norse. A fixture, a detector or a quotation is declared in language.allow with its reason (RULES/43)\n")
sys.exit(1)
PY
}

if [ "$MODE" = selftest ]; then
  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/docs"
  # A throwaway allow list: the real one names paths that only exist in the real tree, so a
  # copy here would report every line as rotten — a self-test that fails for the wrong reason
  # teaches nothing.
  printf '# no exceptions in the test root\n' > "$T/language.allow"
  printf 'the config file is here and it is written in English\n' > "$T/docs/clean.md"
  printf '# 一个中文注释\nthe door opens\n' > "$T/docs/chinese.md"
  printf 'Vi behöver se över det här innan vi skickar det till kunden, och det är viktigt att vi gör det nu.\n' > "$T/docs/swedish.md"
  printf 'Die Konfiguration ist nicht fertig und wir müssen das prüfen, aber es ist wichtig.\n' > "$T/docs/german.md"
  printf 'Vi behover se over det har innan vi skickar det till kunden, och det ar viktigt att vi gor det nu.\n' > "$T/docs/swedish-plain.md"
  printf 'Þórr ok Óðinn ríða til Útgarðs — the runes stand, and Skírnir speaks.\n' > "$T/docs/oldnorse.md"
  out="$(judge "$T" dir 2>&1)"; rc=$?
  ok=0; bad=0
  for want in chinese.md swedish.md german.md swedish-plain.md; do
    printf '%s' "$out" | grep -q "$want" && ok=$((ok+1)) || { printf 'FAIL planted fault not caught: %s\n' "$want"; bad=$((bad+1)); }
  done
  printf '%s' "$out" | grep -q 'oldnorse.md' && { printf 'FAIL Old Norse was refused — the one other tongue is allowed\n'; bad=$((bad+1)); }
  printf '%s' "$out" | grep -q 'clean.md' && { printf 'FAIL English was refused\n'; bad=$((bad+1)); }
  [ "$rc" -eq 0 ] && { printf 'FAIL the ward passed on a tree full of faults\n'; bad=$((bad+1)); }
  if [ "$bad" -eq 0 ]; then
    printf 'language-guard: self-test PASS — %s planted fault(s) caught, Old Norse and English allowed\n' "$ok"
    exit 0
  fi
  printf '%s\n' "$out"
  printf 'language-guard: self-test FAILED — %s fault(s)\n' "$bad" >&2
  exit 1
fi

judge "$ROOT" git
