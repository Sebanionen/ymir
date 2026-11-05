// Taste: keywords and recent feedback, the agent's taste questions, and answers that go back to the agent.
import { join } from "node:path";
import { loadPrompt } from "@dna/durable-agent";
import { int, invalid, notFound } from "../errors.ts";
import { applyFeedback } from "../news/taste.ts";
import { labelsOf } from "./feed.ts";
import { bodyOf, oneOf, type Handlers, type RouteDeps } from "./types.ts";

export function tasteRoutes({
  app,
}: RouteDeps): Handlers<"taste.get" | "taste.questions" | "taste.answer"> {
  const { store } = app;
  return {
    "taste.get": (_req, res) =>
      res.json({ keywords: store.taste.keywords(), recent: store.taste.recentFeedback(20) }),
    "taste.questions": (req, res) => {
      const status =
        oneOf(
          req.query.status,
          "status",
          ["open", "answered", "dismissed", "all"] as const,
          true,
        ) ?? "open";
      res.json(store.taste.questions(status === "all" ? undefined : status));
    },
    "taste.answer": async (req, res) => {
      const question = store.taste.question(int(req.params.id, "id"));
      if (!question) throw notFound(`No taste question ${req.params.id}`);
      if (question.status !== "open")
        throw invalid(`Taste question ${question.id} is already ${question.status}`);
      const labels = labelsOf(bodyOf(req).labels);
      if (!labels)
        throw invalid(
          "labels is required: a list of hype, facts, signal (an empty list means none)",
        );
      const answered = store.taste.answer(question.id, labels)!;
      const card = question.cardId ? store.news.card(question.cardId) : undefined;
      if (card) {
        applyFeedback(store, card, { labels });
        app.bus.publish({ type: "feed.card_updated", card: store.news.card(card.id)! });
      }
      app.bus.publish({ type: "taste.question", question: answered });
      const content = loadPrompt(
        join(app.config.promptsDir, "agents"),
        "news-desk",
        "USER_PROMPT_taste_answer.md",
        {
          card_id: question.cardId ?? "none",
          question: question.question,
          card_title: card?.title ?? "unknown",
          labels: labels.join(", ") || "none",
          jev_labels: card?.hfs?.labels.join(", ") || "none",
        },
      );
      await app.main.submit(
        { type: "input", content, requestId: `taste:${question.id}`, whenBusy: "followUp" },
        app.ctx,
      );
      app.log.info("taste.answered", { questionId: question.id, cardId: question.cardId, labels });
      res.json(answered);
    },
  };
}
