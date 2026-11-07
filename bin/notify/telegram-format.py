#!/usr/bin/env python3
"""telegram-format — make a reply readable on a phone before it is sent.

Why: rich text is right, but a wall of prose is not. The bridge renders one long
paragraph as one long paragraph, and the Allfather reads it on a phone. This door
turns a reply into the shape he asked for — one idea per line, short sentences —
without touching code blocks, lists, headings, links or buttons.

    telegram-format.py            # stdin -> stdout, formatted
    telegram-format.py --check    # exit 1 if a line is over the limit (a ward)
    telegram-format.py --max 90   # the line length to aim under (default 90)

What it never does: reflow code fences, tables, existing lists, or telegram_button
blocks; collapse blank lines; or invent words. It only breaks, never rewrites.
"""
from __future__ import annotations

import re
import sys

DEFAULT_MAX = 90
SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


def is_protected(line: str) -> bool:
    s = line.lstrip()
    stripped = s.strip()
    return (
        s.startswith("```")
        or s.startswith("    ")
        or s.startswith("\t")
        or s.startswith("|")
        or s.startswith("#")
        or re.match(r"^([-*+]|\d+[.)])\s+", s) is not None
        or "telegram_button" in line
        # a button payload is machine text: `[{label|prompt}{label|prompt}]`
        or (stripped.startswith("[{") and stripped.endswith("}]"))
    )


def split_sentences(text: str) -> list[str]:
    parts = [p.strip() for p in SENTENCE_END.split(text.strip()) if p.strip()]
    return parts or [text.strip()]


def wrap_words(text: str, max_len: int) -> list[str]:
    """Last resort: break a line too long even after clause splitting."""
    if len(text) <= max_len:
        return [text]
    lines, buf = [], ""
    for word in text.split():
        candidate = f"{buf} {word}".strip() if buf else word
        if len(candidate) <= max_len:
            buf = candidate
        else:
            if buf:
                lines.append(buf)
            buf = word
    if buf:
        lines.append(buf)
    return lines


def format_text(src: str, max_len: int = DEFAULT_MAX) -> str:
    out: list[str] = []
    in_fence = False
    for raw in src.split("\n"):
        if raw.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append(raw)
            continue
        if in_fence or is_protected(raw) or not raw.strip():
            out.append(raw.rstrip())
            continue

        text = raw.strip()
        sentences = split_sentences(text)
        if len(sentences) > 1:
            # one idea per line
            out.extend(sentences)
            continue

        # a single long sentence: break on clause marks first, then words
        out.extend(wrap_words(text, max_len))

    # collapse 3+ blank lines to one, keep single blank lines as paragraph breaks
    cleaned: list[str] = []
    blanks = 0
    for line in out:
        if line.strip():
            blanks = 0
            cleaned.append(line)
        else:
            blanks += 1
            if blanks == 1:
                cleaned.append("")
    return "\n".join(cleaned).strip() + "\n"


def check(src: str, max_len: int = DEFAULT_MAX) -> list[tuple[int, int, str]]:
    bad = []
    for n, line in enumerate(src.split("\n"), start=1):
        if not line.strip() or is_protected(line):
            continue
        if len(line) > max_len:
            bad.append((n, len(line), line.strip()[:60]))
    return bad


def main(argv: list[str]) -> int:
    max_len = DEFAULT_MAX
    mode = "format"
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print(__doc__)
            return 0
        if a == "--check":
            mode = "check"
        elif a == "--max":
            i += 1
            max_len = int(argv[i])
        elif a.startswith("--max="):
            max_len = int(a.split("=", 1)[1])
        else:
            print(f"telegram-format: unknown argument {a}", file=sys.stderr)
            return 2
        i += 1

    src = sys.stdin.read()
    if mode == "check":
        bad = check(src, max_len)
        if not bad:
            print(f"telegram-format: ok — every line is under {max_len}")
            return 0
        for n, length, preview in bad:
            print(f'telegram-format[1]{{line,chars,text}}:\n  {n},{length},"{preview}"')
        return 1

    sys.stdout.write(format_text(src, max_len))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
