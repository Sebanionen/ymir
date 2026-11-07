import { useCallback, useEffect, useMemo, useState } from 'react';
import CardView, { type CardShape, type NearCard, shapeOf } from './CardView';

/**
 * NearBoard — the near-loop screen: the three questions an agent's own loop cannot
 * answer about itself, on one page (plan 199).
 *
 *   the four dials   model · window and both compaction thresholds · the prompt
 *                    surfaces in force · the tool count by source
 *   what waits       the operator's queue — open PRs, the wake queue, mail drafts,
 *                    his own decisions — every card naming its shelf
 *   working now      the agents and panes standing, and the trees in flight
 *
 * Every number comes from a door: `/api/core-four`, `/api/context`, `/api/pending`
 * (all three carrying bin/seat/*.sh), `/api/agents`, `/api/worktrees`. This board
 * DECIDES NOTHING and WRITES NOTHING. A door that cannot answer says so in place; it
 * is never painted as a zero (the 2026-10-23 fault).
 *
 * Every block renders through ONE component, `CardView`, whose anatomy is the browser
 * client's of pi-durable-news-agent (see `vendor/jev/VENDOR.md`).
 */

interface CoreFour {
  model: string;
  context: { window: number; auto_compact_at: number; force_compact_at: number };
  prompt: { file: string; what: string; lines: number }[];
  tools: { extensions: number; mcp_servers: number; total: number };
}

interface PendingItem {
  kind: string;
  what: string;
  where: string;
  since: string;
}

interface LiveContext {
  session: string;
  model: string;
  turns: number;
  context_used: number;
  window: number;
  percent: number;
  remaining: number;
  compactions_seen: number;
  last_finish: string;
  verdict: string;
}

interface AgentRow {
  id: string;
  name: string;
  role: string;
  kind?: string;
  state?: string;
  pane?: string;
  task?: string;
  live?: boolean | null;
}

interface Worktree {
  id: string;
  branch: string;
  head: string;
}

/** One door, read honestly: its data, or the reason it could not answer. */
type Door<T> = { state: 'loading' } | { state: 'ok'; data: T } | { state: 'error'; error: string };

async function readDoor<T>(path: string): Promise<Door<T>> {
  try {
    const r = await fetch(path, { credentials: 'include', signal: AbortSignal.timeout(20_000) });
    if (!r.ok) return { state: 'error', error: `${path} answered HTTP ${r.status}` };
    const raw = await r.text();
    const d = JSON.parse(raw) as T & { error?: string };
    if (d && typeof d === 'object' && 'error' in d && d.error) {
      return { state: 'error', error: String(d.error) };
    }
    return { state: 'ok', data: d };
  } catch (e) {
    return { state: 'error', error: e instanceof Error ? e.message : String(e) };
  }
}

const num = (v: number | undefined): string => (typeof v === 'number' && v > 0 ? v.toLocaleString() : '—');

/** A card whose door did not answer. It names the door and the reason — an unread
 *  panel is a fact on the screen, never a silent empty block. */
function unreadCard(path: string, door: Door<unknown>): NearCard | undefined {
  if (door.state !== 'error') return undefined;
  return {
    id: `unread-${path}`,
    shape: 'brief',
    category: 'unread',
    title: `${path} did not answer`,
    lines: [{ kind: 'summary', text: door.error }],
    source: path,
    sourceHref: path,
    actions: [
      { label: 'open', kind: 'open', title: 'open the raw answer', href: path },
      { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => undefined },
    ],
    glyph: 'ᚼ',
  };
}

/** The two actions every card may carry. `open` is a door that really answers. */
const openDoor = (href: string) => ({ label: 'open', kind: 'open' as const, title: 'open the raw answer', href });

export default function NearBoard() {
  const [dials, setDials] = useState<Door<CoreFour>>({ state: 'loading' });
  const [live, setLive] = useState<Door<LiveContext>>({ state: 'loading' });
  const [pending, setPending] = useState<Door<{ count: number; items: PendingItem[] }>>({ state: 'loading' });
  const [agents, setAgents] = useState<Door<AgentRow[]>>({ state: 'loading' });
  const [trees, setTrees] = useState<Door<Worktree[]>>({ state: 'loading' });
  const [hidden, setHidden] = useState<Record<string, true>>({});
  const [at, setAt] = useState<number>(Date.now());

  // EACH DOOR FILLS ITS OWN BLOCK. A door may take seconds (it spawns a script), and
  // waiting on all five together would leave the whole page blank behind the slowest —
  // which is how a working board looks broken. readDoor never rejects: it answers with
  // an error card, so one door's silence can never take the others down.
  const read = useCallback(() => {
    setAt(Date.now());
    void readDoor<CoreFour>('/api/core-four').then(setDials);
    void readDoor<LiveContext>('/api/context').then(setLive);
    void readDoor<{ count: number; items: PendingItem[] }>('/api/pending').then(setPending);
    void readDoor<AgentRow[]>('/api/agents').then(setAgents);
    void readDoor<Worktree[]>('/api/worktrees').then(setTrees);
  }, []);

  useEffect(() => {
    read();
  }, [read]);

  const dismiss = useCallback((id: string) => setHidden((h) => ({ ...h, [id]: true })), []);

  /** The four dials, as four cards. */
  const dialCards = useMemo<NearCard[]>(() => {
    if (dials.state !== 'ok') {
      const u = unreadCard('/api/core-four', dials);
      return u ? [u] : [];
    }
    const c = dials.data;
    const ctx = live.state === 'ok' ? live.data : undefined;
    const cards: NearCard[] = [
      {
        id: 'dial-model',
        shape: 'headline',
        category: 'model',
        title: c.model,
        lines: [
          {
            kind: 'dek',
            text: 'the seat\'s agent, read from the harness settings and then the portable catalog',
          },
        ],
        source: 'core-four · settings.json',
        sourceHref: '/api/core-four',
        actions: [openDoor('/api/core-four'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('dial-model') }],
        glyph: 'ᚲ',
      },
      {
        id: 'dial-window',
        shape: 'brief',
        category: 'window',
        title: `${num(c.context.window)} tokens`,
        lines: [
          {
            kind: 'summary',
            text: `auto-compact at ${num(c.context.auto_compact_at)} · force-compact at ${num(c.context.force_compact_at)}`,
          },
          ...(ctx
            ? [
                {
                  kind: 'why' as const,
                  text: `this session: ${num(ctx.context_used)} used, ${ctx.percent}% of the window, ${num(
                    ctx.remaining,
                  )} left — ${ctx.verdict}`,
                },
              ]
            : []),
        ],
        source: 'core-four · agent-runtime.env',
        sourceHref: '/api/context',
        age: ctx ? `${ctx.turns} turns` : undefined,
        actions: [openDoor('/api/context'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('dial-window') }],
        glyph: 'ᚹ',
      },
      {
        id: 'dial-prompt',
        shape: 'brief',
        category: 'prompt',
        title: `${c.prompt.length} surfaces in force`,
        lines: [
          { kind: 'summary', text: c.prompt.map((p) => p.file).join(' · ') },
        ],
        source: 'AGENTS.md · RULES · the skill index',
        sourceHref: '/api/core-four',
        actions: [openDoor('/api/core-four'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('dial-prompt') }],
        glyph: 'ᛊ',
      },
      {
        id: 'dial-tools',
        shape: 'brief',
        category: 'tools',
        title: `${c.tools.total} doors`,
        lines: [
          { kind: 'summary', text: `${c.tools.extensions} extensions · ${c.tools.mcp_servers} MCP servers` },
        ],
        source: '.pi/extensions · mcp-adapter.json',
        sourceHref: '/api/core-four',
        actions: [openDoor('/api/core-four'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('dial-tools') }],
        glyph: 'ᛏ',
      },
    ];
    return cards;
  }, [dials, live, dismiss]);

  /** What waits on him, one card per line, each naming its shelf. */
  const pendingCards = useMemo<NearCard[]>(() => {
    if (pending.state !== 'ok') {
      const u = unreadCard('/api/pending', pending);
      return u ? [u] : [];
    }
    return pending.data.items.map((it, i) => {
      const id = `pending-${i}`;
      // A pull request and a decision are things to act on now; a wake line and a
      // draft are things to read. That is the only difference the two shapes carry.
      const shape: CardShape = shapeOf(
        it.kind === 'pull request' || it.kind === 'decision' ? 'signal_alert' : 'brief',
      );
      const pr = /#(\d+)/.exec(it.what);
      const href =
        it.kind === 'pull request' && pr ? `https://github.com/zerwiz/ymir/pull/${pr[1]}` : '/api/pending';
      return {
        id,
        shape,
        category: it.kind,
        title: it.what,
        lines:
          shape === 'signal_alert'
            ? [
                { kind: 'action', text: it.kind === 'pull request' ? 'review it, then seal the merge' : 'answer it' },
                { kind: 'why', text: it.where },
              ]
            : [{ kind: 'summary', text: it.where }],
        source: it.where,
        sourceHref: '/api/pending',
        age: it.since || undefined,
        actions: [
          { label: 'open', kind: 'open', title: `open ${it.kind}`, href },
          { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss(id) },
        ],
        glyph: 'ᚱ',
      };
    });
  }, [pending, dismiss]);

  /** Who is standing, and the trees in flight. */
  const liveCards = useMemo<NearCard[]>(() => {
    if (agents.state !== 'ok') {
      const u = unreadCard('/api/agents', agents);
      return u ? [u] : [];
    }
    const standing = agents.data.filter((a) => a.live === true || (a.pane ?? '') !== '');
    const cards: NearCard[] = standing.map((a) => {
      const id = `agent-${a.id}`;
      return {
        id,
        shape: shapeOf('brief'),
        category: a.kind ?? a.role,
        title: a.name,
        lines: [{ kind: 'summary', text: a.task || 'no task named' }],
        source: a.pane || 'no pane',
        sourceHref: '/api/agents',
        age: a.state,
        actions: [openDoor('/api/agents'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss(id) }],
        glyph: 'ᛉ',
      };
    });
    if (standing.length === 0) {
      cards.push({
        id: 'agent-none',
        shape: 'brief',
        category: 'agents',
        title: 'no pane answered',
        lines: [{ kind: 'summary', text: 'the roster is listed, but nobody is standing' }],
        source: '/api/agents',
        sourceHref: '/api/agents',
        actions: [openDoor('/api/agents'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('agent-none') }],
        glyph: 'ᛉ',
      });
    }
    if (trees.state === 'ok') {
      const inFlight = trees.data.filter((t) => t.id !== '(main)');
      cards.push({
        id: 'trees',
        shape: 'brief',
        category: 'worktrees',
        title: `${inFlight.length} trees in flight`,
        lines: [
          {
            kind: 'summary',
            text:
              inFlight.length === 0
                ? 'no isolated worktree is standing'
                : inFlight.slice(0, 10).map((t) => `${t.id} (${t.branch} @ ${t.head})`).join(' · ') +
                  (inFlight.length > 10 ? ` · and ${inFlight.length - 10} more` : ''),
          },
        ],
        source: 'git worktree list',
        sourceHref: '/api/worktrees',
        actions: [openDoor('/api/worktrees'), { label: 'dismiss', kind: 'dismiss', title: 'hide this card from this view only', onAct: () => dismiss('trees') }],
        glyph: 'ᛃ',
      });
    }
    return cards;
  }, [agents, trees, dismiss]);

  const shown = (cards: NearCard[]) => cards.filter((c) => !hidden[c.id]);

  const block = (kicker: string, title: string, sub: string, cards: NearCard[]) => {
    const visible = shown(cards);
    return (
      <section className="panel">
        <div className="panel-head">
          <div className="panel-title">
            <span className="glyph" aria-hidden="true">{kicker}</span>
            {title}
            <span className="mono dim" style={{ marginLeft: '.4rem', fontSize: '.72rem' }}>{visible.length}</span>
          </div>
        </div>
        <div className="panel-body">
          <p className="ssub" style={{ margin: '0 0 .8rem', fontSize: '.78rem' }}>{sub}</p>
          <div className="card-grid">
            {visible.map((c) => <CardView key={c.id} card={c} />)}
          </div>
        </div>
      </section>
    );
  };

  return (
    <>
      <header className="shead">
        <p className="skicker">
          <span aria-hidden="true">ᚱ</span> the near loop · what is blocked on you
        </p>
        <h1>the near loop</h1>
        <p className="ssub">
          the four dials · what waits on you · who is working now
          <span className="mono dim" style={{ marginLeft: '.6rem', fontSize: '.7rem' }}>
            read {new Date(at).toLocaleTimeString()}
          </span>
        </p>
        <button type="button" className="chip" onClick={() => void read()} style={{ marginTop: '.6rem' }}>
          re-read the doors
        </button>
      </header>

      {block('ᚲ', 'the four dials', 'the model, its window and both compaction thresholds, the prompt surfaces in force, the tools', dialCards)}
      {block('ᚹ', 'what waits on you', 'every line the record says is blocked on him, each card naming its shelf', pendingCards)}
      {block('ᛉ', 'working now', 'the agents and panes standing, and the trees in flight — read, never started from here', liveCards)}

      <p className="mono dim" style={{ fontSize: '.68rem', padding: '0 0 .6rem' }}>
        scores are jev's (Hype · Facts · Signal); a card with no classification says so rather than
        inventing a number
      </p>
    </>
  );
}
