#!/usr/bin/env python3
"""gna_notify.py — tell the arm about mail that arrived, once, as it arrives.

  gna_notify.py --pending            # what the arm would be told, and nothing else
  gna_notify.py --nudge              # say it to the seat's arm (state/.wake-queue)
  gna_notify.py --nudge --limit 3    # one line per message, up to N; then one summary line

WHY. A desk that only speaks at 07:00 answers "what arrived yesterday"; the Allfather asked for
*"as they come"*. The arm (bin/pi/syn-watch.sh) already watches state/.wake-queue and raises a
wake into the session, so this is not a new road — it is the desk finally using it.

THREE LAWS THIS HOLDS:

  1 · ONCE. A notified message is marked `notified_at` by appending a NEW version to the spine
      (the store is append-only; nothing is edited). Re-running says nothing twice.
  2 · BATCHED. The arm has a flood brake, so the default is ONE line for the whole run, naming
      the count and the first messages — never one wake per message.
  3 · INBOUND ONLY. The house's own outgoing letters are context, not news.

An arrival that cannot be spoken is a FAILURE and says so; it is never rendered as "nothing new".
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gna_store  # noqa: E402

TREE = Path(os.environ.get("YMIR_TREE", Path.home() / "ymir"))


def latest_versions():
    """The newest record per (account, id) — the spine is append-only, so newest wins."""
    latest = {}
    if not gna_store.SPINE.exists():
        return latest
    for line in gna_store.SPINE.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = gna_store._json_loads(line)
        key = (row.get("account", ""), str(row.get("id")))
        latest[key] = row
    return latest


def pending():
    notified = already_notified()
    out = []
    for (_, _), row in latest_versions().items():
        if row.get("direction") not in ("in", "inbound"):
            continue
        if (row.get("account", ""), str(row.get("id"))) in notified:
            continue
        if str(row.get("auto_submitted") or "").strip() or str(row.get("precedence") or "").strip() in ("bulk", "junk", "list"):
            continue
        out.append(row)
    out.sort(key=lambda r: str(r.get("received_at") or r.get("ingested_at") or ""))
    return out


def line_for(rows):
    n = len(rows)
    if n == 1:
        r = rows[0]
        who = (r.get("from") or {}).get("name") or (r.get("from") or {}).get("email") or "somebody"
        return f"mail: 1 new — {r.get('classification','')} · {who} · {str(r.get('subject'))[:70]} (id {str(r.get('id'))[:12]})"
    first = []
    for r in rows[:3]:
        who = (r.get("from") or {}).get("name") or (r.get("from") or {}).get("email") or "somebody"
        first.append(f"{r.get('classification','')} from {who}: {str(r.get('subject'))[:58]}")
    more = "" if n <= 3 else f"; and {n-3} more"
    return f"mail: {n} new — " + " | ".join(first) + more


def ledger() -> Path:
    return gna_store.MAIL_DIR / "notified.jsonl"


def already_notified() -> set:
    """Which (account, id) the arm has been told about.

    NOT a spine version: `gna_store._sha` hashes CONTENT only (subject, from, body, class …), so a
    record carrying `notified_at` hashes identically and the append is skipped as unchanged —
    measured 2026-11-05, "marked 0 version(s)". The notification ledger is its own append-only file,
    which keeps the spine meaning "one line per content state" and makes "was he told?" a separate,
    honest question."""
    seen = set()
    p = ledger()
    if not p.exists():
        return seen
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        seen.add((row.get("account", ""), str(row.get("id"))))
    return seen


def mark_notified(rows):
    stamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
    p = ledger()
    p.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with p.open("a", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps({
                "account": r.get("account", ""), "id": str(r.get("id")),
                "notified_at": stamp, "notified_by": "gna_notify",
                "classification": r.get("classification", ""),
                "subject": str(r.get("subject", ""))[:120],
            }, ensure_ascii=False) + "\n")
            written += 1
    return {"written": written, "skipped": 0}


def seat_and_home():
    # The seat a wire nudge names is the MACHINE's seat id (`host=` in .ymir-seat), never the
    # agent's name: `sindri` is the primary, `nidavellir` is the seat, and seat-wire refuses the
    # former with "it carries no machine{host,ssh_user}" (measured 2026-11-05).
    seat = os.environ.get("YMIR_SEAT") or ""
    if not seat:
        try:
            for line in (Path.home() / ".pi/agent/extensions/.ymir-seat").read_text().splitlines():
                if line.startswith("host="):
                    seat = line.split("=", 1)[1].strip()
        except OSError:
            pass
    return seat or os.uname().nodename


def local_queue() -> Path:
    """The arm's own queue: <home>/state/.wake-queue, the file syn-watch reads.

    It is NOT reached through `seat-wire.sh nudge`: that door is for a PEER, and it refuses its
    own seat by design ("a seat that answers itself is a loop"). The local queue is written here,
    under the same lock the extensions use, in the same one-line shape every other raiser uses.
    """
    home = os.environ.get("YMIR_HOME") or ""
    if not home:
        try:
            home = (Path.home() / ".config/ymir/home").read_text().strip()
        except OSError:
            home = str(Path.home() / "Documents/ymirhome")
    return Path(home) / "state" / ".wake-queue"


def nudge(text):
    q = local_queue()
    try:
        q.parent.mkdir(parents=True, exist_ok=True)
        lock = q.with_suffix(q.suffix + ".lock")
        with open(lock, "w") as lf:
            import fcntl
            fcntl.flock(lf, fcntl.LOCK_EX)
            with open(q, "a", encoding="utf-8") as fh:
                fh.write(text.rstrip("\n") + "\n")
        return True, f"queued in {q}"
    except OSError as exc:
        return False, f"cannot write {q}: {exc}"


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--pending", action="store_true", help="print what would be said")
    ap.add_argument("--nudge", action="store_true", help="say it to the seat's arm")
    ap.add_argument("--limit", type=int, default=0, help="speak one line per message, up to N")
    args = ap.parse_args()

    rows = pending()
    if not rows:
        print("gna_notify: nothing new to tell the arm")
        return 0

    lines = []
    if args.limit and args.limit > 0:
        for r in rows[: args.limit]:
            lines.append(line_for([r]))
        if len(rows) > args.limit:
            lines.append(line_for(rows[args.limit:]))
    else:
        lines.append(line_for(rows))

    for l in lines:
        print(("nudge> " if args.nudge else "would say> ") + l)

    if not args.nudge:
        return 0

    ok = True
    for l in lines:
        said, detail = nudge(l)
        if not said:
            ok = False
            print(f"gna_notify: FAIL the arm refused the line: {detail}", file=sys.stderr)
    if ok:
        result = mark_notified(rows)
        print(f"gna_notify: marked {result.get('written', 0)} version(s) notified")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
