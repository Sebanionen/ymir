# The forge joins the places — Code is a tile on the desk

**Date:** 2026-11-02 · **Component:** gimle · **At the Allfather's word**

## What was wrong

The desk offered Board, Documents, Whiteboard, Meetings and Book — and not the forge, which is where the code
and the pull requests actually live. The rung the suite claims to serve is *"the suite — hall, Documents,
Whiteboard, Files, **Code**"*, and the only way to Code was to remember the hostname.

## What changed

One tile, between Board and Documents:

```
("Code", "https://forgejo.zerwiz.org", "repositories and pull requests — Forgejo")
```

Named **Code** rather than Forgejo, because every other tile names the job and lets the description carry the
engine ("projects and tasks — Plane").

## Measured

```
python3 -c "import ast; ast.parse(...)"          → syntax ok
render with Remote-User: zerwiz                  → the tile renders, href forgejo.zerwiz.org
```

A tile is a link, so a forge that is down cannot break the desk: the page still renders and the link fails on
its own.
