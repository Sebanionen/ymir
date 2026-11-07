// Each generative UI enum value maps to one Vue component. Unknown values render as a brief and log a warning.
import type { Component } from "vue";
import type { CardComponent } from "@dna/sdk";
import BriefCard from "./BriefCard.vue";
import FactCheckCard from "./FactCheckCard.vue";
import HeadlineCard from "./HeadlineCard.vue";
import HypeWatchCard from "./HypeWatchCard.vue";
import QuoteCard from "./QuoteCard.vue";
import ReleaseCard from "./ReleaseCard.vue";
import SignalAlertCard from "./SignalAlertCard.vue";
import ThreadPulseCard from "./ThreadPulseCard.vue";

export const CARD_COMPONENTS: Record<CardComponent, Component> = {
  headline: HeadlineCard,
  brief: BriefCard,
  signal_alert: SignalAlertCard,
  fact_check: FactCheckCard,
  hype_watch: HypeWatchCard,
  release: ReleaseCard,
  thread_pulse: ThreadPulseCard,
  quote: QuoteCard,
};

export function cardComponent(name: string): Component {
  const found = CARD_COMPONENTS[name as CardComponent];
  if (!found) console.warn(`Unknown card component ${name}, rendering a brief`);
  return found ?? BriefCard;
}
