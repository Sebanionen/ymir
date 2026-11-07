import { useEffect, type CSSProperties } from 'react';
import { useYmir } from '../state/store';
import { GATES, realmDef } from '../data/realms';
import { applyMeta } from '../data/metadata';
import { Rail } from './Rail';
import { Topbar } from './Topbar';
import { BottomStream } from './BottomStream';
import { MobileNav } from './MobileNav';
import { Fleet } from '../gates/Fleet';
import { Tasks } from '../gates/Tasks';
import { Well } from '../gates/Well';
import { Runes } from '../gates/Runes';
import { Reviews } from '../gates/Reviews';
import { Processes } from '../gates/Processes';
import { Files } from '../gates/Files';
import { OmniChat } from '../gates/OmniChat';
import { Forge } from '../gates/Forge';
import { Profile } from '../gates/Profile';
import { Runtime } from '../gates/Runtime';
import { Cron } from '../gates/Cron';
import { Sessions } from '../gates/Sessions';
import { Worktrees } from '../gates/Worktrees';
import { Trace } from '../gates/Trace';
import { Decisions } from '../gates/Decisions';
import { Stats } from '../gates/Stats';
import { Managandr } from '../gates/Managandr';
import { Snotra } from '../gates/Snotra';
import { Mail } from '../gates/Mail';
import { Skirnir } from '../gates/Skirnir';

function Stage() {
  const gate = useYmir((s) => s.gate);
  switch (gate) {
    case 'fleet':
      return <Fleet />;
    case 'tasks':
      return <Tasks />;
    case 'well':
      return <Well />;
    case 'runes':
      return <Runes />;
    case 'reviews':
      return <Reviews />;
    case 'processes':
      return <Processes />;
    case 'files':
      return <Files />;
    case 'chat':
      return <OmniChat />;
    case 'skirnir':
      return <Skirnir />;
    case 'forge':
      return <Forge />;
    case 'profile':
      return <Profile />;
    case 'runtime':
      return <Runtime />;
    case 'cron':
      return <Cron />;
    case 'sessions':
      return <Sessions />;
    case 'worktrees':
      return <Worktrees />;
    case 'trace':
      return <Trace />;
    case 'decisions':
      return <Decisions />;
    case 'stats':
      return <Stats />;
    case 'managandr':
      return <Managandr />;
    case 'snotra':
      return <Snotra />;
    case 'mail':
      return <Mail />;
    default:
      return <Fleet />;
  }
}

function PageFeed() {
  const streams = useYmir((s) => s.streams);
  const gate = useYmir((s) => s.gate);
  const items = (streams[gate]?.length ? streams[gate] : streams.all ?? []).slice(0, 3);
  return (
    <div className="page-feed" aria-live="polite" title="Live page feed — last 40">
      {items.length === 0 ? (
        <span className="pf-line dim">awaiting the first message…</span>
      ) : (
        items.map((e) => (
          <span className="pf-line" key={e.id}>
            <span className="pf-ts">
              {new Date(e.ts).toLocaleTimeString('en-GB', { hour12: false })}
            </span>
            <span className="pf-from">{e.from}</span>
            <span className="pf-msg" title={e.message}>
              {e.message}
            </span>
          </span>
        ))
      )}
    </div>
  );
}

export function Shell() {
  const realm = useYmir((s) => s.realm);
  const session = useYmir((s) => s.session);
  const density = useYmir((s) => s.density);
  const gate = useYmir((s) => s.gate);
  const streamHeight = useYmir((s) => s.streamHeight);

  const gateDef = GATES.find((g) => g.id === gate);
  const tenant = session?.tenants.find((t) => t.realm === realm);
  const def = realmDef(realm, tenant);

  useEffect(() => {
    applyMeta(gate, def.tenant);
  }, [gate, def.tenant]);

  return (
    <div
      className="shell"
      data-realm={realm}
      data-density={density}
      style={{ '--stream-h': `${streamHeight}px` } as CSSProperties}
    >
      <Rail />
      <Topbar />
      <main className="stage" role="main">
        <div className="stage-header-row">
          {gateDef ? (
            <div className="stage-deck">
              <span aria-hidden="true">{gateDef.glyph}</span> {gateDef.hint}
            </div>
          ) : (
            <span />
          )}
          <PageFeed />
        </div>
        <Stage />
      </main>
      <BottomStream />
      <MobileNav />
    </div>
  );
}
