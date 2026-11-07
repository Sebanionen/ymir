#!/usr/bin/env python3
"""a2a-front — the ward in front of the A2A door, for hands that are not on our tailnet.

Nothing reaches the A2A node without a token that verifies, and no token is enough
without a grant. The card is public by design; everything else is checked here.

    a2a-front.py serve --upstream http://127.0.0.1:8301 --pub <ed25519.pub.pem> \
        --aud heimdall --listen 127.0.0.1:8400 [--rune bin/records/runes-append.sh]

    a2a-front.py mint  --key <ed25519.key.pem> --peer andre --skill well-recall \
        --aud heimdall --minutes 60 [--iss heimdall]

    a2a-front.py verify --token <jwt> --pub <ed25519.pub.pem> --aud heimdall --skill well-recall

The three refusals, each carved as a Rune and each named in the answer:

    401  no bearer token            — "a token is required"
    401  token does not verify      — expired, wrong issuer, wrong audience, bad signature
    403  token verifies, no skill   — "this token names no such skill"

A token is EdDSA over a JWT: `iss` (the house), `aud` (the seat), `skills` (a list),
`sub` (the collaborator), `iat`/`exp`. Short-lived by default; re-minted on request.
"""
from __future__ import annotations

import argparse
import json
import uuid
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib import error as urlerror
from urllib import request as urlrequest

try:
    import jwt
    from cryptography.hazmat.primitives import serialization
except Exception as exc:  # pragma: no cover - a clean refusal, never a traceback
    print(f"a2a-front: the crypto doors are missing ({exc})", file=sys.stderr)
    raise SystemExit(3)

ALG = "EdDSA"


def load_key(path: str) -> object:
    data = Path(path).read_bytes()
    if b"PRIVATE KEY" in data:
        return serialization.load_pem_private_key(data, password=None)
    return serialization.load_pem_public_key(data)


def mint(args: argparse.Namespace) -> int:
    key = load_key(args.key)
    now = int(time.time())
    claims = {
        "iss": args.iss,
        "aud": args.aud,
        "sub": args.peer,
        "skills": [args.skill],
        "iat": now,
        "exp": now + int(args.minutes) * 60,
        "jti": f"{args.peer}-{args.skill}-{uuid.uuid4().hex}",
    }
    token = jwt.encode(claims, key, algorithm=ALG)
    if isinstance(token, bytes):
        token = token.decode()
    print(token)
    return 0


def verify(token: str, pub: str, aud: str, skill: str | None) -> tuple[bool, str, dict]:
    key = load_key(pub)
    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=[ALG],
            audience=aud,
            options={"require": ["exp", "iat", "aud", "iss", "skills"]},
        )
    except jwt.ExpiredSignatureError:
        return False, "token expired", {}
    except jwt.InvalidAudienceError:
        return False, f"token is not for this seat (aud != {aud})", {}
    except Exception as exc:
        return False, f"token does not verify: {exc}", {}
    if skill:
        skills = claims.get("skills") or []
        if skill not in skills:
            return False, f"this token names no such skill ({skill})", claims
    return True, "ok", claims


def carve(rune: str | None, actor: str, event: str, message: str) -> None:
    """One Rune per call, allowed or refused. A record that can be skipped is not a record."""
    if not rune:
        return
    import subprocess

    try:
        subprocess.run(
            ["bash", rune, actor, event, "--message", message],
            check=False,
            timeout=15,
            capture_output=True,
        )
    except Exception:
        pass


_SEEN: dict[str, float] = {}   # jti -> expiry, replay guard
_CALLS: dict[str, list[float]] = {}  # sub -> call timestamps, rate limit
RATE_PER_MIN = 30


def _replay(jti: str, exp: int) -> bool:
    """True when this token has been used before. A JWT is a ticket, not a season pass."""
    now = time.time()
    for k, e in list(_SEEN.items()):
        if e < now:
            _SEEN.pop(k, None)
    if jti and jti in _SEEN:
        return True
    if jti:
        _SEEN[jti] = float(exp)
    return False


def _over_rate(sub: str) -> bool:
    now = time.time()
    window = _CALLS.setdefault(sub or "anonymous", [])
    window[:] = [t for t in window if now - t < 60]
    if len(window) >= RATE_PER_MIN:
        return True
    window.append(now)
    return False


class Handler(BaseHTTPRequestHandler):
    upstream = ""
    pub = ""
    aud = "heimdall"
    rune: str | None = None
    server_version = "a2a-front/1.0"

    def log_message(self, fmt: str, *args) -> None:  # quieter logs; the Rune is the record
        sys.stderr.write("a2a-front: " + (fmt % args) + "\n")

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _refuse(self, code: int, reason: str, who: str) -> None:
        carve(self.rune, "a2a-front", "a2a.refused", f"{who or 'anonymous'} refused: {reason}")
        self._json(code, {"error": "refused", "reason": reason})

    def do_GET(self) -> None:
        if self.path.startswith("/.well-known/agent-card.json"):
            try:
                with urlrequest.urlopen(self.upstream.rstrip("/") + "/.well-known/agent-card.json", timeout=10) as r:
                    body = r.read()
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except urlerror.URLError as exc:
                self._json(502, {"error": "upstream unreachable", "reason": str(exc)})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        length = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(length) if length else b"{}"

        auth = self.headers.get("authorization") or ""
        if not auth.startswith("Bearer "):
            self._refuse(401, "a token is required — Authorization: Bearer <jwt>", "")
            return
        token = auth[7:].strip()

        skill = None
        try:
            body = json.loads(raw or b"{}")
            params = body.get("params") or {}
            skill = params.get("skill") or (params.get("metadata") or {}).get("skill")
        except Exception:
            body = {}

        ok, reason, claims = verify(token, self.pub, self.aud, skill)
        who = (claims or {}).get("sub", "")
        if not ok:
            # a verified token naming a skill it does not hold is 403, not 401:
            # the caller is authenticated and the answer is "not granted".
            code = 403 if reason.startswith("this token names no such skill") else 401
            self._refuse(code, reason, who)
            return

        if _replay(str(claims.get("jti") or ""), int(claims.get("exp") or 0)):
            self._refuse(409, "this token has already been used (jti replay)", who)
            return
        if _over_rate(who):
            self._refuse(429, f"rate limit: more than {RATE_PER_MIN} calls in a minute", who)
            return

        try:
            req = urlrequest.Request(
                self.upstream.rstrip("/") + "/",
                data=raw,
                headers={"content-type": "application/json", "accept": "application/json"},
                method="POST",
            )
            with urlrequest.urlopen(req, timeout=60) as r:
                answer = r.read()
                code = r.status
        except urlerror.HTTPError as exc:
            answer, code = exc.read(), exc.code
        except urlerror.URLError as exc:
            carve(self.rune, "a2a-front", "a2a.upstream", f"{who} reached the ward; upstream failed: {exc}")
            self._json(502, {"error": "upstream unreachable", "reason": str(exc)})
            return

        carve(self.rune, "a2a-front", "a2a.allowed", f"{who} called {skill or 'the node'} — {code}")
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(answer)))
        self.end_headers()
        self.wfile.write(answer)


def serve(args: argparse.Namespace) -> int:
    host, _, port = args.listen.rpartition(":")
    Handler.upstream = args.upstream
    Handler.pub = args.pub
    Handler.aud = args.aud
    Handler.rune = args.rune
    srv = ThreadingHTTPServer((host or "127.0.0.1", int(port)), Handler)
    print(f"a2a-front: listening on {args.listen} → {args.upstream} (aud={args.aud})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="a2a-front.py", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("serve")
    s.add_argument("--upstream", required=True)
    s.add_argument("--pub", required=True)
    s.add_argument("--aud", default="heimdall")
    s.add_argument("--listen", default="127.0.0.1:8400")
    s.add_argument("--rune", default=None)
    s.set_defaults(func=serve)

    m = sub.add_parser("mint")
    m.add_argument("--key", required=True)
    m.add_argument("--peer", required=True)
    m.add_argument("--skill", required=True)
    m.add_argument("--aud", default="heimdall")
    m.add_argument("--iss", default="heimdall")
    m.add_argument("--minutes", default="60")
    m.set_defaults(func=mint)

    v = sub.add_parser("verify")
    v.add_argument("--token", required=True)
    v.add_argument("--pub", required=True)
    v.add_argument("--aud", default="heimdall")
    v.add_argument("--skill", default=None)
    def _verify(a):
        ok, reason, claims = verify(a.token, a.pub, a.aud, a.skill)
        print(json.dumps({"ok": ok, "reason": reason, "sub": claims.get("sub"), "skills": claims.get("skills")}))
        return 0 if ok else 1
    v.set_defaults(func=_verify)

    args = p.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
