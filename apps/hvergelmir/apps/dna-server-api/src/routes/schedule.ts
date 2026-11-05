// How often scheduled sweeps run and how many cards each presents: GET the setting with its presets and the next
// sweep, PATCH everyMinutes (a preset, or null for off), cardsPerSweep (1 to 30), or both.
import { invalid } from "../errors.ts";
import { MAX_CARDS } from "../news/schedule.ts";
import { bodyOf, num, type Handlers, type RouteDeps } from "./types.ts";

export function scheduleRoutes({ app }: RouteDeps): Handlers<"schedule.get" | "schedule.set"> {
  return {
    "schedule.get": (_req, res) => res.json(app.schedule.state()),
    "schedule.set": (req, res) => {
      const body = bodyOf(req);
      const presets = app.schedule.presets();
      const every = body.everyMinutes;
      if (every !== undefined && every !== null && !presets.includes(every as number))
        throw invalid(`everyMinutes must be one of ${presets.join(", ")}, or null for off`);
      const cards = num(body, "cardsPerSweep", { min: 1, max: MAX_CARDS, integer: true });
      if (every === undefined && cards === undefined)
        throw invalid("Send everyMinutes, cardsPerSweep, or both");
      const state = app.schedule.set({
        ...(every !== undefined ? { everyMinutes: every as number | null } : {}),
        ...(cards !== undefined ? { cardsPerSweep: cards } : {}),
      });
      app.log.info("schedule.set", {
        everyMinutes: state.everyMinutes,
        cardsPerSweep: state.cardsPerSweep,
      });
      app.bus.publish({ type: "schedule", schedule: state });
      res.json(state);
    },
  };
}
