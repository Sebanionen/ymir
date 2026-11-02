#!/usr/bin/env python3
"""desk.py — Gimlé's desk: the page behind the door.

The hall's login is a door; this is the desk behind it. It answers one question — *what is mine to do,
and what was decided* — from the house's own record, in the house's own cloth. It is deliberately small:

  • it renders, it never writes;
  • it reads a JSON the projector writes (`meetings.json`), so the record stays in the hoard;
  • it trusts the identity Authelia has already established, passed by Caddy as `Remote-User`.

    desk.py --port 8487 --data /srv/gimle-desk/meetings.json [--plane-url URL --plane-token T]

Sections, in the order a person actually needs them:
  1 · due this week      — actions owed by me, with the meeting they came from
  2 · last decisions     — the most recent decisions across my places
  3 · questions for me   — open questions with my name against them
  4 · the tiles          — Plane · AFFiNE · Excalidraw · Files (when it lands)
"""
from __future__ import annotations

import argparse

try:                      # the board is a second source; if it is down the desk keeps working
    import plane_reader
except Exception:         # noqa: BLE001
    plane_reader = None

import datetime
import html
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

CLOTH = """
:root{--ymir-bg-0:#0e0c09;--ymir-bg-1:#151209;--ymir-bg-2:#1a1610;--ymir-line:#2b241a;
 --ymir-bronze:#c9973f;--ymir-bronze-deep:#7d5f2a;--ymir-bone:#cfc3a9;--ymir-bone-dim:#9a8f75;
 --ymir-bone-faint:#6b6250;--ymir-steel:#96a0a8;--ymir-blood:#c2584a;
 --bevel:inset 0 0 0 1px rgba(201,151,79,.12);
 --f-display:"Cormorant",Georgia,serif;--f-body:"Newsreader",Georgia,serif;--f-mono:"IBM Plex Mono",ui-monospace,monospace}
*{box-sizing:border-box}body{margin:0;background:
 radial-gradient(1000px 600px at 12% -10%,#1b1710 0%,transparent 60%),var(--ymir-bg-0);
 color:var(--ymir-bone);font-family:var(--f-body);font-size:15px;line-height:22px}
a{color:var(--ymir-bronze);text-decoration:none}
.wrap{max-width:1080px;margin:0 auto;padding:34px 22px 60px}
header{display:flex;align-items:baseline;justify-content:space-between;gap:16px;border-bottom:1px solid var(--ymir-line);padding-bottom:14px}
h1{font-family:var(--f-display);font-weight:400;font-size:40px;margin:0;letter-spacing:.02em}
h1 em{font-style:italic;color:var(--ymir-bronze)}
.who{font-family:var(--f-mono);font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--ymir-bone-faint)}
h2{font-family:var(--f-mono);font-size:11px;letter-spacing:.2em;text-transform:uppercase;color:var(--ymir-bronze);margin:34px 0 10px}
.card{background:var(--ymir-bg-1);border:1px solid var(--ymir-line);border-radius:10px;box-shadow:var(--bevel);padding:16px 18px}
ul{list-style:none;margin:0;padding:0}
li{padding:10px 0;border-bottom:1px solid var(--ymir-line)}
li:last-child{border-bottom:0}
.meta{font-family:var(--f-mono);font-size:11px;color:var(--ymir-bone-faint);letter-spacing:.06em}
.title{color:var(--ymir-bone)}
.due{color:var(--ymir-bronze);font-family:var(--f-mono);font-size:11px}
.over{color:var(--ymir-blood)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin-top:8px}
.tile{display:block;background:var(--ymir-bg-1);border:1px solid var(--ymir-line);border-radius:10px;padding:16px;box-shadow:var(--bevel)}
.tile:hover{border-color:var(--ymir-bronze-deep)}
.tile b{display:block;font-family:var(--f-mono);font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--ymir-bone)}
.tile span{display:block;font-size:13px;color:var(--ymir-bone-faint);margin-top:4px}
.empty{color:var(--ymir-bone-faint);font-style:italic}
footer{margin-top:40px;font-family:var(--f-mono);font-size:10.5px;color:var(--ymir-bone-faint);letter-spacing:.1em;text-align:center}
"""

TILES = [
    ("Board", "https://board.zerwiz.org", "projects and tasks — Plane"),
    ("Code", "https://forgejo.zerwiz.org", "repositories and pull requests — Forgejo"),
    ("Documents", "https://affine.zerwiz.org", "pages and databases — AFFiNE"),
    ("Whiteboard", "https://whiteboard.zerwiz.org", "drawing and mind maps — Excalidraw"),
    ("Meetings", "https://affine.zerwiz.org", "the record of what was said and decided"),
    ("Book", "https://book.zerwiz.org", "a time that suits you — Cal.com"),
]


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"generated": "", "meetings": []}


def mine(rows, person: str):
    if not person:
        return rows
    p = person.lower()
    return [r for r in rows if p in (str(r.get("owner", "")) + str(r.get("who", ""))).lower()]


OPERATOR_ENV = "GIMLE_OPERATOR"


def places_for(person: str, data_path: str) -> list[str] | None:
    """Which places this person may see — or None for 'everything' (the operator).

    The map lives beside the record (`places.json`): `{"person": ["place substring", …]}`.
    **Default deny**: a person not named in the map sees nothing; only the operator (named by
    `GIMLE_OPERATOR`) sees every place. That is H3's fix, and it fails closed on purpose.
    """
    operator = os.environ.get(OPERATOR_ENV, "")
    if operator and person.lower() == operator.lower():
        return None
    path = os.path.join(os.path.dirname(data_path), "places.json")
    try:
        with open(path, encoding="utf-8") as fh:
            mapping = json.load(fh)
    except Exception:
        return []                     # no map → nobody but the operator sees anything
    for who, places in mapping.items():
        if who.lower() == person.lower():
            return [str(x) for x in places]
    return []


def render(person: str, data: dict, allowed: list[str] | None = None, docs: list | None = None) -> str:
    today = datetime.date.today()
    horizon = today + datetime.timedelta(days=7)
    actions, decisions, questions = [], [], []
    meetings = data.get("meetings", [])
    if allowed is not None:
        meetings = [m for m in meetings
                    if any(str(m.get("title", "")).lower().startswith(a.lower()) or
                           a.lower() in str(m.get("title", "")).lower() for a in allowed)]
    for m in meetings:
        for a in m.get("actions", []):
            a["meeting"] = m.get("title", m.get("id", ""))
            actions.append(a)
        for d in m.get("decisions", []):
            d["meeting"] = m.get("title", m.get("id", ""))
            decisions.append(d)
        for q in m.get("questions", []):
            q["meeting"] = m.get("title", m.get("id", ""))
            questions.append(q)

    def due_row(a):
        due = str(a.get("due") or "").strip()
        label, cls = "date unresolved", "meta"
        try:
            d = datetime.date.fromisoformat(due[:10])
            if d < today:
                label, cls = f"overdue · {due}", "due over"
            elif d <= horizon:
                label, cls = f"due {due}", "due"
            else:
                label, cls = f"due {due}", "meta"
        except Exception:
            pass
        return (f'<li><div class="title">{html.escape(str(a.get("text") or a.get("action") or ""))}</div>'
                f'<div class="{cls}">{html.escape(label)}'
                f' · <span class="meta">{html.escape(str(a.get("owner") or "owner unresolved"))}</span>'
                f' · <span class="meta">{html.escape(str(a.get("meeting") or ""))}</span></div></li>')

    def plain_row(r, key="text"):
        return (f'<li><div class="title">{html.escape(str(r.get(key) or ""))}</div>'
                f'<div class="meta">{html.escape(str(r.get("meeting") or ""))}'
                f'{(" · " + html.escape(str(r.get("who") or r.get("owner")))) if (r.get("who") or r.get("owner")) else ""}</div></li>')

    mine_actions = [a for a in mine(actions, person)]
    mine_questions = [q for q in mine(questions, person)]

    def section(title, rows, renderer):
        if not rows:
            body = '<ul><li class="empty">nothing here — a quiet desk</li></ul>'
        else:
            body = "<ul>" + "".join(renderer(r) for r in rows[:8]) + "</ul>"
        return f'<h2>{title}</h2><div class="card">{body}</div>'

    def board_row(card):
        due = card.get("due") or ""
        return (f'<li><b>{html.escape(card.get("name", "")[:110])}</b>'
                f'<div class="meta">{html.escape(card.get("project", ""))}'
                f'{(" · due " + html.escape(due)) if due else ""}</div></li>')

    board_cards, board_detail = [], "the board reader is not installed"
    if plane_reader is not None:
        try:
            board_cards, board_detail = plane_reader.board_for(person)
        except Exception as exc:                       # noqa: BLE001
            board_cards, board_detail = [], f"the board did not answer ({exc.__class__.__name__})"

    rows = []
    for group in docs or []:
        links = "".join(
            f'<li><a href="/desk/docs/{html.escape(group["project"])}/{html.escape(n)}">{html.escape(n)}</a></li>'
            for n in group["files"][:8])
        rows.append(f'<h2>{html.escape(group["title"])} <span class="meta">— mirrored</span></h2>'
                    f'<div class="card"><ul>{links}</ul></div>')
    docs_html = "".join(rows)

    tiles = "".join(f'<a class="tile" href="{html.escape(url)}"><b>{html.escape(name)}</b>'
                    f'<span>{html.escape(desc)}</span></a>' for name, url, desc in TILES)

    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gimlé — the desk</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cormorant:ital,wght@0,400;0,600;1,400&family=Newsreader:opsz,wght@6..72,300;6..72,400&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>{CLOTH}</style></head><body><div class="wrap">
<header><h1>The <em>desk</em></h1><span class="who">{html.escape(person or "friend")} · {today.isoformat()}</span></header>
{section("From the board — assigned to you", board_cards, board_row)}
<div class="meta" style="margin:-6px 0 14px 4px;opacity:.6">{html.escape(board_detail)}</div>
{section("Due this week", mine_actions, due_row)}
{section("Last decisions", decisions[:5], plain_row)}
{section("Questions waiting on me", mine_questions, plain_row)}
{docs_html}
<h2>The places</h2><div class="tiles">{tiles}</div>
<footer>Gimlé — the hall that outlives the fire · on Zerwiz&rsquo;s own hardware · <a href="/manual.html" style="color:inherit;border-bottom:1px solid rgba(201,151,79,.4)">user manual</a></footer>
</div></body></html>"""


DOC_ROOTS = ("md", "html", "txt")


def doc_path(data_path: str, project: str, name: str) -> str | None:
    """A mirrored document, or None. The mirror writes into data/docs/<project>/; until this door
    existed those files were written and never read, and `/docs/...` through the hall answered 200
    with the login page — a green that showed nothing (Rule 37). Only a flat file name is accepted:
    no separators, no dots leading, no traversal, and only the three suffixes a mirrored record uses.
    """
    if not project or not name or "/" in name or "\\" in name or name.startswith("."):
        return None
    if ".." in project or "/" in project or project.startswith("."):
        return None
    if name.rsplit(".", 1)[-1].lower() not in DOC_ROOTS:
        return None
    root = os.path.join(os.path.dirname(data_path), "docs", project)
    path = os.path.join(root, name)
    real = os.path.realpath(path)
    if not real.startswith(os.path.realpath(root) + os.sep):
        return None
    return real if os.path.isfile(real) else None


def may_read_doc(allowed: list[str] | None, project: str) -> bool:
    """The same membership rule as the record: None means the operator (everything), a list means
    the places that person may see, and a project not named in it is not theirs to read."""
    if allowed is None:
        return True
    return any(str(a).lower() in project.lower() or project.lower() in str(a).lower() for a in allowed)


def docs_for(data_path: str, allowed: list[str] | None) -> list[dict]:
    """The mirrored documents this person may read, newest first.

    The mirror writes into `<data>/docs/<project>/`; this is how a person *finds* them without knowing a
    URL. The rule is the same one the door uses (`may_read_doc`): a place not granted is not listed and
    not served. A `index.md` beside them supplies the project's title, because a mirror should say what
    it is a mirror of.
    """
    root = os.path.join(os.path.dirname(data_path), "docs")
    out = []
    try:
        projects = sorted(p for p in os.listdir(root) if os.path.isdir(os.path.join(root, p)))
    except OSError:
        return out
    for project in projects:
        if not may_read_doc(allowed, project):
            continue
        title = project
        index = os.path.join(root, project, "index.md")
        try:
            with open(index, encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("# "):
                        title = line[2:].strip()
                        break
        except OSError:
            pass
        files = []
        try:
            for name in sorted(os.listdir(os.path.join(root, project))):
                if doc_path(data_path, project, name):
                    files.append(name)
        except OSError:
            files = []
        if files:
            out.append({"project": project, "title": title, "files": files})
    return out


class Handler(BaseHTTPRequestHandler):
    data_path = ""
    server_version = "gimle-desk/1.0"

    def do_GET(self):  # noqa: N802
        if self.path.startswith("/health"):
            return self._send(200, "text/plain", b"ok")
        person = self.headers.get("Remote-User", "") or self.headers.get("X-Forwarded-User", "")
        allowed = places_for(person, self.data_path)
        if self.path.startswith("/desk/docs/") or self.path.startswith("/docs/"):
            return self._serve_doc(person, allowed)

        body = render(person, load(self.data_path), allowed,
                      docs_for(self.data_path, allowed)).encode("utf-8")
        self._send(200, "text/html; charset=utf-8", body)

    def _serve_doc(self, person: str, allowed):
        rest = self.path.split("/docs/", 1)[-1].split("?")[0]
        parts = [p for p in rest.split("/") if p]
        if len(parts) != 2:
            return self._send(404, "text/plain", b"not found")
        project, name = parts
        if not may_read_doc(allowed, project):
            return self._send(403, "text/plain", b"not yours to read")
        path = doc_path(self.data_path, project, name)
        if not path:
            return self._send(404, "text/plain", b"not found")
        ctype = "text/markdown; charset=utf-8" if path.endswith(".md") else "text/plain; charset=utf-8"
        with open(path, "rb") as fh:
            return self._send(200, ctype, fh.read())

    def _send(self, code: int, ctype: str, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # keep the journal quiet; one line per request
        sys.stderr.write("desk %s %s\n" % (self.headers.get("Remote-User", "-"), fmt % args))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8487)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--data", default="/srv/gimle-desk/meetings.json")
    args = ap.parse_args(argv)
    Handler.data_path = args.data
    srv = HTTPServer((args.bind, args.port), Handler)
    print(f"gimle desk on http://{args.bind}:{args.port} · data {args.data}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
