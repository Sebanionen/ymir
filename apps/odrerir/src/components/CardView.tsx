import type { HfsCategory, HfsResult } from '../vendor/jev/policy';

/**
 * CardView — ONE card anatomy, re-implemented in React from pi-durable-news-agent's
 * browser client (MIT; see `vendor/jev/VENDOR.md`). Its components are Vue and are
 * NOT imported; the SHAPE of a card is, because the near-loop page is meant to look
 * like a sibling of that app rather than a new language:
 *
 *   title · category chip · score + confidence · source + age · two actions
 *
 * A card is one interface, whatever it carries — a pending item, a dial, an agent, a
 * plan. The five shapes are the five the news client renders; anything else falls back
 * to `brief`, exactly as its own registry does for an unknown component.
 *
 * The scores are jev's vocabulary, never ours: `HfsResult` comes from the vendored
 * policy, and a card with no classification says "Not ranked yet" — it never invents a
 * number to fill the slot.
 */

export const CARD_SHAPES = ['headline', 'brief', 'signal_alert', 'fact_check', 'hype_watch'] as const;
export type CardShape = (typeof CARD_SHAPES)[number];

/** What a shape's body may say. The kind decides the weight, so the five shapes differ
 *  by emphasis and structure without five separate components to drift apart. */
export type CardLineKind = 'dek' | 'summary' | 'action' | 'why' | 'verdict' | 'evidence';

export interface CardLine {
  text: string;
  kind: CardLineKind;
}

/** open · dismiss — the two actions every card may carry. `href` opens a door that
 *  really exists; `onAct` acts in this page only. A card that has neither carries
 *  none: a button that does nothing is worse than no button. */
export interface CardAction {
  label: string;
  title: string;
  kind: 'open' | 'dismiss';
  href?: string;
  onAct?: () => void;
}

export interface NearCard {
  id: string;
  shape: CardShape;
  /** the category chip — the fixed word for what this card is */
  category: string;
  title: string;
  lines: CardLine[];
  /** where it came from: the shelf, the file, the door */
  source: string;
  sourceHref?: string;
  age?: string;
  /** jev's ranking, when a classification exists */
  hfs?: HfsResult;
  actions: CardAction[];
  glyph?: string;
}

/** An unknown component renders as `brief` and says so, as the news registry does. */
export function shapeOf(raw: string): CardShape {
  if ((CARD_SHAPES as readonly string[]).includes(raw)) return raw as CardShape;
  if (typeof console !== 'undefined') console.warn(`Unknown card shape ${raw}, rendering a brief`);
  return 'brief';
}

const HFS_NAMES: Record<HfsCategory, string> = { signal: 'Signal', facts: 'Facts', hype: 'Hype' };

/** Score and confidence, in the pills the news client uses: each chip fills to its
 *  score in its own category colour, and the primary category is the emphasised one. */
function HfsChips({ hfs }: { hfs?: HfsResult }) {
  if (!hfs) return <span className="hfs pending">Not ranked yet</span>;
  return (
    <div className="hfs" aria-label={`Ranked by jev: ${hfs.ranked.map((r) => `${HFS_NAMES[r.category]} ${r.score}`).join(', ')}`}>
      {hfs.ranked.map((r, i) => (
        <span
          key={r.category}
          className={`hfs-chip ${r.category}${i === 0 ? ' primary' : ''}${hfs.labels.includes(r.category) ? ' label' : ''}`}
          style={{ ['--fill' as string]: `${Math.max(0, Math.min(100, r.score))}%` }}
          title={`${HFS_NAMES[r.category]} ${r.score} of 100, confidence ${Math.round(r.confidence * 100)} percent, ranked by jev`}
        >
          {HFS_NAMES[r.category]} <strong>{r.score}</strong>
        </span>
      ))}
      {hfs.suspectCombo && (
        <span className="hfs-warn" title="Hype and signal without facts">
          check it
        </span>
      )}
    </div>
  );
}

/** The shape's own body. Five cases, one place — so no shape can drift from another. */
function Body({ card }: { card: NearCard }) {
  const kinds = (...want: CardLineKind[]) =>
    card.lines.filter((l) => want.includes(l.kind));
  switch (card.shape) {
    case 'headline':
      return (
        <>
          <h3 className="card-title big">{card.title}</h3>
          {kinds('dek', 'summary').map((l, i) => (
            <p key={i} className="card-dek">{l.text}</p>
          ))}
        </>
      );
    case 'signal_alert':
      return (
        <>
          <h3 className="card-title">{card.title}</h3>
          {kinds('action').map((l, i) => (
            <p key={i} className="card-action">{l.text}</p>
          ))}
          {kinds('why', 'summary', 'dek').map((l, i) => (
            <p key={i} className="card-body muted">{l.text}</p>
          ))}
        </>
      );
    case 'fact_check':
      return (
        <>
          <h3 className="card-title">{card.title}</h3>
          {kinds('verdict').map((l, i) => (
            <p key={i} className="verdict">{l.text}</p>
          ))}
          <ul className="icon-list">
            {kinds('evidence', 'why', 'summary').map((l, i) => (
              <li key={i}>{l.text}</li>
            ))}
          </ul>
        </>
      );
    case 'hype_watch':
      return (
        <>
          <h3 className="card-title">{card.title}</h3>
          {kinds('why', 'verdict').map((l, i) => (
            <p key={i} className="card-action">{l.text}</p>
          ))}
          {kinds('dek', 'summary').map((l, i) => (
            <p key={i} className="card-body muted">{l.text}</p>
          ))}
        </>
      );
    case 'brief':
    default:
      return (
        <>
          <h3 className="card-title">{card.title}</h3>
          {kinds('summary', 'dek', 'why').map((l, i) => (
            <p key={i} className="card-dek">{l.text}</p>
          ))}
        </>
      );
  }
}

export default function CardView({ card }: { card: NearCard }) {
  return (
    <article className="card" data-card-id={card.id} data-shape={card.shape} data-category={card.category}>
      <div className="card-media" aria-hidden="true">{card.glyph ?? 'ᛜ'}</div>
      <div className="card-content">
        <div className="card-meta">
          {card.sourceHref ? (
            <a className="source" href={card.sourceHref} target="_blank" rel="noopener" title={`Open ${card.source}`}>
              {card.source}
            </a>
          ) : (
            <span className="source" title={card.source}>{card.source}</span>
          )}
          {card.age && <span className="time">{card.age}</span>}
          <span className="timeline-chip">{card.category}</span>
          <span className="grow" />
        </div>
        <div className="card-main">
          <Body card={card} />
        </div>
        <div className="card-foot">
          <HfsChips hfs={card.hfs} />
          <span className="grow" />
          {card.actions.map((a) =>
            a.href ? (
              <a
                key={a.label}
                className={`fb ${a.kind}`}
                href={a.href}
                target="_blank"
                rel="noopener"
                title={a.title}
              >
                {a.label}
              </a>
            ) : (
              <button
                key={a.label}
                type="button"
                className={`fb ${a.kind}`}
                title={a.title}
                onClick={a.onAct}
              >
                {a.label}
              </button>
            ),
          )}
        </div>
      </div>
    </article>
  );
}
