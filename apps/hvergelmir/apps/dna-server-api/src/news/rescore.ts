// Rescore news cards whose Hype, Facts and Signal came from an older hfs command. After an upgrade (Facts now reads
// the page and measures what can be checked) it runs once in the background; each item is scored once per version.
import { runParallel } from "@dna/durable-agent";
import type { Deps } from "../deps.ts";
import { pageText } from "./page.ts";

export async function rescoreCards(
  deps: Pick<Deps, "store" | "judge" | "http" | "log">,
  onCard: (cardId: number) => void,
  signal?: AbortSignal,
): Promise<number> {
  const version = deps.judge.commands.hfs.version;
  const seen = new Set<number>();
  const cards = deps.store.news.cardsToRescore(version).filter((c) => {
    if (seen.has(c.itemId!)) return false;
    seen.add(c.itemId!);
    return true;
  });
  let rescored = 0;
  await runParallel(cards, 3, async (card) => {
    if (signal?.aborted) return;
    const item = deps.store.news.item(card.itemId!);
    if (!item) return;
    const page = await pageText(deps, item);
    if (signal?.aborted) return;
    // The feed's own words first, then what the page says.
    const text = page ? `${item.excerpt ?? item.title}\n\n${page}`.slice(0, 2400) : undefined;
    const hfs = await deps.judge.hfs(item, { sweepId: card.sweepId }, undefined, text);
    if (signal?.aborted) return;
    const attention = deps.judge.attention(hfs, item.relevance ?? 0.5);
    for (const cardId of deps.store.news.cardIdsForItem(item.id)) {
      deps.store.news.setCardHfs(cardId, hfs, attention);
      onCard(cardId);
    }
    rescored++;
  });
  return rescored;
}
