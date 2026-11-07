#!/usr/bin/env python3
"""herdr-agents.py — list the agents standing in this herdr session, as TOON.

Kept as its own file rather than an inline -c: the JSON shape has nested quotes
that are painful to escape inside a shell heredoc, and a separate file can be
tested on its own.

ONE reader for one question, because a second parser of the same JSON is how
`herdr pane list` came to be read as if a pane were an agent (plan 189 §18.2: a
pane is not an agent — only `herdr agent list` shows a worker). The spawner's
seat proof and the sweep's liveness cross-check both ask this door, so they
cannot disagree about whether a seat is standing.

  --find --cwd <path> [--pane <id>]
      prints `<pane>\t<state>\t<cwd>` and exits 0 when an agent's FOREGROUND cwd
      (or its working directory) is <path>, or when the named pane hosts an
      agent; exits 1 when no agent matches. That is the whole test: the pane is
      the evidence, `state/<id>.status` is only the claim.

Usage: herdr-agents.py [--json] [--find [--cwd P] [--pane P]]
"""
import json
import subprocess
import sys


def fetch() -> list:
    raw = subprocess.run(
        ["herdr", "agent", "list"],
        capture_output=True, text=True, timeout=15,
    ).stdout
    return (json.loads(raw).get("result") or {}).get("agents") or []


def main() -> int:
    args = sys.argv[1:]
    try:
        agents = fetch()
    except Exception as exc:  # noqa: BLE001
        print(f"herdr-agents[1]{{state}}:\n  \"cannot read herdr agents ({exc})\"")
        return 1

    if "--find" in args:
        want_cwd = ""
        want_pane = ""
        i = 0
        while i < len(args):
            if args[i] == "--cwd" and i + 1 < len(args):
                want_cwd = args[i + 1].rstrip("/") or "/"
                i += 2
                continue
            if args[i] == "--pane" and i + 1 < len(args):
                want_pane = args[i + 1]
                i += 2
                continue
            i += 1
        for a in agents:
            pane = a.get("pane_id") or ""
            fg = (a.get("foreground_cwd") or "").rstrip("/") or "/"
            cwd = (a.get("cwd") or "").rstrip("/") or "/"
            hit_cwd = bool(want_cwd) and want_cwd in (fg, cwd)
            hit_pane = bool(want_pane) and want_pane == pane
            if hit_cwd or hit_pane:
                print(f"{pane}\t{a.get('agent_status') or 'unknown'}\t{fg}")
                return 0
        return 1

    if "--json" in args:
        print(json.dumps(agents, indent=2))
        return 0

    print(f"herdr-agents[{len(agents)}]{{kind,state,pane,cwd,foreground}}:")
    for a in agents:
        kind = a.get("agent") or "?"
        state = a.get("agent_status") or "unknown"
        pane = a.get("pane_id") or "?"
        cwd = a.get("cwd") or "?"
        fg = a.get("foreground_cwd") or cwd
        print(f'  "{kind}","{state}","{pane}","{cwd}","{fg}"')
    return 0


if __name__ == "__main__":
    sys.exit(main())
