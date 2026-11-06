# every opencode seat was born dead on opencode v2

**Date:** 2026-11-06 · **Component:** harness

## What was wrong

The spawn launched `opencode --model … --prompt "$(cat brief)"`. OpenCode v2.0.16 removed the top-level
`--model` and `--prompt` shape: the pane answered `ERROR Unrecognized flag: --model in command opencode`, and
every opencode seat died while the dispatcher printed `spawned`. Measured in the growth-agent UI errand: the
herdr seat-prove found no agent in the pane.

## Why

The launcher was written for OpenCode v1. V2 moved the message to `opencode run`, with `--model` on that
subcommand; the top-level command no longer accepts either flag. The `seat-prove` in `einherjar-spawn.sh` is
what caught it — without it, the dispatcher would have printed `spawned` and the errand would have been silent.

## Fix

- `bin/agents/einherjar-spawn.sh`: the opencode launch is
  `opencode run --model <model> --auto "$(cat <prompt>)"`; `--auto` keeps the worker unattended.
- The dry-run preview prints the same shape for opencode, so the plan and the launch cannot disagree.
- The `pi` path is unchanged.

## Proof

- `opencode run --help` on 2.0.16 lists `--model` and the positional message; `opencode --help` does not.
- The old command in a pane: `ERROR Unrecognized flag: --model in command opencode`.
- The patched dry-run: `opencode run --model opencode-go/deepseek-v4.1-flash --auto "$(cat …/prompt.md)"`.
- A herdr seat (`w4:p1`) ran the opencode worker in `.yggdrasil/growth-ui-truth-01`; `herdr agent list` shows
  the pane's foreground cwd.
- `bash -n bin/agents/einherjar-spawn.sh` clean.

## Not done

The `OPENCODE_CONFIG_CONTENT` permission override is kept; a v2 config-file shape is a separate question. The
Windows layer is untouched.
