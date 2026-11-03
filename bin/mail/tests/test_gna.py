#!/usr/bin/env python3
"""The proofs plan 116 asks for before the desk is shown to a human."""

from __future__ import annotations

import json
import os
import re
import sys
import socketserver
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
AGENT_DIR = HERE.parent

TMP = Path(tempfile.mkdtemp(prefix="gna-test-"))
os.environ["YMIR_HOME"] = str(TMP)
(TMP / "hodd/memory/mail").mkdir(parents=True)
(TMP / "hodd/state").mkdir(parents=True)
(TMP / "hodd/memory/mail/accounts.yaml").write_text(
    "accounts:\n"
    "  - id: operator@example.com\n    grant: X\n    status: scoped\n"
    "  - id: team@example.com\n    grant: Y\n    status: scoped\n"
    "  - id: reader@example.org\n    transport: imap\n    status: scoped\n"
    "    imap:\n"
    "      host_key: GNA_IMAP_HOST\n      port_key: GNA_IMAP_PORT\n"
    "      tls_key: GNA_IMAP_TLS\n      user_key: GNA_IMAP_USER\n"
    "      password_key: GNA_IMAP_PASSWORD\n      mailbox: INBOX\n"
    "house:\n"
    "  - address: gimle@example.org\n    route: catch-all\n    forward_to: operator@example.com\n"
    "  - address: dead@nowhere.example\n    route: catch-all\n    forward_to: operator@example.com\n"
    "  - address: team@example.com\n    route: catch-all\n    forward_to: team@example.com\n"
    "domains:\n"
    "  example.org:\n    expect_mx:\n      - mx.example.org\n    via: fixture\n"
    "  nowhere.example:\n    expect_mx:\n      - mx.nowhere.example\n    via: fixture\n",
    encoding="utf-8",
)

sys.path.insert(0, str(AGENT_DIR))
import gna_addresses  # noqa: E402
import gna_desk  # noqa: E402
import gna_import  # noqa: E402
import gna_judge  # noqa: E402
import gna_store  # noqa: E402


def record(**over) -> dict:
    base = {
        "id": "m1",
        "account": "operator@example.com",
        "direction": "in",
        "thread_key": "t1",
        "from": {"name": "Craig Example", "email": "craig@example.com"},
        "to": [{"name": "the operator", "email": "operator@example.com"}],
        "subject": "Faktura 2026-10",
        "body_text": "Bifogad faktura for oktober.",
        "received_at": "2026-10-23T10:00:00+00:00",
        "labels": ["INBOX", "UNREAD"],
        "classification": "invoice",
        "confidence": 0.85,
        "proposed_action": "file_invoice",
        "matched_by": "sender_email",
        "person_id": "craig-martin",
        "evidence": "test",
    }
    base.update(over)
    return base


class StoreScope(unittest.TestCase):
    def test_no_account_is_refused(self):
        for call in (lambda: gna_store.latest(""), lambda: gna_store.latest(None)):
            with self.assertRaises(gna_store.ScopeError):
                call()

    def test_undeclared_account_is_refused(self):
        with self.assertRaises(gna_store.ScopeError):
            gna_store.latest("someone@example.com")

    def test_message_never_crosses_accounts(self):
        gna_store.append([record()])
        with self.assertRaises(gna_store.ScopeError):
            gna_store.get_message("team@example.com", "m1")

    def test_each_account_sees_only_its_own(self):
        gna_store.append([
            record(id="a1", account="operator@example.com"),
            record(id="b1", account="team@example.com", received_at="2026-10-23T11:00:00+00:00"),
        ])
        ids_a = {r["id"] for r in gna_store.latest("operator@example.com")}
        ids_b = {r["id"] for r in gna_store.latest("team@example.com")}
        self.assertIn("a1", ids_a)
        self.assertNotIn("b1", ids_a)
        self.assertIn("b1", ids_b)
        self.assertNotIn("a1", ids_b)


class Judge(unittest.TestCase):
    people = {"craig@example.com": {"id": "craig-martin", "project": "wayof"}}

    def test_known_sender_invoice_is_high_confidence(self):
        verdict = gna_judge.judge(record(), self.people)
        self.assertEqual(verdict["classification"], "invoice")
        self.assertEqual(verdict["proposed_action"], "file_invoice")
        self.assertGreaterEqual(verdict["confidence"], 0.6)
        self.assertIn("craig-martin", verdict["evidence"])

    def test_unknown_sender_lands_in_unsure(self):
        verdict = gna_judge.judge(record(**{"from": {"email": "someone@example.com"},
                                            "subject": "Hej", "body_text": "Hej pa dig"}), self.people)
        self.assertLess(verdict["confidence"], 0.6)
        self.assertEqual(verdict["classification"], "other")

    def test_thread_inherits(self):
        parent = record(id="m0", classification="invoice", person_id="craig-martin")
        verdict = gna_judge.judge(record(id="m2", subject="Re: Faktura", body_text="Tack!"), self.people, parent)
        self.assertEqual(verdict["classification"], "invoice")
        self.assertEqual(verdict["matched_by"], "thread")

    def test_house_sender_is_not_a_human_question(self):
        verdict = gna_judge.judge(
            record(**{"from": {"email": "team@example.com"}, "subject": "[Copy] team door"}),
            self.people,
            house={"team@example.com"},
        )
        self.assertEqual(verdict["proposed_action"], "archive")
        self.assertEqual(verdict["matched_by"], "house")

    def test_every_verdict_carries_evidence(self):
        for sender in ({"email": "craig@example.com"}, {"email": "x@y.z"}):
            verdict = gna_judge.judge(record(**{"from": sender}), self.people)
            self.assertTrue(verdict["evidence"])
            self.assertIn(verdict["classification"], gna_judge.CLASSES)
            self.assertIn(verdict["proposed_action"], gna_judge.ACTIONS)


class Desk(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        gna_desk.Handler.token_value = "test-token"
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), gna_desk.Handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path: str, token: str | None = "test-token"):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}")
        if token:
            req.add_header("authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as exc:
            return exc.code, json.load(exc)

    def test_health_never_names_a_subject(self):
        status, body = self.get("/health", token=None)
        self.assertEqual(status, 200)
        self.assertEqual(body["send_capability"], "none")
        self.assertNotIn("messages_list", json.dumps(body))

    def test_without_token_is_refused(self):
        self.assertEqual(self.get("/queue?account=operator@example.com", token=None)[0], 401)

    def test_without_account_scope_is_refused(self):
        status, body = self.get("/queue")
        self.assertEqual(status, 400)
        self.assertIn("account scope required", body["error"])

    def test_undeclared_account_is_refused(self):
        status, body = self.get("/queue?account=someone@example.com")
        self.assertEqual(status, 400)
        self.assertIn("not declared", body["error"])

    def test_queue_is_scoped_and_ordered_into_columns(self):
        gna_store.append([record(id="q1")])
        status, body = self.get("/queue?account=operator@example.com&hours=100000")
        self.assertEqual(status, 200)
        self.assertIn("q1", {r["id"] for r in body["columns"]["needs_you"]})

    def test_post_is_not_allowed(self):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}/draft", data=b"{}", method="POST")
        req.add_header("authorization", "Bearer test-token")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(req, timeout=5)
        self.assertEqual(ctx.exception.code, 405)




MESSAGE = (
    b"From: Craig Example <craig@example.com>\r\n"
    b"To: gimle@example.org\r\n"
    b"Subject: Faktura 2026-10\r\n"
    b"Message-ID: <fixture-1@example.com>\r\n"
    b"Date: Fri, 23 Oct 2026 10:00:00 +0000\r\n"
    b"Content-Type: text/plain; charset=utf-8\r\n\r\n"
    b"Bifogad faktura for oktober.\r\n"
)


class FixtureIMAP(socketserver.ThreadingTCPServer):
    """A real IMAP4rev1 socket, small enough to read: no TLS, no state, one message.

    It records every command it is sent, so the proof can show the reader never asked
    to change anything — EXAMINE and FETCH only."""

    allow_reuse_address = True
    daemon_threads = True

    def __init__(self) -> None:
        self.seen: list[str] = []
        self.user = "reader@example.org"
        self.password = "fixture"
        super().__init__(("127.0.0.1", 0), _ImapHandler)
        self.port = self.server_address[1]


class _ImapHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:  # noqa: C901 - a protocol handler is a switch
        self.wfile.write(b"* OK fixture IMAP4rev1 ready\r\n")
        self.wfile.flush()
        while True:
            line = self.rfile.readline()
            if not line:
                return
            text = line.decode("utf-8", "replace").rstrip("\r\n")
            self.server.seen.append(text)
            tag, _, rest = text.partition(" ")
            verb = rest.split(" ", 1)[0].upper() if rest else ""
            args = rest[len(verb):].strip()
            if verb == "CAPABILITY":
                self.write("* CAPABILITY IMAP4rev1\r\n", tag, "OK CAPABILITY completed")
            elif verb == "LOGIN":
                if "reader@example.org" in args and "fixture" in args:
                    self.write(None, tag, "OK LOGIN completed")
                else:
                    self.write(None, tag, "NO LOGIN failed")
            elif verb in ("EXAMINE", "SELECT"):
                self.write("* 1 EXISTS\r\n* OK [UIDVALIDITY 1] UIDs valid",
                           tag, f"OK [READ-ONLY] {verb} completed")
            elif verb == "UID" and args.upper().startswith("SEARCH"):
                wanted = "1" if "gimle@example.org" in args or "TO" not in args.upper() else ""
                self.write(f"* SEARCH {wanted}".rstrip(), tag, "OK UID SEARCH completed")
            elif verb == "UID" and args.upper().startswith("FETCH"):
                self.wfile.write(b"* 1 FETCH (UID 1 RFC822 {" + str(len(MESSAGE)).encode() + b"}\r\n")
                self.wfile.write(MESSAGE)
                self.wfile.write(b")\r\n")
                self.write(None, tag, "OK UID FETCH completed")
            elif verb == "LOGOUT":
                self.write("* BYE fixture signing off", tag, "OK LOGOUT completed")
                return
            elif verb == "NOOP":
                self.write(None, tag, "OK NOOP completed")
            else:
                self.write(None, tag, f"BAD unsupported {verb}")

    def write(self, untagged: str | None, tag: str, tagged: str) -> None:
        payload = ""
        if untagged:
            payload += untagged + "\r\n"
        payload += f"{tag} {tagged}\r\n"
        self.wfile.write(payload.encode("utf-8"))
        self.wfile.flush()


class ImapReader(unittest.TestCase):
    """The second transport, proven against a real socket (plan 116 §15.3.2)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.server = FixtureIMAP()
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.secrets = TMP / "imap-secrets.env"
        cls.secrets.write_text(
            f"GNA_IMAP_HOST=127.0.0.1\nGNA_IMAP_PORT={cls.server.port}\nGNA_IMAP_TLS=none\n"
            "GNA_IMAP_USER=reader@example.org\nGNA_IMAP_PASSWORD=fixture\n",
            encoding="utf-8",
        )
        os.environ["GNA_SECRETS_FILE"] = str(cls.secrets)

    @classmethod
    def tearDownClass(cls) -> None:
        os.environ.pop("GNA_SECRETS_FILE", None)
        cls.server.shutdown()
        cls.server.server_close()

    def test_row_names_the_transport(self):
        row = gna_store.declared_accounts()["reader@example.org"]
        self.assertEqual(gna_import.transport_of(row), "imap")

    def test_a_message_read_over_imap_keeps_its_to_header(self):
        records = gna_import.collect("reader@example.org", days=2, max_messages=10)
        self.assertEqual(len(records), 1)
        record = records[0]
        self.assertEqual(record["to_header"], "gimle@example.org")
        self.assertEqual(record["subject"], "Faktura 2026-10")
        self.assertEqual(record["id"], "fixture-1@example.com")
        self.assertEqual(record["account"], "reader@example.org")
        self.assertIn(record["classification"], gna_judge.CLASSES)
        self.assertTrue(record["evidence"])

    def test_the_search_finds_the_message_addressed_to_gimle(self):
        records = gna_import.search_address("reader@example.org", "gimle@example.org", days=2)
        self.assertEqual([r["id"] for r in records], ["fixture-1@example.com"])

    def test_the_reader_never_asks_the_store_to_change_anything(self):
        gna_import.collect("reader@example.org", days=2, max_messages=10)
        commands = " ".join(self.server.seen).upper()
        for mutation in ("STORE", "COPY", "EXPUNGE", "APPEND", "DELETE", "MOVE", "SEARCH ALL"):
            self.assertNotIn(mutation, commands)
        self.assertIn("EXAMINE", commands)

    def test_an_account_with_no_imap_block_is_refused(self):
        with self.assertRaises(SystemExit) as ctx:
            gna_import.imap_target({"id": "operator@example.com", "transport": "imap"})
        self.assertIn("no IMAP account is declared", str(ctx.exception))

    def test_a_key_named_but_absent_is_refused_by_name(self):
        row = {"id": "x@example.org", "transport": "imap",
               "imap": {"host_key": "GNA_IMAP_HOST", "user_key": "GNA_MISSING_KEY",
                        "password_key": "GNA_IMAP_PASSWORD"}}
        with self.assertRaises(SystemExit) as ctx:
            gna_import.imap_target(row)
        self.assertIn("GNA_MISSING_KEY", str(ctx.exception))

    def test_plaintext_off_loopback_is_refused(self):
        row = {"id": "y@example.org", "transport": "imap",
               "imap": {"host_key": "GNA_IMAP_HOST", "user_key": "GNA_IMAP_USER",
                        "password_key": "GNA_IMAP_PASSWORD", "tls_key": "GNA_IMAP_TLS",
                        "tls": "none"}}
        saved = os.environ["GNA_SECRETS_FILE"]
        offbox = TMP / "imap-offbox.env"
        offbox.write_text(self.secrets.read_text(encoding="utf-8").replace(
            "GNA_IMAP_HOST=127.0.0.1", "GNA_IMAP_HOST=mail.example.com"), encoding="utf-8")
        os.environ["GNA_SECRETS_FILE"] = str(offbox)
        try:
            with self.assertRaises(SystemExit) as ctx:
                gna_import.imap_target(row)
            self.assertIn("unencrypted", str(ctx.exception))
        finally:
            os.environ["GNA_SECRETS_FILE"] = saved



class FixtureDNS(threading.Thread):
    """A resolver on loopback: MX for example.org, NXDOMAIN for anything else.

    The register measures rather than assumes, so its proof must control the DNS it
    measures — a test that asks the real internet is a test that changes with it."""

    daemon = True

    def __init__(self) -> None:
        super().__init__()
        import socket as _socket

        self.sock = _socket.socket(_socket.AF_INET, _socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.stop = False

    def run(self) -> None:
        import struct as _struct

        while not self.stop:
            try:
                packet, peer = self.sock.recvfrom(2048)
            except OSError:
                continue
            try:
                names, offset = [], 12
                while packet[offset]:
                    names.append(packet[offset + 1: offset + 1 + packet[offset]].decode())
                    offset += 1 + packet[offset]
                name = ".".join(names)
                answers = [(10, f"mx.{name}")] if name in ("example.org", "example.com") else []
                flags = 0x8180 if answers else 0x8183
                body = _struct.pack(">HHHHHH", _struct.unpack(">H", packet[:2])[0], flags, 1, len(answers), 0, 0)
                body += gna_addresses._encode_name(name) + _struct.pack(">HH", 15, 1)
                for preference, host in answers:
                    rdata = _struct.pack(">H", preference) + gna_addresses._encode_name(host)
                    body += b"\xc0\x0c" + _struct.pack(">HHIH", 15, 1, 60, len(rdata)) + rdata
                self.sock.sendto(body, peer)
            except (IndexError, ValueError):
                continue

class Addresses(unittest.TestCase):
    """Door 1 and door 3: the register measures, and the desk tells the truth about it."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.dns = FixtureDNS()
        cls.dns.start()
        os.environ["GNA_DNS_SERVER"] = f"127.0.0.1:{cls.dns.port}"
        os.environ.pop("GNA_DNS_OFFLINE", None)
        gna_addresses.ARRIVALS = TMP / "hodd/state/mail/inbound-arrivals.jsonl"
        gna_addresses.ALIAS_CACHE = TMP / "hodd/state/mail/alias-probe.json"

    @classmethod
    def tearDownClass(cls) -> None:
        os.environ.pop("GNA_DNS_SERVER", None)
        cls.dns.stop = True
        cls.dns.sock.close()

    def setUp(self) -> None:
        # every proof starts from an empty ledger: "unproven" must mean what it says
        try:
            gna_addresses.ARRIVALS.unlink()
        except OSError:
            pass

    def rows(self) -> dict:
        return {row["address"]: row for row in gna_addresses.register()}

    def test_an_address_whose_domain_has_no_mx_is_undeliverable(self):
        row = self.rows()["dead@nowhere.example"]
        self.assertEqual(row["mx"], "absent")
        self.assertEqual(row["state"], "undeliverable")
        self.assertEqual(row["deliverable"], "no")

    def test_mx_and_a_route_is_declared_not_deliverable(self):
        row = self.rows()["gimle@example.org"]
        self.assertEqual(row["mx"], "present")
        self.assertEqual(row["route"], "catch-all")
        self.assertEqual(row["state"], "unproven")
        self.assertIn("no test message", row["reason"])

    def test_an_arrival_proof_makes_it_deliverable_and_the_state_is_a_plain_word(self):
        gna_addresses.append_arrival({"to": "gimle@example.org", "to_header": "gimle@example.org",
                                      "account": "operator@example.com"})
        row = self.rows()["gimle@example.org"]
        self.assertEqual(row["state"], "deliverable")
        document = gna_addresses.honesty()
        line = {a["address"]: a for a in document["addresses"]}["gimle@example.org"]
        self.assertEqual(line["deliverable"], "deliverable")
        self.assertEqual(line["forwarded"], "operator@example.com")
        self.assertEqual(line["unreadable"], "no")
        self.assertTrue(line["arrived"])

    def test_the_honesty_line_is_exactly_three_words_per_address(self):
        for line in gna_addresses.honesty()["addresses"]:
            self.assertIn(line["deliverable"],
                          ("deliverable", "declared", "outbound-only", "unmeasured", "undeliverable"))
            self.assertTrue(line["forwarded"])
            self.assertIn(line["unreadable"], ("yes", "no"))

    def test_the_desk_renders_the_line_and_says_why_an_inbox_is_empty(self):
        document = gna_desk.honesty()
        state = gna_desk.inbox_state("operator@example.com", document)
        self.assertIn(state["inbox_state"], ("arrivable", "declared-only", "cannot-arrive"))
        self.assertTrue(state["notice"])
        self.assertTrue(state["addresses"])
        toon = gna_addresses.toon_honesty(document)
        self.assertIn("honesty[", toon)
        self.assertIn("gimle@example.org", toon)

    def test_an_account_no_address_forwards_into_cannot_receive(self):
        document = gna_desk.honesty()
        state = gna_desk.inbox_state("reader@example.org", document)
        self.assertEqual(state["inbox_state"], "cannot-arrive")
        self.assertIn("no declared address", state["notice"])


class InboundDoor(unittest.TestCase):
    """The shell door's own decisions, run as a subprocess exactly as a hand would.

    `--mx-only` asks the first question the door asks — "could mail arrive here at all" —
    which is the whole of the skip path: exit 0 ready, exit 3 skip-with-reason."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.dns = FixtureDNS()
        cls.dns.start()
        cls.script = AGENT_DIR / "inbound-test.sh"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.dns.stop = True
        cls.dns.sock.close()

    def run_door(self, *args: str):
        import subprocess

        env = dict(os.environ)
        env["YMIR_HOME"] = str(TMP)
        env["GNA_DNS_SERVER"] = f"127.0.0.1:{self.dns.port}"
        env.pop("GNA_DNS_OFFLINE", None)
        return subprocess.run([str(self.script), *args], capture_output=True, text=True, env=env, timeout=120)

    def test_an_address_that_can_receive_is_ready(self):
        done = self.run_door("--mx-only", "--to", "gimle@example.org")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("READY", done.stdout)
        self.assertIn('"present"', done.stdout)

    def test_an_address_with_no_mx_skips_with_the_reason_and_exit_3(self):
        done = self.run_door("--mx-only", "--to", "dead@nowhere.example")
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("SKIP", done.stdout)
        self.assertIn("no MX record", done.stdout)
        self.assertIn("mx.nowhere.example", done.stdout)

    def test_an_undeclared_address_is_refused_rather_than_tested(self):
        done = self.run_door("--mx-only", "--to", "stranger@elsewhere.example")
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("not declared", done.stdout)

    def test_a_same_domain_sender_is_refused_because_it_proves_nothing(self):
        done = self.run_door("--mx-only", "--to", "team@example.com", "--from", "operator@example.com")
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("another domain", done.stdout)


class InboundChain(unittest.TestCase):
    """The acceptance chain, end to end and offline: MX measured → arrival found by To: →
    the proof is written where the register reads it → the address becomes deliverable."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.dns = FixtureDNS()
        cls.dns.start()
        os.environ["GNA_DNS_SERVER"] = f"127.0.0.1:{cls.dns.port}"
        cls.imap = FixtureIMAP()
        cls.thread = threading.Thread(target=cls.imap.serve_forever, daemon=True)
        cls.thread.start()
        cls.secrets = TMP / "chain-secrets.env"
        cls.secrets.write_text(
            f"GNA_IMAP_HOST=127.0.0.1\nGNA_IMAP_PORT={cls.imap.port}\nGNA_IMAP_TLS=none\n"
            "GNA_IMAP_USER=reader@example.org\nGNA_IMAP_PASSWORD=fixture\n", encoding="utf-8")
        os.environ["GNA_SECRETS_FILE"] = str(cls.secrets)

    @classmethod
    def tearDownClass(cls) -> None:
        os.environ.pop("GNA_SECRETS_FILE", None)
        os.environ.pop("GNA_DNS_SERVER", None)
        cls.dns.stop = True
        cls.dns.sock.close()
        cls.imap.shutdown()
        cls.imap.server_close()

    def setUp(self) -> None:
        try:
            gna_addresses.ARRIVALS.unlink()
        except OSError:
            pass

    def test_the_arrival_is_found_by_its_to_header_and_proven(self):
        proof = gna_addresses.await_arrival("reader@example.org", "gimle@example.org",
                                           timeout=10, poll=0.2)
        self.assertEqual(proof.get("result"), "arrived", proof)
        self.assertEqual(proof["to_header"], "gimle@example.org")
        self.assertTrue(gna_addresses.ARRIVALS.exists())
        rows = {row["address"]: row for row in gna_addresses.register()}
        self.assertEqual(rows["gimle@example.org"]["state"], "deliverable")

    def test_the_desk_then_says_the_inbox_can_receive(self):
        gna_addresses.await_arrival("reader@example.org", "gimle@example.org", timeout=10, poll=0.2)
        state = gna_desk.inbox_state("operator@example.com", gna_desk.honesty())
        self.assertEqual(state["inbox_state"], "arrivable")

    def test_a_message_that_never_arrives_is_a_timeout_and_never_a_proof(self):
        proof = gna_addresses.await_arrival("reader@example.org", "nobody@example.org",
                                           timeout=0.5, poll=0.1)
        self.assertEqual(proof.get("result"), "timeout")
        self.assertFalse(gna_addresses.ARRIVALS.exists())


class NoSendCapability(unittest.TestCase):
    FORBIDDEN = (
        r"messages/send",
        r"\bsmtplib\b",
        r"users/me/drafts",
        r"mail-send\.sh",
        r"gmail\.send",
    )

    def test_no_file_here_can_send(self):
        for path in sorted(AGENT_DIR.glob("gna_*.py")) + [AGENT_DIR / "mail-scan.sh"]:
            text = path.read_text(encoding="utf-8")
            for pattern in self.FORBIDDEN:
                self.assertIsNone(
                    re.search(pattern, text),
                    f"{path.name} carries a send path: {pattern}",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
