# The platform shim gains the verbs, and a ratchet so the debt can only fall

**Date:** 2026-11-02 · **Component:** platforms · **From plan 160 Phase 1**

## What was wrong

`bin/fleet/ymir-platform.sh` was the one place a platform difference was known — and it had no verb for the
facilities the doors actually use. Measured: **44 files call `stat -c`, 44 `sha256sum`, 10 `flock`, 8 `mapfile`,
5 `nproc`, 5 `sed -i`** — 116 callers, every one GNU-only, and only 24 files sourcing the shim at all.

## What changed

The shim gains six verbs, each with the BSD/macOS spelling behind it: `ymir_stat` (size · mtime · mode),
`ymir_sha256` (`sha256sum` → `shasum -a 256` → `openssl dgst`), `ymir_nproc`, `ymir_sed_i` (the `-i ''` split),
`ymir_lock` (`flock` → a mkdir-lock), and `ymir_read_lines` (`mapfile` → a while-read for bash 3.2).

And a **ratchet**, not a wall: `bin/gates/checks/portability-ratchet.sh` counts the files still calling a GNU
spelling and compares each against a baseline in the home (`hodd/data/portability-baseline.yaml`). A count may
fall; a count that rises fails the check. Fixing 116 callers in one change would be a rewrite with no test —
forbidding new ones is arithmetic and can start today.

## Measured

```
portability-ratchet[6]{verb,now,baseline,verdict}:
  "stat -c","44","44","ok"      "sha256sum","44","44","ok"     "flock","10","10","ok"
  "mapfile","8","8","ok"        "nproc","5","5","ok"           "sed -i ","5","5","ok"
```

The verbs answer on this host (`ymir_sha256` returns the digest, `ymir_stat size` the size, `ymir_read_lines`
fills an array).

## Still owed

Routing the 116 callers through the verbs, in the order that matters — the gates and the record first. The
baseline falls as each pass lands, and the ward keeps the next caller honest.
