import { useEffect, useMemo, useState } from 'react';
import { skuldCall, skuldInit } from '../skuld';
import { esc, stBadge } from '../board';
import SkuldStatusChip from './SkuldStatus';

/**
 * PlansBoard — the roadmap, wearing the SAME anatomy and skin as the tickets
 * board (plan 55 law): the same table with status badges, a +new door that
 * reveals an inline panel, and a detail sheet with the plan's body and the
 * tickets it rides. Every plan is cut from the tickets — a plan's tickets must
 * exist before the plan does.
 */
function cells(line: string): { id: string; ns: string; st: string; tickets: string; title: string } {
  const c = line.split('|');
  return { id: c[0] ?? '', ns: c[1] ?? '', st: c[2] ?? '', tickets: c[3] ?? '', title: c.slice(4).join('|') };
}

export default function PlansBoard() {
  const [rows, setRows] = useState<string[]>([]);
  const [tickets, setTickets] = useState<string[]>([]);
  const [fStatus, setFStatus] = useState('');
  const [msg, setMsg] = useState<{ cls: string; text: string } | null>(null);
  const [newOpen, setNewOpen] = useState(false);
  const [detail, setDetail] = useState<string | null>(null);
  // WHICH DOOR ANSWERED. Skuld is the WRITE door (plans_create); the ledger of numbered
  // files is the READ source. Naming the door on screen is how the operator knows the
  // book is empty rather than the board being broken.
  const [source, setSource] = useState<'skuld' | 'ledger'>('skuld');
  const [files, setFiles] = useState<Record<string, string>>({});

  const statuses = useMemo(() => Array.from(new Set(rows.map((r) => cells(r).st))), [rows]);
  const visible = useMemo(
    () => rows.filter((r) => !fStatus || cells(r).st === fStatus),
    [rows, fStatus],
  );

  useEffect(() => {
    void (async () => {
      await skuldInit().catch(() => undefined);
      // only lines carrying the row shape (id|ns|state|…) count — a "no plans"
      // sentence is the EMPTY state, never a row (2026-09-24).
      const t = await skuldCall('tickets_list', { namespace: 'ymir' }).catch(() => '');
      setTickets((t.split('\n') ?? []).filter((r) => r.includes('|')));
      await loadPlans().catch(() => undefined);
    })();
    const onRetry = () => void loadPlans().catch(() => undefined);
    window.addEventListener('skuld:retry', onRetry);
    return () => window.removeEventListener('skuld:retry', onRetry);
  }, []);

  async function loadPlans() {
    // A board that says "no plans" while the ledger carries every plan as a numbered
    // file is the bug (2026-11-05). So an empty — or silent — Skuld is not the empty
    // state; it is the signal to read the record itself. The ledger's rows are shaped
    // exactly as Skuld answers, so ONE table serves both doors.
    let fromBook: string[] = [];
    try {
      const p = await skuldCall('plans_list', { namespace: 'ymir' });
      fromBook = (p.split('\n') ?? []).filter((r) => r.includes('|'));
    } catch {
      // a silent door falls through to the ledger, exactly as an empty one does
    }
    if (fromBook.length > 0) {
      setSource('skuld');
      setFiles({});
      setRows(fromBook);
      return;
    }
    try {
      const r = await fetch('/api/plans', { credentials: 'include', signal: AbortSignal.timeout(20_000) });
      const d = (await r.json()) as {
        plans?: { n: number; slug: string; state: string; title: string; file: string }[];
      };
      const list = (d.plans ?? []).filter((p) => Number.isFinite(p.n));
      const map: Record<string, string> = {};
      for (const p of list) map[String(p.n)] = p.file;
      setSource('ledger');
      setFiles(map);
      setRows(list.map((p) => `${p.n}|ymir|${p.state}|-|${p.title}`));
    } catch {
      setSource('ledger');
      setFiles({});
      setRows([]);
    }
  }

  const d = detail ? detail.split('|') : [];

  return (
    <>
      <header className="shead">
        <p className="skicker"><span aria-hidden="true">ᛚ</span> the plans · the roadmap</p>
        <h1>the roadmap</h1>
        <p className="ssub">every plan cut from the tickets — its body, its state, the tickets it rides</p>
      </header>

      <section className="panel">
        <div className="panel-head">
          <div className="panel-title">
            <span className="glyph" aria-hidden="true">ᛚ</span>
            the plans <span className="mono dim" style={{ marginLeft: '.4rem', fontSize: '.72rem' }}>{visible.length}</span>
          </div>
          <button type="button" className="td-act" onClick={() => setNewOpen((v) => !v)}>+ new plan</button>
          <span className="mono dim" style={{ fontSize: '.68rem' }}>
            {source === 'ledger' ? `the ledger · ${rows.length} files` : 'skuld · the book'}
          </span>
          <SkuldStatusChip />
        </div>
        <div className="panel-body flush">
          <div className="filters">
            <select value={fStatus} onChange={(e) => setFStatus(e.target.value)}>
              <option value="">state: any</option>
              {statuses.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </div>

          {newOpen && (
            <div style={{ padding: '.7rem .9rem', borderBottom: '1px solid var(--hall-steel)' }}>
              <form
                className="book-form"
                onSubmit={async (e) => {
                  e.preventDefault();
                  const f = new FormData(e.currentTarget);
                  const picked = Array.from(e.currentTarget.querySelectorAll<HTMLOptionElement>('#ticket-pick option:checked')).map((o) => parseInt(o.value, 10));
                  const r = await skuldCall('plans_create', {
                    namespace: f.get('namespace'),
                    title: f.get('title'),
                    body: f.get('body'),
                    tickets: picked,
                  });
                  setMsg({ cls: /created/.test(r) ? 'ok' : 'err', text: r });
                  if (/created/.test(r)) {
                    setNewOpen(false);
                    await loadPlans();
                  }
                }}
              >
                <div className="book-row">
                  <select name="namespace" defaultValue="ymir" style={{ background: 'var(--hall-bg)', color: 'var(--hall-bone)', border: '1px solid var(--hall-steel)', borderRadius: 2, padding: '.5rem .6rem' }}>
                    <option>ymir</option>
                  </select>
                </div>
                <input name="title" placeholder="plan title" required />
                <textarea name="body" rows={4} placeholder="the plan's body — anything plan-sized is written first" required />
                <div className="book-row" style={{ alignItems: 'flex-start' }}>
                  <select name="tickets" id="ticket-pick" multiple size={6} style={{ minHeight: '7.5rem', background: 'var(--hall-bg)', color: 'var(--hall-bone)', border: '1px solid var(--hall-steel)', borderRadius: 2, padding: '.3rem .4rem', font: 'inherit' }}>
                    {tickets.length === 0 && <option disabled>reading the tickets…</option>}
                    {tickets.map((t) => {
                      const c = t.split('|');
                      return <option key={c[0]} value={c[0]}>{c[2]}/{c[1]}  {c[5]}</option>;
                    })}
                  </select>
                  <span className="mono dim" style={{ fontSize: '.68rem' }}>press to pick the tickets the plan rides (multiselect)</span>
                  <button type="submit">cut the plan</button>
                </div>
                {msg && <div className={`msg ${msg.cls}`}>{msg.text}</div>}
              </form>
            </div>
          )}

          <table className="tick-table">
            <thead>
              <tr><th>ID</th><th>title</th><th>state</th><th>rides</th></tr>
            </thead>
            <tbody>
              {visible.length === 0 && (
                <tr>
                  <td colSpan={4} className="dim" style={{ padding: '.6rem .7rem' }}>
                    {source === 'ledger'
                      ? 'the ledger answered no plans — no numbered file sits in the ledger either'
                      : 'no plans cut yet — the tickets board waits at #/tickets'}
                  </td>
                </tr>
              )}
              {visible.map((r) => {
                const c = cells(r);
                return (
                  <tr
                    key={c.id}
                    onClick={async () => {
                      // A ledger row has no ticket-backed body to fetch: the file IS the
                      // plan, and the sheet names it rather than pretending to read it.
                      if (source === 'ledger') {
                        setDetail(r);
                        return;
                      }
                      const raw = await skuldCall('plans_get', { id: parseInt(c.id, 10) });
                      setDetail(raw);
                    }}
                  >
                    <td className="mono dim">#{esc(c.id)}</td>
                    <td>{esc(c.title)}</td>
                    <td dangerouslySetInnerHTML={{ __html: stBadge(c.st) }} />
                    <td className="mono dim">{esc(c.tickets || '-')}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      {detail && d.length >= 3 && (
        <div className="ticket-detail" role="dialog" aria-modal="true">
          <div className="td-backdrop" onClick={() => setDetail(null)} />
          <div className="td-panel">
            <div className="td-head" style={{ display: 'flex', alignItems: 'center' }}>
              <span className="mono dim">plan #{esc(d[0])} · {esc(d[1])} · {esc(d[2] ?? '')}</span>
              <button type="button" className="td-close" onClick={() => setDetail(null)}>✕</button>
            </div>
            <h2>{esc(cells(detail).title)}</h2>
            <p className="td-desc">{esc(d[3] ?? '')}</p>
            <div className="td-row">
              <span className="mono dim">rides tickets: {esc(cells(detail).tickets || '-')}</span>
            </div>
            {source === 'ledger' && (
              <div className="td-row">
                <span className="mono dim">
                  the plan is the file: {esc(files[String(d[0])] ?? '(the ledger did not name it)')}
                </span>
              </div>
            )}
          </div>
        </div>
      )}
    </>
  );
}