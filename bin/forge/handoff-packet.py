#!/usr/bin/env python3
"""handoff-packet.py — the door to the one artefact that crosses from a smith to the reviewer.

WHY (plan 203 §3, §14.1, §15.2 gap 1): the plan described a packet and built no way to write
one, so every smith invented a shape. Two shapes then existed — this door's and the contract in
`schemas/handoff-packet.toon` — which is the drift gap 1 was meant to end. So this door now
WRITES AND READS THAT SCHEMA, field for field, and refuses anything else.

The refusals that carry the design:

  · the sha check (§14.1) — a packet names a commit. A fetched head that is not the packet's
    head is refused in the rule's own words: a packet may not vouch for code that moved.
  · the changed list is CHECKED, not believed — every path is compared with the real diff, and a
    packet that understates its footprint is refused with the omitted path named.
  · a gate named is not evidence — `all pass`, `CI green`, `n/a` and their cousins are refused.
  · a `review[]` block written by a smith is refused: that block is the reviewer's, and a packet
    that already contains a verdict is a review that did not happen.
  · `floor partial` is refused: a partial floor is a refusal waiting to happen (schema rule 6).

Usage:
  handoff-packet.sh write <id> --task T --plan P [--branch B] [--base REF] [--head SHA]
                              --gate "name|cmd|exit|tail"... --test "cmd|exit|tail"...
                              [--claim "line|state|evidence"]... [--not-done "item|why"]...
                              [--need "what|who"]... [--repo DIR] [--packet FILE]
  handoff-packet.sh check <id> [--repo DIR] [--fetched SHA] [--packet FILE]
  handoff-packet.sh show  <id> [--packet FILE]

Exit: 0 written / the packet is sound · 1 refused (the refusal names the fault) · 2 usage.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys

TOOL = "handoff-packet"
SCHEMA = "schemas/handoff-packet.toon"
PACKET_FIELDS = ["task", "plan", "branch", "base", "head", "author", "written_at",
                 "ruleset", "floor"]
BLOCKS = ["changed", "gates", "tests", "claims", "not_done", "needs"]
BLOCK_COLS = {
    "changed": ["path", "added", "removed", "why"],
    "gates": ["gate", "cmd", "exit", "output_tail"],
    "tests": ["cmd", "exit", "tail"],
    "claims": ["claim", "state", "evidence"],
    "not_done": ["item", "why"],
    "needs": ["need", "who"],
}
CLAIM_STATES = {"verified", "unverified"}
NEED_WHO = {"allfather", "operator", "licence", "key"}
EMPTY_CLAIMS = {"", "all pass", "all passed", "pass", "passed", "green", "ci green",
                "n/a", "na", "none", "ok", "tests pass", "gates pass", "see ci"}


# --------------------------------------------------------------------------- refusal


def refuse(headline, rows=None, help_line=None):
    print(f'{TOOL}: REFUSED — {headline}', file=sys.stderr)
    if rows:
        print(f'{TOOL}[{len(rows)}]{{fault,detail}}:', file=sys.stderr)
        for fault, detail in rows:
            print(f'  "{fault}","{detail}"', file=sys.stderr)
    if help_line:
        print(f'help: {help_line}', file=sys.stderr)
    sys.exit(1)


def usage_error(msg):
    print(f'{TOOL}: {msg}', file=sys.stderr)
    print('help: handoff-packet.sh --help', file=sys.stderr)
    sys.exit(2)


# --------------------------------------------------------------------------- home


def home_root():
    """The home is RESOLVED, never guessed (defaults-guard): hoard-lib owns where it lives."""
    here = os.path.dirname(os.path.abspath(__file__))
    lib = os.path.abspath(os.path.join(here, "..", "vault", "hoard-lib.sh"))
    try:
        out = subprocess.run(["bash", "-c", f'. "{lib}"; v=""; ymir_home_root v; printf %s "$v"'],
                             capture_output=True, text=True, timeout=30)
        if out.stdout.strip():
            return out.stdout.strip()
    except Exception:
        pass
    return os.environ.get("YMIR_HOME", "")


def packet_dir():
    state = os.environ.get("YMIR_STATE_DIR") or os.path.join(home_root(), "state")
    return os.path.join(state, "handoff")


# --------------------------------------------------------------------------- git


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if check and p.returncode != 0:
        refuse(f"git {' '.join(args)} failed in {repo}", [("git", (p.stderr or p.stdout).strip()[:300])])
    return p.stdout.strip()


def repo_root(path):
    return git(path or ".", "rev-parse", "--show-toplevel")


# --------------------------------------------------------------------------- toon io


HEADER = re.compile(r"^([a-z_]+)\[(\d+)\]\{([^}]*)\}:\s*$")
ROW = re.compile(r'^\s+"([^"]*)"(.*)$')


def _cells(rest):
    """The remaining `,"a","b"` tail of a row, quoted cells only."""
    return re.findall(r'"([^"]*)"', rest)


def _num(cell, what, faults):
    try:
        return int(cell)
    except (TypeError, ValueError):
        faults.append((what, f"not an integer: {cell!r}"))
        return 0


def read_packet(path):
    if not os.path.exists(path):
        refuse(f"no packet at {path}", [("missing", path)],
               "handoff-packet.sh write <id> — a reviewer reads a packet, never a promise")
    packet = {"rows": {}, "changed": [], "gates": [], "tests": [], "claims": [],
              "not_done": [], "needs": [], "review": [], "faults": [], "headers": {}}
    block = None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = HEADER.match(line)
        if m:
            block = m.group(1)
            packet["headers"][block] = [c.strip() for c in m.group(3).split(",")]
            continue
        m = ROW.match(line)
        if not m or block is None:
            continue
        first, rest = m.group(1), m.group(2)
        if block == "packet":
            cols = packet["headers"].get("packet", [])
            cells = [first] + _cells(rest)
            for col, cell in zip(cols, cells):
                packet["rows"][col] = cell
            continue
        if block in ("changed", "gates", "tests", "claims", "not_done", "needs"):
            cols = packet["headers"].get(block, BLOCK_COLS[block])
            cells = [first] + _cells(rest)
            row = dict(zip(cols, cells))
            for k in ("added", "removed", "exit"):
                if k in row:
                    row[k] = _num(row[k], f"{block}.{k}", packet["faults"])
            packet[block].append(row)
        elif block == "review":
            packet["review"].append([first] + _cells(rest))
    return packet


def q(v):
    return str(v).replace('"', "'").replace("\n", " ").strip()


def write_packet(path, p):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = ["# written by bin/forge/handoff-packet.py — the contract is schemas/handoff-packet.toon",
           "",
           "packet[1]{" + ",".join(PACKET_FIELDS) + "}:",
           '  "' + '","'.join(q(p[k]) for k in PACKET_FIELDS) + '"',
           ""]
    for block, cols in BLOCK_COLS.items():
        rows = p[block]
        out.append(f"{block}[{len(rows)}]{{{','.join(cols)}}}:")
        for r in rows:
            out.append('  "' + '","'.join(q(r.get(c, "")) for c in cols) + '"')
        out.append("")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out).rstrip() + "\n")
    return path


# --------------------------------------------------------------------------- evidence


def evidence(value, what):
    v = (value or "").strip()
    if not v:
        refuse(f"{what} carries no evidence", [(what, "empty")],
               f"a {what} row carries the OUTPUT — the command and its tail")
    if v.lower() in EMPTY_CLAIMS:
        refuse(f"{what} is a claim, not evidence: {v!r}", [(what, v)],
               f'write what the {what} printed, never "all pass"')
    return v


def split_row(text, n, what):
    parts = [x.strip() for x in text.split("|")]
    if len(parts) != n:
        usage_error(f'{what} takes {n} |-separated cells, got {len(parts)}: {text!r}')
    return parts


def floor_facts(repo):
    """The rules floor's own answer: its hash, and whether it loaded whole."""
    here = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(here, "review-rules.sh")
    if not os.path.exists(script):
        return "none", "partial"
    p = subprocess.run(["bash", script, repo], capture_output=True, text=True, timeout=120)
    h = re.search(r'"ruleset","([0-9a-f]+)"', p.stdout)
    return (h.group(1) if h else "none"), ("complete" if p.returncode == 0 else "partial")


# --------------------------------------------------------------------------- write


def cmd_write(a):
    repo = repo_root(a.repo)
    if not a.task or not a.plan:
        usage_error("write needs --task (what this was supposed to be) and --plan (the document that says so)")
    branch = a.branch or git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    head = a.head or git(repo, "rev-parse", "HEAD")
    base_ref = a.base or "origin/main"
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        refuse(f"head is not a full sha: {head}", [("head", head)],
               "a packet names a commit by its full sha — a branch name can move")
    base = git(repo, "rev-parse", base_ref, check=False)
    if not base:
        refuse(f"base {base_ref} does not resolve in {repo}", [("base", base_ref)],
               "fetch first: a packet whose base nobody has cannot be verified")
    author = a.author or os.environ.get("YMIR_AGENT_NAME") or git(repo, "config", "user.name", check=False)
    if not author:
        usage_error("no author — set --author, $YMIR_AGENT_NAME, or git user.name")
    ruleset, floor = floor_facts(repo)

    changed = []
    for line in git(repo, "diff", "--numstat", f"{base}...{head}", check=False).splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        path = parts[2]
        why = git(repo, "log", "-1", "--format=%s", head, "--", path, check=False) or "no commit names it"
        changed.append({"path": path, "added": int(parts[0]) if parts[0].isdigit() else 0,
                        "removed": int(parts[1]) if parts[1].isdigit() else 0, "why": why})

    gates = []
    for g in a.gate or []:
        name, cmd, exit_code, tail = split_row(g, 4, "--gate")
        gates.append({"gate": name, "cmd": cmd, "exit": exit_code,
                      "output_tail": evidence(tail, "gates.output_tail")})
    tests = []
    for t in a.test or []:
        cmd, exit_code, tail = split_row(t, 3, "--test")
        tests.append({"cmd": cmd, "exit": exit_code, "tail": evidence(tail, "tests.tail")})
    claims = []
    for c in a.claim or []:
        line, state, ev = split_row(c, 3, "--claim")
        if state not in CLAIM_STATES:
            usage_error(f'--claim state must be verified|unverified, got {state!r}')
        claims.append({"claim": line, "state": state, "evidence": ev})
    not_done = []
    for n in a.not_done or []:
        item, why = split_row(n, 2, "--not-done")
        not_done.append({"item": item, "why": why})
    needs = []
    for n in a.need or []:
        what, who = split_row(n, 2, "--need")
        if who not in NEED_WHO:
            usage_error(f'--need who must be allfather|operator|licence|key, got {who!r}')
        needs.append({"need": what, "who": who})

    if not gates:
        usage_error("write needs at least one --gate (the output, not the name)")
    if not tests:
        usage_error("write needs at least one --test (the command, its exit, its tail)")

    packet = {"task": a.task, "plan": a.plan, "branch": branch, "base": base_ref,
              "head": head, "author": author,
              "written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
              "ruleset": ruleset, "floor": floor,
              "changed": changed, "gates": gates, "tests": tests, "claims": claims,
              "not_done": not_done or [{"item": "none", "why": "nothing was left"}],
              "needs": needs or [{"need": "none", "who": "operator"}]}
    path = a.packet or os.path.join(packet_dir(), f"{a.id}.packet")
    write_packet(path, packet)
    print(f'{TOOL}[1]{{packet,branch,head,changed,gates,floor,state}}:')
    print(f'  "{path}","{branch}","{head}","{len(changed)}","{len(gates)}","{floor}","written"')
    print(f'help: the reviewer runs `handoff-packet.sh check {a.id}` before the diff')


# --------------------------------------------------------------------------- check


def cmd_check(a):
    path = a.packet or os.path.join(packet_dir(), f"{a.id}.packet")
    p = read_packet(path)
    faults = list(p["faults"])

    if p["review"]:
        faults.append(("review", "a smith wrote the reviewer's block — the verdict belongs to the "
                                 "reviewer, and a packet that carries one is a review that never ran"))
    for k in PACKET_FIELDS:
        if not p["rows"].get(k):
            faults.append((k, "missing from the packet row"))

    floor = p["rows"].get("floor", "")
    if floor and floor not in ("complete", "partial"):
        faults.append(("floor", f"not complete|partial: {floor!r}"))
    if floor == "partial":
        faults.append(("floor", "partial — a refusal waiting to happen (schema rule 6); work the floor "
                                "until it loads whole, then write the packet"))

    head = p["rows"].get("head", "")
    if head and not re.fullmatch(r"[0-9a-f]{40}", head):
        faults.append(("head", f"not a full sha: {head!r}"))

    for row in p["gates"]:
        if row.get("output_tail", "").strip().lower() in EMPTY_CLAIMS:
            faults.append(("gates.output_tail", f"{row.get('gate', '?')} carries {row.get('output_tail')!r}"))
    for row in p["tests"]:
        if row.get("tail", "").strip().lower() in EMPTY_CLAIMS:
            faults.append(("tests.tail", f"{row.get('cmd', '?')} carries {row.get('tail')!r}"))
    for row in p["claims"]:
        if row.get("state") not in CLAIM_STATES:
            faults.append(("claims.state", f"not verified|unverified: {row.get('state')!r}"))

    repo = a.repo or os.environ.get("YMIR_PACKET_REPO", ".")
    try:
        repo = repo_root(repo)
    except SystemExit:
        repo = None

    base_sha = (p["rows"].get("base") or "").strip()
    if base_sha and not re.fullmatch(r"[0-9a-f]{40}", base_sha):
        base_sha = ""

    if repo and re.fullmatch(r"[0-9a-f]{40}", head):
        if subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{head}^{{commit}}"],
                          capture_output=True).returncode != 0:
            faults.append(("head", f"{head[:12]} is not a commit in {repo} — fetch the branch first"))
        if base_sha:
            if subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{base_sha}^{{commit}}"],
                              capture_output=True).returncode != 0:
                faults.append(("base", f"{base_sha[:12]} is not in {repo} — the diff cannot be verified"))
            else:
                claimed = [c["path"] for c in p["changed"]]
                actual = [ln for ln in git(repo, "diff", "--name-only", f"{base_sha}...{head}",
                                           check=False).splitlines() if ln]
                missing = sorted(set(actual) - set(claimed))
                extra = sorted(set(claimed) - set(actual))
                if missing:
                    faults.append(("changed", "understated — the diff carries "
                                              f"{len(missing)} path(s) the packet omits: " + ", ".join(missing[:5])))
                if extra:
                    faults.append(("changed", "overstated — the packet claims "
                                              f"{len(extra)} path(s) the diff does not touch: " + ", ".join(extra[:5])))
        else:
            faults.append(("base", f"no full sha: {p['rows'].get('base')!r} — the diff cannot be verified"))

    if a.fetched and a.fetched.strip() != head:
        faults.append(("fetched", f"the fetched head {a.fetched[:12]} is not the packet's head {head[:12]} "
                                  "— a packet may not vouch for code that moved (plan 203 §14.1)"))

    if faults:
        refuse(f"packet {a.id or path} cannot be trusted", faults,
               "the packet is not read: fix the named rows, or write a new packet for the new head")

    print(f'{TOOL}[1]{{packet,branch,head,changed,gates,tests,state}}:')
    print(f'  "{path}","{p["rows"].get("branch", "")}","{head}","{len(p["changed"])}",'
          f'"{len(p["gates"])}","{len(p["tests"])}","sound"')
    print("note: soundness is not approval — run the gates on the fetched commit yourself (plan 203 §15.3)")


def cmd_show(a):
    path = a.packet or os.path.join(packet_dir(), f"{a.id}.packet")
    if not os.path.exists(path):
        refuse(f"no packet at {path}", [("missing", path)])
    sys.stdout.write(open(path, encoding="utf-8").read())


# --------------------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(prog="handoff-packet.sh")
    sub = ap.add_subparsers(dest="cmd")

    w = sub.add_parser("write")
    w.add_argument("id")
    w.add_argument("--task"); w.add_argument("--plan"); w.add_argument("--branch")
    w.add_argument("--base"); w.add_argument("--head"); w.add_argument("--author")
    w.add_argument("--gate", action="append"); w.add_argument("--test", action="append")
    w.add_argument("--claim", action="append"); w.add_argument("--not-done", action="append")
    w.add_argument("--need", action="append")
    w.add_argument("--repo"); w.add_argument("--packet")

    c = sub.add_parser("check")
    c.add_argument("id", nargs="?")
    c.add_argument("--repo"); c.add_argument("--fetched"); c.add_argument("--packet")

    s = sub.add_parser("show")
    s.add_argument("id", nargs="?"); s.add_argument("--packet")

    a = ap.parse_args()
    if a.cmd == "write":
        cmd_write(a)
    elif a.cmd == "check":
        if not a.id and not a.packet:
            usage_error("check needs an id or --packet")
        cmd_check(a)
    elif a.cmd == "show":
        if not a.id and not a.packet:
            usage_error("show needs an id or --packet")
        cmd_show(a)
    else:
        print(__doc__.strip())
        sys.exit(2)


if __name__ == "__main__":
    main()
