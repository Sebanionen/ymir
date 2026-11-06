"""OpenCode coding-agent interface — the smidja can run through opencode CLI.

Mirrors agent_pi.run(): spawns `opencode run --format json` (NDJSON event
stream) and consumes it line by line. Tool records are normalized to the shape
agents.py's ToolCallTracker expects, so the visualizer paints real tool calls.

Session continuation is the same mechanism as pi, with one twist: opencode
rejects unknown session ids, so a fresh run created with a smidja id
(`smidja-...`) is launched WITHOUT `--session`; the real `ses_...` id from the
event stream is returned, and the caller stores it for the next call.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Callable, Optional

from .data_types import PiRequest, PiResult
from .utils import now_iso, operator_env

OPENCODE_PATH = os.environ.get("OPENCODE_PATH", "opencode")

RESULT_SNIPPET_CHARS = 20_000
ARG_VALUE_CHARS = 20_000
LABEL_CHARS = 80

PRIMARY_ARGS = ("command", "path", "file_path", "pattern", "query", "url")


def _clip(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _label(tool: str, args: dict) -> str:
    value = next((args[key] for key in PRIMARY_ARGS
                  if isinstance(args.get(key), str) and args[key].strip()), "")
    if not value:
        value = next((v for v in args.values() if isinstance(v, str) and v.strip()), "")
    value = " ".join(str(value).split())
    return f"{tool}: {_clip(value, LABEL_CHARS)}" if value else tool


def run(request: PiRequest, on_event: Optional[Callable[[dict], None]] = None,
        on_spawn: Optional[Callable[[int], None]] = None,
        on_exit: Optional[Callable[[int], None]] = None) -> PiResult:
    """Run one non-interactive opencode turn against the NDJSON event stream.

    The system prompt rides inside the message (opencode CLI has no
    --system-prompt); the agent treats it as standing instructions.
    """
    message = f"{request.system_prompt}\n\n{request.prompt}"
    cmd = [OPENCODE_PATH, "run", "--format", "json",
           "--model", request.model, "--auto"]
    if request.session_id.startswith("ses_"):
        cmd += ["--session", request.session_id]   # continue the real opencode session
    cmd.append(message)

    raw_path = Path(request.raw_output_path)
    raw_path.parent.mkdir(parents=True, exist_ok=True)

    process = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, bufsize=1, cwd=request.cwd,
                               env=operator_env())
    if on_spawn:
        on_spawn(process.pid)

    result = PiResult(session_id=request.session_id)
    text = ""
    tokens = 0
    cost = 0.0
    context_tokens = 0
    with raw_path.open("a") as raw:
        assert process.stdout is not None
        for line in process.stdout:
            raw.write(line)
            raw.flush()
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("sessionID"):
                result.session_id = event["sessionID"]
            part = event.get("part") or {}
            ptype = part.get("type", "")
            if ptype == "text":
                chunk = part.get("text", "")
                if chunk:
                    text += chunk
            elif ptype == "reasoning":
                # Nemotron & friends stream their chain-of-thought as reasoning
                # parts. It never goes into result.text (that is fed to the JSON
                # parser), but it is forwarded as a thinking event and left in
                # raw_output.jsonl verbatim so the visualizer can show it.
                chunk = part.get("text", "") or ""
                if chunk and on_event:
                    on_event({"type": "thinking", "text": chunk,
                              "surface": "opencode"})
            elif ptype == "message":
                # Some opencode versions carry reasoning inside message parts as
                # content items ({type: "reasoning", text}) rather than a bare
                # reasoning part — normalize both to a thinking event.
                for c in part.get("content") or []:
                    if (isinstance(c, dict) and c.get("type") == "reasoning"
                            and c.get("text") and on_event):
                        on_event({"type": "thinking", "text": str(c["text"]),
                                  "surface": "opencode"})
            elif ptype == "tool":
                state = part.get("state") or {}
                status = state.get("status", "completed")
                args = state.get("input") or {}
                meta = state.get("metadata") or {}
                exit_code = meta.get("exit")
                is_error = status != "completed" or (
                    exit_code is not None and str(exit_code) != "0")
                output = state.get("output") or state.get("error") or ""
                tool = part.get("tool") or "tool"
                if tool == "task" and on_event:
                    # opencode's NATIVE subagent dispatch (the `task` tool).
                    # Folded into a dedicated subagent_dispatch event so the
                    # trace UI shows real dispatch and gates can verify it —
                    # it is NOT a plain tool call. The raw `tool_use` line is
                    # still written verbatim to raw_output.jsonl (the gate's
                    # authoritative evidence). The child's final report rides
                    # in state.output — passed through so the subagent lane
                    # shows what the child ACTUALLY produced (P1), not a shell.
                    on_event({
                        "type": "subagent_dispatch",
                        "subagent_type": args.get("subagent_type")
                                         or args.get("agent") or "general",
                        "description": args.get("description") or "",
                        "prompt": args.get("prompt") or "",
                        "status": status,
                        "output": output,
                        "is_error": bool(is_error),
                    })
                elif on_event:
                    on_event({
                        "type": "tool_execution_end",
                        "toolName": tool,
                        "toolCallId": part.get("callID")
                                     or str(part.get("id") or ""),
                        "args": args,
                        "isError": bool(is_error),
                        "result": {"content": [{"type": "text", "text": output}]},
                    })
            elif ptype == "step-finish":
                usage_tokens = part.get("tokens") or {}
                total = usage_tokens.get("total") or 0
                if total:
                    tokens += int(total)
                    context_tokens = int(total)
                    cache = usage_tokens.get("cache") or {}
                    # The LAST step's raw usage + stop reason, so the phase can
                    # record input/cache_read/output and whether the turn was cut
                    # off — the accumulated `usage` cannot answer either.
                    result.last_usage = {
                        "input": usage_tokens.get("input") or 0,
                        "output": usage_tokens.get("output") or 0,
                        "reasoning": usage_tokens.get("reasoning") or 0,
                        "cacheRead": cache.get("read") or 0,
                        "cacheWrite": cache.get("write") or 0,
                    }
                    result.last_finish = str(part.get("reason") or "")
                    result.usage.add_turn({
                        "input": usage_tokens.get("input") or 0,
                        "output": usage_tokens.get("output") or 0,
                        "reasoning": usage_tokens.get("reasoning") or 0,
                        "cacheRead": cache.get("read") or 0,
                        "cacheWrite": cache.get("write") or 0,
                        "cost": {"total": part.get("cost") or 0.0},
                    }, int(total))
                    # P2 additive: forward a LIVE usage event so the runner can
                    # trace + add_usage mid-run (the session row's
                    # total_tokens/total_cost grow while running, instead of
                    # staying 0 until the phase ends). The internal
                    # accumulation above is untouched.
                    if on_event:
                        on_event({
                            "type": "usage",
                            "tokens": int(total),
                            "cost": float(part.get("cost") or 0.0),
                            "surface": "opencode",
                        })
                cost += float(part.get("cost") or 0.0)

    stderr = process.stderr.read() if process.stderr else ""
    result.returncode = process.wait()
    if on_exit:
        on_exit(process.pid)
    result.text = text.strip()
    result.tokens = tokens
    result.cost = cost
    result.context_tokens = context_tokens
    if result.returncode != 0 and not result.text:
        raise RuntimeError(
            f"opencode exited {result.returncode}: {stderr.strip()[-800:]}")
    return result