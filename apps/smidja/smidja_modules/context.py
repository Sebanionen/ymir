"""Context telemetry — how full a phase left its window, and the one verdict.

A phase that ends with the window nearly full is not the same thing as a phase
that succeeded. This module is the ONE place that decides which of those it was,
so the trace, the banner, the session status and the database cannot disagree.

The four verdicts are the exact strings `bin/seat/context.sh` prints — that door
is the house's answer to "what does my context hold", and the smithy must not
grow a second vocabulary for the same fact. Two more are added for states the
door never has to face (a trace read long after the run):

    room to work                    below the auto threshold (< 50% of window)
    past the auto threshold         >= 50% and < 75%
    near the window — compact now   >= 75% of window (the force threshold)
    TRUNCATED                       the last turn ended on the length limit
    window unknown                  no door could say how large the window is
    no usage recorded               the phase recorded no usage at all

`window unknown` and `no usage recorded` are honest empties, never greens: a
surface may not show what it did not receive (RULES/37).

**The window is never a table.** It comes from the doors the rest of the house
uses, probed in order and cached per model:

  1. the dispatcher's own read (``agent_pi`` asks pi's merged model catalog)
  2. ``~/.pi/agent/models.json`` — pi's registry
  3. ``bin/model/catalog.sh`` — the machine's catalog
  4. ``bin/seat/core-four.sh --json`` — the seat's own window, used only when it
     names the same model (otherwise it is another model's ceiling and says so)
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Optional

# The two thresholds, as a share of the window. These are the numbers the seat's
# doors already use (bin/seat/context.sh, bin/seat/core-four.sh): auto at a half,
# force at three quarters. Nothing here invents a third policy.
AUTO_RATIO = 0.5
FORCE_RATIO = 0.75

VERDICT_ROOM = "room to work"
VERDICT_AUTO = "past the auto threshold"
VERDICT_NEAR = "near the window — compact now"
VERDICT_TRUNCATED = "TRUNCATED"
VERDICT_UNKNOWN = "window unknown"
VERDICT_NO_USAGE = "no usage recorded"

# Every word this module may return, in one tuple, for tests and readers.
VERDICTS = (VERDICT_ROOM, VERDICT_AUTO, VERDICT_NEAR, VERDICT_TRUNCATED,
            VERDICT_UNKNOWN, VERDICT_NO_USAGE)

# A stop reason that means the model ran out of room rather than finished.
_TRUNCATING_FINISH = {"length", "max_tokens", "max-tokens", "max_output_tokens"}

_WINDOW_CACHE: dict[str, tuple[int, str]] = {}


def auto_at(window: int) -> int:
    """The token count at which the auto-compaction threshold sits."""
    return int(window * AUTO_RATIO) if window else 0


def force_at(window: int) -> int:
    """The token count at which the force threshold sits — the one that presses."""
    return int(window * FORCE_RATIO) if window else 0


def percent(used: int, window: int) -> float:
    """Occupancy as a share of the window, rounded the way the seat door rounds."""
    return round(100.0 * used / window, 1) if window else 0.0


def pressed(used: int, window: int, finish: str = "") -> bool:
    """True when the phase ended at or above the force threshold, or was cut off.

    A truncated turn is pressed by definition: the window did not merely fill, it
    stopped the work. A window of 0 is unknown, not full — it never presses.
    """
    if str(finish or "").lower() in _TRUNCATING_FINISH:
        return True
    return bool(window) and used >= force_at(window)


def verdict(used: int, window: int, finish: str = "") -> str:
    """The one word this phase's context earned.

    Order matters: truncation outranks a full window (the work was stopped, not
    merely tight), and an unknown window outranks every threshold because no
    threshold can be measured against it.
    """
    if str(finish or "").lower() in _TRUNCATING_FINISH:
        return VERDICT_TRUNCATED
    if not window:
        return VERDICT_UNKNOWN
    if not used:
        return VERDICT_NO_USAGE
    if used >= force_at(window):
        return VERDICT_NEAR
    if used >= auto_at(window):
        return VERDICT_AUTO
    return VERDICT_ROOM


# ── the window, from the house's own doors ───────────────────────────────────

def repo_root(start: Optional[Path] = None) -> Optional[Path]:
    """The tree that owns ``bin/model/catalog.sh`` — found, never assumed."""
    for cand in (start, *Path(__file__).resolve().parents):
        if cand is None:
            continue
        p = Path(cand)
        while True:
            if (p / "bin" / "model" / "catalog.sh").is_file():
                return p
            if p.parent == p:
                break
            p = p.parent
    return None


def _parse_catalog_context(raw: str) -> int:
    """Turn the catalog's ``262.1K`` / ``1M`` into a token count."""
    text = (raw or "").strip().strip('"').strip()
    if not text:
        return 0
    mult = 1
    if text[-1] in "Kk":
        mult, text = 1000, text[:-1]
    elif text[-1] in "Mm":
        mult, text = 1_000_000, text[:-1]
    try:
        return int(float(text) * mult)
    except ValueError:
        digits = "".join(ch for ch in text if ch.isdigit())
        return int(digits) * mult if digits else 0


def _split_model(model: str) -> tuple[str, str]:
    """``provider/model`` → (provider, model id); a bare id answers ("", id)."""
    if "/" in model:
        return tuple(model.split("/", 1))  # type: ignore[return-value]
    return "", model


def _from_pi_registry(model: str) -> int:
    """pi's merged catalog: the registry file first, then `pi --list-models`."""
    provider, model_id = _split_model(model)
    try:
        from . import agent_pi          # local import: keeps this module standalone
        window = agent_pi.context_window(provider, model_id)
        if window:
            return int(window)
    except Exception:
        pass
    return 0


def _from_catalog_door(model: str, root: Optional[Path]) -> int:
    """``bin/model/catalog.sh`` — the machine's own answer, TOON rows."""
    if root is None:
        return 0
    door = root / "bin" / "model" / "catalog.sh"
    if not door.is_file():
        return 0
    provider, model_id = _split_model(model)
    try:
        out = subprocess.run(["bash", str(door)], capture_output=True, text=True,
                             timeout=90).stdout
    except Exception:
        return 0
    for line in out.splitlines():
        cells = [c.strip().strip('"') for c in line.strip().strip(",").split(",")]
        if len(cells) < 3:
            continue
        if cells[0] != provider and provider:
            continue
        if cells[1] == model_id or cells[1].endswith("/" + model_id):
            return _parse_catalog_context(cells[2])
    return 0


def _from_core_four(model: str, root: Optional[Path]) -> int:
    """``bin/seat/core-four.sh --json`` — the seat's window, when it is THIS model.

    core-four reports the seat's configured model, not an arbitrary one, so its
    number is only this phase's ceiling when the names agree. Otherwise it is
    another model's window and using it would be a lie.
    """
    if root is None:
        return 0
    door = root / "bin" / "seat" / "core-four.sh"
    if not door.is_file():
        return 0
    try:
        out = subprocess.run(["bash", str(door), "--json"], capture_output=True,
                             text=True, timeout=90).stdout
        data = json.loads(out)
    except Exception:
        return 0
    seat_model = str(data.get("model") or "")
    if seat_model and seat_model != model and not seat_model.endswith("/" + model):
        return 0
    try:
        return int((data.get("context") or {}).get("window") or 0)
    except (TypeError, ValueError):
        return 0


def window_for(model: str, hint: int = 0,
               root: Optional[Path] = None) -> tuple[int, str]:
    """The model's context ceiling and which door answered.

    ``hint`` is what the dispatcher already resolved (it asks pi's catalog at
    spawn time), so the common path never spawns a subprocess. A model with no
    answer anywhere returns ``(0, "unknown")`` — never a guessed default.
    """
    if not model:
        return 0, "unknown"
    if hint and hint > 0:
        return int(hint), "dispatcher"
    cached = _WINDOW_CACHE.get(model)
    if cached is not None:
        return cached
    base = root if root is not None else repo_root()
    for source, probe in (("registry", lambda: _from_pi_registry(model)),
                          ("catalog", lambda: _from_catalog_door(model, base)),
                          ("core-four", lambda: _from_core_four(model, base))):
        window = probe()
        if window:
            _WINDOW_CACHE[model] = (window, source)
            return _WINDOW_CACHE[model]
    _WINDOW_CACHE[model] = (0, "unknown")
    return _WINDOW_CACHE[model]


# ── the block a phase records ────────────────────────────────────────────────

def phase_context(model: str, used: int, window: int, source: str = "",
                  input_tokens: int = 0, cache_read: int = 0, output: int = 0,
                  finish: str = "", thinking: str = "") -> dict:
    """The context block written to ``agent_end`` — the phase's own receipt.

    ``used`` is the last turn's window occupancy (input + cache read + output),
    not the phase's spend: spend bills every turn, occupancy is how full the
    window stands right now. The two are deliberately different numbers and both
    are recorded (spend in ``usage``, occupancy here).

    ``model`` and ``thinking`` are recorded here as well as on ``agent_start``,
    because this receipt is the phase's own record: the trace must be able to
    answer "which model, at which thinking level" from one event, without
    depending on the start event still being present in the ledger.
    """
    window = int(window or 0)
    used = int(used or 0)
    pct = percent(used, window)
    return {
        "model": model or "",
        "thinking": thinking or "",
        "input": int(input_tokens or 0),
        "cache_read": int(cache_read or 0),
        "output": int(output or 0),
        "used": used,
        "window": window,
        "percent": pct,
        "auto_compact_at": auto_at(window),
        "force_compact_at": force_at(window),
        "remaining": max(window - used, 0) if window else 0,
        "last_finish": finish or "",
        "window_source": source or ("dispatcher" if window else "unknown"),
        "verdict": verdict(used, window, finish),
        "pressed": pressed(used, window, finish),
    }
