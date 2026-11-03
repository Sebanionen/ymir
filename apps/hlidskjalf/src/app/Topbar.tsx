import { useEffect, useState } from 'react';
import { useYmir } from '../state/store';
import { WORKSPACES } from '../data/realms';
import { gateApi, type WorkspaceRow } from '../services/api';
import { AccentPicker } from '../components/AccentPicker';
import { AccountMenu } from '../components/AccountMenu';
import { HallsSwitcher, raise } from '../components/Halls';
import { SnotraLive } from '../components/SnotraLive';
import { Ward } from '../components/Ward';

export function Topbar() {
  const realm = useYmir((s) => s.realm);
  const setRealm = useYmir((s) => s.setRealm);
  const query = useYmir((s) => s.query);
  const setQuery = useYmir((s) => s.setQuery);
  const density = useYmir((s) => s.density);
  const setDensity = useYmir((s) => s.setDensity);
  const agents = useYmir((s) => s.agents);
  const [rows, setRows] = useState<WorkspaceRow[]>([]);
  const [adding, setAdding] = useState(false);

  const load = () => void gateApi.workspaces().then(setRows).catch(() => {});
  useEffect(load, [realm]);

  // The canonical workspaces come from the registry, never from retired tenants.
  const list = (rows.length
    ? rows.map((w) => ({ id: w.id, name: w.name }))
    : WORKSPACES.map((w) => ({ id: w.id, name: w.name ?? w.id }))
  ).map((w) => ({ ...w, glyph: WORKSPACES.find((x) => x.id === w.id)?.glyph ?? 'ᛗ' }));

  async function addWorkspace() {
    const name = window.prompt('New workspace name');
    if (!name) return;
    setAdding(true);
    const slug = name.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/(^-|-$)/g, '');
    try {
      await gateApi.createWorkspace({ name: slug, kind: 'personal', domains: ['life', 'development'] });
      load();
    } catch {
      /* gate API offline — still switch locally */
    }
    setAdding(false);
    if (slug) setRealm(slug);
  }

  return (
    <header className="topbar">
      <div className="ws-switch" role="group" aria-label="Workspace">
        {list.map((w) => (
          <button
            key={w.id}
            className={`ws-chip ${w.id === realm ? 'on' : ''}`}
            onClick={() => setRealm(w.id)}
            title={`Workspace · ${w.name ?? w.id}`}
          >
            <span className="house-glyph" aria-hidden="true">
              {w.glyph}
            </span>
            {w.name ?? w.id}
          </button>
        ))}
        <button className="ws-chip add" onClick={addWorkspace} disabled={adding} title="New workspace">
          ＋
        </button>
      </div>

      <div className="trace-chip" title="Fleet — nominal agents of connected">
        <span className="label">Fleet</span>
        <span
          className="value"
          style={{
            color: !agents.length
              ? undefined
              : agents.every((a) => a.status === 'nominal')
                ? 'var(--ymir-ok)'
                : agents.some((a) => a.status === 'nominal')
                  ? 'var(--ymir-warn)'
                  : 'var(--ymir-danger)',
          }}
        >
          {agents.filter((a) => a.status === 'nominal').length}/{agents.length}
        </span>
      </div>

      <label className="search">
        <span aria-hidden="true">ᛊ</span>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={`Search ${realm} workspace…`}
          aria-label="Workspace-scoped search"
        />
        <kbd>/</kbd>
      </label>

      <div className="topbar-spacer" />

      {/* The three halls: raise Hlidskjalf, Smíðja, or Sessrúmnir from anywhere.
          The same gate launcher the Omarchy key bindings and the chooser use. */}
      <HallsSwitcher current="hlidskjalf" />

      {/* The live tail: ONE click to start listening, one to close the book, and
          the words as they are spoken. A front for snotra-live.sh, never a
          second pipeline. */}
      <Ward />
      <button type="button" className="btn btn-sm" style={{ whiteSpace: 'nowrap', flexShrink: 0 }} onClick={() => useYmir.getState().setGate('skirnir')}
        title="Tala med assistenten – separat från Snotras mötesinspelning">Skírnir – Tala</button>
      <SnotraLive />

      {/* The Óðrerir Live Hall — the landing's live board, not one of the three
          apps: it opens as a page in its own tab. The rune is Othala, the hall. */}
      <button
        type="button"
        className="hall-btn"
        onClick={() => void raise('odrerir')}
        title="Óðrerir — the hall, in its own window (never a browser tab)"
      >
        <span className="glyph" aria-hidden="true">
          ᛟ
        </span>
        To the Hall
      </button>

      <AccentPicker />

      <button
        className="icon-btn"
        aria-pressed={density === 'compact'}
        onClick={() => setDensity(density === 'compact' ? 'comfortable' : 'compact')}
        title="Compact density"
      >
        {density === 'compact' ? 'ᛃ' : 'ᚼ'}
      </button>

      <AccountMenu />
    </header>
  );
}
