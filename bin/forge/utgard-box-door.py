#!/usr/bin/env python3
"""utgard-box-door.py — the one road out of a box.

A box has no internet. It has ONE peer: this door. The door is a plain HTTP
proxy that answers only the names it was told, and it holds the model
credential so the box never does — the box is handed a placeholder key and the
door swaps in the real one on the way to the rail.

That is the whole design, and it is the reason a box can run an agent without
ever being trusted:

  * the box names `rail:8080`, a name with no meaning outside the door;
  * the door resolves that name to wherever the rail actually is;
  * the door injects `Authorization`, so no key exists inside the box;
  * anything not in the map is refused by name, with the rule quoted.

Configuration (all env, never a file, never a flag):
  UTGARD_DOOR_MAP   "rail=<host>:<port>,gate=<host>:<port>"  the allowlist
  UTGARD_DOOR_KEY   the bearer the door injects for the name `rail`
  UTGARD_DOOR_PORT  the port to listen on (default 3128)
  UTGARD_DOOR_LOG   "quiet" to keep stderr for refusals only

Exit: 0 stopped · 1 refused to start (bad config) · 2 usage.
"""

from __future__ import annotations

import asyncio
import os
import sys

USAGE = (
    "usage: utgard-box-door.py  (env: UTGARD_DOOR_MAP, UTGARD_DOOR_KEY, "
    "UTGARD_DOOR_PORT, UTGARD_DOOR_LOG)"
)

REFUSAL = (
    "HTTP/1.1 403 Forbidden\r\n"
    "Content-Type: text/plain; charset=utf-8\r\n"
    "Connection: close\r\n"
    "Content-Length: {n}\r\n"
    "\r\n"
    "{body}"
)


def log(message: str) -> None:
    sys.stderr.write("door: " + message + "\n")
    sys.stderr.flush()


def parse_map(spec: str) -> dict[str, tuple[str, int]]:
    """`rail=host:8080,gate=host:3889` -> {'rail': ('host', 8080), ...}.

    A malformed entry is a refusal, never a skipped line: an allowlist that
    silently loses an entry is a door that silently closes on working traffic.
    """
    allow: dict[str, tuple[str, int]] = {}
    for item in spec.split(","):
        item = item.strip()
        if not item:
            continue
        name, sep, target = item.partition("=")
        if not sep or not name.strip() or ":" not in target:
            raise ValueError(f"bad entry in UTGARD_DOOR_MAP: {item!r} (want name=host:port)")
        host, _, port = target.strip().rpartition(":")
        try:
            number = int(port)
        except ValueError:
            raise ValueError(f"bad port in UTGARD_DOOR_MAP entry: {item!r}") from None
        if not host.strip() or not (0 < number < 65536):
            raise ValueError(f"bad entry in UTGARD_DOOR_MAP: {item!r} (want name=host:port)")
        allow[name.strip().lower()] = (host.strip(), number)
    if not allow:
        raise ValueError("UTGARD_DOOR_MAP is empty: a door with no names answers nothing")
    return allow


def authority_of(name: str) -> str:
    """The name a client asked for, without a port or a trailing dot."""
    head = name.strip().lower()
    if head.startswith("["):  # [::1]:8080
        return head[1 : head.index("]")] if "]" in head else head
    return head.split(":", 1)[0].rstrip(".")


class Door:
    def __init__(self, allow: dict[str, tuple[str, int]], key: str, quiet: bool):
        self.allow = allow
        self.key = key
        self.quiet = quiet

    def refusal(self, why: str) -> bytes:
        body = (why + "\n") * 1
        return REFUSAL.format(n=len(body.encode()), body=body).encode()

    async def handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            head = await asyncio.wait_for(self._read_head(reader), timeout=30)
        except (asyncio.TimeoutError, asyncio.IncompleteReadError, ConnectionError):
            writer.close()
            return
        if not head:
            writer.close()
            return

        try:
            request_line, *header_lines = head.decode("latin-1").split("\r\n")
            method, target, version = request_line.split(" ", 2)
        except ValueError:
            writer.write(self.refusal("door: malformed request line"))
            await writer.drain()
            writer.close()
            return

        if method.upper() == "CONNECT":
            await self.tunnel(target, reader, writer)
            return
        await self.forward(method, target, version, header_lines, reader, writer)

    @staticmethod
    async def _read_head(reader: asyncio.StreamReader) -> bytes:
        buffer = b""
        while b"\r\n\r\n" not in buffer:
            chunk = await reader.read(4096)
            if not chunk:
                return buffer
            buffer += chunk
            if len(buffer) > 65536:
                raise ConnectionError("request head too large")
        return buffer

    async def tunnel(self, authority: str, reader, writer) -> None:
        name = authority_of(authority)
        route = self.allow.get(name)
        if route is None:
            log(f"refused CONNECT {authority} — not a name this door answers")
            writer.write(
                self.refusal(
                    f"door: no road to {name!r}. The box reaches only: "
                    + ", ".join(sorted(self.allow))
                    + "."
                )
            )
            await writer.drain()
            writer.close()
            return
        try:
            up_r, up_w = await asyncio.open_connection(*route)
        except OSError as exc:
            writer.write(self.refusal(f"door: the road to {name} is shut ({exc})."))
            await writer.drain()
            writer.close()
            return
        if not self.quiet:
            log(f"CONNECT {authority} -> {route[0]}:{route[1]}")
        writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        await writer.drain()
        await asyncio.gather(
            self._pump(reader, up_w),
            self._pump(up_r, writer),
            return_exceptions=True,
        )

    async def forward(self, method, target, version, header_lines, reader, writer) -> None:
        # Absolute-form: the client names a scheme and a NAME, never a place:
        #   GET <scheme>://<allowlisted-name>/v1/models HTTP/1.1
        if target.split(":", 1)[0].lower() not in ("http", "https") or "://" not in target:
            writer.write(
                self.refusal(
                    "door: this is a proxy. Ask for http://<name>/… and the name must be "
                    + ", ".join(sorted(self.allow))
                    + "."
                )
            )
            await writer.drain()
            writer.close()
            return
        scheme, _, rest = target.partition("://")
        authority, slash, path = rest.partition("/")
        name = authority_of(authority)
        route = self.allow.get(name)
        if route is None:
            log(f"refused {method} {target} — not a name this door answers")
            writer.write(
                self.refusal(
                    f"door: no road to {name!r}. The box reaches only: "
                    + ", ".join(sorted(self.allow))
                    + "."
                )
            )
            await writer.drain()
            writer.close()
            return

        path = "/" + path if slash else "/"
        forwarded: list[str] = [f"{method} {path} {version}"]
        saw_host = False
        for line in header_lines:
            if not line:
                continue
            lower = line.lower()
            if lower.startswith(("proxy-connection:", "connection:", "keep-alive:")):
                continue
            if lower.startswith("authorization:"):
                # The box holds a placeholder; the door is the one that decides.
                continue
            if lower.startswith("host:"):
                saw_host = True
            forwarded.append(line)
        if not saw_host:
            forwarded.append(f"Host: {authority}")
        if self.key and name in ("rail",):
            forwarded.append(f"Authorization: Bearer {self.key}")
        forwarded.append("Connection: close")

        try:
            up_r, up_w = await asyncio.open_connection(*route)
        except OSError as exc:
            writer.write(self.refusal(f"door: the road to {name} is shut ({exc})."))
            await writer.drain()
            writer.close()
            return
        if not self.quiet:
            log(f"{method} {name}{path} -> {route[0]}:{route[1]}")
        up_w.write(("\r\n".join(forwarded) + "\r\n\r\n").encode("latin-1"))
        await up_w.drain()
        await asyncio.gather(
            self._pump(reader, up_w),
            self._pump(up_r, writer),
            return_exceptions=True,
        )

    @staticmethod
    async def _pump(src: asyncio.StreamReader, dst: asyncio.StreamWriter) -> None:
        try:
            while True:
                chunk = await src.read(65536)
                if not chunk:
                    break
                dst.write(chunk)
                await dst.drain()
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            try:
                if dst.can_write_eof():
                    dst.write_eof()
            except (OSError, RuntimeError):
                pass


async def main() -> int:
    spec = os.environ.get("UTGARD_DOOR_MAP", "")
    key = os.environ.get("UTGARD_DOOR_KEY", "")
    quiet = os.environ.get("UTGARD_DOOR_LOG", "") == "quiet"
    try:
        port = int(os.environ.get("UTGARD_DOOR_PORT", "3128"))
    except ValueError:
        log("UTGARD_DOOR_PORT is not a number")
        return 1
    try:
        allow = parse_map(spec)
    except ValueError as exc:
        log(str(exc))
        return 1

    door = Door(allow, key, quiet)
    server = await asyncio.start_server(door.handle, "0.0.0.0", port)
    log(
        f"listening on :{port} · roads: "
        + ", ".join(f"{name}->{host}:{p}" for name, (host, p) in sorted(allow.items()))
        + ("" if key else " · no key to inject")
    )
    async with server:
        await server.serve_forever()
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(USAGE, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        sys.exit(0)
