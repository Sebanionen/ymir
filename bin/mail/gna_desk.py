#!/usr/bin/env python3
"""Gná's desk — read-only, loopback, one account per request.

  gna_desk.py                 # 127.0.0.1:8494, token in hodd/state/gna-desk.token
  gna_desk.py --port 8494 --print-token

  gna_desk.py --honesty          the honesty line on stdout, TOON (no server)

  GET /health                        no token, counts only, never a subject
  GET /accounts                      the declared scope
  GET /addresses                     the honesty line: deliverable · forwarded · unreadable
  GET /queue?account=A&hours=48      the four columns, with the honesty line beside them
  GET /message?account=A&id=ID       one message, inside that account

THE HONESTY LINE (plan 116 §15.3.3). An empty queue is ambiguous: it can mean "nothing
needs you" or "nothing could arrive, and nobody could have read it if it had". Every
queue answer therefore carries, per declared address, `deliverable · forwarded ·
unreadable` and an `inbox_state` for the account — the desk can never render an empty
inbox where nothing was able to land.

There is no draft route and no approve route in this file. The desk at P0 reads;
the hand that sends is the Allfather's, through the gate that already exists.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))

import gna_addresses
import gna_store


def token() -> str:
    env = os.environ.get("GNA_DESK_TOKEN")
    if env:
        return env.strip()
    gna_store.STATE_DIR.mkdir(parents=True, exist_ok=True)
    if gna_store.TOKEN_FILE.exists():
        return gna_store.TOKEN_FILE.read_text(encoding="utf-8").strip()
    value = secrets.token_urlsafe(32)
    gna_store.TOKEN_FILE.write_text(value, encoding="utf-8")
    gna_store.TOKEN_FILE.chmod(0o600)
    return value


def column_of(record: dict) -> str:
    if record.get("handled_at"):
        return "done"
    if record.get("direction") == "out":
        return "waiting"
    if float(record.get("confidence") or 0) < 0.6:
        return "unsure"
    if record.get("proposed_action") == "archive":
        return "done"
    return "needs_you"


def row(record: dict) -> dict:
    sender = record.get("from") or {}
    return {
        "id": record.get("id"),
        "account": record.get("account"),
        "from": {"name": sender.get("name", ""), "email": sender.get("email", "")},
        "subject": record.get("subject"),
        "received_at": record.get("received_at"),
        "summary": (record.get("body_text") or "").strip().split("\n")[0][:220],
        "classification": record.get("classification"),
        "confidence": record.get("confidence"),
        "proposed_action": record.get("proposed_action"),
        "person_id": record.get("person_id"),
        "project_id": record.get("project_id"),
        "matched_by": record.get("matched_by"),
        "evidence": record.get("evidence"),
        "column": column_of(record),
    }


def queue(account: str, hours: int) -> dict:
    rows = [r for r in gna_store.latest(account, hours) if (r.get("direction") or "in") == "in"]
    columns = {"needs_you": [], "unsure": [], "waiting": [], "done": []}
    for record in rows:
        columns[column_of(record)].append(row(record))
    oldest = ""
    for record in rows:
        if column_of(record) in ("needs_you", "unsure"):
            oldest = record.get("received_at") or oldest
    document = honesty()
    inbox = inbox_state(account, document)
    return {
        "account": account,
        "window_hours": hours,
        "columns": columns,
        "counts": {k: len(v) for k, v in columns.items()},
        "oldest_waiting": oldest,
        "inbox_state": inbox["inbox_state"],
        "notice": inbox["notice"],
        "addresses": inbox["addresses"],
        "address_counts": document["counts"],
    }


def honesty() -> dict:
    """Per address: deliverable · forwarded · unreadable. Measured, or declared honestly."""
    return gna_addresses.honesty()


def account_addresses(account: str, document: dict) -> list[dict]:
    """The declared addresses whose mail lands IN this account."""
    return [row for row in document["addresses"] if (row.get("forwarded") or "").lower() == account]


def inbox_state(account: str, document: dict) -> dict:
    """Can anything arrive here at all? The answer the desk must show beside an empty queue."""
    rows = account_addresses(account, document)
    states = [row["deliverable"] for row in rows]
    if any(state == "deliverable" for state in states):
        state, notice = "arrivable", "proven: a test message reached this account"
    elif any(state == "declared" for state in states):
        state, notice = "declared-only", ("no arrival is proven yet — the address has MX and a route, "
                                          "but no test message has landed (bin/mail/inbound-test.sh proves it)")
    elif not rows:
        state, notice = "cannot-arrive", ("no declared address forwards into this account, so an empty queue "
                                          "here means nothing was ever addressed to it")
    else:
        state, notice = "cannot-arrive", "nothing could arrive: " + "; ".join(
            f"{row['address']} — {row['reason']}" for row in rows)
    return {"account": account, "inbox_state": state, "notice": notice, "addresses": rows}


class Handler(BaseHTTPRequestHandler):
    server_version = "gna-desk/0.1"
    token_value = ""

    def _json(self, payload: dict, status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authed(self) -> bool:
        header = self.headers.get("authorization", "")
        supplied = header[7:].strip() if header.lower().startswith("bearer ") else ""
        return bool(supplied) and secrets.compare_digest(supplied, self.token_value)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path.rstrip("/") or "/"

        if path == "/health":
            stats = gna_store.stats()
            last_run = gna_store.last_run()
            return self._json({
                "ok": True,
                "read_only": True,
                "send_capability": "none",
                "accounts": stats.get("declared", []),
                "messages": stats.get("accounts", {}),
                "versions": stats.get("versions", 0),
                "last_ingest": stats.get("last_ingest", ""),
                "last_run": last_run,
                "addresses": honesty()["counts"],
            })

        if not self._authed():
            return self._json({"error": "unauthorized"}, HTTPStatus.UNAUTHORIZED)

        account = (query.get("account") or [""])[0]
        try:
            if path == "/accounts":
                return self._json({"accounts": sorted(gna_store.declared_accounts())})
            if path == "/addresses":
                document = honesty()
                document["inbox"] = {name: inbox_state(name, document)
                                     for name in sorted(gna_store.declared_accounts())}
                return self._json(document)
            if path == "/queue":
                hours = int((query.get("hours") or ["48"])[0])
                return self._json(queue(gna_store.require_account(account), hours))
            if path == "/message":
                message_id = (query.get("id") or [""])[0]
                record = gna_store.get_message(gna_store.require_account(account), message_id)
                return self._json(row(record) | {"body_text": record.get("body_text", "")})
        except gna_store.ScopeError as exc:
            return self._json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except ValueError as exc:
            return self._json({"error": f"bad parameter: {exc}"}, HTTPStatus.BAD_REQUEST)

        return self._json({"error": "not found",
                           "routes": ["/health", "/accounts", "/addresses", "/queue", "/message"]},
                          HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        return self._json({"error": "the desk is read-only at P0: there is no draft and no approve route"},
                          HTTPStatus.METHOD_NOT_ALLOWED)

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("gna-desk %s\n" % (fmt % args))


def main() -> int:
    ap = argparse.ArgumentParser(description="Gná's read-only desk")
    ap.add_argument("--port", type=int, default=int(os.environ.get("GNA_DESK_PORT", "8494")))
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--print-token", action="store_true")
    ap.add_argument("--honesty", action="store_true",
                    help="print the honesty line (deliverable · forwarded · unreadable) and exit")
    args = ap.parse_args()
    if args.honesty:
        document = honesty()
        print(gna_addresses.toon_honesty(document))
        accounts = sorted(gna_store.declared_accounts())
        if not accounts:
            print("inbox[0]{account}:\n")
            print("the desk serves no declared account — it can read no mailbox at all")
            return 0
        print(f"inbox[{len(accounts)}]{{account,inbox_state,notice}}:")
        for name in accounts:
            state = inbox_state(name, document)
            print(f'  "{name}","{state["inbox_state"]}",'
                  f'"{state["notice"].replace(chr(34), chr(39))}"')
        return 0
    if args.host not in ("127.0.0.1", "localhost", "::1"):
        raise SystemExit("gna-desk: loopback only — the desk is never bound to a public address")

    Handler.token_value = token()
    if args.print_token:
        print(Handler.token_value)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(json.dumps({"desk": f"http://{args.host}:{args.port}", "read_only": True,
                      "accounts": sorted(gna_store.declared_accounts())}))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
