import { useEffect, useState } from 'react';
import EmberBackground from './components/EmberBackground';
import LivehallBoard from './components/LivehallBoard';
import NearBoard from './components/NearBoard';
import TicketsBoard from './components/TicketsBoard';
import PlansBoard from './components/PlansBoard';

/**
 * Óðrerir — the Live Hall, a Hlidskjalf-type app (plan 55): the ember hearth,
 * the translucent panels, the halls buttons in the same design as the high
 * seat. Three doors — `#/` the hall, `#/tickets`, `#/plans` — and the raise
 * buttons that call the gate through the vite /api proxy (same-origin, so the
 * local desktop seat is trusted; 2026-09-24).
 */

// The three halls, one hinge: these buttons raise the other Ymir windows
// through the Hlidskjalf gate, exactly as the high seat's own switcher does.
const HALLS = [
  { id: 'hlidskjalf', glyph: 'ᚺ', name: 'Hlidskjalf' },
  { id: 'smidja', glyph: 'ᛊ', name: 'Smíðja' },
  { id: 'sessrumnir', glyph: 'ᛋ', name: 'Sessrúmnir' },
  { id: 'odrerir', glyph: 'ᛟ', name: 'Óðrerir' },
];

function isDesktopSeat(): boolean {
  const w = window as unknown as { ymirDesktop?: { desktop?: boolean } };
  return w.ymirDesktop?.desktop === true;
}

function raiseHall(id: string) {
  if (id === 'odrerir') return; // you are here
  // Same-origin: the vite proxy sends /api to the Hlidskjalf gate, so the
  // desktop seat's marker rides without a CORS wall.
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (isDesktopSeat()) headers['x-ymir-surface'] = 'desktop';
  fetch('/api/desktop', {
    method: 'POST',
    headers,
    credentials: 'include',
    body: JSON.stringify({ view: id }),
    signal: AbortSignal.timeout(8000),
  }).catch(() => undefined); // a quiet gate never breaks the board
}

type View = 'hall' | 'tickets' | 'plans' | 'near';
function viewFromHash(): View {
  const h = window.location.hash.replace(/^#\/?/, '');
  if (h === 'tickets') return 'tickets';
  if (h === 'plans') return 'plans';
  if (h === 'near') return 'near';
  return 'hall';
}

const DOORS: { id: View; label: string }[] = [
  { id: 'hall', label: 'the board' },
  { id: 'near', label: 'the near loop' },
  { id: 'tickets', label: 'the tickets' },
  { id: 'plans', label: 'the plans' },
];

export default function App() {
  const [view, setView] = useState<View>(viewFromHash);
  useEffect(() => {
    const onHash = () => setView(viewFromHash());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  return (
    <>
      <EmberBackground />
      <div className="hall-top">
        <span className="hall-mast">
          <span aria-hidden="true">ᛟ</span> YMIR · ÓÐRERIR — THE LIVE HALL
        </span>
        <span className="hall-links">
          {DOORS.map((d) => (
            <a
              key={d.id}
              className="hall-back"
              href={`#/${d.id == null ? '' : d.id === 'hall' ? '' : d.id}`}
              data-here={view === d.id ? '1' : undefined}
            >
              {d.label}
            </a>
          ))}
        </span>
        <span className="hall-btns" role="group" aria-label="the halls">
          {HALLS.map((h) => (
            <button
              key={h.id}
              type="button"
              className="hall-btn"
              aria-pressed={h.id === 'odrerir'}
              onClick={() => raiseHall(h.id)}
            >
              <span aria-hidden="true">{h.glyph}</span>
              {h.name}
            </button>
          ))}
        </span>
      </div>
      <main className={view === 'hall' ? 'hall-stage' : 'hall-wrap'}>
        {view === 'hall' ? (
          <LivehallBoard />
        ) : view === 'tickets' ? (
          <TicketsBoard />
        ) : view === 'plans' ? (
          <PlansBoard />
        ) : (
          <NearBoard />
        )}
      </main>
    </>
  );
}