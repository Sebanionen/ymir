#!/usr/bin/env python3
"""telegram-roster.py — who speaks in a chat, remembered.

Telegram will not list a group's members (Bot API: chat, count, administrators,
one known id — and nothing more), and the bridge hands the agent the text without
the sender. So the only complete member list a bot can build is a ROSTER BUILT
FROM WHO SPEAKS: every arriving message carries its chat and its sender, and this
file remembers them.

The store is the house's memory of people, so it lives in the HOARD, never in the
public tree (a name is private data, Rule 04):

    <hoard>/data/telegram-rosters/<chat-id>.yaml

A row is a RECORD of who spoke. It is never a grant of anything: authority stays
with the gate and with the Allfather's word.

    telegram-roster.py record --chat ID --user ID --name S [--username U] [--message ID] [--title T]
    telegram-roster.py list   --chat ID
    telegram-roster.py show   --chat ID --user ID
    telegram-roster.py chats
    telegram-roster.py sync-admins --chat ID

Exit: 0 ok · 1 refused · 2 usage.
"""
from __future__ import annotations

import argparse
import datetime
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("unavailable: PyYAML is required\n")
    raise SystemExit(3)


def hoard() -> Path:
    """The hoard, resolved by the ONE resolver — never guessed here (Rule 07)."""
    explicit = os.environ.get("YMIR_HOARD")
    if explicit:
        return Path(explicit)
    door = Path(__file__).resolve().parents[2] / "bin" / "vault" / "hodd.sh"
    try:
        out = subprocess.run(["bash", str(door), "path"], capture_output=True, text=True, timeout=20)
    except Exception as exc:  # pragma: no cover
        sys.stderr.write(f"unavailable: cannot resolve the hoard ({exc})\n")
        raise SystemExit(3)
    path = (out.stdout or "").strip()
    if out.returncode != 0 or not path:
        sys.stderr.write("unavailable: bin/vault/hodd.sh did not answer with a path\n")
        raise SystemExit(3)
    return Path(path)


def root() -> Path:
    return hoard() / "data" / "telegram-rosters"


def now() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def load(chat: str) -> dict:
    path = root() / f"{chat}.yaml"
    if not path.exists():
        return {"chat": str(chat), "title": "", "members": [], "messages_seen": []}
    doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    doc.setdefault("members", [])
    doc.setdefault("messages_seen", [])
    return doc


def save(chat: str, doc: dict) -> Path:
    root().mkdir(parents=True, exist_ok=True)
    path = root() / f"{chat}.yaml"
    doc["updated"] = now()
    path.write_text(yaml.safe_dump(doc, sort_keys=False, allow_unicode=True, width=100), encoding="utf-8")
    return path


def row(doc: dict, user: str) -> dict | None:
    for member in doc["members"]:
        if str(member.get("id")) == str(user):
            return member
    return None


def toon(rows: list[dict], chat: str = "") -> str:
    head = f"roster[{len(rows)}]{{id,name,username,role,source,messages,last_seen}}:"
    out = [head]
    for m in rows:
        out.append(
            '  "%s","%s","%s","%s","%s","%s","%s"'
            % (
                m.get("id", ""),
                str(m.get("name", "")).replace('"', "'"),
                m.get("username", "") or "",
                m.get("role", "member"),
                m.get("source", "observed"),
                m.get("messages", 0),
                m.get("last_seen", ""),
            )
        )
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="telegram-roster")
    p.add_argument("verb", choices=("record", "list", "show", "chats", "sync-admins"))
    p.add_argument("--chat", default="")
    p.add_argument("--user", default="")
    p.add_argument("--name", default="")
    p.add_argument("--username", default="")
    p.add_argument("--message", default="")
    p.add_argument("--title", default="")
    p.add_argument("--admins-json", default="", help="the raw getChatAdministrators payload, for sync-admins")
    args = p.parse_args(argv)

    if args.verb == "chats":
        base = root()
        if not base.exists():
            sys.stdout.write("chats[0]{chat,title,members}:\n")
            return 0
        rows = []
        for f in sorted(base.glob("*.yaml")):
            doc = yaml.safe_load(f.read_text(encoding="utf-8")) or {}
            rows.append((f.stem, doc.get("title", ""), len(doc.get("members") or [])))
        sys.stdout.write(f"chats[{len(rows)}]{{chat,title,members}}:\n")
        for c, t, n in rows:
            sys.stdout.write(f'  "{c}","{t}","{n}"\n')
        return 0

    if not args.chat:
        sys.stderr.write("refused: --chat is required (a roster that guessed its room would file a name in the wrong place)\n")
        return 2

    doc = load(args.chat)
    if args.title:
        doc["title"] = args.title

    if args.verb == "record":
        if not (args.user and args.name):
            sys.stderr.write("refused: record needs --user and --name\n")
            return 2
        if args.message and args.message in doc["messages_seen"]:
            sys.stdout.write(toon(doc["members"]))
            return 0
        member = row(doc, args.user)
        if member is None:
            member = {
                "id": str(args.user),
                "name": args.name,
                "username": args.username,
                "role": "member",
                "source": "observed",
                "first_seen": now(),
                "messages": 0,
            }
            doc["members"].append(member)
        member["name"] = args.name or member.get("name", "")
        if args.username:
            member["username"] = args.username
        member["messages"] = int(member.get("messages", 0)) + (0 if args.message and args.message in doc["messages_seen"] else 1)
        member["last_seen"] = now()
        if args.message:
            doc["messages_seen"] = (doc["messages_seen"] + [args.message])[-200:]
        path = save(args.chat, doc)
        sys.stdout.write(toon(doc["members"]))
        sys.stderr.write(f"roster: {path}\n")
        return 0

    if args.verb == "list":
        sys.stdout.write(toon(doc["members"]))
        return 0

    if args.verb == "show":
        if not args.user:
            sys.stderr.write("refused: show needs --user\n")
            return 2
        member = row(doc, args.user)
        if member is None:
            sys.stderr.write(f"refused: no roster row for {args.user} in chat {args.chat}\n")
            return 1
        sys.stdout.write(yaml.safe_dump(member, sort_keys=False, allow_unicode=True))
        return 0

    if args.verb == "sync-admins":
        if not args.admins_json:
            sys.stderr.write("refused: sync-admins needs --admins-json (the getChatAdministrators result)\n")
            return 2
        import json

        try:
            payload = json.loads(args.admins_json)
        except Exception:
            sys.stderr.write("refused: --admins-json is not JSON\n")
            return 1
        admins = payload.get("result") if isinstance(payload, dict) else payload
        if not isinstance(admins, list):
            sys.stderr.write("refused: that payload carries no administrator list\n")
            return 1
        added = 0
        for entry in admins:
            user = (entry or {}).get("user") or {}
            uid = str(user.get("id", ""))
            if not uid:
                continue
            name = " ".join(x for x in [user.get("first_name") or "", user.get("last_name") or ""] if x).strip()
            member = row(doc, uid)
            if member is None:
                member = {"id": uid, "name": name, "username": user.get("username") or "", "role": "admin",
                          "source": "api", "first_seen": now(), "messages": 0}
                doc["members"].append(member)
                added += 1
            else:
                member["role"] = "admin"
                member["source"] = "api"
                member["name"] = member.get("name") or name
                member["username"] = member.get("username") or (user.get("username") or "")
        save(args.chat, doc)
        sys.stdout.write(toon(doc["members"]))
        sys.stderr.write(f"roster: {added} admin(s) added from the API\n")
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
