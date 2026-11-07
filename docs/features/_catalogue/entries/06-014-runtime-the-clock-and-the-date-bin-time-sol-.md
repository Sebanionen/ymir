---
section: planned-named-and-designed-not-yet-built
---
| Runtime | **The clock and the date** | `bin/time/sol.sh` (**Sól**) answers the time once — local with its offset, UTC, epoch, a sortable stamp, the zone and its source — and does `add`/`diff` correctly across daylight-saving, reporting elapsed and calendar distance separately. Wired into the session digest; `check` refuses to call an unsynchronised clock sane | [docs/features/the-clock.md](docs/features/the-clock.md) |
