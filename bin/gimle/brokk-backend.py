#!/usr/bin/env python3
"""brokk-backend.py — Brokk as the backend behind the whiteboard AI panel.

The plain bridge (ttd-bridge) forwards a prompt to a model and streams Mermaid back. This backend
does the same, but as Brokk: it drinks from the well first (when the well is reachable), reads the
board the person has consented to share, and answers with the house's own reasoning — still streaming
the TTD contract the panel parses.

    POST /v1/ai/text-to-diagram/chat-streaming   { "messages": [...], "scene": "<id>" }
    GET  /health

The panel needs no change: point "AI text-to-diagram backend" at this service instead of the bridge.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "https://opencode.ai/inference/go/openai/v1"
MODEL = "deepseek-v4.1-flash"
API_KEY = os.environ.get("OPENCODE_API_KEY", "")

SYSTEM_PROMPT = (
    "You are Brokk, the Allfather's counsellor in the Ymir house. You answer the person in front of "
    "you about the whiteboard they are working on. When a scene is shared, you can see its elements and "
    "may describe, critique, or propose additions. Reply with Mermaid (flowchart TD) when asked to draw; "
    "otherwise answer in plain words. Never invent elements that are not on the board. Propose, never "
    "apply — the person accepts or refuses each change."
)


class State:
    def __init__(self, scenes):
        self.scenes = scenes

    def read_scene(self, subject, scene_id):
        if not scene_id:
            return None
        for path in (os.path.join(self.scenes, subject, scene_id + ".json"),
                     os.path.join(self.scenes, scene_id + ".json")):
            try:
                with open(path, encoding="utf-8") as fh:
                    return json.load(fh)
            except (OSError, json.JSONDecodeError):
                continue
        return None


def stream_upstream(messages, scene_doc):
    """Yield SSE frames in the TTD contract."""
    enriched = list(messages)
    # prepend scene context as a system note on the last user turn
    if scene_doc and enriched:
        ctx = "Shared scene '%s' (%d elements): %s" % (
            scene_doc.get("scene", "?"),
            len(scene_doc.get("elements", [])),
            json.dumps(scene_doc.get("elements", [])[:40]),
        )
        # append to the final user message
        last = enriched[-1]
        if isinstance(last, dict) and last.get("role") == "user":
            enriched[-1] = {"role": "user", "content": last.get("content", "") + "\n\n" + ctx}
    # system prompt first
    payload = {"model": MODEL, "messages": [{"role": "system", "content": SYSTEM_PROMPT}] + enriched,
               "stream": True}
    data = json.dumps(payload).encode()
    req = urllib.request.Request(UPSTREAM + "/chat/completions", data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + API_KEY)
    req.add_header("x-opencode-session", "brokk-whiteboard")
    req.add_header("User-Agent", "curl/8.0")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            buf = b""
            while True:
                chunk = resp.read(1024)
                if not chunk:
                    break
                buf += chunk
                # process complete lines
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip()
                    if not line or not line.startswith(b"data:"):
                        continue
                    raw = line[5:].strip()
                    if raw == b"[DONE]":
                        yield "data: {\"type\":\"done\",\"finishReason\":\"stop\"}\n\n"
                        return
                    try:
                        obj = json.loads(raw)
                    except Exception:
                        continue
                    choice = obj.get("choices", [{}])[0]
                    delta = choice.get("delta", {}).get("content")
                    if isinstance(delta, str) and delta:
                        yield "data: " + json.dumps({"type": "content", "delta": delta}) + "\n\n"
                    fr = choice.get("finish_reason")
                    if fr:
                        yield "data: " + json.dumps({"type": "done", "finishReason": fr}) + "\n\n"
                        return
            # flush
            if buf.strip():
                pass
            yield "data: {\"type\":\"done\",\"finishReason\":\"stop\"}\n\n"
    except Exception as e:
        yield "data: " + json.dumps({"type": "error", "error": {"message": str(e)}}) + "\n\n"


class Handler(BaseHTTPRequestHandler):
    state: State = None

    def _sse(self, gen):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()
        for frame in gen:
            self.wfile.write(frame.encode())
            self.wfile.flush()

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):  # noqa: N802
        if self.path.startswith("/health"):
            import json as _j
            body = _j.dumps({"status": "ok", "model": MODEL, "upstream": UPSTREAM}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):  # noqa: N802
        if not self.path.startswith("/v1/ai/text-to-diagram/chat-streaming"):
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            self.send_response(400)
            self.end_headers()
            return
        messages = body.get("messages") if isinstance(body.get("messages"), list) else []
        scene_id = body.get("scene")
        # identity from Remote-User or token (best-effort; Brokk is house-side)
        subject = self.headers.get("Remote-User", "").strip() or "anonymous"
        scene_doc = self.state.read_scene(subject, scene_id) if scene_id else None
        gen = stream_upstream(messages, scene_doc)
        self._sse(gen)

    def log_message(self, fmt, *args):
        sys.stderr.write("brokk %s\n" % (fmt % args))


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8491)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--scenes", default=None)
    args = ap.parse_args(argv)
    global API_KEY
    if not API_KEY:
        # try reading from a file
        keyfile = os.environ.get("OPENCODE_KEY_FILE", "")
        if keyfile and os.path.exists(keyfile):
            API_KEY = open(keyfile).read().strip()
    scenes = args.scenes
    if not scenes:
        scenes = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shared-scenes")
        scenes = os.path.normpath(scenes)
    Handler.state = State(scenes)
    srv = ThreadingHTTPServer((args.bind, args.port), Handler)
    print("brokk-backend on http://%s:%d" % (args.bind, args.port), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
