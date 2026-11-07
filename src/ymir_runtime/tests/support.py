"""Test doubles and fixtures for the engine's unit suite.

A `Recorder` stands where the real `proc.run` stands. `git` is passed through to
the real binary (a worktree is not something a double can fake honestly), and
every backend command is answered from a scripted table — so a module's DECISION
is asserted without a pane, a server, or a model ever being touched.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Iterable, Mapping, Sequence

from ymir_runtime import proc

Completed = subprocess.CompletedProcess


def completed(rc: int = 0, stdout: str = "", stderr: str = "") -> Completed:
    return Completed(args=[], returncode=rc, stdout=stdout, stderr=stderr)


class Recorder:
    """A `proc.Runner` that records argv and answers from a scripted table."""

    def __init__(
        self,
        *,
        catalog: Sequence[str] | None = None,
        responses: Mapping[str, Completed] | None = None,
        default: Completed | None = None,
    ) -> None:
        self.calls: list[list[str]] = []
        self.catalog = list(catalog) if catalog is not None else [
            "llama-swap/qwen3.6-35b-a3b@iq3_s",
            "openai/gpt-5",
        ]
        self.responses = dict(responses or {})
        self.default = default if default is not None else completed(0, "", "")

    def __call__(self, argv: Sequence[str], **kwargs) -> Completed:
        argv = [str(part) for part in argv]
        self.calls.append(argv)
        head = argv[0]

        if head == "git":
            return proc.run(argv, cwd=kwargs.get("cwd"), env=kwargs.get("env"))

        # A scripted answer wins over every default below: a test that needs a
        # refusal must be able to script the door it is refusing from.
        joined = " ".join(argv)
        bare = " ".join([Path(head).name, *argv[1:]])
        for prefix, response in self.responses.items():
            if joined.startswith(prefix) or bare.startswith(prefix):
                return response

        if Path(head).name == "pi-launcher.sh":
            # The ONE launcher generator (bin/seat/pi-launcher.sh) is a shell door;
            # the double answers the shape it composes for THIS seat, so the engine's
            # test asserts the wiring (discovery off, every extension named, the brief
            # carried) without a pane, and cannot pass on a hand-built line.
            args = argv[1:]
            cwd = args[1] if len(args) > 1 else "."
            model = brief = ""
            for index, part in enumerate(args):
                if part == "--model" and index + 1 < len(args):
                    model = args[index + 1]
                if part == "--brief" and index + 1 < len(args):
                    brief = args[index + 1]
            model_flag = f" --model '{model}'" if model else ""
            return completed(0, f"pi{model_flag} -ne -e {cwd}/.pi/extensions/a/index.ts \"$(cat '{brief}')\"" + "\n")

        if Path(head).name == "seat-prove.sh":
            # A healthy backend answers with the pane the agent stands in. A test
            # that wants a DEAD seat scripts its own refusal (bin/seat/seat-prove.sh).
            pane = argv[1] if len(argv) > 1 else "?"
            return completed(0, f"{pane}\tworking\n")

        if head == "pi" and "--list-models" in argv:
            body = "\n".join(
                f"{token.split('/', 1)[0]} {token.split('/', 1)[1]}" for token in self.catalog
            )
            return completed(0, body + "\n")

        return self.default

    def saw(self, prefix: str) -> list[list[str]]:
        matches = []
        for call in self.calls:
            joined = " ".join(call)
            bare = " ".join([Path(call[0]).name, *call[1:]])
            if joined.startswith(prefix) or bare.startswith(prefix):
                matches.append(call)
        return matches


def make_repo(path: Path) -> Path:
    """A real, minimal git repo with one commit — the honest fixture."""
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    (path / "README.md").write_text("engine fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(path), "add", "README.md"], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(path),
            "-c",
            "user.email=engine@test",
            "-c",
            "user.name=engine-test",
            "commit",
            "-qm",
            "init",
        ],
        check=True,
    )
    return path


def engine_env(tmp: Path, *, repo: Path | None = None, **extra: str) -> dict[str, str]:
    """An environment whose home, state and data all live in a temp dir."""
    home = tmp / "home"
    (home / "config").mkdir(parents=True, exist_ok=True)
    env = {
        "YMIR_HOME": str(home),
        "YMIR_STATE_DIR": str(home / "state"),
        "YMIR_DATA_DIR": str(home / "hodd" / "data"),
        "YMIR_SETTINGS_DIR": str(home / "config"),
        "BROKK_ROOT_OVERRIDE": str(repo or (tmp / "repo")),
        "YMIR_ENGINE_ROOT": str(repo or (tmp / "repo")),
        "YMIR_CONFIG_DIR": str(tmp / "config"),
        "XDG_STATE_HOME": str(tmp / "state-root"),
    }
    env.update(extra)
    return env


def write_brief(tmp: Path, seat_id: str, body: str) -> Path:
    """A brief in the record location the engine reads (data/<id>/brief.md)."""
    target = tmp / "home" / "hodd" / "data" / seat_id / "brief.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(body, encoding="utf-8")
    return target


def tmux_responses(window: str = "@7", pane_ok: bool = True) -> dict[str, Completed]:
    """The tmux replies a healthy or a dead seat gives."""
    if pane_ok:
        return {
            "tmux has-session": completed(1, "", "no session"),
            "tmux list-windows -t brokk -F": completed(0, "shell\n"),
            "tmux list-windows -a -F": completed(0, "shell\n@3\n" + window + "\n"),
            "tmux new-window": completed(0, window + "\n"),
        }
    return {
        "tmux has-session": completed(1, "", "no session"),
        "tmux list-windows -t brokk -F": completed(0, "shell\n"),
        "tmux list-windows -a -F": completed(0, "shell\n@3\n"),
        "tmux new-window": completed(0, window + "\n"),
    }


def iter_pairs(items: Iterable[tuple[str, str]]) -> dict[str, str]:
    return {key: value for key, value in items}


class LiveSeatRunner:
    """A tmux that really dies when its window is killed — for the reap proof."""

    def __init__(self, window: str = "@7", *, alive: bool = True, fail_kill: bool = False) -> None:
        self.calls: list[list[str]] = []
        self.window = window
        self.alive = alive
        self.fail_kill = fail_kill

    def __call__(self, argv: Sequence[str], **kwargs) -> Completed:
        argv = [str(part) for part in argv]
        self.calls.append(argv)
        joined = " ".join(argv)
        if joined.startswith("tmux list-windows -a -F"):
            return completed(0, f"@3\n{self.window}\n" if self.alive else "@3\n")
        if joined.startswith("tmux kill-window"):
            if self.fail_kill:
                return completed(1, "", "refused")
            self.alive = False
            return completed(0, "", "")
        if joined.startswith("tmux new-window"):
            return completed(0, f"{self.window}\n")
        if joined.startswith("tmux list-windows -t"):
            return completed(0, "shell\n")
        return completed(0, "", "")

    def saw(self, prefix: str) -> list[list[str]]:
        return [call for call in self.calls if " ".join(call).startswith(prefix)]
