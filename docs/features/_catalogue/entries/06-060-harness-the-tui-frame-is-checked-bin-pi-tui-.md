---
section: planned-named-and-designed-not-yet-built
---
| Harness | **The TUI frame is checked** (`bin/pi/tui-frame-check.sh`) | Drives a real pi in a pty at a chosen width with `PI_TUI_WRITE_LOG`, replays the raw ANSI stream (CUP/ED/EL/OSC aware, grapheme-aware) and **fails if any write reaches past the right edge**, reporting the row, column and bytes; it also reports whether pi left autowrap disabled (`ESC[?7l`), which is the mechanism behind a clipped row and the repaint that then shifts it. Measured 2026-10-23: fullscreen disables autowrap at startup and never restores it; regular never touches it — which is why this seat runs `"tuiMode": "regular"` | [docs/features/the-tui-frame-check.md](docs/features/the-tui-frame-check.md) |
