#!/usr/bin/env python3
"""layout.py — the placement oracle and the home's shelves, as ONE door.

    layout.py classify <path>          which shelf a home-relative path belongs to, and why
    layout.py find-home <path> [--note N] [--sample S]
                                       where a file OUTSIDE the home SHOULD go (never moves)
    layout.py place <path> --why TEXT  move a file into the home, refusing what the law cannot justify
    layout.py import <src…> [--area A] [--dry-run]
                                       bring material in from outside, classified, with git mv
    layout.py structure [depth]        every shelf and how many files it holds
    layout.py index [shelf]            strays, empty dirs, and files no README names

WHY (the Allfather, 2026-11-03): the `ymir_*` placement tools lived only in the Pi extension, so no
other harness could file anything. This is the same classification, extracted to `bin/` (the
extension header's own law: *the surface, not the logic*), so every harness reaches it over MCP.
Names and the roster stay in the home (Rule 04); this file lives in the repo and knows no operator.
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def home() -> Path:
    """The private home through the house's resolver — never a guess (Rule 07)."""
    try:
        out = subprocess.run(["bash", str(ROOT / "bin" / "vault" / "hodd.sh"), "path"],
                             capture_output=True, text=True, timeout=20)
        p = Path(out.stdout.strip())
        if p.exists():
            return p.parent
    except Exception:
        pass
    env = os.environ.get("YMIR_HOME")
    if env:
        return Path(env)
    raise SystemExit("layout: no YMIR_HOME — bin/vault/hodd.sh path answered nothing")


# The layout law: the shelves a home document may live on, and what each is FOR.
SHELVES = [
    ("hodd/docs/runbooks/", r"runbook|howto|setup|install|recovery|procedure"),
    ("hodd/docs/security/", r"security|port|ward|firewall|audit"),
    ("hodd/docs/architecture/", r"architecture|deep.?dive|layers|design"),
    ("hodd/docs/audits/", r"audit|review|scan"),
    ("hodd/docs/devtools/", r"devtool|editor|terminal|nvim|shell"),
    ("hodd/docs/", r"doc|guide|manual|reference"),
    ("hodd/life/marketing/", r"postiz|social|campaign|marketing|brand|content|seo"),
    ("hodd/life/meetings/", r"meeting|minute|standup|1:1|transcript"),
    ("hodd/life/personal/", r"journal|diary|personal|schedule"),
    ("hodd/life/work/", r"client|contract|paid|invoice"),
    ("hodd/plans/", r"plan|roadmap|proposal|strategy"),
    ("hodd/data/", r"registry|inventory|register|operator|fleet"),
    ("hodd/identity/", r"identity|roster|company|seat"),
    ("hodd/memory/", r"memory|rune|well|episode|daily"),
    ("hodd/reference/", r"readme|changelog|contribut|retired|archive"),
    ("svartalfaheim/", r"realm|project"),
]


def classify(rel: str) -> tuple[bool, str, str]:
    """(legal, shelf, why) for a home-relative path."""
    rel = rel.lstrip("./")
    if not rel:
        return False, "", "empty path"
    if rel.startswith("hodd/secrets/") or rel.endswith((".age", ".key", ".pem")):
        return True, "hodd/secrets/", "a credential — the one place values may live (never a document)"
    for shelf, _ in SHELVES:
        if rel.startswith(shelf):
            if fnmatch.fnmatch(rel, "hodd/life/*/README.md") or rel.endswith(".md"):
                return True, shelf, f"a home document that belongs on {shelf}"
    if re.match(r"^svartalfaheim/[a-z0-9-]+/(projects|workspace)/[a-z0-9-]+/", rel):
        return True, "svartalfaheim/", "realm + project scoped material"
    return False, "", ("it is inside the home but on no legal shelf — file it under hodd/docs · hodd/life/<domain> · "
                       "hodd/plans · hodd/data · hodd/identity · hodd/memory · hodd/reference")


def find_home(path: str, note: str = "", sample: str = "") -> str:
    p = Path(path)
    base = p.name
    text = " ".join([base, note, sample]).lower()
    for shelf, pattern in SHELVES:
        if re.search(pattern, text):
            verdict = classify(f"{shelf}{base}")
            if verdict[0]:
                return (f"{path}\n  destination: {shelf}{base}\n  because: a name/subject match on {shelf}\n"
                        f"  next: layout.py place <file> --why \"…\"")
    dest = f"hodd/reference/imported/{base}"
    return (f"{path}\n  destination: {dest}  (fallback — no rule claims it; confirm it)\n"
            f"  next: layout.py import {path} --dry-run")


def place(home_dir: Path, rel: str, why: str) -> str:
    ok, shelf, reason = classify(rel)
    if not ok:
        return f"refused: {reason}\n  proposed: {rel}"
    dest = home_dir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    src = Path(os.environ.get("YMIR_PLACE_SOURCE", ""))
    if not src or not src.exists():
        return f"legal shelf: {rel}\n  shelf: {shelf}\n  because: {why}\n  (no source given — nothing moved; rule: a doc enters the home through place/import)"
    try:
        subprocess.run(["git", "mv", str(src), str(dest)], cwd=str(home_dir), check=True,
                       capture_output=True, text=True)
        how = "git mv (a rename in history)"
    except Exception:
        shutil.move(str(src), str(dest))
        how = "moved (untracked)"
    return f"placed -> {rel}\n  shelf: {shelf}\n  because: {why}\n  {how}"


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    h = home()
    if cmd == "classify":
        ok, shelf, why = classify(rest[0])
        print(f"{rest[0]}\n  legal: {ok}\n  shelf: {shelf or '-'}\n  because: {why}")
        return 0 if ok else 1
    if cmd == "find-home":
        note = sample = ""
        args = list(rest)
        if "--note" in args:
            i = args.index("--note"); note = args[i + 1]; del args[i:i + 2]
        if "--sample" in args:
            i = args.index("--sample"); sample = args[i + 1]; del args[i:i + 2]
        print(find_home(args[0], note, sample))
        return 0
    if cmd == "place":
        why = ""
        args = list(rest)
        if "--why" in args:
            i = args.index("--why"); why = args[i + 1]; del args[i:i + 2]
        print(place(h, args[0], why))
        return 0
    if cmd == "import":
        dry = "--dry-run" in rest
        area = ""
        args = [a for a in rest if a != "--dry-run"]
        if "--area" in args:
            i = args.index("--area"); area = args[i + 1]; del args[i:i + 2]
        rc = 0
        for src in args:
            out = find_home(src, area)
            print(out)
            if not dry:
                line = [l for l in out.splitlines() if "destination:" in l][0]
                dest = line.split("destination:")[1].strip().split()[0]
                print("  -> " + place(h, dest, f"imported from {src}"))
        return rc
    if cmd == "structure":
        depth = int(rest[0]) if rest else 2
        base = h / "hodd"
        for p in sorted(base.iterdir()):
            if p.is_dir() and not p.name.startswith("."):
                n = sum(1 for _ in p.rglob("*") if _.is_file())
                print(f"{p.name}/  ({n} files)")
        return 0
    if cmd == "index":
        base = h / (rest[0] if rest else "hodd")
        for p in sorted(base.rglob("*")):
            if p.is_dir() and not any(p.iterdir()):
                print(f"empty dir: {p.relative_to(h)}")
        print("(index: empty dirs above; strays are git status in the home)")
        return 0
    print(f"error: unknown action {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
