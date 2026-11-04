#!/usr/bin/env python3
"""skills-mcp — the skills door: three tools and one file fetcher, nothing writable.

WHY (plan 184 §3): a skill read into context costs 2–20 K tokens; 196 skills is beyond any
window, and one tool per skill would repeat the same mistake in tool schemas instead of prose.
So the door is deliberately tiny — a collaborator's model sees FOUR tool descriptions, about
three hundred tokens, always — and pays for a skill only when it asks for one:

    skills_search(query)      names + a one-line description + a token estimate — never bodies
    skills_get(name, full)    the front matter always; the body only when full=true
    skills_templates(tag)     the names of the generic templates, fetched by skills_file
    skills_file(path)         ONE named file out of published/, path-confined

What it may read is one tree and one tree only: `published/` — the built, redacted, hashed
copy (bin/skills/share-build.sh). There is **no write path, no shell, no network call**: the
server never runs a command, never opens a socket of its own, and never reads the live skill
shelves, the vault or the well. A borrow is a read.

Run:
    python3 tools/skills-mcp/skills-mcp.py                 # stdio (a harness spawns it)
    python3 tools/skills-mcp/skills-mcp.py --http 127.0.0.1:8791   # loopback HTTP, behind Gimle
    python3 tools/skills-mcp/skills-mcp.py --selftest      # what this door holds and where
    python3 tools/skills-mcp/skills-mcp.py --schema-tokens # the load cost, in tokens

Env: SKILLS_MCP_ROOT overrides the published tree (default: the resolved home's
`hodd/skills-share/published`). Nothing else is configurable on purpose.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

MAX_FILE_BYTES = 256 * 1024


# ── the published tree, resolved without a shell ────────────────────────────────
def _home() -> Path | None:
    """The operator's home: env → the recorded choice → the usual default. Never a guess."""
    env = os.environ.get("YMIR_HOME")
    if env:
        return Path(env).expanduser()
    record = Path(os.environ.get("YMIR_CONFIG_DIR", Path.home() / ".config" / "ymir")) / "home"
    try:
        if record.is_file():
            line = record.read_text().strip().splitlines()[0].strip()
            if line:
                return Path(line)
    except (OSError, IndexError):
        pass
    default = Path.home() / "Documents" / "ymirhome"
    return default if default.is_dir() else None


def published_root() -> Path:
    env = os.environ.get("SKILLS_MCP_ROOT")
    if env:
        return Path(env).expanduser()
    home = _home()
    return (home / "hodd" / "skills-share" / "published") if home else Path("published")


# ── reading the built copy ──────────────────────────────────────────────────────
def _skills() -> list[dict]:
    """Every published skill, from its manifest.json — the door lists a build, never a shelf."""
    root = published_root()
    out: list[dict] = []
    if not root.is_dir():
        return out
    for d in sorted(root.iterdir()):
        if not d.is_dir():
            continue
        man = d / "manifest.json"
        skill_md = d / "SKILL.md"
        if not man.is_file() or not skill_md.is_file():
            continue
        try:
            meta = json.loads(man.read_text(encoding="utf-8"))
            text = skill_md.read_text(encoding="utf-8", errors="replace")
        except (OSError, ValueError):
            continue
        out.append({
            "name": meta.get("name", d.name),
            "version": meta.get("version", "0.0.0"),
            "sha256": meta.get("sha256", ""),
            "source_rev": meta.get("source_rev", "unknown"),
            "dir": d,
            "text": text,
            "description": _front_matter(text, "description") or "(no description declared)",
        })
    return out


def _front_matter(text: str, key: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.strip().lower().startswith(key + ":"):
            return line.split(":", 1)[1].strip()
    return ""


def _front_matter_block(text: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == "---":
            return "\n".join(lines[: i + 1])
    return ""


def _body(text: str) -> str:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return text
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == "---":
            return "\n".join(lines[i + 1:]).strip()
    return text


def _tokens(n_chars: int) -> int:
    return (n_chars + 3) // 4


def _templates(skill: dict) -> list[str]:
    base = skill["dir"]
    found = []
    for sub in ("templates", "assets"):
        p = base / sub
        if not p.is_dir():
            continue
        for f in sorted(p.rglob("*")):
            if f.is_file():
                found.append(str(f.relative_to(published_root())))
    return found


# ── the server ──────────────────────────────────────────────────────────────────
try:
    from mcp.server.fastmcp import FastMCP
except ImportError:  # pragma: no cover - the one production dependency
    FastMCP = None  # type: ignore[assignment]


def _build(host: str = "127.0.0.1", port: int = 8791):
    mcp = FastMCP("skills", host=host, port=port)

    @mcp.tool()
    def skills_search(query: str, limit: int = 8) -> str:
        """Find skills: one line per hit — name, description, token estimate. Never a body."""
        q = (query or "").strip().lower()
        skills = _skills()
        if not skills:
            return f"no published skills at {published_root()} — the door has nothing to lend"
        hits = [s for s in skills if q in s["name"].lower() or q in s["description"].lower()] if q else skills
        hits.sort(key=lambda s: (0 if q and q in s["name"].lower() else 1, s["name"]))
        hits = hits[: max(1, min(int(limit or 8), 25))]
        if not hits:
            names = ", ".join(s["name"] for s in skills[:12])
            return f"no skill matches {query!r}. Published: {names}"
        return "\n".join(
            f"{s['name']} — {s['description']} (~{_tokens(len(s['text']))} tokens; v{s['version']})"
            for s in hits
        )

    @mcp.tool()
    def skills_get(name: str, full: bool = False) -> str:
        """Load ONE skill by name: front matter only, or its body with full=true."""
        for s in _skills():
            if s["name"] == name:
                head = _front_matter_block(s["text"])
                files = _templates(s)
                meta = [f"sha256: {s['sha256']}", f"source_rev: {s['source_rev']}"]
                if files:
                    meta.append("files: " + ", ".join(files))
                if not full:
                    return "\n".join([head, *meta, "", "(body withheld — call skills_get with full=true)"])
                return "\n".join([head, *meta, "", _body(s["text"])])
        names = ", ".join(x["name"] for x in _skills())
        return f"no skill named {name!r}. Published: {names or '(none)'}"

    @mcp.tool()
    def skills_templates(tag: str = "") -> str:
        """List template paths a published skill ships; tag narrows by skill or file name."""""
        t = (tag or "").strip().lower()
        rows = []
        for s in _skills():
            for path in _templates(s):
                if t and t not in path.lower():
                    continue
                rows.append(path)
        if not rows:
            return f"no templates match {tag!r} — call skills_templates with no tag to see them all"
        return "\n".join(rows)

    @mcp.tool()
    def skills_file(path: str) -> str:
        """Fetch ONE file from published/ by the path skills_templates gave; path-confined."""
        root = published_root().resolve()
        if not root.is_dir():
            return f"no published tree at {root}"
        want = (path or "").strip().lstrip("/")
        if not want:
            return "skills_file needs a path from skills_templates"
        target = (root / want).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            return "refused: that path is outside the published tree"
        if target.is_dir():
            return "refused: that path is a directory — ask for a file"
        if not target.is_file():
            return f"no such file in the published tree: {want}"
        try:
            if target.stat().st_size > MAX_FILE_BYTES:
                return f"refused: {want} is larger than {MAX_FILE_BYTES // 1024} KiB"
            return target.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            return f"unreadable: {exc}"

    return mcp


def _tool_schemas(mcp) -> list[dict]:
    tools = mcp._tool_manager.list_tools()  # sync view of the registered tools
    return [
        {"name": t.name, "description": t.description or "", "parameters": t.parameters}
        for t in tools
    ]


def main(argv: list[str]) -> int:
    http = ""
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--http":
            http = args.pop(0) if args else ""
        elif a.startswith("--http="):
            http = a.split("=", 1)[1]
        elif a == "--selftest":
            return selftest()
        elif a == "--schema-tokens":
            return schema_tokens()
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print(f"error: unknown argument {a}", file=sys.stderr)
            return 2

    if FastMCP is None:
        print(
            "skills-mcp: the MCP SDK is missing. Install it once for this user:\n"
            "  python3 -m pip install --user mcp\n"
            "The door is useless without it, so it refuses rather than half-starts.",
            file=sys.stderr,
        )
        return 1

    host, port = "127.0.0.1", 8791
    if http:
        host, _, port_s = http.partition(":")
        host = host or "127.0.0.1"
        port = int(port_s or "8791")
        if host not in ("127.0.0.1", "localhost", "::1"):
            print(
                f"skills-mcp: refusing to bind {host} — this door is LOOPBACK ONLY; Gimle is the "
                "surface that faces the world, never the door itself.",
                file=sys.stderr,
            )
            return 2

    mcp = _build(host=host, port=port)
    mcp.run(transport="streamable-http" if http else "stdio")
    return 0


def selftest() -> int:
    mcp = _build() if FastMCP is not None else None
    root = published_root()
    skills = _skills()
    print("skills_mcp_selftest[3]{items,count,detail}:")
    if mcp is None:
        print('  "tools","0","the MCP SDK is missing — python3 -m pip install --user mcp"')
    else:
        names = [t["name"] for t in _tool_schemas(mcp)]
        print(f'  "tools","{len(names)}","{", ".join(names)}"')
    print(f'  "published_root","{"present" if root.is_dir() else "absent"}","{root}"')
    print(f'  "skills","{len(skills)}","{", ".join(s["name"] for s in skills) or "(none published yet)"}"')
    return 0 if mcp is not None else 1


def schema_tokens() -> int:
    if FastMCP is None:
        print("skills-mcp: the MCP SDK is missing — python3 -m pip install --user mcp", file=sys.stderr)
        return 1
    mcp = _build()
    payload = json.dumps(_tool_schemas(mcp), ensure_ascii=False)
    tokens = _tokens(len(payload))
    verdict = "ok" if tokens < 400 else "TOO LARGE"
    print(f"schema_tokens[3]{{tools,chars,tokens}}:\n  \"{len(_tool_schemas(mcp))}\",\"{len(payload)}\",\"{tokens}\"")
    print(f"budget: {tokens} token(s) of {400} — {verdict}")
    return 0 if tokens < 400 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
