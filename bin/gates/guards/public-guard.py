#!/usr/bin/env python3
"""public-guard.py — the public tree carries TEMPLATES and LOGIC, and nothing private.

RULES/04, at the Allfather's word (2026-11-03): *"YMIR CAN ONLY CARRY TEMPLASTE AND LOCIG::
NOT SECREATS OR PRIVATE DATA::"*. The repository is PUBLIC, so four classes are refused:

  1. SECRET   — a credential shape (key, token, private key header).
  2. NAME     — a word the operator has declared his own (`$YMIR_HOME/hodd/security/operator-words.txt`).
                The words are NEVER in this file: RULES/04 says a guard that names them re-creates the leak.
  3. TOPOLOGY — a private address, a tailnet host, a machine name. Allowed only as a SHAPE:
                a CIDR range (`192.168.0.0/16`), RFC 5737 documentation space, or `<host>.tailnet.ts.net`.
  4. MAILBOX  — a personal address. Allowed only as an RFC 2606 example domain, a noreply account
                form, a house identity, an ssh identity (`git@github.com`), or a bare host with no dot.

Written in python because the shell version judged four classes with three chained greps and an
allow-list of substrings, and a ward whose allow-list can be satisfied by a substring is a ward that
passes on the thing it was meant to refuse (measured 2026-11-03: it both missed a real LAN default
and flagged its own rule text).

Usage:
  public-guard.py --tree            # every tracked file (what CI runs)
  public-guard.py --staged          # what is about to be committed
  public-guard.py FILE...           # named files
  public-guard.py --list            # the classes and what each allows

Exit: 0 clean · 1 findings · 2 usage.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

VERSION = "2.0.0"

# ── allowed shapes, named explicitly ────────────────────────────────────────────────────────────
# A RANGE is documentation; a HOST is a place this house stands. The distinction is the rule.
CIDR_ALLOWED = {
    "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10",
    "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24",  # RFC 5737
    "172.20.0.0/16",                                      # Docker's default bridge pool: a published constant
}
DOC_NETS = ("192.0.2.", "198.51.100.", "203.0.113.", "127.0.0.1", "0.0.0.0")
# A CLASSSIFIER'S OWN TEST needs an input on each side of the line — that is what it classifies.
# These are the first host of each declared range and the cloud metadata address everybody's
# allow-list names; they are not a place this house stands.
SENTINELS = {"10.0.0.0", "172.16.0.0", "192.168.0.0", "100.64.0.1", "169.254.169.254"}
# ALLOWED: the generic suffixes themselves (`tailnet.ts.net`, `tail.ts.net`) and the placeholder
# shapes. REFUSED: a real tailnet id (`tailefab81`) or a real seat name in front of one.
TAILNET_ALLOWED = re.compile(
    r"^(<host>|<seat>|<tailnet>|<machine>)?\.?(tailnet|tail)\.ts\.net$", re.I)
MAILBOX_ALLOWED_DOMAIN = re.compile(
    r"(^|\.)(example\.(com|org|net)|example|invalid|test|localhost|ymir|ymir\.local|zerwiz\.org|github\.com|githubusercontent\.com|way-of\.com)$", re.I
)
SSH_IDENTITIES = {"git", "ssh", "root", "user", "ubuntu", "operator", "noreply", "no-reply", "bot"}
EMAILS_OPT_IN = {"<the operator>", "<a personal address>", "<the operator's address>"}

IPV4 = re.compile(r"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(/\d{1,2})?\b")
TAILNET = re.compile(r"\b([a-z0-9][a-z0-9-]*)\.(?:[a-z0-9]+\.)?ts\.net\b", re.I)
MAILBOX = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9._-]+(?:\.[A-Za-z0-9._-]+)*\.[A-Za-z]{2,}\b")
SECRET = re.compile(
    r"(ghp|gho|ghs|ghr)_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+"
    r"|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)
SECRET_ALLOW = re.compile(r"AKIAIOSFODNN7EXAMPLE|AKIA[A-Z0-9]*EXAMPLE")
# The guards that NAME a shape, and the rule text that quotes one, are the declaration itself.
# GENERATED, third-party content: a lockfile repeats upstream text verbatim (a deprecation message
# that names the package author's own address). Editing it breaks an install, and the address is
# not this house's. Judged as an artifact, never rewritten.
GENERATED = {"package-lock.json", "bun.lock", "pnpm-lock.yaml", "yarn.lock", "apps/smidja-factory/apps/visualizer/package-lock.json"}

GUARD_FILES = {
    "bin/gates/guards/public-guard.sh", "bin/gates/guards/public-guard.py",
    "bin/gates/guards/secret-guard.sh", "bin/gates/guards/hoard-guard.sh",
    "bin/gates/guards/identity-guard.sh", "bin/gates/guards/private-guard.py",
    # The test that proves this ward REFUSES must itself contain one planted sample of each class —
    # it writes them into a scratch file, never into the tree. Naming it here is the same exception
    # as the guards above, and the test is the reason the exception is safe: remove the test and the
    # exemption goes with it.
    "bin/gates/checks/public-data-ward.test.sh",
}


def is_private(octets: tuple[int, ...]) -> bool:
    a, b, _c, _d = octets
    return (a == 10) or (a == 172 and 16 <= b <= 31) or (a == 192 and b == 168) or (a == 100 and 64 <= b <= 127)


def topology_findings(line: str) -> list[str]:
    out: list[str] = []
    for m in IPV4.finditer(line):
        text = m.group(0)
        octets = tuple(int(m.group(i)) for i in range(1, 5))
        if not is_private(octets):
            continue
        if "/" in text:                                  # a RANGE: documentation, allowed if the space is
            if text in CIDR_ALLOWED:
                continue
            out.append(f"a private CIDR outside the declared ranges: {text}")
            continue
        if line[max(0, m.start() - 7):m.start()].lower().endswith("::ffff:"):
            continue                                     # an IPv6-mapped form in a parser's own test
        if text.startswith(DOC_NETS) or text in SENTINELS:
            continue
        out.append("a private address (a place this house stands)")
    for m in TAILNET.finditer(line):
        if not TAILNET_ALLOWED.match(m.group(0)):
            out.append("a tailnet host")
    return out


ASSET_SUFFIX = re.compile(r"^\d+x\.(png|jpe?g|svg|webp|gif)$", re.I)


def mailbox_findings(line: str) -> list[str]:
    out: list[str] = []
    for m in MAILBOX.finditer(line):
        addr = m.group(0)
        if "\x00" in addr:
            continue
        if addr in EMAILS_OPT_IN or any(marker in addr for marker in ("<", ">")):
            continue
        local, _, domain = addr.rpartition("@")
        tail = domain.rsplit(".", 2)[-2:] if "." in domain else []
        if tail and ASSET_SUFFIX.match(".".join(tail)):
            continue                                      # `Icon@2x.png` is an asset, not an address
        if local.lower() in SSH_IDENTITIES:
            continue
        if "." not in domain:                            # user@host — not an internet address
            continue
        if MAILBOX_ALLOWED_DOMAIN.search(domain):
            continue
        out.append(f"a personal mailbox ({'*' * len(local)}@{domain.split('.')[-1]})")
    return out


def operator_words(root: Path) -> list[str]:
    home = os.environ.get("YMIR_HOME", "")
    if not home:
        lib = root / "bin" / "vault" / "hoard-lib.sh"
        if lib.exists():
            try:
                out = subprocess.run(["bash", "-c", f'. "{lib}"; ymir_home_root h; printf %s "$h"'],
                                     capture_output=True, text=True, timeout=20).stdout
                home = out.strip()
            except Exception:
                home = ""
    if not home:
        return []
    listing = Path(home) / "hodd" / "security" / "operator-words.txt"
    if not listing.is_file():
        return []
    return [ln.strip() for ln in listing.read_text(errors="replace").splitlines()
            if ln.strip() and not ln.strip().startswith("#")]


def scan(path: str, text: str, words: list[str], home: str) -> list[str]:
    findings: list[str] = []
    is_guard = path in GUARD_FILES
    for n, line in enumerate(text.splitlines(), 1):
        if SECRET.search(line) and not SECRET_ALLOW.search(line) and not is_guard:
            findings.append(f"{path}:{n}: a credential shape")
        if not is_guard:
            findings.extend(f"{path}:{n}: {msg}" for msg in topology_findings(line))
            findings.extend(f"{path}:{n}: {msg}" for msg in mailbox_findings(line))
        for w in words:
            if re.search(rf"\b{re.escape(w)}\b", line, re.I):
                findings.append(f"{path}:{n}: names the operator (RULES/04) — the word is masked here on purpose")
                break
    return findings


def tracked(root: Path) -> list[str]:
    try:
        out = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, timeout=120).stdout
    except Exception:
        return []
    return [p for p in out.decode("utf-8", "surrogateescape").split("\0") if p]


def staged(root: Path) -> list[str]:
    try:
        out = subprocess.run(["git", "-C", str(root), "diff", "--cached", "--name-only", "--diff-filter=ACM", "-z"],
                             capture_output=True, timeout=60).stdout
    except Exception:
        return []
    return [p for p in out.decode("utf-8", "surrogateescape").split("\0") if p]


def main(argv: list[str]) -> int:
    root = Path(__file__).resolve().parents[3]
    words = operator_words(root)
    home = os.environ.get("YMIR_HOME", "")

    if argv and argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv and argv[0] in ("-v", "--version"):
        print(VERSION)
        return 0
    if argv and argv[0] == "--list":
        print("public_guard[4]{class,what_is_refused,what_is_allowed}:")
        print('  "secret","a credential shape","the documented dummy keys a test uses"')
        print(f'  "name","a word declared in $YMIR_HOME/hodd/security/operator-words.txt","nothing — the list is the authority" ({len(words)} declared)')
        print('  "topology","a private address, a CIDR outside the declared ranges, a tailnet host","192.168.0.0/16 · 10.0.0.0/8 · 172.16.0.0/12 · 100.64.0.0/10 · RFC 5737 space · <host>.tailnet.ts.net"')
        print('  "mailbox","a personal address","example.com/.org/.net · .invalid · .test · git@github.com · noreply · <the operator>"')
        return 0

    mode = argv[0] if argv and argv[0].startswith("--") else ""
    if mode == "--tree":
        files = tracked(root)
    elif mode == "--staged":
        files = staged(root)
    elif mode:
        print(f"error: unknown flag {mode}\nhelp: public-guard.py [--tree|--staged|FILE...]", file=sys.stderr)
        return 2
    else:
        files = [a for a in argv if not a.startswith("-")]

    if not words:
        # A CLEAN SKIP IS A PASS; A FALSE GREEN IS NOT. Say which half was not checked.
        print("public_guard[1]{state,detail}:")
        print('  "names","SKIP — no $YMIR_HOME/hodd/security/operator-words.txt on this machine; the other three classes are judged"')

    findings: list[str] = []
    for rel in files:
        p = root / rel
        if not p.is_file():
            continue
        if rel in GENERATED or rel.rsplit("/", 1)[-1] in {"package-lock.json", "bun.lock", "pnpm-lock.yaml", "yarn.lock"}:
            continue                                      # generated third-party text
        try:
            raw = p.read_bytes()[:400_000]
            if b"\x00" in raw[:8000]:
                continue                                  # a binary is not a public DOCUMENT
            text = raw.decode("utf-8", "replace")
        except Exception:
            continue
        findings.extend(scan(rel, text, words, home))

    if not findings:
        print(f'public_guard[1]{{files,verdict}}:\n  "{len(files)}","PASS — templates and logic; no secret, no operator word, no topology, no mailbox"')
        return 0

    print(f'public_guard[1]{{files,findings}}:\n  "{len(files)}","{len(findings)}"')
    for f in findings[:20]:
        print("  " + f)
    if len(findings) > 20:
        print(f'  "…","{len(findings) - 20} more"')
    print("help: a private value belongs in $YMIR_HOME; a private address is allowed only as a CIDR range "
          "or RFC 5737 space; a fixture is judged like any other file (RULES/04)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
