"""Console reporter: one narrative, two destinations.

Every line an smidja prints ALSO lands in the db as a `log` event, so the swim-lane
UI reads the same story the terminal does. Both go through `_emit` — print and
trace cannot drift. Plain sequential lines only: no spinners, no live displays,
so a CI log reads exactly like a terminal.
"""

from __future__ import annotations

from rich.console import Console as RichConsole
from rich.markup import escape
from rich.panel import Panel
from rich.text import Text

from .data_types import EnvelopeBase, EventRecord, Phase

KIND_COLOR = {"engineer": "cyan", "agent": "magenta", "code": "yellow"}
MAX_LINE = 160          # dynamic text (summaries, violations, errors) is clipped


def _clip(text: str, limit: int = MAX_LINE) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


class Console:
    """Bound to one run's tracer. Reachable as `run.console` everywhere."""

    def __init__(self, tracer, smidja_id: str):
        self.tracer = tracer
        self.smidja_id = smidja_id
        self.phase_id = ""          # current lane — log events attach to it
        self.phase_name = ""
        self.results: list[str] = []            # phase statuses, for the summary
        self._finished = False                  # the summary panel prints once
        self._out = RichConsole(highlight=False, soft_wrap=True)

    # ── the one helper: print AND trace, always together ────────────────────
    def _emit(self, markup: str, level: str = "info", renderable=None) -> None:
        text = Text.from_markup(markup)
        self._out.print(renderable if renderable is not None else text)
        self.tracer.event(EventRecord(
            smidja_id=self.smidja_id, phase_id=self.phase_id, type="log",
            name=self.phase_name or "console",
            payload={"message": text.plain, "level": level}))

    # ── session ─────────────────────────────────────────────────────────────
    def session_started(self, smidja_id: str, engineer: str) -> None:
        self._emit(f"[bold cyan]smidja_id:[/bold cyan] [bold]{escape(smidja_id)}[/bold]"
                   f"   [dim]engineer[/dim] {escape(engineer)}")

    def session_finished(self, ok: bool, tokens: int, cost: float, db_path: str,
                         status: str = "", note: str = "") -> None:
        if self._finished:
            return
        self._finished = True
        passed = sum(1 for r in self.results if r == "success")
        pressed = sum(1 for r in self.results if r == "context-pressed")
        # `status` is the settled word (success · context-pressed · fail) so the
        # banner can never say green over a run that pressed its window.
        word = status or ("success" if ok else "fail")
        style = {"success": "green", "context-pressed": "yellow"}.get(word, "red")
        mark = {"success": "✓ success",
                "context-pressed": "◐ context-pressed"}.get(word, "✗ fail")
        rows = [f" [dim]status[/dim]   [{style}]{escape(mark)}[/{style}]",
                f" [dim]phases[/dim]   {passed}/{len(self.results)} passed"
                + (f" · {pressed} context-pressed" if pressed else ""),
                f" [dim]tokens[/dim]   {tokens:,}",
                f" [dim]cost[/dim]     ${cost:.4f}",
                f" [dim]smidja_id[/dim]   {escape(self.smidja_id)}",
                f" [dim]db[/dim]       {escape(str(db_path))}",
                f" [dim]next[/dim]     [bold]just trace {escape(self.smidja_id)}[/bold]"]
        if note:
            rows.insert(1, f" [dim]reason[/dim]   {escape(_clip(note))}")
        panel = Panel(Text.from_markup("\n".join(rows)),
                      title="[bold]smidja complete[/bold]",
                      border_style=style, expand=False)
        plain = (f"session {self.smidja_id} {word} · "
                 f"{passed}/{len(self.results)} phases · {pressed} context-pressed · "
                 f"{tokens:,} tokens · ${cost:.4f}")
        self._emit(escape(plain), level="info" if ok else "error", renderable=panel)

    # ── phases ──────────────────────────────────────────────────────────────
    def phase_started(self, phase: Phase) -> None:
        self.phase_id, self.phase_name = phase.phase_id, phase.params.name
        p = phase.params
        color = KIND_COLOR.get(p.kind, "white")
        line = (f"[bold {color}]▶ {phase.seq:02d} {escape(p.name)}[/bold {color}]"
                f"  [{color}]{p.kind}[/{color}] [dim]· {escape(p.owner)}[/dim]")
        if p.description:
            line += f"  [dim]{escape(_clip(p.description))}[/dim]"
        self._emit(line)

    def phase_ended(self, phase: Phase, seconds: float) -> None:
        ok = phase.status == "success"
        self.results.append(phase.status)
        if phase.status == "context-pressed":
            mark = "[yellow]◐[/yellow]"
        else:
            mark = "[green]✓[/green]" if ok else "[red]✗[/red]"
        line = f"  {mark} {escape(phase.params.name)} [dim]{seconds:.1f}s[/dim]"
        if phase.status == "context-pressed":
            line += "  [yellow]context-pressed[/yellow]"
        if not ok and phase.status != "context-pressed" and phase.error:
            line += f"  [red]{escape(_clip(phase.error))}[/red]"
        self._emit(line, level="info" if ok else "warn" if phase.status == "context-pressed" else "error")
        self.phase_id, self.phase_name = "", ""

    def note(self, message: str) -> None:
        """Free-form detail inside the current phase — what `ph.log()` recorded."""
        self._emit(f"  [dim]· {escape(_clip(message))}[/dim]")

    # ── agents ──────────────────────────────────────────────────────────────
    def agent_started(self, name: str, model: str, session_id: str) -> None:
        self._emit(f"  [magenta]▸[/magenta] {escape(name)} [dim]{escape(model)}[/dim]"
                   f"  [dim]session {escape(session_id)}[/dim]")

    def agent_finished(self, name: str, tokens: int, cost: float) -> None:
        self._emit(f"  [dim]└ {escape(name)} used {tokens:,} tokens · ${cost:.4f}[/dim]")

    def context_receipt(self, name: str, receipt: dict) -> None:
        """The phase's context receipt, printed where the phase ends.

        This is the line the old banner never had: how full the window stood
        when the agent stopped, and whether that was a green or a press.
        """
        used = int(receipt.get("used") or 0)
        window = int(receipt.get("window") or 0)
        pct = receipt.get("percent") or 0
        if window:
            measure = f"{used:,} / {window:,} · {pct}%"
        else:
            measure = f"{used:,} / ? · window unknown"
        verdict = receipt.get("verdict") or ""
        if receipt.get("pressed"):
            self._emit(f"  [yellow]◐ {escape(name)} context {escape(measure)} "
                       f"— {escape(verdict)}[/yellow]", level="warn")
            return
        self._emit(f"  [dim]· {escape(name)} context {escape(measure)} "
                   f"— {escape(verdict)}[/dim]")

    def retry(self, name: str, attempt: int, limit: int, reason: str) -> None:
        self._emit(f"  [yellow]⟳[/yellow] {escape(name)} retry {attempt}/{limit} "
                   f"[dim]— same session · {escape(_clip(reason))}[/dim]", level="warn")

    # ── verification ────────────────────────────────────────────────────────
    def gate_result(self, name: str, report) -> None:
        """A gate reports WHAT it checked, not just whether it passed."""
        ok = report.passed
        mark = "[green]✓[/green]" if ok else "[red]✗[/red]"
        summary = (f"{len(report.checks)} checked" if ok
                   else f"[red]{len(report.violations)} of {len(report.checks)} failed[/red]")
        self._emit(f"  {mark} gate [dim]{escape(name)}[/dim] [dim]{summary}[/dim]",
                   level="info" if ok else "error")
        for check in report.checks:
            style = "dim" if check.ok else "dim red"
            detail = f" — {_clip(check.note)}" if check.note else ""
            self._emit(f"    [{style}]{'·' if check.ok else '✗'} {escape(_clip(check.item))}"
                       f"{escape(detail)}[/{style}]", level="info" if check.ok else "error")

    def envelope_summary(self, envelope: EnvelopeBase) -> None:
        ok = envelope.status == "success"
        line = (f"  {'[green]✓[/green]' if ok else '[red]✗[/red]'} "
                f"{type(envelope).__name__} [dim]{escape(_clip(envelope.summary))}[/dim]")
        self._emit(line, level="info" if ok else "error")
        if envelope.artifacts:
            self._emit(f"    [dim]artifacts: {escape(_clip(', '.join(envelope.artifacts)))}[/dim]")
