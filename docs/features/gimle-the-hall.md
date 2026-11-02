# Gimlé — the hall, the desk and the MCP

**What it is.** Gimlé is the team's own workspace on Zerwiz's hardware: one door (`gimle.zerwiz.org`), and
behind it the desk — what is due, what was decided, what waits on you — then the places: Plane for projects
and tasks, AFFiNE for documents and databases, Excalidraw for drawing. Snotra's meeting record feeds the desk;
the same record answers the MCP.

**What you need.** A gate account (invitation only), and for the MCP a token minted by the house.

## The addresses

| what | where |
|---|---|
| the door (hall) | https://gimle.zerwiz.org |
| the portal (Authelia) | https://auth.zerwiz.org |
| the board (Plane) | https://board.zerwiz.org |
| documents (AFFiNE) | https://affine.zerwiz.org |
| whiteboard (Excalidraw) | https://whiteboard.zerwiz.org |
| book a time (Cal.com) | https://book.zerwiz.org |

## Booking a time

`book.zerwiz.org` is **Cal.com**, one calendar per member, behind the same suite. A counterpart picks a
free slot from the member's own booking page; the meeting then lands in the calendar, and Snotra's ear
writes its record into the desk. That is the loop: **a booking becomes a meeting, and a meeting becomes a
record** — nobody types the minutes twice.

The desk carries it as the **Book** tile, beside Board and Documents.

**The booking page itself is public on purpose.** A person who has no account in the hall must still be
able to choose a time — that is what a booking link is for. The administrative side (sign-in, event types,
settings) is the part that belongs behind the gate; do not put the whole hostname behind Authelia or the
only people who can book are the ones who already have an account.

## The mirrored documents

The hourly mirror copies a project's status documents onto the heart; the desk serves them at
`/desk/docs/<project>/<file>`, behind the same membership rule as the record — a person who may not see a
place may not read its mirrored documents either. Only flat `.md`, `.html` and `.txt` names are served, and
nothing outside the project's own directory.

## The desk

`bin/gimle/desk.py` renders the page behind the door: **due this week**, **last decisions**, **questions
waiting on me**, then the tiles. It reads a JSON the projector writes and trusts `Remote-User` from Authelia
(Caddy passes it). It never writes.

```bash
bin/gimle/desk.py --port 8487 --data /srv/gimle-desk/meetings.json
```

## The MCP (read-only phase)

`bin/gimle/mcp-read.py` is one MCP server for the suite, JSON-RPC over `POST /mcp`:

```
who_am_i · list_places · my_tasks · place_board · meeting_record · who_owes_what · find_doc · read_scene
```

Auth is `Authorization: Bearer <token>` (one token per line in `mcp-tokens`, as `<token> <subject>`). Every
call is appended to `access.jsonl` as `at · subject · tool · verdict · why`; a call without a valid token is
refused **and recorded**. Tools whose backend is not yet wired (`find_doc`, `read_scene`) answer an honest
`isError` with the reason instead of pretending.

**Limits, said plainly:** this phase is read-only; Plane's backend is the meeting record until a Plane API
token is issued; AFFiNE is not yet reachable from MCP. Excalidraw scenes are reachable **only when their owner
has consented to share** one: `read_scene` reads from the house's shared-scenes store, and a scene that has
not been shared answers an honest `isError` ("scene not shared with the house — consent required"). The
consent flow (a "Share this scene with the house" button in the panel) is the next piece; until it ships,
a shared scene is a file dropped under `<data>/shared-scenes/<subject>/<scene>.json`.

**If it does not work.** `systemctl --user status gimle-desk gimle-mcp`; `curl -H "Remote-User: you"
http://127.0.0.1:8487/` for the desk; `curl -X POST http://127.0.0.1:8489/mcp -H 'Authorization: Bearer …'
-d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'` for the MCP. 401 means the token is not in the file; a
recorded refusal means it is.
