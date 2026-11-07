// An upvote leaves a lead: the card's site, offered to the next sweep so the agent can save it as a source.
import type { Card, HfsCategory, SourceLead } from "@dna/sdk";
import type { Store } from "../db/store.ts";
import { isAggregator, siteKey, watching } from "./sources/discover.ts";

/** Show me more, or a Signal label, on a card: one lead per site the sweep does not watch yet. */
export function leadsFromUpvote(
  store: Store,
  card: Card,
  input: { signal?: "more" | "less"; labels?: HfsCategory[] },
): SourceLead[] {
  if (input.signal !== "more" && !input.labels?.includes("signal")) return [];
  const itemIds = card.itemId
    ? [card.itemId]
    : card.storyId
      ? store.news.storyItems(card.storyId)
      : [];
  const sources = store.sources.list();
  const leads = new Map<string, SourceLead>();
  for (const item of store.news.items(itemIds)) {
    let site: string;
    try {
      site = siteKey(item.url);
    } catch {
      continue;
    }
    if (leads.has(site) || isAggregator(item.url) || watching(sources, item.url)) continue;
    leads.set(
      site,
      store.sources.addLead({
        site,
        url: item.url,
        title: item.title,
        cardId: card.id,
        itemId: item.id,
      }),
    );
  }
  return [...leads.values()];
}
