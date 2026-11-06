# 2026-11-06 — the manifest counted only what it added

**Component:** collab (Vingólf) · **Door:** `bin/collab/standardise.sh` · **Plan:** none — seen on the first
refresh of a client repository

## What was wrong

`.collab-kit.json` is written by the installer so the next hand can see *what standard this repository carries
and when it arrived*. It recorded one number — the count of files this run **added** — under the name `files`.

A refresh therefore wrote:

```json
{ "kit": "1.1.0", "applied": "2026-11-06T18:23:34Z", "files": 0 }
```

True of the run and false of the kit. A reader opening that file would conclude the standard is empty, and the
number that was supposed to make the install legible said the opposite of the truth.

## What changed

The manifest now carries both numbers:

```json
{ "kit": "1.1.0", "applied": "…", "files": 20, "installed_this_run": 0 }
```

`files` is what the kit holds (counted from `bin/collab/kit/` at write time), `installed_this_run` is what the
run added. Nothing else in the installer changed.

## Proved

- `standardise.sh --apply` on a scratch repository with no kit: `files: 20`, `installed_this_run: 20`.
- The same command on a repository already at 1.1.0: `files: 20`, `installed_this_run: 0` — and
  `--check` says `present: 20, missing: 0, different: 0`.

## What was NOT done

The manifest still carries no list of the individual files or their hashes; a per-file record would let
`--check` prove a file is unmodified rather than merely present, and that is a larger change than this fault
needs. Named here so it is a decision, not an oversight.

## CHANGE LOG

- **2026-11-06** — written after `fixes-guard` refused a push carrying the manifest fix with no note of its own;
  the gate was right, and the sentence explaining it belonged to the earlier note rather than to a file of its
  own.
