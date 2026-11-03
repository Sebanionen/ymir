# doc-sweep could not find its own resolver — a gate that refused with the file in front of it

**Date:** 2026-11-02 · **Component:** gate · **Found while routing a portable verb, and not caused by it**

## What was wrong

`bin/gates/doc-sweep.sh` searched for `hoard-lib.sh` at every ancestor directory *as a bare file*:

```sh
_yh="$SCRIPT_DIR"
for _i in 1 2 3 4 5; do
  [ -r "$_yh/hoard-lib.sh" ] && . "$_yh/hoard-lib.sh"
  _yh="$(cd "$_yh/.." && pwd)"
done
```

The resolver lives at `bin/vault/hoard-lib.sh`, so the walk passed it by, and the gate exited 2 with
*"bin/vault/hoard-lib.sh is missing — the home is never guessed"* — while the file sat exactly there. Confirmed
pre-existing: the same failure happens with a clean `git stash`.

## What changed

The canonical path is tried first (`$ROOT/bin/vault/hoard-lib.sh`), then the walk, now also looking inside
`bin/vault/` at each ancestor. The bare-`hoard-lib.sh` candidate is kept for an old layout.

## Measured

```
before:  doc-sweep: bin/vault/hoard-lib.sh is missing — the home is never guessed   (exit 2)
after:   doc-sweep --check prints its plan vocabulary and exits 0
```

## Why it matters beyond this gate

A gate that cannot find the resolver is a gate that answers "no" to everything, and a "no" that looks like a
configuration mistake is the easiest kind of failure to leave standing. This is the third member of one family
found in a day: the deployed desk ahead of its tree, Skírnir's twenty-four counted roots, and now a walk that
looked for the resolver in the wrong shape.
