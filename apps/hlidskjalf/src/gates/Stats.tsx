import { useState } from 'react';
import { useYmir } from '../state/store';
import { MetricTile } from '../components/MetricTile';

const pct = (n: number) => `${(n * 100).toFixed(1)}%`;
const M = (n: number) => `${(n / 1_000_000).toFixed(3)}M`;
const usd = (n: number) => `$${n.toFixed(4)}`;
const usd2 = (n: number) => `$${n.toFixed(2)}`;

/** Stats — 1:1 with the Smiðja visualizer: runs, token optimization,
 *  local-vs-online providers, commercial comparison, by chain & workflow. */
export function Stats() {
  const stats = useYmir((s) => s.smidjaStats);
  const [selectedModel, setSelectedModel] = useState('');
  const harnessUsage = useYmir((st) => st.usage);

  // THE GATE REPORTS THE HARNESSES (pi + opencode). The smithy keeps its own.
  const harness = harnessUsage?.gate ?? null;

  const totals = harness?.totals ?? stats?.totals ?? { runs: 0, success: 0, fail: 0, running: 0, tokens: 0, cost: 0 };
  const usage = harness?.usage ?? stats?.usage ?? { input: 0, output: 0, cache_read: 0, cache_write: 0, total: 0 };
  const providers = harness?.providers ?? stats?.providers ?? {
    local: { events: 0, sessions: 0, tokens: 0, cost: 0, input: 0, output: 0, cache_read: 0 },
    online: { events: 0, sessions: 0, tokens: 0, cost: 0, input: 0, output: 0, cache_read: 0 },
    per_model: [],
  };
  const catalog = stats?.vendor_catalog ?? [];
  const byChain = harness?.by_chain ?? stats?.by_chain ?? [];
  const byModel = harness?.by_model ?? stats?.by_model ?? [];
  const chosen =
    catalog.find((m) => m.id === selectedModel) ?? catalog[0] ?? null;

  const successRate = totals.runs ? pct(totals.success / totals.runs) : '—';
  const providerShare = (kind: 'local' | 'online') => {
    const total = providers.local.tokens + providers.online.tokens;
    return total ? pct(providers[kind].tokens / total) : '—';
  };

  const tierGroups = [1, 2, 3].map((t) => ({
    label: catalog.find((m) => m.tier === t)?.tier_label ?? `Tier ${t}`,
    models: catalog.filter((m) => m.tier === t),
  }));

  return (
    <>
      <div className="stage-head">
        <div>
          <h1 className="stage-title">Statistics</h1>
          <p className="stage-deck">Every harness run — pi &amp; opencode · tokens, cost, savings</p>
        </div>
      </div>

      {harnessUsage && (
        <section className="panel" style={{ marginTop: 12, padding: 12 }}>
          <h2 style={{ fontSize: 13, opacity: 0.8, margin: '0 0 6px' }}>
            Harnesses · opencode &amp; pi
          </h2>
          <p className="pf-line dim" style={{ margin: '0 0 8px' }}>
            {harnessUsage.totals.messages.toLocaleString()} messages ·{' '}
            {(harnessUsage.totals.input / 1e6).toFixed(1)}M in / {(harnessUsage.totals.output / 1e6).toFixed(1)}M out ·
            cache-hit {(harnessUsage.totals.cache_hit_ratio * 100).toFixed(1)}% · last {harnessUsage.window_days} days
          </p>
          <table className="pf-table">
            <thead>
              <tr><th>Model</th><th>Source</th><th>Messages</th><th>In</th><th>Out</th></tr>
            </thead>
            <tbody>
              {harnessUsage.by_model.slice(0, 8).map((m) => (
                <tr key={m.source + m.model}>
                  <td>{m.model}</td>
                  <td>{m.source}</td>
                  <td>{m.messages.toLocaleString()}</td>
                  <td>{(m.input / 1e6).toFixed(1)}M</td>
                  <td>{(m.output / 1e6).toFixed(1)}M</td>
                </tr>
              ))}
              {harnessUsage.by_model.length === 0 && (
                <tr><td colSpan={5} style={{ padding: 6, opacity: 0.6 }}>no harness usage in the window</td></tr>
              )}
            </tbody>
          </table>
        </section>
      )}

      <section className="panel" style={{ marginBottom: 'var(--ymir-space-4)' }}>
        <div className="panel-head">
          <div className="panel-title"><span className="glyph" aria-hidden="true">ᛗ</span> Runs</div>
        </div>
        <div className="metric-grid">
          <MetricTile label="Total runs" value={totals.runs} />
          <MetricTile label="Success" value={totals.success} tone="var(--ymir-ok)" />
          <MetricTile label="Fail" value={totals.fail} tone="var(--ymir-danger)" />
          <MetricTile label="Running" value={totals.running} tone="var(--ymir-cyan-1)" />
          <MetricTile label="Success rate" value={successRate} />
          <MetricTile label="Tokens" value={totals.tokens.toLocaleString()} />
          <MetricTile label="Actual cost" value={usd(totals.cost)} tone="var(--ymir-warn)" />
        </div>
      </section>

      <section className="panel" style={{ marginBottom: 'var(--ymir-space-4)' }}>
        <div className="panel-head">
          <div className="panel-title"><span className="glyph" aria-hidden="true">ᚦ</span> Token optimization <span className="dim">(LLM token metrics)</span></div>
        </div>
        <div className="metric-grid">
          <MetricTile label="Uncached input" value={M(usage.input)} />
          <MetricTile label="Output" value={M(usage.output)} />
          <MetricTile label="Cache read" value={M(usage.cache_read)} tone="var(--ymir-ok)" />
          <MetricTile label="Cache write" value={M(usage.cache_write)} />
          <MetricTile label="Total tokens" value={M(usage.total)} />
          {/* ONE formula for the cache ratio: the harness aggregate when it is present,
              the smithy's own when it is not. Two formulas gave 98.3% and 0.0% in the
              same panel (2026-11-05). */}
          <MetricTile
            label="Cache-hit ratio"
            value={pct(harnessUsage?.totals?.cache_hit_ratio ?? stats?.cache_hit_ratio ?? 0)}
            tone="var(--ymir-ok)"
          />
          <MetricTile label="Avg CHR / run" value={pct(stats?.avg_cache_hit_per_run ?? harnessUsage?.totals?.cache_hit_ratio ?? 0)} />
        </div>
      </section>

      <section className="panel" style={{ marginBottom: 'var(--ymir-space-4)' }}>
        <div className="panel-head">
          <div className="panel-title">
            <span className="glyph" aria-hidden="true">ᛋ</span> Model provider <span className="dim">(local = own hardware vs online cloud APIs)</span>
          </div>
        </div>
        <div className="metric-grid">
          <MetricTile label={`Local tokens · ${providerShare('local')}`} value={M(providers.local.tokens)} tone="var(--ymir-ok)" />
          <MetricTile label={`Online tokens · ${providerShare('online')}`} value={M(providers.online.tokens)} tone="var(--ymir-danger)" />
          <MetricTile label="Local calls" value={providers.local.events} tone="var(--ymir-ok)" />
          <MetricTile label="Online calls" value={providers.online.events} tone="var(--ymir-danger)" />
          <MetricTile label="Local cost" value={usd(providers.local.cost)} tone="var(--ymir-ok)" />
          <MetricTile label="Online cost" value={usd(providers.online.cost)} tone="var(--ymir-danger)" />
          <MetricTile label="Local sessions" value={providers.local.sessions} tone="var(--ymir-ok)" />
          <MetricTile label="Online sessions" value={providers.online.sessions} tone="var(--ymir-danger)" />
        </div>
        <div className="split-bar" title={`local ${providerShare('local')} / online ${providerShare('online')}`}>
          <div className="split-local" style={{ width: providerShare('local') }} />
          <div className="split-online" style={{ width: providerShare('online') }} />
        </div>
        <div className="split-legend">
          <span><i className="dot dot-local" /> local (pi, LM Studio, Ollama) — {providerShare('local')}</span>
          <span><i className="dot dot-online" /> online (cloud APIs) — {providerShare('online')}</span>
        </div>
        {providers.per_model.length ? (
          <table className="data-table">
            <thead>
              <tr><th>Model</th><th>Agent</th><th>Kind</th><th>Cells</th><th>Tokens</th><th>Cost</th></tr>
            </thead>
            <tbody>
              {providers.per_model.map((m) => (
                <tr key={m.model}>
                  <td className="mono">{m.model}</td>
                  <td className="muted">{m.coding_agent ?? '—'}</td>
                  <td><span className={`badge ${m.kind}`}>{m.kind}</span></td>
                  <td className="num">{m.events}</td>
                  <td className="num">{M(m.tokens)}</td>
                  <td className="num">{usd(m.cost)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : null}
      </section>

      <section className="panel" style={{ marginBottom: 'var(--ymir-space-4)' }}>
        <div className="panel-head">
          <div className="panel-title">
            <span className="glyph" aria-hidden="true">ᚠ</span> Commercial comparison <span className="dim">(what these runs would cost on vendors, with caching)</span>
          </div>
        </div>
        <div className="row" style={{ gap: 10, marginBottom: 12, flexWrap: 'wrap' }}>
          <label className="field" style={{ minWidth: 300 }}>
            <span>Model</span>
            <select
              id="vendor-model"
              value={chosen?.id ?? ''}
              onChange={(e) => setSelectedModel(e.target.value)}
            >
              {tierGroups.map((g) => (
                <optgroup key={g.label} label={g.label}>
                  {g.models.map((m) => (
                    <option key={m.id} value={m.id}>#{m.rank} {m.name} — {m.provider}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </label>
          {chosen ? (
            <span className="dim" style={{ fontSize: 12 }}>
              rates: ${chosen.input_price.toFixed(2)} in / ${chosen.cache_price.toFixed(2)} cache / ${chosen.output_price.toFixed(2)} out per 1M
            </span>
          ) : null}
        </div>
        {chosen ? (
          <table className="data-table">
            <thead>
              <tr><th>Model</th><th>Cached cost</th><th>Total cost</th><th>Savings vs actual</th><th>Saved</th></tr>
            </thead>
            <tbody>
              <tr>
                <td><b>{chosen.name}</b> <span className="dim">· {chosen.provider} · #{chosen.rank}</span></td>
                <td className="num">{usd2(chosen.cached_cost)}</td>
                <td className="num">{usd2(chosen.total_cost)}</td>
                <td className="num" style={{ color: 'var(--ymir-ok)' }}>+{usd2(chosen.savings)}</td>
                <td className="num" style={{ color: 'var(--ymir-ok)' }}>{pct(chosen.savings_pct)}</td>
              </tr>
            </tbody>
          </table>
        ) : null}
      </section>

      <div className="gate-grid cols-2">
        <section className="panel">
          <div className="panel-head">
            <div className="panel-title"><span className="glyph" aria-hidden="true">ᛚ</span> By chain</div>
          </div>
          <div className="panel-body flush">
            {byChain.length ? (
              <table className="data-table">
                <thead>
                  <tr><th>Chain</th><th>Runs</th><th>Success</th><th>Rate</th><th>Tokens</th><th>Cost</th></tr>
                </thead>
                <tbody>
                  {byChain.map((c, i) => (
                    <tr key={`${c.chain}-${i}`}>
                      <td className="mono">{c.chain}</td>
                      <td className="num">{c.runs}</td>
                      <td className="num">{c.success}</td>
                      <td className="num">{c.runs ? pct(c.success / c.runs) : '—'}</td>
                      <td className="num">{c.tokens.toLocaleString()}</td>
                      <td className="num">{usd(c.cost)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="muted" style={{ padding: 12 }}>No runs yet.</div>
            )}
          </div>
        </section>

        <section className="panel">
          <div className="panel-head">
            <div className="panel-title"><span className="glyph" aria-hidden="true">ᛗ</span> By workflow</div>
          </div>
          <div className="panel-body flush">
            {byModel.length ? (
              <table className="data-table">
                <thead>
                  <tr><th>Workflow</th><th>Runs</th><th>Success</th><th>Rate</th><th>Tokens</th><th>Cost</th></tr>
                </thead>
                <tbody>
                  {byModel.map((m) => (
                    <tr key={m.model}>
                      <td className="mono">{m.model}</td>
                      <td className="num">{m.runs}</td>
                      <td className="num">{m.success}</td>
                      <td className="num">{m.runs ? pct(m.success / m.runs) : '—'}</td>
                      <td className="num">{m.tokens.toLocaleString()}</td>
                      <td className="num">{usd(m.cost)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="muted" style={{ padding: 12 }}>No workflows yet.</div>
            )}
          </div>
        </section>
      </div>
    </>
  );
}
