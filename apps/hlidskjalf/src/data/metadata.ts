import type { GateId } from '../types';

export interface PageMeta {
  title: string;
  description: string;
}

export const SITE = {
  name: 'Ymir · Hlidskjalf',
  url: 'https://ymir.local',
  image: '/og.png',
  twitter: '@ymir',
};

/** Smíðja's eye — the trace visualizer. The API on :8437 also serves the built UI. */
export const VISUALIZER_URL =
  (import.meta.env.VITE_VISUALIZER_URL as string | undefined) ?? 'http://127.0.0.1:8437';

/**
 * The Óðrerir Live Hall — the landing's carved stone/bronze board. It is not one
 * of the three apps (those the gate raises), so its door is a plain page in a new
 * tab. On this machine the hall answers on :4322; anywhere else, the public hall.
 */
export const HALL_URL = (() => {
  const override = import.meta.env.VITE_HALL_URL as string | undefined;
  if (override) return override;
  const host = typeof window === 'undefined' ? '' : window.location.host;
  const local = host.startsWith('localhost') || host.startsWith('127.0.0.1');
  return local ? 'http://localhost:4322' : 'https://hall.ymir.zerwiz.org';
})();

/** Per-gate metadata — every view is a page and declares its own story. */
export const GATE_META: Record<GateId, PageMeta> = {
  skirnir: { title: 'Skírnir – Tala', description: 'Talk with the assistant locally, with your microphone permission and approved knowledge.' },
  fleet: {
    title: 'Fleet',
    description:
      'Agent Cards, live status, and A2A hops across the realm — the forge stays hot.',
  },
  tasks: {
    title: 'Tasks',
    description:
      'The A2A lifecycle board: SUBMITTED → WORKING → terminal states that never restart.',
  },
  well: {
    title: 'The Well',
    description:
      'Mimirsbrunn recall, episodes, and timeline. Drink before you act, water it after.',
  },
  runes: {
    title: 'Runes',
    description:
      'The append-only ledger — every significant action carved once, checksum-chained.',
  },
  reviews: {
    title: 'Glitnir · Reviews',
    description:
      'Human-in-the-loop pull-request reviews. Mjollnir strikes and returns, but never force-merges.',
  },
  processes: {
    title: 'Valhalla',
    description:
      'Process supervision across PM2, Docker, and systemd — dead daemons brought back.',
  },
  files: {
    title: 'Skrymir',
    description:
      'The giant’s hand — a realm-scoped file browser served through Bifrost.',
  },
  chat: {
    title: 'OmniChat',
    description:
      'Speak with Kaia, the oracle by the well. She recalls before she dispatches.',
  },
  forge: {
    title: 'The Forge',
    description:
      'Create and edit Eindri agents and skills — every worker earns a mythological name that matches its craft.',
  },
  profile: {
    title: 'Profile',
    description:
      'Personal and company settings — your accent, your tenants’ colours, the house seal, and members.',
  },
  runtime: {
    title: 'Runtime',
    description:
      'The Sága session digest — lock, bridge, wakes, fleet, context, and the Nornir start, as injected at session open.',
  },
  cron: {
    title: 'Cron · Nornir',
    description:
      'The scheduled jobs of the Nornir, their times, and their health.',
  },
  sessions: {
    title: 'Sessions · Smiðja',
    description:
      'Every factory run — phases, status, tokens, and cost — read from the smithy’s own smidja.db.',
  },
  worktrees: { title: 'Worktrees', description: 'Yggdrasil isolated worktrees — id, branch, owning agent, head.' },
  trace: {
    title: 'Trace',
    description:
      'A run’s lanes, phases, agents, and tool calls; the span-nested execution path.',
  },
  decisions: {
    title: 'Decisions',
    description:
      'Failures grouped by phase and model, with the fix to apply — what to change to make the system work.',
  },
  stats: {
    title: 'Stats',
    description:
      'Runs, tokens, and cost — totals and by chain and model.',
  },
  managandr: {
    title: 'Mánagandr',
    description:
      'The read calendar: the month grid, the Nornir collision hairlines, the smithy\u2019s lanes, and the well\u2019s density. No write path.',
  },
  snotra: {
    title: 'Snotra',
    description:
      'The meeting record: the shelf, the record, the participants, and the follow-up draft. Prepare, approve, send — never edit.',
  },
  mail: {
    title: 'Gná',
    description:
      'The one mail desk: what needs you, what is unsure, what waits on an answer, and what was recorded. Read-only — Gná drafts, the Allfather sends.',
  },
};

function setMeta(attr: 'name' | 'property', key: string, content: string): void {
  let el = document.head.querySelector<HTMLMetaElement>(`meta[${attr}="${key}"]`);
  if (!el) {
    el = document.createElement('meta');
    el.setAttribute(attr, key);
    document.head.appendChild(el);
  }
  el.setAttribute('content', content);
}

/** Apply title + description + social tags for the active gate. */
export function applyMeta(gate: GateId, tenant: string): void {
  const m = GATE_META[gate] ?? GATE_META.fleet;
  const title = `${m.title} · ${tenant} · ${SITE.name}`;
  const url = `${SITE.url}/#/${gate}`;

  document.title = title;

  setMeta('name', 'description', m.description);
  setMeta('property', 'og:site_name', SITE.name);
  setMeta('property', 'og:type', 'website');
  setMeta('property', 'og:title', title);
  setMeta('property', 'og:description', m.description);
  setMeta('property', 'og:image', SITE.image);
  setMeta('property', 'og:url', url);
  setMeta('name', 'twitter:card', 'summary_large_image');
  setMeta('name', 'twitter:site', SITE.twitter);
  setMeta('name', 'twitter:title', title);
  setMeta('name', 'twitter:description', m.description);
  setMeta('name', 'twitter:image', SITE.image);
}
