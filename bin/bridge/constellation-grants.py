#!/usr/bin/env python3
"""constellation-grants.py — the grants shelf on the A2A road, in the existing shape.

One grant is one explicit share: our house grants another house's Ymir the named
skills, for a time, signed by our Heimdall key. The document is the SAME registry
`src/ymir_runtime/grants.py` judges (plan 58) — this tool only writes and reads it,
it never reimplements the law. A cross-operator grant needs a signature from EACH
party (Rule 05), so a grant we have signed and the peer has not is `pending` and
may not be used; `activate` refuses until their signature verifies.

    constellation-grants.py list   <file> [--peer NAME]
    constellation-grants.py add    <file> --json FILE      (a fully signed draft)
    constellation-grants.py add-signature <file> --grant-id ID --signer KID --sig SIG
    constellation-grants.py activate <file> --grant-id ID
    constellation-grants.py revoke <file> --grant-id ID [--peer NAME]

Exit: 0 ok, 1 refused, 2 usage.
"""
from __future__ import annotations

import argparse
import datetime
import json
import sys
from typing import Any

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("constellation: PyYAML is required\n")
    raise SystemExit(1)


def refuse(message: str) -> int:
    sys.stderr.write(f"constellation: {message}\n")
    return 1


def load(path: str) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        doc = {}
    if not isinstance(doc, dict):
        raise SystemExit(refuse(f"{path} is not a grants registry"))
    doc.setdefault("version", 1)
    grants = doc.setdefault("grants", [])
    if not isinstance(grants, list):
        raise SystemExit(refuse(f"{path}: grants must be a list"))
    return doc


def save(path: str, doc: dict[str, Any]) -> None:
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(doc, fh, sort_keys=False, allow_unicode=True, width=100)


def find(doc: dict[str, Any], grant_id: str = "", peer: str = "") -> list[dict[str, Any]]:
    out = []
    for grant in doc.get("grants") or []:
        if grant_id and grant.get("grant_id") != grant_id:
            continue
        if peer:
            names = {
                str((grant.get("grantor") or {}).get("ymir", "")),
                str((grant.get("grantee") or {}).get("ymir", "")),
            }
            if peer not in names:
                continue
        out.append(grant)
    return out


def toon(rows: list[dict[str, Any]]) -> str:
    lines = ["grants[%d]{grant_id,peer,skills,state,expires}:" % len(rows)]
    for grant in rows:
        grantor = str((grant.get("grantor") or {}).get("ymir", ""))
        grantee = str((grant.get("grantee") or {}).get("ymir", ""))
        peer = f"{grantor}->{grantee}"
        skills = ",".join(grant.get("skills") or [])
        lines.append(
            f'  "{grant.get("grant_id", "")}","{peer}","{skills}","{grant.get("state", "")}","{grant.get("expires", "")}"'
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="constellation-grants", add_help=True)
    parser.add_argument("mode", choices=("list", "add", "add-signature", "activate", "revoke"))
    parser.add_argument("file")
    parser.add_argument("--peer", default="")
    parser.add_argument("--json", default="")
    parser.add_argument("--grant-id", default="")
    parser.add_argument("--signer", default="")
    parser.add_argument("--sig", default="")
    args = parser.parse_args(argv)

    doc = load(args.file)

    if args.mode == "list":
        sys.stdout.write(toon(find(doc, peer=args.peer)))
        return 0

    if args.mode == "add":
        if not args.json:
            return refuse("add needs --json <a signed grant draft>")
        with open(args.json, encoding="utf-8") as fh:
            grant = json.load(fh)
        if not grant.get("grant_id"):
            return refuse("the draft names no grant_id")
        if find(doc, grant_id=grant["grant_id"]):
            return refuse(f"grant {grant['grant_id']} already exists; a replayed id is refused")
        doc["grants"].append(grant)
        save(args.file, doc)
        sys.stdout.write(f"grant {grant['grant_id']} {grant.get('state', 'pending')}\n")
        return 0

    if args.mode == "add-signature":
        if not (args.grant_id and args.signer and args.sig):
            return refuse("add-signature needs --grant-id, --signer and --sig")
        for grant in find(doc, grant_id=args.grant_id):
            signatures = grant.setdefault("signatures", [])
            if any(sig.get("signer") == args.signer for sig in signatures):
                return refuse(f"grant {args.grant_id} already carries a signature from {args.signer}")
            signatures.append(
                {
                    "signer": args.signer,
                    "alg": "ed25519",
                    "key_id": args.signer,
                    "sig": args.sig,
                }
            )
            save(args.file, doc)
            sys.stdout.write(f"signature added {args.grant_id} {args.signer}\n")
            return 0
        return refuse(f"no grant {args.grant_id}")

    if args.mode == "activate":
        for grant in find(doc, grant_id=args.grant_id):
            needed = {
                str((grant.get("grantor") or {}).get("heimdall", "")),
                str((grant.get("grantee") or {}).get("heimdall", "")),
            }
            have = {str(sig.get("signer", "")) for sig in grant.get("signatures") or []}
            missing = sorted(n for n in needed - have if n)
            if missing:
                return refuse(
                    f"grant {args.grant_id} cannot be activated: no signature from {', '.join(missing)} "
                    f"(the realm law requires one from each party)"
                )
            grant["state"] = "active"
            grant["issued"] = (
                grant.get("issued") or datetime.datetime.now().astimezone().isoformat(timespec="seconds")
            )
            save(args.file, doc)
            sys.stdout.write(f"grant {args.grant_id} active\n")
            return 0
        return refuse(f"no grant {args.grant_id}")

    if args.mode == "revoke":
        targets = find(doc, grant_id=args.grant_id, peer=args.peer)
        if not targets:
            return refuse("no grant matched; revoke needs --grant-id or --peer")
        for grant in targets:
            grant["state"] = "revoked"
            grant["revoked_at"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
        save(args.file, doc)
        sys.stdout.write(f"revoked {len(targets)} grant(s)\n")
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
