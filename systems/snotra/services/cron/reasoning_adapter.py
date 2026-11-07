#!/usr/bin/env python3
"""reasoning_adapter — LLM reasoning adapter for Snotra.

WHY: Snotra needs an AI model for logic, not just transcription and summarization.
The reasoning model handles extraction (transcript → decisions/actions/questions),
suggested steps generation, duplicate detection, card classification, and identity
matching. Just like Pi uses an LLM for reasoning, Snotra uses an LLM for the parts
that are currently deterministic but would benefit from intelligence.

WHAT IT DOES: implements a reasoning adapter that uses an LLM provider (OpenAI,
Anthropic, Google, or local) for logic tasks. The deterministic baseline always
runs first; the LLM pass improves quality but is never the authority.

THE TASKS:
  extract     — transcript → decisions/actions/questions (LLM pass, improves recall)
  steps       — action → ordered, actionable steps
  dedup       — new card → check against existing (semantic duplicate detection)
  classify    — card content → workstream board/list
  identity    — speaker name → user ID (from context)
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))


class ReasoningAdapter:
    """LLM reasoning adapter for Snotra logic tasks."""

    def __init__(self, provider: str, model: str, api_key: str | None = None,
                 base_url: str | None = None):
        self.provider = provider.strip().lower()
        self.model = model
        self.api_key = api_key
        self.base_url = base_url or self._default_base_url()
        self._token = api_key

    def _default_base_url(self) -> str:
        if self.provider == "openai":
            return "https://api.openai.com/v1"
        if self.provider == "anthropic":
            return "https://api.anthropic.com/v1"
        if self.provider == "google":
            return "https://generativelanguage.googleapis.com/v1beta"
        if self.provider in ("local", "llama_local"):
            return os.environ.get("LLAMA_SWAP_URL", "http://127.0.0.1:8080/v1")
        return "https://api.openai.com/v1"

    def _call_llm(self, system_prompt: str, user_prompt: str, max_tokens: int = 500) -> str:
        """Call the LLM provider and return the response text."""
        import urllib.request
        if self.provider == "anthropic":
            url = f"{self.base_url}/messages"
            body = json.dumps({
                "model": self.model,
                "max_tokens": max_tokens,
                "system": system_prompt,
                "messages": [{"role": "user", "content": user_prompt}],
            }).encode()
            headers = {
                "x-api-key": self._token or "",
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            }
        elif self.provider == "google":
            url = f"{self.base_url}/models/{self.model}:generateContent?key={self._token}"
            body = json.dumps({
                "contents": [{"parts": [{"text": user_prompt}]}],
                "systemInstruction": {"parts": [{"text": system_prompt}]},
                "generationConfig": {"maxOutputTokens": max_tokens, "temperature": 0},
            }).encode()
            headers = {"Content-Type": "application/json"}
        else:
            # OpenAI-compatible (OpenAI, local llama.cpp)
            url = f"{self.base_url}/chat/completions"
            body = json.dumps({
                "model": self.model,
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt},
                ],
                "temperature": 0,
                "max_tokens": max_tokens,
            }).encode()
            headers = {
                "Authorization": f"Bearer {self._token or ''}",
                "Content-Type": "application/json",
            }

        req = urllib.request.Request(url, data=body, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.loads(r.read().decode())
        except Exception as e:
            print(f"  note: LLM call failed — {e}", file=sys.stderr)
            return ""

        if self.provider == "anthropic":
            return data.get("content", [{}])[0].get("text", "")
        if self.provider == "google":
            return data.get("candidates", [{}])[0].get("content", {}).get("parts", [{}])[0].get("text", "")
        return data.get("choices", [{}])[0].get("message", {}).get("content", "")

    def test_connection(self) -> bool:
        """Test if the provider is reachable and the API key is valid."""
        result = self._call_llm("You are a test assistant.", "Say 'ok'.", max_tokens=5)
        return bool(result)

    def extract(self, transcript: str) -> str:
        """Extract decisions, actions, and open questions from transcript."""
        system_prompt = (
            "You are a meeting transcript analyzer. Extract decisions, action items, "
            "and open questions from the transcript.\n\n"
            "RULES:\n"
            "- A discussion is NOT a decision. Only extract items where someone "
            "explicitly agreed, committed, or asked.\n"
            "- The transcript may have errors. Use context to infer meaning.\n"
            "- If two people speak simultaneously, attribute to the one who was "
            "interrupted.\n"
            "- If you cannot determine an owner, set owner to null.\n"
            "- If you cannot determine a due date, set due_date to null.\n\n"
            "OUTPUT FORMAT (JSON array, no markdown, no code fences):\n"
            '[{"type": "decision|action|question", "statement": "...", '
            '"owner": "name or null", "due_date": "YYYY-MM-DD or null", '
            '"evidence_quote": "verbatim quote", "timestamp": "HH:MM:SS or null"}]\n\n'
            "EXAMPLE:\n"
            'Transcript: "We decided to use Trello. Reygan will circulate the '
            'agreement by Friday. Open question: who holds admin?"\n'
            'Output: [{"type":"decision","statement":"Use Trello for the board",'
            '"owner":null,"due_date":null,"evidence_quote":"We decided to use Trello",'
            '"timestamp":null},{"type":"action","statement":"Circulate the developer '
            'agreement","owner":"Reygan","due_date":null,'
            '"evidence_quote":"Reygan will circulate the agreement by Friday",'
            '"timestamp":null},{"type":"question","statement":"Who holds admin on '
            'the board panel?","owner":null,"due_date":null,'
            '"evidence_quote":"Open question: who holds admin?","timestamp":null}]'
        )
        result = self._call_llm(system_prompt, f"Transcript:\n{transcript[:15000]}", max_tokens=1200)
        # Validate output
        return self._validate_json(result) or result

    def _validate_json(self, text: str) -> str | None:
        """Validate and clean LLM JSON output. Returns cleaned JSON or None if invalid."""
        import re
        # Try to extract JSON from markdown code blocks
        m = re.search(r'```(?:json)?\s*\n(.*?)\n```', text, re.DOTALL)
        if m:
            text = m.group(1).strip()
        # Try to find a JSON array
        m = re.search(r'\[.*\]', text, re.DOTALL)
        if m:
            text = m.group(0)
        try:
            data = json.loads(text)
            if not isinstance(data, list):
                return None
            # Validate each item
            cleaned = []
            for item in data:
                if not isinstance(item, dict):
                    continue
                if "type" not in item or "statement" not in item:
                    continue
                if item["type"] not in ("decision", "action", "question"):
                    continue
                cleaned.append({
                    "type": item["type"],
                    "statement": str(item.get("statement", "")),
                    "owner": item.get("owner") if item.get("owner") else None,
                    "due_date": item.get("due_date") if item.get("due_date") else None,
                    "evidence_quote": item.get("evidence_quote") if item.get("evidence_quote") else None,
                    "timestamp": item.get("timestamp") if item.get("timestamp") else None,
                })
            return json.dumps(cleaned) if cleaned else None
        except (json.JSONDecodeError, Exception):
            return None

    def steps(self, action_text: str) -> str:
        """Generate suggested steps for an action."""
        system_prompt = (
            "You are a task breakdown assistant. Given an action item, generate "
            "3-5 concrete, ordered, actionable steps.\n\n"
            "RULES:\n"
            "- Each step should take 5-30 minutes. If a step takes longer, break "
            "it down further.\n"
            "- If the action is already a single step, output just that step.\n"
            "- Output as a numbered list, one step per line.\n"
            "- Do not include explanations or context — just the steps.\n\n"
            "EXAMPLE:\n"
            "Action: Circulate the developer agreement to all three developers.\n"
            "1. Locate the final version of the developer agreement.\n"
            "2. Draft an email to all three developers with the agreement attached.\n"
            "3. Review the email for accuracy and correct recipient addresses.\n"
            "4. Send the email before end of day Friday.\n"
            "5. Track responses and follow up with non-responders."
        )
        return self._call_llm(system_prompt, f"Action item: {action_text}", max_tokens=300)

    def dedup(self, new_card: str, existing_cards: str) -> str:
        """Detect if a new card is a semantic duplicate of existing cards."""
        system_prompt = (
            "You are a duplicate detector. Given a new card and a list of existing "
            "cards, determine if the new card is a semantic duplicate.\n\n"
            "A DUPLICATE is: same deliverable, same owner, same scope.\n"
            "NOT a duplicate: same topic but different deliverable, or same "
            "deliverable but different owner/scope.\n\n"
            "Output: 'duplicate: <existing card id> (confidence: high/medium/low)' "
            "or 'unique'.\n\n"
            "EXAMPLE:\n"
            "New card: Send NDA to client\n"
            "Existing: ACT-001: Email the NDA to the customer\n"
            "Output: duplicate: ACT-001 (confidence: high)\n\n"
            "New card: Review the contract\n"
            "Existing: ACT-001: Email the NDA to the customer\n"
            "Output: unique"
        )
        return self._call_llm(system_prompt, f"New card: {new_card}\nExisting cards:\n{existing_cards}", max_tokens=100)

    def classify(self, card_text: str, categories: list[str] | None = None) -> str:
        """Classify a card into a workstream board/list."""
        cats = categories or ["patent", "vertical", "docs", "control-tower", "meetings"]
        system_prompt = (
            "You are a workstream classifier. Given a card's text, classify it into "
            "one of: " + ", ".join(cats) + ".\n\n"
            "RULES:\n"
            "- Output only the classification, nothing else.\n"
            "- If none match, output 'unclassified'.\n"
            "- If multiple match, output the primary one.\n\n"
            "EXAMPLES:\n"
            "'We need to file the provisional patent this week' → patent\n"
            "'Let's score the verticals for the pilot' → vertical\n"
            "'Read the agreement and send questions in writing' → docs"
        )
        return self._call_llm(system_prompt, f"Card text: {card_text}", max_tokens=50)

    def identity(self, speaker: str, context: str) -> str:
        """Resolve a speaker name to their full name from context."""
        system_prompt = (
            "You are an identity resolver. Given a speaker name from a transcript "
            "and context about the meeting participants, resolve the speaker to their "
            "full name.\n\n"
            "RULES:\n"
            "- Output only the full name, nothing else.\n"
            "- If you can't resolve, output the original name unchanged.\n"
            "- If ambiguous (two people with the same first name), output "
            "'ambiguous: <name1>, <name2>'.\n"
            "- Handle nicknames and abbreviations from context.\n\n"
            "EXAMPLE:\n"
            "Speaker: Reygan\nContext: Reygan Assareh (chair), <the operator> <the operator> (operator)\n"
            "Output: Reygan Assareh"
        )
        return self._call_llm(system_prompt, f"Speaker: {speaker}\nContext: {context}", max_tokens=50)


def get_reasoning_adapter(config: dict | None = None) -> ReasoningAdapter | None:
    """Factory: create a reasoning adapter from config. Returns None if not configured."""
    config = config or {}
    reasoning = config.get("reasoning", {})
    if not reasoning.get("enabled", False):
        return None
    provider = reasoning.get("provider", "openai")
    model = reasoning.get("model", "gpt-4o-mini")
    api_key = reasoning.get("api_key")
    base_url = reasoning.get("base_url")
    # Try env vars
    if not api_key:
        env_key = f"{provider.upper()}_API_KEY"
        api_key = os.environ.get(env_key)
    if not api_key and provider in ("openai", "local", "llama_local"):
        api_key = os.environ.get("LLAMA_SWAP_API_KEY")
    # Try reading from Pi auth.json (Ymir's credential store)
    if not api_key:
        try:
            auth_path = os.path.expanduser("~/.pi/agent/auth.json")
            if os.path.isfile(auth_path):
                d = json.load(open(auth_path))
                v = d.get("llama-swap", {})
                api_key = v.get("key") or v.get("tokens", {}).get("access_token")
        except Exception:
            pass
    if not api_key:
        return None
    return ReasoningAdapter(provider, model, api_key, base_url)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Snotra reasoning adapter")
    parser.add_argument("task", choices=["extract", "steps", "dedup", "classify", "identity", "test"])
    parser.add_argument("input", nargs="?", default="")
    parser.add_argument("--context", default="")
    parser.add_argument("--provider", default="openai")
    parser.add_argument("--model", default="gpt-4o-mini")
    parser.add_argument("--api-key", default=None)
    args = parser.parse_args()

    adapter = ReasoningAdapter(args.provider, args.model, args.api_key)
    if args.task == "test":
        print("ok" if adapter.test_connection() else "fail")
    elif args.task == "extract":
        # Read transcript from file if it's a path, otherwise use as text
        transcript = args.input
        try:
            if os.path.isfile(transcript):
                transcript = open(transcript, encoding="utf-8").read()
        except Exception:
            pass
        print(adapter.extract(transcript))
    elif args.task == "steps":
        print(adapter.steps(args.input))
    elif args.task == "dedup":
        print(adapter.dedup(args.input, args.context))
    elif args.task == "classify":
        print(adapter.classify(args.input))
    elif args.task == "identity":
        print(adapter.identity(args.input, args.context))

**2026-11-03 (correction, appended):** the operator's name was redacted — it is personal data and belongs in the home, not in a public repository (RULES/04, RULES/06).
