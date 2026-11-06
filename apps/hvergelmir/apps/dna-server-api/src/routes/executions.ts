// Execution detail: runs, one run with everything it did, one tool call, and per day usage.
import { int, notFound, optInt } from "../errors.ts";
import type { Handlers, RouteDeps } from "./types.ts";

export function executionRoutes({
  app,
}: RouteDeps): Handlers<
  "executions.runs" | "executions.run" | "executions.toolCalls" | "executions.toolCall" | "usage"
> {
  const t = app.store.telemetry;
  return {
    "executions.runs": (req, res) => {
      const conversationId = optInt(req.query.conversationId, "conversationId");
      const sweepId = optInt(req.query.sweepId, "sweepId");
      res.json(
        t.runs({
          sweepId,
          conversationId,
          before: optInt(req.query.before, "before"),
          limit: Math.min(int(req.query.limit, "limit", 50), 200),
          topLevel: conversationId === undefined && sweepId === undefined,
        }),
      );
    },
    "executions.run": (req, res) => {
      const run = t.run(int(req.params.id, "id"));
      if (!run) throw notFound(`No run ${req.params.id}`);
      res.json(run);
    },
    "executions.toolCalls": (req, res) => {
      const sweepId = optInt(req.query.sweepId, "sweepId");
      if (sweepId !== undefined) return res.json(t.toolCallsForSweep(sweepId));
      const conversationId =
        optInt(req.query.conversationId, "conversationId") ?? (app.main.id as number);
      res.json(
        t.toolCallsForConversation(
          conversationId,
          Math.min(int(req.query.limit, "limit", 200), 500),
        ),
      );
    },
    "executions.toolCall": (req, res) => {
      const call = t.toolCall(int(req.params.id, "id"));
      if (!call) throw notFound(`No tool call ${req.params.id}`);
      res.json(call);
    },
    usage: (req, res) => res.json(t.usage(Math.min(int(req.query.days, "days", 14), 90))),
  };
}
