/**
 * Hlidskjalf gate API — a read-only view of the Brokk runtime (plan 29).
 *
 * The runtime is file-based: state/, config/, workspace/memory/, .agents/. This
 * server reads those artifacts and the runtime status scripts, and serves the
 * shapes the SPA already declares in src/services/api.ts. It is read-only; no
 * endpoint mutates the runtime.
 *
 *   bun run apps/hlidskjalf/server/index.ts        # API on :3889
 *   PORT=3889 bun run server/index.ts
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { Database } from 'bun:sqlite';
import { dirname, extname, join, resolve } from 'node:path';
import { readdir as readdirAsync, readFile as readFileAsync } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { createVoiceHandler, voiceAccess } from './voice.ts';
import {
  findAccount,
  invitesOpen,
  listAccounts,
  listInvites,
  register,
  verify as verifyAccount,
} from './accounts.ts';
import { A2A_PROTOCOL, type AgentInterface } from '../../../packages/contracts/src/index.ts';

const PORT = Number(process.env.PORT ?? 3889);
const HERE = import.meta.dir;
const ROOT = resolve(HERE, '../../..'); // the checkout this app is served from
const AGENTS_DIR = join(ROOT, '.agents/agents');
const SUBAGENTS_DIR = join(ROOT, '.agents/subagents');
const AGENTS_ALT = existsSync(AGENTS_DIR) ? AGENTS_DIR : SUBAGENTS_DIR;
const CONFIG_DIR = join(ROOT, '.agents/config');
const STATE_DIR = join(ROOT, 'state');
// The ledger lives in the HOARD, never in the checkout (Rule 04 / migration
// 0004): $YMIR_HOARD, else $YMIR_HOME/hodd, else the recorded home's hodd.
/** $YMIR_HOME — the hoard's home: env -> the recorded choice -> ONE default
 * (Rule 07; bin/vault/hoard-lib.sh owns the record file and the default name). */
const HOME_DIR = process.env.YMIR_HOME ?? (() => {
  try {
    const rec = readFileSync(join(process.env.XDG_CONFIG_HOME ?? join(homedir(), '.config'), 'ymir', 'home'), 'utf8').trim().split('\n')[0].trim();
    if (rec) return rec;
  } catch {
    // no record yet — fall through to the one documented default
  }
  return join(homedir(), 'Documents', 'ymirhome');
})();
const HOARD = process.env.YMIR_HOARD ?? join(process.env.YMIR_HOME ?? join(homedir(), 'Documents', 'ymirhome'), 'hodd');
const RUNES = join(HOARD, 'memory/runes_audit.md');
const voice = createVoiceHandler({ root: ROOT, home: process.env.SKIRNIR_HOME ?? HOME_DIR,
  temp: process.env.SKIRNIR_VOICE_TMP ?? join(HOARD, 'state/runtime/skirnir-voice') });
const WELL = join(ROOT, '.agents/memory/well/episodes.jsonl');
// The engram store lives in the hoard (never the tree); the well lane reads its
// supersede TIMESTAMPS only — never a fact's text (plan 60 Part 9's ward).
const WELL_DB = join(HOARD, 'memory/kaia.engram');
const MASTERPLAN = join(ROOT, 'docs/masterplan.md');

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });

/* ---- Gná, the mail desk (plan 116) ---------------------------------------- *
 * The desk is a service of its own on loopback (hodd/bin/gna-agent/gna_desk.py),
 * not a branch inside this file: mail carries a per-account security boundary and
 * that must not live in a 2,700-line monolith. This gate only forwards, with the
 * desk's own token, and passes its refusals through unchanged — an account-less
 * query answers 400 naming what is missing, never an empty queue. */
const MAIL_DESK = process.env.GNA_DESK_URL ?? 'http://127.0.0.1:8490';
const MAIL_TOKEN_FILE = join(HOARD, 'state/gna-desk.token');

function mailDeskToken(): string {
  try {
    return readFileSync(MAIL_TOKEN_FILE, 'utf8').trim();
  } catch {
    return '';
  }
}

async function mailDesk(path: string, params: Record<string, string> = {}): Promise<Response> {
  const token = mailDeskToken();
  if (!token) {
    return json({
      error: 'the desk has no token yet — raise it with: python3 hodd/bin/gna-agent/gna_desk.py',
    }, 503);
  }
  const qs = new URLSearchParams(params).toString();
  try {
    const r = await fetch(`${MAIL_DESK}${path}${qs ? `?${qs}` : ''}`, {
      headers: { authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(15000),
    });
    const body = await r.json().catch(() => ({ error: 'the desk sent no JSON' }));
    return json(body, r.status);
  } catch (e) {
    return json({ error: `the desk did not answer at ${MAIL_DESK}: ${(e as Error).message}` }, 503);
  }
}

function read(path: string): string {
  try {
    return readFileSync(path, 'utf8');
  } catch {
    return '';
  }
}

function run(cmd: string[]): string {
  try {
    // Bound every runtime probe so a stuck script can never hang a request.
    const p = Bun.spawnSync(['timeout', '12', ...cmd], {
      cwd: ROOT,
      stdout: 'pipe',
      stderr: 'pipe',
    });
    return new TextDecoder().decode(p.stdout ?? new Uint8Array()).trim();
  } catch {
    return '';
  }
}

/* ---- caches: a request must never re-scan a growing file or re-spawn ------- *
 * The gate reads append-only ledgers and probes live runtime scripts on every
 * request. Both grow without bound, so an uncached read is O(file) per request.
 * These two helpers memoise the reads and move the probes off the event loop. */
const MEMO = new Map<string, { t: number; v: unknown }>();
const INFLIGHT = new Map<string, Promise<unknown>>();

/** Serve a repeated pure read from memory for `ttlMs`. */
function memo<T>(key: string, ttlMs: number, fn: () => T): T {
  const hit = MEMO.get(key);
  const now = Date.now();
  if (hit && now - hit.t < ttlMs) return hit.v as T;
  const v = fn();
  MEMO.set(key, { t: now, v });
  return v;
}

/** Async memo: concurrent callers share one in-flight promise, never a throng. */
function memoAsync<T>(key: string, ttlMs: number, fn: () => Promise<T>): Promise<T> {
  const hit = MEMO.get(key);
  const now = Date.now();
  if (hit && now - hit.t < ttlMs) return Promise.resolve(hit.v as T);
  const running = INFLIGHT.get(key);
  if (running) return running as Promise<T>;
  const p = fn()
    .then((v) => {
      MEMO.set(key, { t: Date.now(), v });
      INFLIGHT.delete(key);
      return v;
    })
    .catch((e) => {
      INFLIGHT.delete(key);
      throw e;
    });
  INFLIGHT.set(key, p);
  return p;
}

/** Read-only subprocess probe, off the event loop. `timeout` still bounds a
 *  stuck script, but the loop is never blocked waiting on it, and a brief cache
 *  means concurrent polls share one spawn. Mutating actions keep `run()`. */
async function runAsync(cmd: string[], ttlMs = 3000): Promise<string> {
  return memoAsync('run:' + cmd.join('\u0000'), ttlMs, async () => {
    try {
      const proc = Bun.spawn(['timeout', '12', ...cmd], {
        cwd: ROOT,
        stdout: 'pipe',
        stderr: 'pipe',
      });
      const out = await new Response(proc.stdout).text();
      await proc.exited;
      return out.trim();
    } catch {
      return '';
    }
  });
}

/* ---- the seat doors (near the loop) -------------------------------------- */
// The four dials, what waits on the operator, and this session's context are owned
// by three doors in bin/seat/. The gate is a CARRIER only: it runs the door, memoises
// the read, and never re-implements what the door already knows. A door that cannot
// answer says so — it is never painted as a zero (the 2026-10-23 fault).
async function seatDoor<T>(door: string, ttlMs: number): Promise<T | { error: string }> {
  const key = `door:${door}`;
  const hit = MEMO.get(key);
  if (hit && Date.now() - hit.t < ttlMs) return hit.v as T;
  const failed = (error: string) => ({ error }); // never cached: a re-read must retry
  let raw = '';
  try {
    const proc = Bun.spawn(['timeout', '10', 'bash', `bin/seat/${door}.sh`, '--json'], {
      cwd: ROOT,
      stdout: 'pipe',
      stderr: 'ignore',
    });
    // THE READ IS BOUNDED TOO. A door that starts its own child (core-four asks the model
    // catalog) can leave the pipe open after `timeout` kills the shell — and then a plain
    // `await new Response(stdout).text()` never returns, which hung this endpoint forever
    // on 2026-11-06. A stuck pipe is the door failing to answer, and it says so.
    raw = await Promise.race([
      new Response(proc.stdout).text(),
      new Promise<string>((resolve) => setTimeout(() => resolve(''), 11_000)),
    ]);
    try {
      proc.kill('SIGKILL');
    } catch {
      // already gone
    }
  } catch {
    return failed(`bin/seat/${door}.sh could not be started`);
  }
  raw = raw.trim();
  if (!raw) return failed(`bin/seat/${door}.sh did not answer in time`);
  try {
    const parsed = JSON.parse(raw) as T;
    MEMO.set(key, { t: Date.now(), v: parsed });
    return parsed;
  } catch {
    return failed(`bin/seat/${door}.sh answered with something that is not JSON: ${raw.slice(0, 120)}`);
  }
}

interface PlanRow {
  n: number;
  slug: string;
  title: string;
  state: string;
  file: string;
}

/** A plan's status leads with its state; the middot or dash that follows is the
 *  detail, and the board has a cell, not a paragraph. */
function tidyState(raw: string): string {
  const s = raw.toLowerCase().replace(/[*`]/g, '').trim();
  return s.split(/[\u00b7\u2014,;(]/)[0].trim().split(/\s+/).slice(0, 3).join(' ') || 'undeclared';
}

/** THE LEDGER'S OWN INDEX carries each plan's state in the LAST cell of its row —
 *  plans/README.md is what bin/gates/plan-audit.sh holds the ledger to ("a row that
 *  names the plan AND carries a status"). The oldest section's rows end in a PATH
 *  instead, which is a table and not a state, so a `.md` last cell is skipped. */
async function ledgerIndex(root: string): Promise<Record<number, string>> {
  const out: Record<number, string> = {};
  let text = '';
  try {
    text = await readFileAsync(join(root, 'README.md'), 'utf8');
  } catch {
    return out; // no index: the body's own status line is the only word there is
  }
  for (const line of text.split('\n')) {
    const m = /^\|\s*(\d+)\s*\|(.+)\|\s*$/.exec(line);
    if (!m) continue;
    const cells = m[2].split('|').map((c) => c.trim());
    const last = (cells[cells.length - 1] ?? '').replace(/[*`]/g, '').trim();
    if (!last || /^[-: ]+$/.test(last) || /\.md$/.test(last)) continue;
    out[Number(m[1])] = tidyState(last);
  }
  return out;
}

/** The plan's own word for its state, when its index row did not give one. Plans
 *  carry two shapes — a TOON `"status","…"` header and a Markdown `**Status:** …`
 *  line — and 114 of 149 declare neither, so `undeclared` is the honest answer and
 *  the board shows it as such rather than guessing. */
function planState(body: string): string {
  const head = body.slice(0, 1500);
  const raw =
    /^\s*"status"\s*,\s*"([^"]+)"/m.exec(head)?.[1] ??
    /^\*\*Status:?\*\*:?\s*(.+)$/m.exec(head)?.[1] ??
    '';
  return raw ? tidyState(raw) : 'undeclared';
}

/** Where the ledger lives. Discovered, never hardcoded (Rule 07): a realm keeps its
 *  plans at `<realm>/{projects,workspace}/ymir/plans`, the same shelf
 *  bin/records/weave.sh finds. */
async function ledgerRoot(): Promise<string> {
  if (process.env.YMIR_PLANS_DIR) return process.env.YMIR_PLANS_DIR;
  const base = join(HOME_DIR, 'svartalfaheim');
  const found: string[] = [];
  try {
    for (const realm of await readdirAsync(base, { withFileTypes: true })) {
      if (!realm.isDirectory() || realm.name.startsWith('.')) continue;
      for (const mid of ['projects', 'workspace']) {
        const p = join(base, realm.name, mid, 'ymir', 'plans');
        if (existsSync(p)) found.push(p);
      }
    }
  } catch {
    // a home with no realm shelf is an empty ledger, and the board says so
  }
  return found[0] ?? join(base, 'work', 'projects', 'ymir', 'plans');
}

/** THE LEDGER, read where it lives: one numbered file per plan. Skuld's plans table
 *  is the WRITE door, and it has been empty while the ledger carried every plan as a
 *  file (2026-11-05) — a board that says "no plans" over 149 files is the bug this
 *  read answers. `old-plans/` is the RETIRED shelf and is skipped by name: its
 *  numbers repeat the living ones, and a retired plan shown as live is a lie. */
async function planLedger(): Promise<{ count: number; ledger: string; plans: PlanRow[] }> {
  const root = await ledgerRoot();
  const index = await ledgerIndex(root);
  const rows: PlanRow[] = [];
  const walk = async (dir: string, depth: number): Promise<void> => {
    if (depth > 2) return;
    let ents;
    try {
      ents = await readdirAsync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of ents) {
      const full = join(dir, e.name);
      if (e.isDirectory()) {
        if (e.name === 'old-plans' || e.name.startsWith('.')) continue;
        await walk(full, depth + 1);
        continue;
      }
      const m = /^(\d+)-(.+)\.md$/.exec(e.name);
      if (!m) continue;
      let body = '';
      try {
        body = (await readFileAsync(full, 'utf8')).slice(0, 8000);
      } catch {
        continue;
      }
      const title = (body.match(/^#\s+(.+)$/m)?.[1] ?? m[2].replace(/-/g, ' '))
        .replace(/^Plan\s+\d+\s*[\u2014:-]\s*/i, '')
        .trim();
      rows.push({
        n: Number(m[1]),
        slug: m[2],
        title,
        state: index[Number(m[1])] ?? planState(body),
        file: full.startsWith(root) ? full.slice(root.length + 1) : e.name,
      });
    }
  };
  await walk(root, 0);
  rows.sort((a, b) => b.n - a.n || a.slug.localeCompare(b.slug));
  return { count: rows.length, ledger: 'svartalfaheim', plans: rows };
}

/* ---- Yggdrasil worktrees ------------------------------------------------- */
async function worktrees(): Promise<Array<{ id: string; branch: string; path: string; head: string; agent: string }>> {
  const out = await runAsync(['git', 'worktree', 'list', '--porcelain']);
  const rows: Array<{ id: string; branch: string; path: string; head: string; agent: string }> = [];
  let cur: { path?: string; head?: string; branch?: string } = {};
  const push = () => {
    if (!cur.path) return;
    const p = cur.path;
    const id = p.includes('/.yggdrasil/') ? p.split('/.yggdrasil/')[1] : '(main)';
    rows.push({ id, branch: cur.branch ?? '-', path: p, head: (cur.head ?? '').slice(0, 8), agent: id === '(main)' ? '-' : id });
  };
  for (const line of out.split('\n')) {
    if (line.startsWith('worktree ')) { push(); cur = { path: line.slice(9).trim() }; }
    else if (line.startsWith('HEAD ')) cur.head = line.slice(5).trim();
    else if (line.startsWith('branch ')) cur.branch = line.slice(7).trim().replace('refs/heads/', '');
    else if (line.trim() === 'detached') cur.branch = 'detached';
  }
  push();
  return rows;
}

/* ---- frontmatter (YAML subset) ------------------------------------------- */
function frontmatter(text: string): Record<string, unknown> {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const out: Record<string, unknown> = {};
  let listKey: string | null = null;
  for (const line of m[1].split('\n')) {
    if (/^\s*-\s+/.test(line) && listKey) {
      (out[listKey] as unknown[]).push(line.replace(/^\s*-\s+/, '').replace(/^["']|["']$/g, ''));
      continue;
    }
    const kv = line.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (!kv) continue;
    const [, k, v] = kv;
    if (v === '') {
      out[k] = [];
      listKey = k;
    } else {
      out[k] = v.replace(/^["']|["']$/g, '');
      listKey = null;
    }
  }
  return out;
}

/* ---- /api/agents --------------------------------------------------------- */
function agents() {
  const model = read(join(CONFIG_DIR, 'eindri-harness')).trim() || 'opencode-go/deepseek-v4-flash';
  const files = existsSync(AGENTS_ALT)
    ? readdirSync(AGENTS_ALT).filter((f) => f.endsWith('.md') && f !== 'galdr.md')
    : [];
  return files.map((f) => {
    const text = read(join(AGENTS_ALT, f));
    const fm = frontmatter(text);
    const id = String(fm.name ?? f.replace(/\.md$/, ''));
    const norse = String(fm.norse_name ?? fm.name ?? id);
    // Real, sourced fields only — no fabricated status/trace/tasks.
    const registered = existsSync(join(ROOT, '.opencode/agents', `${id}.md`));
    const a2a: AgentInterface = { protocol: A2A_PROTOCOL, endpoint: `local://${id}`, signed: false };
    return {
      id,
      name: norse.charAt(0).toUpperCase() + norse.slice(1),
      role: String(fm.descriptor ?? fm.role ?? 'agent'),
      realm: 'work',
      domain: String(fm.domain ?? 'ymirlabs'),
      status: registered ? 'nominal' : 'degraded',
      capabilities: Array.isArray(fm.capabilities) ? fm.capabilities : [],
      skills: [],
      interface: a2a,
      model: String(fm.model ?? '') || model,
      uptime: 0,
      tasksDone: 0,
      traceability: 0,
    };
  });
}

/* ---- /api/tasks (forge orders) ------------------------------------------- */
function orders_uncached() {
  const text = read(MASTERPLAN);
  const out: { id: string; title: string; phase: string; status: string }[] = [];
  const lines = text.split('\n');
  let cur: { id: string; title: string; phase: string; status: string } | null = null;
  for (const line of lines) {
    const h = line.match(/^\*\*(W\d{4}) — (.+?)\*\*\s*$/);
    if (h) {
      if (cur) out.push(cur);
      cur = { id: h[1], title: h[2].trim(), phase: 'P?', status: 'ADDED' };
      continue;
    }
    if (!cur) continue;
    const ph = line.match(/^- Phase:\s*([^·]+)/);
    if (ph) cur.phase = ph[1].trim();
    const st = line.match(/^- Status:\s*([A-Z/]+)/);
    if (st && !/^\+/.test(line)) cur.status = st[1];
    const note = line.match(/^\s*-\s+\d{4}-\d{2}-\d{2}\s+([A-Z]+)\b/);
    if (note) cur.status = note[1];
  }
  if (cur) out.push(cur);
  return out;
}

function orders() {
  return memo('orders', 2000, orders_uncached);
}

function tasks() {
  const now = new Date().toISOString();
  return orders().map((o, i) => ({
    id: o.id,
    title: o.title,
    state: o.status === 'COMPLETED' ? 'COMPLETED' : o.status === 'BLOCKED' ? 'INPUT_REQUIRED' : 'WORKING',
    realm: 'wayof',
    agent: 'Brokk',
    agentId: 'brokk',
    order: o.phase,
    progress: o.status === 'COMPLETED' ? 100 : 25,
    startedAt: now,
    updatedAt: now,
    artifacts: [],
    log: [`${o.id} · ${o.status} · ${o.phase}`],
  }));
}

/* ---- /api/runes ---------------------------------------------------------- */
function runes_uncached() {
  return read(RUNES)
    .split('\n')
    .filter((l) => l.trim().startsWith('{'))
    .map((l, i) => {
      try {
        const e = JSON.parse(l);
        const level = /fail|error/i.test(e.event ?? '') ? 'danger' : /warn|stale/i.test(e.event ?? '') ? 'warn' : /briefing|written/i.test(e.event ?? '') ? 'ok' : 'info';
        return {
          id: e.checksum ? String(e.checksum).slice(0, 12) : `rune-${i}`,
          ts: e.timestamp ?? '',
          agent: e.actor ?? 'brokk',
          module: e.event ?? '',
          event: e.message ?? '',
          checksum: String(e.checksum ?? '').slice(0, 12),
          realm: e.realm || 'wayof',
          order: e.order ?? '',
          level,
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .reverse();
}

function runes() {
  return memo('runes', 3000, runes_uncached);
}

/* ---- /api/well ----------------------------------------------------------- */
const MIMIR_URL = process.env.MIMIRSBRUNN_URL ?? 'http://127.0.0.1:4602';

function wellTitle(body: string, i = 0): string {
  return (body.split('\n')[0] ?? '').replace(/^#+\s*/, '').slice(0, 80) || `episode ${i}`;
}

/** The local JSONL well — used when the engram bridge is down. */
function localWell(q = '') {
  const rows = read(WELL)
    .split('\n')
    .filter((l) => l.trim().startsWith('{'))
    .map((l, i) => {
      try {
        const e = JSON.parse(l);
        const body = String(e.content ?? '');
        return {
          id: e.hash ?? `ep-${i}`,
          title: wellTitle(body, i),
          body: body.slice(0, 600),
          score: 0.9,
          mode: 'hybrid',
          agentScope: e.source ?? 'assets/data',
          ts: e.timestamp ?? '',
          tags: Array.isArray(e.tags) ? e.tags : [],
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean) as { title: string; body: string }[];
  const ql = q.toLowerCase();
  const filtered = q ? rows.filter((r) => `${r.title} ${r.body}`.toLowerCase().includes(ql)) : rows;
  return filtered.slice(0, 60).reverse();
}

/** Drink from the well: the engram bridge answers when it is up, else the file. */
async function well(q = '') {
  try {
    const url = q
      ? `${MIMIR_URL}/recall?q=${encodeURIComponent(q)}&k=60`
      : `${MIMIR_URL}/recent?limit=60`;
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (res.ok) {
      const data = (await res.json()) as {
        results?: { score?: number; episode?: { id?: string; content?: string; timestamp?: string; tags?: string[]; actors?: string[]; agent_id?: string } }[];
        episodes?: { id?: string; content?: string; timestamp?: string; tags?: string[]; actors?: string[]; agent_id?: string }[];
      };
      if (data.results) {
        return data.results.map((r) => {
          const e = r.episode ?? {};
          const body = String(e.content ?? '');
          return {
            id: e.id ?? '',
            title: wellTitle(body),
            body: body.slice(0, 600),
            score: r.score ?? 0,
            mode: 'hybrid',
            agentScope: (e.actors ?? [])[0] ?? e.agent_id ?? 'well',
            ts: e.timestamp ?? '',
            tags: e.tags ?? [],
          };
        });
      }
      if (data.episodes) {
        return data.episodes.map((e) => {
          const body = String(e.content ?? '');
          return {
            id: e.id ?? '',
            title: wellTitle(body),
            body: body.slice(0, 600),
            score: 0.9,
            mode: 'recent',
            agentScope: (e.actors ?? [])[0] ?? e.agent_id ?? 'well',
            ts: e.timestamp ?? '',
            tags: e.tags ?? [],
          };
        });
      }
    }
  } catch {
    /* bridge down — fall through to the local file */
  }
  return localWell(q);
}

/* ---- /api/mimir/health --------------------------------------------------- */
// The well lane's decay axis (plan 60 Part 9): the DAYS a fact was superseded,
// read straight from the engram store — timestamps only, never `subject`,
// `predicate`, `object` or episode content. `/api/well` serves episodes, not
// facts; this is the one fact-shaped datum the grid needs, and it carries no
// private text. A missing store is an empty list, and the lane says so.
function wellSupersedeDates(store?: unknown): string[] {
  const dbPath = typeof store === 'string' && store ? store : WELL_DB;
  try {
    if (!existsSync(dbPath)) return [];
    const db = new Database(dbPath, { readonly: true });
    try {
      const rows = db
        .query("select distinct substr(superseded_at,1,10) as d from facts where superseded_at is not null order by d")
        .all() as { d?: string }[];
      return rows.map((r) => r.d ?? '').filter(Boolean);
    } finally {
      db.close();
    }
  } catch {
    return [];
  }
}

async function mimirHealth() {
  let base: Record<string, unknown> = { status: 'down', store: null, episodes: 0, agents: [] };
  try {
    const res = await fetch(`${MIMIR_URL}/health`, { signal: AbortSignal.timeout(4000) });
    if (res.ok) base = (await res.json()) as Record<string, unknown>;
  } catch {
    /* down */
  }
  return { ...base, superseded_dates: wellSupersedeDates(base.store) };
}

/** One full episode from the well — the Allfather reads the whole memory. */
async function wellEpisode(id: string) {
  if (!id) return null;
  try {
    const res = await fetch(`${MIMIR_URL}/episode?id=${encodeURIComponent(id)}`, { signal: AbortSignal.timeout(6000) });
    if (res.ok) return await res.json();
  } catch {
    /* bridge down */
  }
  return null;
}

/* ---- /api/processes ------------------------------------------------------ */
async function processes() {
  const out: unknown[] = [];
  const cron = await runAsync(['bash', 'bin/time/nornir-cron-start.sh', '--status']);
  const bridge = await runAsync(['bash', 'bin/bridge/bifrost-bridge.sh', '--status']);
  out.push({
    id: 'nornir-cron', name: 'Nornir cron', daemon: 'scheduler', manager: 'pm2',
    status: cron.includes('running') ? 'nominal' : 'down', cpu: 0, mem: 12, restarts: 0,
    uptime: 3600, realm: 'platform',
  });
  out.push({
    id: 'bifrost-bridge', name: 'Bifrost model bridge', daemon: 'opencode-go bridge', manager: 'systemd',
    status: bridge.includes('"up"') ? 'nominal' : 'down', cpu: 0, mem: 18, restarts: 0,
    uptime: 3600, realm: 'platform',
  });
  // The fleet's daemons across PM2/Docker/systemd, read-only from Valhalla.
  for (const r of parseToon(await runAsync(['bash', 'bin/agents/valhalla.sh', 'list']))) {
    const st = /running|active|online/i.test(r.status)
      ? 'nominal'
      : /exit|fail|inactive|dead|stop/i.test(r.status)
        ? 'down'
        : 'degraded';
    out.push({
      id: r.id,
      name: r.name,
      daemon: r.manager,
      manager: r.manager,
      status: st,
      cpu: Number(r.cpu) || 0,
      mem: Number(r.mem) || 0,
      restarts: Number(r.restarts) || 0,
      uptime: Number(r.uptime) || 0,
      realm: 'platform',
    });
  }
  return out;
}

/* ---- /api/smidja (the smithy's own trace, read-only) --------------------- */
// The smithy's db lives where the RUNTIME keeps it: $YMIR_HOME first (the data
// belongs outside the repo), else the app tree it moved into. It sat at the repo
// root's old path for a year; when the tree moved, this reader quietly opened
// nothing and every statistic showed zero - a gate with nothing to say.
const SMIDJA_DB = (() => {
  if (process.env.SMIDJA_DB) return process.env.SMIDJA_DB;
  const candidates = [
    join(process.env.YMIR_HOME ?? join(homedir(), 'Documents', 'ymirhome'), 'smidja', 'smidja.db'),
    join(ROOT, 'apps', 'smidja', 'smidja_data', 'smidja.db'),
  ];
  return candidates.find((c) => existsSync(c)) ?? candidates[1];
})();

function smidja(): Database | null {
  try {
    if (!existsSync(SMIDJA_DB)) return null;
    return new Database(SMIDJA_DB, { readonly: true });
  } catch {
    return null;
  }
}

function smidjaHealth() {
  const db = smidja();
  if (!db) return { db: 'absent', sessions: 0 };
  try {
    const r = db.query('select count(*) c from sessions').get() as { c?: number };
    return { db: 'present', sessions: r?.c ?? 0 };
  } catch {
    return { db: 'present', sessions: 0 };
  } finally {
    db.close();
  }
}

function smidjaSessions(limit = 100) {
  const db = smidja();
  if (!db) return [];
  try {
    return db
      .query(
        'select smidja_id, smidja_name, status, engineer, total_tokens, total_cost, started_at, ended_at from sessions order by started_at desc limit ?',
      )
      .all(limit);
  } catch {
    return [];
  } finally {
    db.close();
  }
}

function smidjaSession(id: string) {
  const db = smidja();
  if (!db) return null;
  try {
    const session = db.query('select * from sessions where smidja_id = ?').get(id);
    if (!session) return null;
    return {
      session,
      phases: db.query('select * from phases where smidja_id = ? order by seq, rowid').all(id),
      events: db
        .query('select rowid, event_id, phase_id, parent_id, type, name, payload_json, tokens, started_at, ended_at from events where smidja_id = ? order by rowid limit 2000')
        .all(id),
      envelopes: db.query('select * from envelopes where smidja_id = ? order by created_at, rowid').all(id),
      gates: db.query('select * from gate_results where smidja_id = ? order by id').all(id),
      agents: db.query('select * from agent_sessions where smidja_id = ? order by created_at, agent').all(id),
    };
  } catch {
    return null;
  } finally {
    db.close();
  }
}

function smidjaDecisions() {
  const db = smidja();
  if (!db) return { total_failed: 0, decisions: [] };
  try {
    const decisions = db
      .query(
        "select ph.name phase, ph.error, ag.model, count(*) count from phases ph left join agent_sessions ag on ag.smidja_id=ph.smidja_id and ag.agent=ph.owner where ph.status='fail' group by ph.name, ph.error, ag.model order by count desc",
      )
      .all();
    return { total_failed: decisions.length, decisions };
  } catch {
    return { total_failed: 0, decisions: [] };
  } finally {
    db.close();
  }
}

interface VendorModelDef {
  id: string;
  name: string;
  provider: string;
  tier: 1 | 2 | 3;
  rank: number;
  pin: number;
  po: number;
  cache: number;
}

// Commercial model catalog — rates are standard pay-as-you-go API prices per 1M
// tokens (input/output), midpoint where the spec quotes a range. `cache` is the
// share of the input price billed on a cache read (OpenAI/DeepSeek/Meta 50%,
// Google 25%, Anthropic 10%). Ported 1:1 from the Smiðja visualizer db.ts.
const VENDOR_MODELS: VendorModelDef[] = [
  { id: 'gpt-5.5-pro', name: 'GPT-5.5 Pro', provider: 'OpenAI', tier: 1, rank: 1, pin: 30.0, po: 180.0, cache: 0.5 },
  { id: 'o3-pro', name: 'o3-pro', provider: 'OpenAI', tier: 1, rank: 2, pin: 20.0, po: 80.0, cache: 0.5 },
  { id: 'claude-opus', name: 'Claude Opus 4.6 / 5', provider: 'Anthropic', tier: 1, rank: 3, pin: 5.0, po: 25.0, cache: 0.1 },
  { id: 'gpt-5.5', name: 'GPT-5.5', provider: 'OpenAI', tier: 1, rank: 4, pin: 5.0, po: 30.0, cache: 0.5 },
  { id: 'llama-3.1-405b', name: 'Llama 3.1 405B', provider: 'Meta (Hosted)', tier: 1, rank: 5, pin: 3.75, po: 3.75, cache: 0.5 },
  { id: 'gpt-5.4', name: 'GPT-5.4', provider: 'OpenAI', tier: 1, rank: 6, pin: 2.5, po: 15.0, cache: 0.5 },
  { id: 'gpt-4o', name: 'GPT-4o', provider: 'OpenAI', tier: 1, rank: 7, pin: 2.5, po: 10.0, cache: 0.5 },
  { id: 'gemini-3.1-pro', name: 'Gemini 3.1 Pro', provider: 'Google', tier: 1, rank: 8, pin: 2.0, po: 12.0, cache: 0.25 },
  { id: 'o3', name: 'o3', provider: 'OpenAI', tier: 1, rank: 9, pin: 2.0, po: 8.0, cache: 0.5 },
  { id: 'claude-sonnet', name: 'Claude Sonnet 4.6 / 5', provider: 'Anthropic', tier: 1, rank: 10, pin: 2.5, po: 12.5, cache: 0.1 },
  { id: 'mistral-large-3', name: 'Mistral Large 3', provider: 'Mistral AI', tier: 2, rank: 11, pin: 0.5, po: 1.5, cache: 0.5 },
  { id: 'claude-haiku', name: 'Claude Haiku 4.5', provider: 'Anthropic', tier: 2, rank: 12, pin: 1.0, po: 5.0, cache: 0.1 },
  { id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro', provider: 'Google', tier: 2, rank: 13, pin: 1.25, po: 10.0, cache: 0.25 },
  { id: 'o4-mini', name: 'o4-mini', provider: 'OpenAI', tier: 2, rank: 14, pin: 0.55, po: 2.2, cache: 0.5 },
  { id: 'deepseek-r1', name: 'DeepSeek R1', provider: 'DeepSeek', tier: 2, rank: 15, pin: 0.55, po: 2.19, cache: 0.5 },
  { id: 'gemini-3-flash-preview', name: 'Gemini 3 Flash Preview', provider: 'Google', tier: 2, rank: 16, pin: 0.5, po: 3.0, cache: 0.25 },
  { id: 'command-r-plus', name: 'Command R+', provider: 'Cohere', tier: 2, rank: 17, pin: 2.5, po: 10.0, cache: 0.5 },
  { id: 'gpt-5.4-mini', name: 'GPT-5.4 Mini', provider: 'OpenAI', tier: 2, rank: 18, pin: 0.75, po: 4.5, cache: 0.5 },
  { id: 'deepseek-v4', name: 'DeepSeek V4', provider: 'DeepSeek', tier: 2, rank: 19, pin: 0.3, po: 0.5, cache: 0.5 },
  { id: 'codestral', name: 'Codestral', provider: 'Mistral AI', tier: 2, rank: 20, pin: 0.3, po: 0.9, cache: 0.5 },
  { id: 'deepseek-chat-v3.2', name: 'DeepSeek-Chat (V3.2)', provider: 'DeepSeek', tier: 2, rank: 21, pin: 0.28, po: 0.42, cache: 0.5 },
  { id: 'llama-3.3-70b', name: 'Llama 3.3 70B', provider: 'Meta (Hosted)', tier: 2, rank: 22, pin: 0.41, po: 0.52, cache: 0.5 },
  { id: 'mistral-medium-3.5', name: 'Mistral Medium 3.5', provider: 'Mistral AI', tier: 2, rank: 23, pin: 1.5, po: 7.5, cache: 0.5 },
  { id: 'gpt-4.1', name: 'GPT-4.1', provider: 'OpenAI', tier: 2, rank: 24, pin: 2.0, po: 8.0, cache: 0.5 },
  { id: 'qwen-2.5-72b', name: 'Qwen 2.5 72B', provider: 'Alibaba (Hosted)', tier: 2, rank: 25, pin: 0.35, po: 0.4, cache: 0.5 },
  { id: 'gemini-3.7-flash', name: 'Gemini 3.7 Flash', provider: 'Google', tier: 3, rank: 26, pin: 0.75, po: 3.75, cache: 0.25 },
  { id: 'gemini-3.6-flash', name: 'Gemini 3.6 Flash', provider: 'Google', tier: 3, rank: 27, pin: 0.75, po: 3.75, cache: 0.25 },
  { id: 'gpt-4.1-mini', name: 'GPT-4.1 Mini', provider: 'OpenAI', tier: 3, rank: 28, pin: 0.4, po: 1.6, cache: 0.5 },
  { id: 'llama-4-maverick', name: 'Llama 4 Maverick', provider: 'Meta (Hosted)', tier: 3, rank: 29, pin: 0.25, po: 0.875, cache: 0.5 },
  { id: 'gpt-5-mini', name: 'GPT-5 Mini', provider: 'OpenAI', tier: 3, rank: 30, pin: 0.25, po: 2.0, cache: 0.5 },
  { id: 'gemini-3.1-flash-lite', name: 'Gemini 3.1 Flash-Lite', provider: 'Google', tier: 3, rank: 31, pin: 0.25, po: 1.5, cache: 0.25 },
  { id: 'gpt-5.4-nano', name: 'GPT-5.4 Nano', provider: 'OpenAI', tier: 3, rank: 32, pin: 0.2, po: 1.25, cache: 0.5 },
  { id: 'mistral-small-4', name: 'Mistral Small 4', provider: 'Mistral AI', tier: 3, rank: 33, pin: 0.15, po: 0.6, cache: 0.5 },
  { id: 'gpt-4o-mini', name: 'GPT-4o mini', provider: 'OpenAI', tier: 3, rank: 34, pin: 0.15, po: 0.6, cache: 0.5 },
  { id: 'gpt-4.1-nano', name: 'GPT-4.1 Nano', provider: 'OpenAI', tier: 3, rank: 35, pin: 0.1, po: 0.4, cache: 0.5 },
  { id: 'gemini-2.5-flash-lite', name: 'Gemini 2.5 Flash-Lite', provider: 'Google', tier: 3, rank: 36, pin: 0.1, po: 0.4, cache: 0.25 },
  { id: 'llama-4-scout', name: 'Llama 4 Scout', provider: 'Meta (Hosted)', tier: 3, rank: 37, pin: 0.165, po: 0.5, cache: 0.5 },
  { id: 'ministral-8b', name: 'Ministral 8B', provider: 'Mistral AI', tier: 3, rank: 38, pin: 0.1, po: 0.1, cache: 0.5 },
  { id: 'llama-3.2-3b', name: 'Llama 3.2 3B', provider: 'Meta (Hosted)', tier: 3, rank: 39, pin: 0.02, po: 0.02, cache: 0.5 },
  { id: 'ministral-3b', name: 'Ministral 3B', provider: 'Mistral AI', tier: 3, rank: 40, pin: 0.04, po: 0.04, cache: 0.5 },
];

const TIER_LABEL: Record<number, string> = {
  1: 'Tier 1 — heavyweight flagships & enterprise intelligence',
  2: 'Tier 2 — mid-range & high-efficiency workhorses',
  3: 'Tier 3 — flash, mini & edge engines',
};

const LOCAL_MODEL_PREFIXES = ['lmstudio/', 'ollama/', 'localhost/', 'vllm/', 'unsloth/'];
const isLocalModel = (model: string) =>
  LOCAL_MODEL_PREFIXES.some((p) => model.toLowerCase().startsWith(p));

function emptyStats() {
  const provider = () => ({ events: 0, sessions: 0, tokens: 0, cost: 0, input: 0, output: 0, cache_read: 0 });
  const vendorCost = { cached_cost: 0, total_cost: 0, savings: 0, savings_pct: 0 };
  return {
    totals: { runs: 0, success: 0, fail: 0, running: 0, tokens: 0, cost: 0 },
    usage: { input: 0, output: 0, cache_read: 0, cache_write: 0, total: 0 },
    cache_hit_ratio: 0,
    avg_cache_hit_per_run: 0,
    vendors: { gpt4o: { ...vendorCost }, gemini: { ...vendorCost } },
    vendor_catalog: [] as unknown[],
    providers: { local: provider(), online: provider(), per_model: [] as unknown[] },
    by_chain: [] as unknown[],
    by_model: [] as unknown[],
    generated_at: new Date().toISOString(),
  };
}

/** Statistics — runs, tokens, cost, cache-hit ratio, and commercial savings.
 *  Ported 1:1 from the Smiðja visualizer `db.ts` `stats()`: usage comes from
 *  `agent_end` event payloads, model attribution from `agent_start` events. */
function smidjaStats_uncached() {
  const db = smidja();
  if (!db) return emptyStats();
  try {
    const hasSessions = db
      .query("select name from sqlite_master where type='table' and name='sessions'")
      .get();
    if (!hasSessions) return emptyStats();

    const sessions = db
      .query('select smidja_id, smidja_name, status, engineer, total_tokens, total_cost, started_at from sessions order by started_at desc')
      .all() as Array<{
      smidja_id: string;
      smidja_name: string | null;
      status: string | null;
      engineer: string | null;
      total_tokens: number | null;
      total_cost: number | null;
      started_at: string | null;
    }>;

    const totals = { runs: 0, success: 0, fail: 0, running: 0, tokens: 0, cost: 0 };
    for (const s of sessions) {
      totals.runs += 1;
      if (s.status === 'success') totals.success += 1;
      else if (s.status === 'fail') totals.fail += 1;
      else if (s.status === 'running') totals.running += 1;
      totals.tokens += s.total_tokens ?? 0;
      totals.cost += s.total_cost ?? 0;
    }

    const usage = { input: 0, output: 0, cache_read: 0, cache_write: 0, total: 0 };
    const cacheHitRuns: number[] = [];
    interface ModelAgg {
      events: number;
      sessions: Set<string>;
      tokens: number;
      cost: number;
      input: number;
      output: number;
      cache_read: number;
      coding_agent: string | null;
    }
    const modelAggs = new Map<string, ModelAgg>();
    const agentModel = new Map<string, string | null>();
    const agentCoding = new Map<string, string | null>();
    const started = new Map<string, { events: number; sessions: Set<string>; coding_agent: string | null }>();
    const emptyAgg = (): ModelAgg => ({
      events: 0,
      sessions: new Set(),
      tokens: 0,
      cost: 0,
      input: 0,
      output: 0,
      cache_read: 0,
      coding_agent: null,
    });

    for (const s of sessions) {
      const evs = db
        .query('select type, name, payload_json from events where smidja_id = ? order by rowid')
        .all(s.smidja_id) as Array<{ type: string; name: string | null; payload_json: string | null }>;
      let r = 0;
      let t = 0;
      for (const e of evs) {
        let payload: Record<string, unknown> = {};
        try {
          payload = e.payload_json ? JSON.parse(e.payload_json) : {};
        } catch {
          payload = {};
        }
        if (e.type === 'agent_start') {
          const sp = payload as { model?: string; coding_agent?: string };
          if (sp?.model) {
            const key = `${s.smidja_id}|${e.name}`;
            if (!agentModel.has(key)) {
              const st =
                started.get(sp.model) ?? { events: 0, sessions: new Set<string>(), coding_agent: sp.coding_agent ?? null };
              st.events += 1;
              st.sessions.add(s.smidja_id);
              st.coding_agent = sp.coding_agent ?? st.coding_agent;
              started.set(sp.model, st);
            }
            agentModel.set(key, sp.model);
            agentCoding.set(key, sp.coding_agent ?? null);
          }
          continue;
        }
        if (e.type !== 'agent_end') continue;
        const p = payload as {
          usage?: {
            input_tokens?: number;
            output_tokens?: number;
            cache_read_tokens?: number;
            cache_write_tokens?: number;
            total_tokens?: number;
            input_cost?: number;
            output_cost?: number;
            cache_read_cost?: number;
            cache_write_cost?: number;
          };
          cost?: number;
        };
        const u = p?.usage;
        if (!u) continue;
        usage.input += u.input_tokens ?? 0;
        usage.output += u.output_tokens ?? 0;
        usage.cache_read += u.cache_read_tokens ?? 0;
        usage.cache_write += u.cache_write_tokens ?? 0;
        usage.total += u.total_tokens ?? 0;
        r += u.cache_read_tokens ?? 0;
        t += (u.input_tokens ?? 0) + (u.cache_read_tokens ?? 0);
        const model = e.name ? agentModel.get(`${s.smidja_id}|${e.name}`) : undefined;
        if (!model) continue;
        const usageCost =
          (u.input_cost ?? 0) + (u.output_cost ?? 0) + (u.cache_read_cost ?? 0) + (u.cache_write_cost ?? 0);
        const agg = modelAggs.get(model) ?? emptyAgg();
        agg.events += 1;
        agg.sessions.add(s.smidja_id);
        agg.tokens += u.total_tokens ?? 0;
        agg.cost += usageCost || (p.cost ?? 0);
        agg.input += u.input_tokens ?? 0;
        agg.output += u.output_tokens ?? 0;
        agg.cache_read += u.cache_read_tokens ?? 0;
        const coding = e.name ? agentCoding.get(`${s.smidja_id}|${e.name}`) : undefined;
        agg.coding_agent = coding ?? agg.coding_agent;
        modelAggs.set(model, agg);
      }
      if (t > 0) cacheHitRuns.push(r / t);
    }

    for (const [model, st] of started) {
      if (modelAggs.has(model)) continue;
      const agg = emptyAgg();
      agg.events = st.events;
      agg.sessions = st.sessions;
      agg.coding_agent = st.coding_agent;
      modelAggs.set(model, agg);
    }
    const ingested = usage.input + usage.cache_read;
    const cacheHitRatio = ingested > 0 ? usage.cache_read / ingested : 0;

    const vendor = (pin: number, pcr: number, po: number) => {
      const std = (usage.input / 1_000_000) * pin;
      const cached = (usage.cache_read / 1_000_000) * pcr;
      const out = (usage.output / 1_000_000) * po;
      const total = std + cached + out;
      const savings = total - totals.cost;
      const savings_pct = total > 0 ? savings / total : 0;
      return { cached_cost: cached, total_cost: total, savings, savings_pct };
    };
    const gpt4o = vendor(2.5, 1.25, 10.0);
    const gemini = vendor(1.25, 0.3125, 5.0);

    const vendor_catalog = VENDOR_MODELS.map((m) => {
      const v = vendor(m.pin, m.pin * m.cache, m.po);
      return {
        id: m.id,
        name: m.name,
        provider: m.provider,
        tier: m.tier,
        rank: m.rank,
        tier_label: TIER_LABEL[m.tier],
        input_price: m.pin,
        output_price: m.po,
        cache_price: m.pin * m.cache,
        ...v,
      };
    });

    const providerAgg = () => ({ events: 0, sessions: 0, tokens: 0, cost: 0, input: 0, output: 0, cache_read: 0 });
    const providers = { local: providerAgg(), online: providerAgg() };
    for (const [model, agg] of modelAggs) {
      const p = providers[isLocalModel(model) ? 'local' : 'online'];
      p.events += agg.events;
      p.sessions += agg.sessions.size;
      p.tokens += agg.tokens;
      p.cost += agg.cost;
      p.input += agg.input;
      p.output += agg.output;
      p.cache_read += agg.cache_read;
    }
    const per_model = [...modelAggs.entries()]
      .map(([model, agg]) => ({
        model,
        kind: isLocalModel(model) ? ('local' as const) : ('online' as const),
        coding_agent: agg.coding_agent,
        events: agg.events,
        tokens: agg.tokens,
        cost: agg.cost,
      }))
      .sort((a, b) => b.tokens - a.tokens);

    const byChain = new Map<string, { runs: number; success: number; tokens: number; cost: number }>();
    const byModel = new Map<string, { runs: number; success: number; tokens: number; cost: number }>();
    for (const s of sessions) {
      const chain = (s.smidja_name ?? 'smidja').split(' + ')[0];
      const chainAgg = byChain.get(chain) ?? { runs: 0, success: 0, tokens: 0, cost: 0 };
      chainAgg.runs += 1;
      if (s.status === 'success') chainAgg.success += 1;
      chainAgg.tokens += s.total_tokens ?? 0;
      chainAgg.cost += s.total_cost ?? 0;
      byChain.set(chain, chainAgg);

      const modelAgg = byModel.get(s.smidja_name ?? '?') ?? { runs: 0, success: 0, tokens: 0, cost: 0 };
      modelAgg.runs += 1;
      if (s.status === 'success') modelAgg.success += 1;
      modelAgg.tokens += s.total_tokens ?? 0;
      modelAgg.cost += s.total_cost ?? 0;
      byModel.set(s.smidja_name ?? '?', modelAgg);
    }

    return {
      totals,
      usage,
      cache_hit_ratio: cacheHitRatio,
      avg_cache_hit_per_run: cacheHitRuns.length ? cacheHitRuns.reduce((a, b) => a + b, 0) / cacheHitRuns.length : 0,
      vendors: { gpt4o, gemini },
      vendor_catalog,
      providers: { ...providers, per_model },
      by_chain: [...byChain.entries()].map(([chain, agg]) => Object.assign({ chain }, agg)).sort((a, b) => b.runs - a.runs),
      by_model: [...byModel.entries()].map(([model, agg]) => Object.assign({ model }, agg)).sort((a, b) => b.runs - a.runs),
      generated_at: new Date().toISOString(),
    };
  } catch {
    return emptyStats();
  } finally {
    db.close();
  }
}

function smidjaStats() {
  return memo('smidjaStats', 3000, smidjaStats_uncached);
}

/* ---- /api/reviews (real PRs + compliance as checks) ---------------------- */
// Glitnir's truth (audited 2026-09-24): the old route could never show an
// APPROVED card (no review state was ever fetched), counted the synthetic lint
// card in "Open PRs", swallowed every gh failure silently, and relied on the
// cwd's git remote for repo detection (a packaged install has no .git, so gh
// found nothing and the board was blank). Now: reviewDecision + mergeable are
// fetched, the repo is passed explicitly, a gh failure is REPORTED not
// swallowed, and the payload distinguishes real PR cards from the lint card.
async function reviews() {
  const cards: unknown[] = [];
  let ghError = '';

  // 1. Real pull requests — Glitnir's cards. `--repo` is explicit so the read
  //    works from a packaged install (no .git to detect a remote from); the
  //    default is the repo itself (Rule 07 — one documented default).
  try {
    const repo =
      (run(['git', '-C', ROOT, 'remote', 'get-url', 'origin']).match(/[:/]([^/:]+\/[^/]+?)(?:\.git)?$/) ?? [])[1] ?? 'zerwiz/ymir';
    const list = JSON.parse(
      (await runAsync([
        'gh', 'pr', 'list', '--repo', repo, '--state', 'open', '--limit', '50',
        '--json', 'number,title,author,headRefName,isDraft,updatedAt,additions,deletions,statusCheckRollup,reviewDecision,mergeable',
      ], 15000)) || '[]',
    ) as Array<{
      number: number;
      title: string;
      author?: { login?: string };
      headRefName?: string;
      isDraft?: boolean;
      updatedAt?: string;
      additions?: number;
      deletions?: number;
      reviewDecision?: string;
      mergeable?: string;
      statusCheckRollup?: Array<{ name?: string; context?: string; status?: string; conclusion?: string }>;
    }>;
    for (const pr of list) {
      const checks = (pr.statusCheckRollup ?? []).map((c) => ({
        name: c.name ?? c.context ?? 'check',
        state:
          c.conclusion === 'SUCCESS' || c.status === 'IN_PROGRESS' || c.status === 'QUEUED'
            ? 'nominal'
            : c.conclusion
              ? 'down'
              : 'nominal',
      }));
      const failing = checks.some((c) => c.state === 'down');
      const approved = pr.reviewDecision === 'APPROVED' && !failing;
      cards.push({
        id: `pr-${pr.number}`,
        number: pr.number,
        title: pr.title,
        repo,
        author: pr.author?.login ?? 'unknown',
        realm: 'work',
        // draft → open (awaiting the Allfather); CI failing → changes (blocked);
        // GitHub APPROVED + green → approved (ready to seal).
        state: pr.isDraft ? 'open' : failing ? 'changes' : approved ? 'approved' : 'open',
        mergeable: pr.mergeable ?? undefined,
        checks,
        checklist: [{ label: `branch ${pr.headRefName ?? '?'}`, done: true }],
        additions: pr.additions ?? 0,
        deletions: pr.deletions ?? 0,
        updatedAt: pr.updatedAt ?? new Date().toISOString(),
      });
    }
  } catch (e) {
    // The Allfather must SEE a dead gh, never a silent blank board.
    ghError = e instanceof Error ? e.message : String(e);
  }

  // 2. The compliance card (lint + governed-path checks) always stands, but IT
  //    IS NOT A PULL REQUEST — the board counts real PRs (number > 0) apart.
  const out = await runAsync(['bash', 'bin/agents/brokk-lint.sh', '--quiet'], 60000);
  const compliance = await runAsync(['bash', '.agents/skills/galdr-ymirsystem/scripts/compliance-check.sh', '--json'], 60000);
  let gates: { id: string; status: string; detail: string }[] = [];
  try {
    gates = JSON.parse(compliance).checks ?? [];
  } catch {
    /* ignore */
  }
  const lintOk = out.trim() === '';
  const failing = !lintOk || gates.some((g) => g.status !== 'PASS');
  cards.push({
    id: 'lint', number: 0, title: 'Brokk lint + compliance gate', repo: 'Ymir', author: 'brokk', realm: 'work',
    // A gate with any failing check is never APPROVED — it awaits the Allfather's seal.
    state: failing ? 'changes' : 'open',
    checks: [
      { name: 'lint', state: lintOk ? 'nominal' : 'down' },
      ...gates.map((g) => ({ name: g.id, state: g.status === 'PASS' ? 'nominal' : 'down' })),
    ],
    checklist: [
      { label: `lint: ${lintOk ? 'clean' : 'issues found'}`, done: lintOk },
      ...gates.map((g) => ({ label: `${g.id}: ${g.detail}`, done: g.status === 'PASS' })),
    ],
    additions: 0, deletions: 0, updatedAt: new Date().toISOString(),
  });
  return { cards, ghError };
}

/* ---- /api/files (realm tree) --------------------------------------------- */
/** Resolve a workspace id to its on-disk scope: a company container when the
 *  workspace names one, else its repo-root workspace scope. */
function workspaceRoot(realm: string): string {
  // THE HOARD FIRST (Rule 04). A realm's tree lives at $YMIR_HOME/svartalfaheim/
  // <realm>; the checkout is only a legacy fallback for a home not yet migrated.
  // Skrymir was browsing the repo's own directories and reading files whose links
  // point into the hoard — which is why a listed file answered "not found".
  // The realm's OWN tree first. A workspace may name a company, but the operator's
  // projects live under svartalfaheim/<realm>/projects — the company mapping is a
  // display owner, not the shelf. This is why Skrymir showed whynotproductions and
  // not the work tree that holds the meetings.
  const realmTree = join(HOME_DIR, 'svartalfaheim', realm);
  if (existsSync(realmTree)) return realmTree;
  const ws = workspaces().find((w) => w.id === realm);
  if (ws?.company) {
    const company = join(HOME_DIR, 'svartalfaheim', ws.company);
    if (existsSync(company)) return company;
  }
  const scope = join(HOME_DIR, 'workspace', realm);
  if (existsSync(scope)) return scope;
  const slug = realm.toLowerCase().replace(/[^a-z0-9]/g, '');
  const legacy = join(ROOT, 'svartalfaheim', slug);
  if (slug && slug !== realm && existsSync(legacy)) return legacy;
  const legacyScope = join(ROOT, 'workspace', realm);
  if (existsSync(legacyScope)) return legacyScope;
  return realmTree; // the hoard, even when empty: a home is never the repo's
}

function files(realm: string) {
  const base = workspaceRoot(realm);
  const walk = (dir: string, rel: string, depth: number): unknown => {
    const name = rel === '' ? (realm || 'svartalfaheim') : rel.split('/').pop()!;
    const node: Record<string, unknown> = { name, type: 'dir', path: rel || '/', children: [] as unknown[] };
    const maxDepth = Number(process.env.SKRYMIR_MAX_DEPTH ?? 6);
    if (depth > maxDepth || !existsSync(dir)) return node;
    let entries: string[] = [];
    try {
      entries = readdirSync(dir);
    } catch {
      return node;
    }
    for (const e of entries) {
      if (e.startsWith('.')) continue;
      const full = join(dir, e);
      let st;
      try {
        st = statSync(full);
      } catch {
        continue;
      }
      const childRel = rel ? `${rel}/${e}` : e;
      if (st.isDirectory()) (node.children as unknown[]).push(walk(full, childRel, depth + 1));
      else (node.children as unknown[]).push({ name: e, type: 'file', path: childRel, size: st.size, updated: st.mtime.toISOString() });
    }
    return node;
  };
  if (existsSync(base)) return walk(base, '', 0);
  return walk(HOME_DIR, '', 0); // the hoard's home, not the checkout's docs
}

/* ---- /api/file — read one realm file, read-only, scoped ------------------ */
function fileContent(realm: string, rel: string) {
  const base = resolve(workspaceRoot(realm));
  const full = resolve(base, rel);
  if (full !== base && !full.startsWith(base + '/')) return { error: 'outside realm' };
  if (!existsSync(full)) return { error: 'not found' };
  let st;
  try {
    st = statSync(full);
  } catch {
    return { error: 'unreadable' };
  }
  if (!st.isFile()) return { error: 'not a file' };
  if (st.size > 512 * 1024) return { path: rel, size: st.size, body: '', note: 'file too large to preview' };
  return { path: rel, size: st.size, updated: st.mtime.toISOString(), body: read(full) };
}

/* ---- /api/skills — the live skill index (read-only) ---------------------- */
function skills() {
  const dir = join(ROOT, '.agents/skills');
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((d) => existsSync(join(dir, d, 'SKILL.md')) || existsSync(join(dir, d, 'AGENTS.md')))
    .map((d) => {
      const p = existsSync(join(dir, d, 'SKILL.md')) ? join(dir, d, 'SKILL.md') : join(dir, d, 'AGENTS.md');
      const fm = frontmatter(read(p));
      const name = String(fm.name ?? d);
      const description = String(fm.description ?? '').slice(0, 240);
      const aett = name.includes('-') ? name.split('-')[0] : 'galdr';
      return { id: `skl-${d}`, name, aett, description, capabilities: [], validated: true, domain: 'ymirlabs', createdAt: '' };
    });
}

/* ---- /api/runtime -------------------------------------------------------- */
async function runtime() {
  const digest = await runAsync(['bash', 'bin/time/saga-session-start.sh'], 10000);
  const markers = {
    lock: read(join(STATE_DIR, '.lock')).trim(),
    started: existsSync(join(STATE_DIR, '.session-start-complete')),
    armed: existsSync(join(STATE_DIR, '.supervision-armed')),
  };
  return { digest, markers, doc: 'docs/session-start.md' };
}

/* ---- /api/cron ----------------------------------------------------------- */
// The schedule the LOOP reads — never the repo's template. The board used to
// read join(ROOT,'.agents/config'), which ships ONLY cron.yaml.example, so it
// painted "0 jobs" while the loop ran the home's real schedule (2026-09-24).
// bin/time/nornir-cron-start.sh resolves the config first from $YMIR_HOME/config;
// the board resolves the same way.
function cronConfigPath(): { path: string; source: string } {
  const home = join(HOME_DIR, 'config', 'cron.yaml');
  if (existsSync(home)) return { path: home, source: 'home' };
  const repo = join(CONFIG_DIR, 'cron.yaml');
  if (existsSync(repo)) return { path: repo, source: 'repo' };
  const example = join(CONFIG_DIR, 'cron.yaml.example');
  if (existsSync(example)) return { path: example, source: 'example' };
  return { path: '', source: 'none' };
}

interface CronJobLine { at: string; role: string; command: string; }
// Mirror the loop's parse exactly (bin/time/nornir-cron-start.sh): a `@role[,role]`
// gate may sit BEFORE the time (`@heart 06:00 bin/x`) or AFTER (`06:00 @heart
// bin/x`); no gate means any role. One reality for scheduler, API, and board.
function parseCronJobs(cfg: string): CronJobLine[] {
  const jobs: CronJobLine[] = [];
  for (const raw of cfg.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    let rest = line;
    let role = '';
    if (line.startsWith('@')) {
      role = line.split(/\s+/)[0].slice(1);
      rest = line.slice(line.indexOf(' ') + 1).trim();
    }
    const m = rest.match(/^(\d{2}:\d{2})\s+(.+)$/);
    if (!m) continue;
    let tail = m[2];
    if (tail.startsWith('@')) {
      role = tail.split(/\s+/)[0].slice(1);
      tail = tail.slice(tail.indexOf(' ') + 1).trim();
    }
    if (!tail) continue;
    jobs.push({ at: m[1], role, command: tail });
  }
  return jobs;
}
function roleWords(role: string): string[] { return role ? role.split(',') : []; }
function jobApplies(job: CronJobLine, roles: string[]): boolean {
  if (!job.role) return true;               // no gate: any role
  return roleWords(job.role).some((w) => roles.includes(w));
}

async function cron() {
  const { path, source } = cronConfigPath();
  const cfg = path ? read(path) : '';
  const jobs = parseCronJobs(cfg);
  const status = await runAsync(['bash', 'bin/time/nornir-cron-start.sh', '--status']);
  const running = status.includes('running');
  const pid = (status.match(/pid=(\d+)/) ?? [])[1] ?? '';
  // Why a stopped loop is stopped — the log's last word, so 'DOWN' carries a
  // reason, never a bare verdict.
  const log = read(join(STATE_DIR, 'cron.log'));
  const sleepLines = log.split('\n').filter((l) => l.includes('cron retired') || l.includes('cron run'));
  const why = running ? '' : (sleepLines.length
    ? ((sleepLines[sleepLines.length - 1].match(/cron retired - (.+)$/) ?? [])[1] ?? 'stopped')
    : 'never started this session');
  // The seat's own roles, so the board can say which jobs run HERE (plan 51).
  let roles: string[] = [];
  try { roles = ((JSON.parse(await runAsync(['bash', 'bin/fleet/topology.sh', '--json'])) as { roles?: string[] }).roles ?? []) as string[]; } catch { /* no topology */ }
  // Last fire per job, from the loop's date-guard stamps.
  const last: Record<string, string> = {};
  const stampDir = join(STATE_DIR, '.cron-fired');
  for (const j of jobs) {
    const f = join(stampDir, j.command.replace(/[^A-Za-z0-9._-]/g, '_'));
    if (existsSync(f)) last[j.command] = read(f).trim();
  }
  const applies = jobs.filter((j) => jobApplies(j, roles)).length;
  return {
    running, pid, why, source, roles,
    jobs: jobs.map((j) => ({ at: j.at, role: j.role, command: j.command, status: running ? 'scheduled' : 'stopped', applies: jobApplies(j, roles) })),
    last,
  };
}

// The server crons the board must show beside the local ones (plan 54,
// 2026-09-24): whynot and zerwizserver are the fleet's servers (the hoard's
// machines.md; ~/.ssh/config hosts `whynot` and `server` → zerwizserver).
// One ssh round-trip per seat — read-on-demand, machine-local, BatchMode only.
const DEFAULT_SERVER_SEATS = [
  { seat: 'whynot', host: 'whynot' },
  { seat: 'zerwizserver', host: 'server' },
];
function serverSeats(): { seat: string; host: string }[] {
  const env = process.env.YMIR_CRON_SERVER_SEATS;
  if (env) {
    return env.split(/\s+/).filter(Boolean).map((e) => {
      const [seat, host] = e.split(':');
      return { seat, host: host ?? seat };
    });
  }
  return DEFAULT_SERVER_SEATS;
}

async function cronSeats() {
  const { path } = cronConfigPath();
  const localJobs = parseCronJobs(path ? read(path) : '');
  const rows = [];
  for (const s of serverSeats()) {
    const out = await runAsync(
      ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=3', s.host,
        `bash -lc 'G=$HOME/ymir; [ -d "$G/bin" ] || G=$(dirname "$(ls -d "$HOME"/*ymir*/bin 2>/dev/null | head -1)" 2>/dev/null); cd "$G" 2>/dev/null || exit 1; bash bin/time/nornir-cron-start.sh --status; bash bin/fleet/topology.sh --json 2>/dev/null'`],
      8000);
    if (!out) {
      rows.push({ seat: s.seat, host: s.host, reachable: false, running: false, pid: '', roles: [], jobs: localJobs.length, applies: 0, error: 'unreachable (ssh ring)' });
      continue;
    }
    const running = out.includes('running');
    const pid = (out.match(/pid=(\d+)/) ?? [])[1] ?? '';
    let roles: string[] = [];
    try { roles = ((JSON.parse(out.slice(out.indexOf('{'))) as { roles?: string[] }).roles ?? []) as string[]; } catch { /* no topology answer */ }
    rows.push({
      seat: s.seat, host: s.host, reachable: true, running, pid, roles,
      jobs: localJobs.length,
      applies: localJobs.filter((j) => jobApplies(j, roles)).length,
    });
  }
  return rows;
}

/** Forget every cached answer for one command. An ACTION must never be answered
 *  by a status read taken before it ran (the status call is memoised for 3 s). */
function forgetMemo(fragment: string): void {
  for (const key of [...MEMO.keys()]) if (key.includes(fragment)) MEMO.delete(key);
}

/** Start or stop this seat's scheduler — the SAME script the session start runs
 *  (`bin/time/nornir-cron-start.sh`). The board gains a hand, never a second
 *  opinion about how the loop is raised: `start` is idempotent, `stop` kills the
 *  pid the script itself owns. */
async function cronAct(action: 'start' | 'stop') {
  forgetMemo('nornir-cron-start.sh');
  const argv = ['bash', 'bin/time/nornir-cron-start.sh'];
  if (action === 'stop') argv.push('--stop');
  const said = await runAsync(argv, 0);
  forgetMemo('nornir-cron-start.sh');
  return { ok: true, action, said, ...(await cron()) };
}

/* ---- /api/calendar (Mánagandr, the read reckoning) ----------------------- */
// The reader (`tools/calendar/reader.mjs`, its own errand) refreshes the Google
// grant and writes ONE rolling cache under the hoard's state. This route only
// READS that file — there is no write path here, and none anywhere in the gate.
// `state` is the honest word: a missing cache is NOT an empty calendar.
const CALENDAR_CACHE = process.env.MANAGANDR_CACHE ?? join(HOARD, 'state', 'calendar', 'cache.json');
// Freshness window for the cache; env-driven (Rule 07), one documented default.
const CALENDAR_TTL_S = Number(process.env.MANAGANDR_CALENDAR_TTL_SECONDS ?? 6 * 60 * 60);

interface CalendarEventOut {
  id: string;
  title: string;
  start: string;
  end: string | null;
  allDay: boolean;
  cancelled: boolean;
  calendarId: string;
  /** Present only when the cache carries it — a count, never names. */
  attendees?: number;
}
interface CalendarAnswer {
  as_of: string | null;
  state: 'ok' | 'unknown' | 'absent';
  /** Where the answer came from: 'google' | 'cache' | 'fixture' | 'none'. */
  source?: string;
  events: CalendarEventOut[];
}

function pickField(obj: Record<string, unknown>, ...keys: string[]): unknown {
  for (const k of keys) if (obj[k] !== undefined && obj[k] !== null) return obj[k];
  return undefined;
}

/** Normalise one raw cache event to the pinned shape; a stray becomes null. */
function normalizeEvent(raw: unknown, i: number): CalendarEventOut | null {
  if (!raw || typeof raw !== 'object') return null;
  const e = raw as Record<string, unknown>;
  const start = pickField(e, 'start', 'start_at', 'startTime');
  if (typeof start !== 'string' || !start) return null;
  const rawEnd = pickField(e, 'end', 'end_at', 'endTime');
  const end = typeof rawEnd === 'string' ? rawEnd : null;
  const allDayFlag = pickField(e, 'allDay', 'all_day', 'isAllDay');
  // An all-day event is flagged, or is a bare date with no time component.
  const allDay = allDayFlag === true || (end === null && /^\d{4}-\d{2}-\d{2}$/.test(start));
  const status = String(pickField(e, 'status', 'state') ?? '');
  const cancelledFlag = pickField(e, 'cancelled', 'canceled');
  const cancelled = cancelledFlag === true || /cancel/i.test(status);
  const attendeesRaw = pickField(e, 'attendees', 'attendee_count', 'attendeeCount');
  const attendees = Array.isArray(attendeesRaw)
    ? attendeesRaw.length
    : typeof attendeesRaw === 'number'
      ? attendeesRaw
      : undefined;
  const out: CalendarEventOut = {
    id: String(pickField(e, 'id', 'eventId', 'event_id') ?? `ev-${i}`),
    title: String(pickField(e, 'title', 'summary', 'name') ?? '(untitled)'),
    start,
    end: allDay ? null : end,
    allDay,
    cancelled,
    calendarId: String(pickField(e, 'calendarId', 'calendar_id', 'calendar') ?? 'primary'),
  };
  if (attendees !== undefined) out.attendees = attendees;
  return out;
}

function calendar(): CalendarAnswer {
  // No cache at all: the token is Phase 0 and has not been granted. This is NOT
  // an empty day — the gate must say "not granted", never paint a blank grid.
  if (!existsSync(CALENDAR_CACHE)) return { as_of: null, state: 'absent', events: [] };
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(CALENDAR_CACHE, 'utf8'));
  } catch {
    // The file is there but unreadable — unknown, never absent and never empty.
    return { as_of: null, state: 'unknown', events: [] };
  }
  const obj = (parsed && typeof parsed === 'object' ? parsed : {}) as Record<string, unknown>;
  const rawAsOf = pickField(obj, 'as_of', 'asOf', 'generated_at', 'generatedAt', 'fetched_at', 'updated_at', 'at');
  const asOf = typeof rawAsOf === 'string' && rawAsOf ? rawAsOf : null;
  const source = String(pickField(obj, 'source') ?? 'unknown');
  const rawEvents = pickField(obj, 'events', 'items');
  const list = Array.isArray(rawEvents) ? rawEvents : Array.isArray(parsed) ? parsed : [];
  const events = list.map(normalizeEvent).filter(Boolean) as CalendarEventOut[];
  // Freshness is provable only from a readable as_of inside the TTL; anything
  // else is unknown — the cache exists but cannot be trusted for freshness.
  const t = asOf ? Date.parse(asOf) : NaN;
  const fresh = Number.isFinite(t) && Date.now() - t <= CALENDAR_TTL_S * 1000;
  // A FIXTURE is invented data, and a fresh timestamp does not make it real. It
  // is served as `unknown` with its source named, never as `ok` — the grid must
  // never paint "Invented All-Day Gathering" as the Allfather's diary. This
  // happened once (a probe omitted --cache and wrote 5 invented events into the
  // hoard's cache); the reader now refuses that write, and this refuses to
  // present it.
  if (source === 'fixture') {
    return { as_of: asOf, state: 'unknown', source, events };
  }
  return { as_of: asOf, state: fresh ? 'ok' : 'unknown', source, events };
}


/* ---- /api/snotra (the meeting record, plan 93) --------------------------- */
// Reads the store and the project meeting shelves. Draft/send call the Snotra
// doors; they never write a record and never send without the approval call.
const SNOTRA_STORE = process.env.SNOTRA_MEETINGS_DIR ?? join(HOARD, 'life', 'meetings');
const SNOTRA_ROOTS = [SNOTRA_STORE, join(HOME_DIR, 'svartalfaheim')];

interface SnotraMeetingOut {
  id: string; title: string; started_at: string | null; workspace: string;
  source: string; state: string; decisions: number; actions: number;
  has_record: boolean; dir: string; scope: string;
  participants: { name: string; email: string | null }[];
  draft?: string | null;
}

function snotraDirs(): { dir: string; file: string }[] {
  const out: { dir: string; file: string }[] = [];
  const push = (dir: string) => {
    for (const f of ['record.json', 'meeting.json']) {
      const p = join(dir, f);
      if (existsSync(p)) { out.push({ dir, file: p }); return; }
    }
  };
  try {
    for (const lane of readdirSync(SNOTRA_STORE, { withFileTypes: true })) {
      if (!lane.isDirectory()) continue;
      const laneDir = join(SNOTRA_STORE, lane.name);
      for (const m of readdirSync(laneDir, { withFileTypes: true })) {
        if (m.isDirectory()) push(join(laneDir, m.name));
      }
    }
  } catch { /* store absent is not an error */ }
  // Private meetings: the hoard's own shelf.
  try {
    for (const m of readdirSync(join(HOARD, 'workspaces', 'meetings'), { withFileTypes: true })) {
      if (m.isDirectory()) push(join(HOARD, 'workspaces', 'meetings', m.name));
    }
  } catch { /* no private shelf */ }
  try {
    for (const realm of readdirSync(SNOTRA_ROOTS[1], { withFileTypes: true })) {
      if (!realm.isDirectory()) continue;
      const companyMeetings = join(SNOTRA_ROOTS[1], realm.name, 'meetings');
      if (existsSync(companyMeetings)) {
        for (const m of readdirSync(companyMeetings, { withFileTypes: true })) {
          if (m.isDirectory()) push(join(companyMeetings, m.name));
        }
      }
      const projects = join(SNOTRA_ROOTS[1], realm.name, 'projects');
      if (!existsSync(projects)) continue;
      for (const project of readdirSync(projects, { withFileTypes: true })) {
        if (!project.isDirectory()) continue;
        const meetings = join(projects, project.name, 'meetings');
        if (!existsSync(meetings)) continue;
        for (const m of readdirSync(meetings, { withFileTypes: true })) {
          if (m.isDirectory()) push(join(meetings, m.name));
        }
      }
    }
  } catch { /* no project meetings */ }
  return out;
}

function snotraMeetings(): SnotraMeetingOut[] {
  const rows: SnotraMeetingOut[] = [];
  for (const { dir, file } of snotraDirs()) {
    try {
      const d = JSON.parse(readFileSync(file, 'utf8')) as Record<string, any>;
      const m = (d.meeting && typeof d.meeting === 'object') ? d.meeting : d;
      const participants = (d.participants ?? m.participants ?? []) as any[];
      rows.push({
        id: String(m.id ?? m.meeting_id ?? dir.split('/').pop()),
        title: String(m.title ?? m.summary ?? '(untitled)'),
        started_at: m.started_at ?? m.start ?? null,
        workspace: String(m.workspace ?? (dir.includes('/hodd/workspaces/meetings/') ? 'private'
          : dir.includes('/personal/') ? 'personal'
          : (dir.match(/svartalfaheim\/([^/]+)\/(?:meetings|projects)\//) ?? [])[1] ?? 'work')),
        scope: dir.includes('/hodd/workspaces/meetings/') ? 'private'
          : dir.includes('/projects/') ? 'project'
          : dir.includes('/hodd/life/meetings/') ? 'store'
          : 'company',
        source: String(m.source ?? 'manual'),
        state: String(m.state ?? d.state ?? 'captured'),
        decisions: Array.isArray(d.decisions) ? d.decisions.length : 0,
        actions: Array.isArray(d.actions) ? d.actions.length : 0,
        has_record: existsSync(join(dir, 'minutes.md')) || existsSync(join(dir, 'record.md')),
        dir,
        participants: participants.map((p: any) => ({ name: String(p.name ?? ''), email: p.email ?? null })),
      });
    } catch { /* a broken record is skipped, never crashes the shelf */ }
  }
  return rows.sort((a, b) => String(b.started_at ?? '').localeCompare(String(a.started_at ?? '')));
}

function snotraFind(id: string): SnotraMeetingOut | undefined {
  return snotraMeetings().find((m) => m.id === id || m.dir.endsWith('/' + id));
}

function snotraDraft(id: string): { draftId: string } | { error: string } {
  const m = snotraFind(id);
  if (!m) return { error: `no meeting ${id}` };
  const body = join(m.dir, 'followup-email.md');
  if (!existsSync(body)) return { error: 'no follow-up body (run the record pipeline first)' };
  const att: string[] = [];
  for (const f of ['minutes.md', 'record.md', 'decisions.md', 'actions.md']) {
    const p = join(m.dir, f);
    if (existsSync(p)) att.push('--attach', p);
  }
  const record = join(m.dir, 'record.json');
  const args = [join(ROOT, 'systems/snotra/services/letters/mail-send.sh'), 'draft',
    '--from-record', record, '--subject', `${m.title} — Meeting Record`,
    '--body', body, ...att, '--record', m.id];
  const r = spawnSync('bash', args, { encoding: 'utf8', timeout: 120_000 });
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const hit = out.match(/^draft\t(r-\d+)/m);
  if (!hit) return { error: out.trim().split('\n').slice(-2).join(' · ') || 'draft failed' };
  return { draftId: hit[1] };
}

function snotraSend(draftId: string): { sent: string } | { error: string } {
  if (!/^r-\d+$/.test(draftId)) return { error: 'invalid draft id' };
  const r = spawnSync('bash', [join(ROOT, 'systems/snotra/services/letters/mail-send.sh'), 'send', draftId],
    { encoding: 'utf8', timeout: 120_000 });
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  const hit = out.match(/^sent\t(\S+)/m);
  if (!hit) return { error: out.trim().split('\n').slice(-2).join(' · ') || 'send failed' };
  return { sent: hit[1] };
}

/* ---- /api/loaders, /api/checks, /api/settings ---------------------------- */
function parseToon(text: string): Record<string, string>[] {
  const rows: Record<string, string>[] = [];
  const lines = text.split('\n');
  const header = lines.find((l) => /\{[^}]+\}:/.test(l));
  if (!header) return rows;
  const keys = (header.match(/\{([^}]+)\}/) ?? ['', ''])[1].split(',');
  const start = lines.indexOf(header);
  for (let i = start + 1; i < lines.length; i++) {
    const l = lines[i];
    if (!/^\s{2,}"/.test(l)) break;
    const vals = l.trim().split(/","/).map((v) => v.replace(/^"|"$/g, ''));
    const row: Record<string, string> = {};
    keys.forEach((k, idx) => (row[k.trim()] = vals[idx] ?? ''));
    rows.push(row);
  }
  return rows;
}

async function loaders() {
  return parseToon(await runAsync(['bash', 'bin/seat/valknut-load.sh', '--status']));
}
async function checks() {
  try {
    return (JSON.parse(await runAsync(['bash', '.agents/skills/galdr-ymirsystem/scripts/compliance-check.sh', '--json'], 60000)).checks ?? []) as unknown[];
  } catch {
    return [];
  }
}
function settings() {
  const dir = CONFIG_DIR;
  if (!existsSync(dir)) return [];
  return readdirSync(dir).map((f) => {
    const v = read(join(dir, f)).trim().slice(0, 120);
    return { key: f, set: v.length > 0, value: v };
  });
}

/* ---- the live tail (Snotra) — a FRONT for snotra-live.sh, never a second --- *
 * pipeline. The SCRIPT owns the truth: the gate asks it and reports what the
 * script says. Nothing here re-implements transcription, slice timing or engine
 * discovery. The document stays in the hoard (`$YMIR_HOME/hodd/life/meetings/`);
 * only these three authenticated routes read it, and only for the operator. */
const LIVE_SCRIPT = 'systems/snotra/services/ear/snotra-live.sh';

/** A `stop` this gate spawned, still running. `stop` joins every slice into one
 *  WAV, re-transcribes the recording, asks the rail for a summary, writes the
 *  minutes and carves a Rune — MINUTES on a long meeting. So the POST answers at
 *  once, and this is how the surface says "closing the book…" rather than
 *  "stopped": the script silences ffmpeg in its first seconds, so `status`
 *  alone would report stopped while the minutes are still being written. */
let liveClosing: { since: number; done: Promise<unknown> } | null = null;

/** Parse the script's one TOON row: `live_tail{state:listening,doc:/path,…}`. */
function parseLiveRow(out: string): Record<string, string> {
  const row: Record<string, string> = {};
  const m = out.match(/live_tail\{([^}]*)\}/);
  if (!m) return row;
  for (const part of m[1].split(',')) {
    const i = part.indexOf(':');
    if (i > 0) row[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return row;
}

/** The newest `[hh:mm:ss] text` lines of the document the SCRIPT named. A read
 *  only — the words are the operator's own, never copied into the tree. */
function liveLines(doc: string, max = 40): string[] {
  if (!doc || !existsSync(doc)) return [];
  return read(doc)
    .split('\n')
    .filter((l) => /^\[\d{2}:\d{2}:\d{2}\]/.test(l))
    .slice(-max);
}

/** The honest state: `closing` outranks the script's own `stopped`, because the
 *  gate KNOWS a drain is in flight and the surface must never claim a state the
 *  work contradicts. */
async function liveStatus() {
  const out = await runAsync(['bash', LIVE_SCRIPT, 'status'], 1200);
  const row = parseLiveRow(out);
  const listening = row.state === 'listening';
  const doc = row.doc ?? '';
  return {
    state: liveClosing ? ('closing' as const) : listening ? ('listening' as const) : ('idle' as const),
    pid: row.ffmpeg || undefined,
    slices: row.slices_done ? Number(row.slices_done) : undefined,
    doc: doc || undefined,
    lines: listening || liveClosing ? liveLines(doc) : [],
    /** The script's own sentence after the row (the newest line, or its refusal). */
    said: out.split('\n').slice(1).join('\n').trim() || undefined,
  };
}

/* ---- /api/stream (SSE): new runes lines ---------------------------------- */
function stream() {
  let cursor = 0;
  try {
    cursor = statSync(RUNES).size;
  } catch {
    /* no ledger yet */
  }
  let tick: ReturnType<typeof setInterval> | null = null;
  return new Response(
    new ReadableStream({
      start(controller) {
        const enc = new TextEncoder();
        tick = setInterval(() => {
          try {
            const size = statSync(RUNES).size;
            if (size > cursor) {
              const tail = readFileSync(RUNES, 'utf8').slice(cursor);
              cursor = size;
              for (const line of tail.split('\n')) {
                if (!line.trim().startsWith('{')) continue;
                const e = JSON.parse(line);
                const ev = {
                  id: String(e.checksum ?? Date.now()).slice(0, 12),
                  ts: e.timestamp ?? new Date().toISOString(),
                  kind: 'rune',
                  from: e.actor ?? 'brokk',
                  module: e.event ?? '',
                  message: e.message ?? '',
                  checksum: String(e.checksum ?? '').slice(0, 8),
                };
                controller.enqueue(enc.encode(`data: ${JSON.stringify(ev)}\n\n`));
              }
            }
          } catch {
            /* keep streaming */
          }
        }, 2000);
      },
      cancel() {
        if (tick) { clearInterval(tick); tick = null; }
      },
    }),
    { headers: { 'content-type': 'text/event-stream', 'cache-control': 'no-store', connection: 'keep-alive' } },
  );
}

/* ---- /api/chat — Kaia, the oracle by the well ---------------------------- */
const CHAT_DIR = join(STATE_DIR, 'chat');
const CHAT_WINDOW = 40; // rolling context — the last 40 messages
const SAFE_SESSION = /^[A-Za-z0-9._-]+$/;
// Kaia speaks through the models the operator actually connected. The root Pi
// catalog (`~/.pi/agent/models.json`) is the source of truth for the llama.cpp
// router (`:8080`) and LM Studio; the Bifrost bridge (`:4603`) is the online
// fallback. We never guess a llama.cpp model id — we read the one `.pi` uses.
const PI_MODELS_PATH = join(homedir(), '.pi/agent/models.json');
const PI_SETTINGS_PATH = join(homedir(), '.pi/agent/settings.json');
const CHAT_BASES = [
  process.env.CHAT_BASE_URL,
  'http://127.0.0.1:8080/v1',
  'http://127.0.0.1:4603/v1',
].filter(Boolean) as string[];
const CHAT_MODEL_ENV = process.env.CHAT_MODEL;
const modelFor: Record<string, string> = {};

interface ChatTarget {
  base: string;
  model: string;
  key?: string;
  label: string;
  kind: 'local' | 'online';
}
interface ChatCatalogEntry extends ChatTarget {
  id: string;
  name: string;
  provider: string;
}

async function listModels(base: string): Promise<string[]> {
  const res = await fetch(`${base}/models`);
  const data = (await res.json()) as { data?: { id?: string }[] };
  return (data.data ?? []).map((m) => m.id ?? '').filter(Boolean);
}

/**
 * The keys Pi itself uses. `models.json` carries base + model and often NO key —
 * the provider's credential lives in `auth.json` as `{provider: {type, key}}`.
 * Reading only the catalog sent every rail call without an Authorization header,
 * so the local router answered 401 while the rail was up and serving: the chat
 * fell through to Bifrost and reported "no model backend answered".
 */
const PI_AUTH_PATH = join(homedir(), '.pi/agent/auth.json');
function piAuthKeys(): Record<string, string> {
  const out: Record<string, string> = {};
  try {
    const raw = JSON.parse(read(PI_AUTH_PATH)) as Record<string, { key?: string } | string>;
    for (const [pkey, pv] of Object.entries(raw)) {
      const key = typeof pv === 'string' ? pv : pv?.key;
      if (key) out[pkey] = key;
    }
  } catch {
    /* no auth file — an unauthenticated provider stays unauthenticated */
  }
  return out;
}

/** Providers from the root Pi catalog: the exact base/model/key Pi uses. */
function piCatalog(): ChatCatalogEntry[] {
  const out: ChatCatalogEntry[] = [];
  try {
    const raw = JSON.parse(read(PI_MODELS_PATH)) as {
      providers?: Record<string, { baseUrl?: string; apiKey?: string; models?: { id?: string }[] }>;
    };
    const authKeys = piAuthKeys();
    for (const [pkey, pv] of Object.entries(raw.providers ?? {})) {
      const base = pv.baseUrl ?? '';
      if (!base) continue;
      const kind: 'local' | 'online' = /(127\.0\.0\.1|localhost)/.test(base) ? 'local' : 'online';
      const models = (pv.models ?? []).map((m) => m.id ?? '').filter(Boolean);
      const single = models.length === 1;
      for (const mid of models) {
        out.push({
          id: single ? pkey : `${pkey}/${mid}`,
          name: mid,
          provider: pkey,
          kind,
          base,
          model: mid,
          key: pv.apiKey || authKeys[pkey],
          label: mid,
        });
      }
    }
  } catch {
    /* no Pi catalog — fall back to live probing */
  }
  return out;
}

async function resolveModel(base: string): Promise<string> {
  if (CHAT_MODEL_ENV) return CHAT_MODEL_ENV;
  if (modelFor[base]) return modelFor[base];
  const ids = await listModels(base);
  const pick = ids.find((i) => /gemma|qwen|deepseek|hermes/i.test(i)) ?? ids[0];
  if (!pick) throw new Error('no models advertised');
  modelFor[base] = pick;
  return pick;
}

/** Order the backends to try for a chosen model (or the operator's default). */
function resolveChatTarget(model?: string): ChatTarget[] {
  const cat = piCatalog();
  if (model) {
    // One model name can be advertised by several engines (LM Studio :1234,
    // the llama.cpp router :8080, Bifrost :4603). Return EVERY match — a dead
    // engine then falls through to a live one instead of failing the chat.
    // A provider-prefixed id (e.g. lmstudio/<m>) maps to the bare model name.
    const bare = model.includes('/') ? model.slice(model.indexOf('/') + 1) : model;
    const matches = cat.filter((e) => e.id === model || e.name === model || e.model === bare);
    if (matches.length) {
      const seen = new Set<string>();
      return matches.filter((e) => {
        const key = `${e.base}|${e.model}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
    }
    if (/^(opencode-go|opencode)\//.test(model)) {
      return [{ base: 'http://127.0.0.1:4603/v1', model, label: model, kind: 'online' }];
    }
    const raw: ChatTarget[] = [
      { base: 'http://127.0.0.1:8080/v1', model, label: model, kind: 'local' },
      { base: 'http://127.0.0.1:4603/v1', model, label: model, kind: 'online' },
    ];
    return raw;
  }
  // No choice: this seat's named default first (Rule 07 — env, never a literal in
  // the code), then the operator's Pi default, then any local catalog model.
  const targets: ChatTarget[] = [];
  // `CHAT_MODEL` names the model the chat asks when the operator has not picked
  // one. Without it the first local catalog entry won — `apodex-1.0-mini`, the
  // 21.7 GB preset — so the first message of the day swapped the rail away from
  // the model Pi itself was running (2026-10-23).
  if (CHAT_MODEL_ENV) {
    const named = cat.find(
      (e) => e.model === CHAT_MODEL_ENV || e.id === CHAT_MODEL_ENV || e.name === CHAT_MODEL_ENV,
    );
    if (named) targets.push(named);
  }
  try {
    const s = JSON.parse(read(PI_SETTINGS_PATH)) as { defaultProvider?: string; defaultModel?: string };
    const d = cat.find((e) => e.provider === s.defaultProvider && e.model === s.defaultModel) ?? cat.find((e) => e.provider === s.defaultProvider);
    if (d) targets.push(d);
  } catch {
    /* no settings */
  }
  const local = cat.find((e) => e.kind === 'local');
  if (local && !targets.some((t) => t.base === local.base && t.model === local.model)) targets.push(local);
  for (const base of CHAT_BASES) {
    if (!targets.some((t) => t.base === base)) targets.push({ base, model: '', label: '', kind: base.includes('4603') ? 'online' : 'local' });
  }
  return targets;
}

/** Try the ordered targets; return the first non-empty reply. */
async function chatCompletion(
  messages: { role: string; content: string }[],
  targets: ChatTarget[],
): Promise<{ body: string; backend: string; model: string }> {
  let lastErr = '';
  for (const t of targets) {
    try {
      const model = t.model || (await resolveModel(t.base));
      const headers: Record<string, string> = { 'content-type': 'application/json' };
      if (t.key) headers.authorization = `Bearer ${t.key}`;
      const res = await fetch(`${t.base}/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ model, messages, stream: false, temperature: 0.6, max_tokens: Number(process.env.YMIR_CHAT_MAX_TOKENS ?? 4096) }),   // deepseek-v4.1 spends budget on reasoning FIRST: 700 gave an empty answer
      });
      if (!res.ok) {
        lastErr = `${t.base} → ${res.status}`;
        continue;
      }
      const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
      const body = data.choices?.[0]?.message?.content?.trim();
      if (body) return { body, backend: t.base, model };
      lastErr = `${t.base} → empty`;
    } catch (err) {
      lastErr = `${t.base} → ${(err as Error).message}`;
    }
  }
  throw new Error(lastErr || 'no chat backend reachable');
}

/** The models the operator has connected: the root Pi catalog (exact ids,
 *  bases, keys), plus any live online backend. Free-typing is still allowed. */
async function chatModels(): Promise<{ id: string; name: string; provider: string; kind: 'local' | 'online' }[]> {
  const out = new Map<string, { id: string; name: string; provider: string; kind: 'local' | 'online' }>();
  for (const e of piCatalog()) out.set(e.id, { id: e.id, name: e.name, provider: e.provider, kind: e.kind });
  // Online providers Pi knows (opencode-go / opencode) — list without probing.
  try {
    const res = await fetch('http://127.0.0.1:4603/v1/models', { signal: AbortSignal.timeout(2500) });
    if (res.ok) {
      const data = (await res.json()) as { data?: { id?: string }[] };
      for (const m of data.data ?? []) {
        const id = m.id ?? '';
        if (id && !out.has(id)) out.set(id, { id, name: id, provider: 'opencode-go', kind: 'online' });
      }
    }
  } catch {
    /* bridge down */
  }
  return [...out.values()].sort((a, b) => a.id.localeCompare(b.id));
}

const KAIA_SYSTEM = [
  'You are Kaia, the oracle by the well (Mimirsbrunn), the orchestrator of the Ymir fleet.',
  'Address the Allfather directly in every reply; never respond with zero direct address.',
  'Apply Norse methodology: name subsystems for the role-matched figure; never use imported terms.',
  'Drink from the well before you answer; when a recall excerpt is provided, ground the reply in it.',
  'Be concise, direct, and action-oriented — produce outcomes, not preamble.',
  'You may dispatch Eindri in the real system; here, state plainly what you recalled and what you would dispatch.',
].join(' ');

interface ChatRow {
  id: string;
  from: 'user' | 'kaia';
  body: string;
  ts: string;
  recalling?: boolean;
  thinking?: boolean;
  error?: boolean;
  model?: string;
  agents?: string[];
}

function chatFile(session: string): string {
  const safe = SAFE_SESSION.test(session) ? session : 'default';
  return join(CHAT_DIR, `${safe}.jsonl`);
}

function chatHistory(session = 'default'): ChatRow[] {
  return read(chatFile(session))
    .split('\n')
    .filter((l) => l.trim().startsWith('{'))
    .map((l) => {
      try {
        return JSON.parse(l) as ChatRow;
      } catch {
        return null;
      }
    })
    .filter(Boolean) as ChatRow[];
}

function appendChat(session: string, row: ChatRow): void {
  mkdirSync(CHAT_DIR, { recursive: true });
  appendFileSync(chatFile(session), `${JSON.stringify(row)}\n`);
}

/** Every stored conversation, newest first; `default` always exists. */
function chatSessions(): { id: string; messages: number; updated_at: string | null }[] {
  mkdirSync(CHAT_DIR, { recursive: true });
  if (!existsSync(chatFile('default'))) appendFileSync(chatFile('default'), '');
  const ids = readdirSync(CHAT_DIR)
    .filter((f) => f.endsWith('.jsonl'))
    .map((f) => f.replace(/\.jsonl$/, ''))
    .filter((id) => SAFE_SESSION.test(id));
  return ids
    .map((id) => {
      const fp = chatFile(id);
      let messages = 0;
      let updated_at: string | null = null;
      try {
        messages = read(fp).split('\n').filter((l) => l.trim().startsWith('{')).length;
        updated_at = statSync(fp).mtime.toISOString();
      } catch {
        /* empty */
      }
      return { id, messages, updated_at };
    })
    .sort((a, b) => (b.updated_at ?? '').localeCompare(a.updated_at ?? ''));
}

function deleteChatSession(session: string): { ok: boolean } {
  try {
    unlinkSync(chatFile(session));
  } catch {
    /* already gone */
  }
  return { ok: true };
}

/** A bounded recall from the well — Kaia drinks before every dispatch.
 *  Relevance to the query first, recency as the tie-break. */
function chatRecall_uncached(query: string, limit = 6): { text: string; count: number } {
  const lines = read(WELL).split('\n').filter((l) => l.trim().startsWith('{'));
  const terms = query
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((w) => w.length > 3);
  const scored: { score: number; source: string; head: string; i: number }[] = [];
  for (const line of lines) {
    try {
      const e = JSON.parse(line) as { content?: string; source?: string };
      const content = String(e.content ?? '');
      const head = content.split('\n')[0].replace(/^#+\s*/, '').trim();
      if (!head) continue;
      const low = content.toLowerCase();
      let score = 0;
      for (const t of terms) if (low.includes(t)) score++;
      scored.push({ score, source: e.source ?? 'well', head, i: scored.length });
    } catch {
      /* skip malformed */
    }
  }
  scored.sort((a, b) => b.score - a.score || b.i - a.i);
  const picks = scored.slice(0, limit);
  return {
    text: picks.map((p) => `- (${p.source}) ${p.head.slice(0, 140)}`).join('\n'),
    count: picks.length,
  };
}

function chatRecall(query: string, limit = 6): { text: string; count: number } {
  return memo(`chatRecall:${query}:${limit}`, 3000, () => chatRecall_uncached(query, limit));
}

async function postChat(
  session: string,
  content: string,
  model?: string,
  agents?: string[],
): Promise<{ reply: ChatRow; live: boolean }> {
  mkdirSync(CHAT_DIR, { recursive: true });
  const sid = SAFE_SESSION.test(session) ? session : 'default';
  const user: ChatRow = { id: `u-${Date.now()}`, from: 'user', body: content, ts: new Date().toISOString() };
  appendChat(sid, user);

  // Rolling window of the last 40 messages — the context Kaia keeps in view.
  const history = chatHistory(sid).slice(-CHAT_WINDOW);
  const recall = chatRecall(content);
  const lanes = agents?.length ? `\n\nFocused Eindri lanes: ${agents.join(', ')}.` : '';
  const messages = [
    {
      role: 'system',
      content: `${KAIA_SYSTEM}${lanes}\n\nWell recall:\n${recall.text || '(dry — answer from first principles, and say the well was dry)'}`,
    },
    ...history.map((m) => ({ role: m.from === 'user' ? 'user' : 'assistant', content: m.body })),
  ];

  let body: string;
  let live = false;
  let usedModel: string | undefined;
  try {
    const out = await chatCompletion(messages, resolveChatTarget(model));
    body = out.body;
    usedModel = out.model;
    live = true;
  } catch (err) {
    body = `The well is local; no model backend answered (${(err as Error).message}). Recall ran; for a reply, raise a local model (llama-server on :8080) or the Bifrost bridge (\`bin/bridge/bifrost-bridge.sh\`).`;
  }

  const kaia: ChatRow = {
    id: `k-${Date.now()}`,
    from: 'kaia',
    body,
    ts: new Date().toISOString(),
    recalling: recall.count > 0,
    ...(usedModel ? { model: usedModel } : {}),
    ...(agents?.length ? { agents } : {}),
    ...(live ? {} : { error: true }),
  };
  appendChat(sid, kaia);
  return { reply: kaia, live };
}

/* ---- /api/prompts — the smithy's agent prompts, editable in the Forge ---- */
const PROMPT_ROOT = join(ROOT, 'smidja/smidja_data/prompt_engineering');

interface PromptFile {
  agent: string;
  kind: 'system' | 'user';
  path: string;
  body: string;
}

function prompts(): PromptFile[] {
  if (!existsSync(PROMPT_ROOT)) return [];
  const out: PromptFile[] = [];
  for (const agent of readdirSync(PROMPT_ROOT).sort()) {
    const dir = join(PROMPT_ROOT, agent);
    try {
      if (!statSync(dir).isDirectory()) continue;
    } catch {
      continue;
    }
    for (const kind of ['system', 'user'] as const) {
      const fp = join(dir, `${kind}.md`);
      if (existsSync(fp)) {
        out.push({ agent, kind, path: `smidja/smidja_data/prompt_engineering/${agent}/${kind}.md`, body: read(fp) });
      }
    }
  }
  return out;
}

function savePrompt(agent: string, kind: string, body: string): { ok: boolean; path: string } {
  if (!/^[A-Za-z0-9._-]+$/.test(agent) || (kind !== 'system' && kind !== 'user')) {
    throw new Error('bad prompt id');
  }
  const fp = join(PROMPT_ROOT, agent, `${kind}.md`);
  mkdirSync(dirname(fp), { recursive: true });
  writeFileSync(fp, body);
  return { ok: true, path: `smidja/smidja_data/prompt_engineering/${agent}/${kind}.md` };
}

/* ---- /api/workspaces + /api/setup — single-tenant workspaces ------------ */
function workspaces(): { id: string; name: string; kind: string; company?: string; domains: string[] }[] {
  let regPath = join(ROOT, 'registry/workspaces.yaml');
  const hoardReg = join(HOARD, 'identity/workspaces.yaml');
  try { read(hoardReg); regPath = hoardReg; } catch { /* fall back to the tracked scaffold */ }
  const txt = read(regPath);
  const out: { id: string; name: string; kind: string; company?: string; domains: string[] }[] = [];
  let cur: { id: string; name: string; kind: string; company?: string; domains: string[] } | null = null;
  for (const line of txt.split('\n')) {
    const idm = line.match(/^\s*-\s+id:\s*(\S+)/);
    if (idm) {
      if (cur) out.push(cur);
      cur = { id: idm[1], name: idm[1], kind: 'personal', domains: [] };
      continue;
    }
    if (!cur) continue;
    const nm = line.match(/^\s*name:\s*(.+)$/);
    if (nm) cur.name = nm[1].trim();
    const km = line.match(/^\s*kind:\s*(\S+)/);
    if (km) cur.kind = km[1];
    const cm = line.match(/^\s*company:\s*(\S+)/);
    if (cm) cur.company = cm[1];
    const dm = line.match(/^\s*domains:\s*\[(.*)\]/);
    if (dm) cur.domains = dm[1].split(',').map((s) => s.trim()).filter(Boolean);
  }
  if (cur) out.push(cur);
  return out.length ? out : [
    { id: 'work', name: 'Work', kind: 'work', domains: ['company', 'marketing', 'development', 'life'] },
    { id: 'personal', name: 'Personal', kind: 'personal', domains: ['me', 'life', 'development'] },
  ];
}

async function setupStatus() {
  return parseToon(await runAsync(['bash', 'bin/engine/ymir-install.sh', '--check'], 30000));
}
function setupRun() {
  return parseToon(run(['bash', 'bin/engine/ymir-install.sh', '--skip-services']));
}
function workspaceProvision(name: string, kind: string, domains: string) {
  return parseToon(run(['bash', 'bin/agents/workspace-provision.sh', name, '--kind', kind, '--domains', domains]));
}

/* ---- tunnel gate (hardcoded for now) ------------------------------------- */
// Temporary HTTP Basic Auth for the public tunnel. Override with
// HLIDSKJALF_AUTH="user:pass"; replace with Heimdall (oauth2-proxy) later.
const GATE_AUTH = process.env.HLIDSKJALF_AUTH ?? '';
const SMIDJA_URL = process.env.SMIDJA_VIZ_URL ?? 'http://127.0.0.1:8437';
// No default host: which hostname serves the smithy is the machine's fact.
const SMIDJA_HOST = (process.env.SMIDJA_HOST ?? '').toLowerCase();
const ODRERIR_HOST = (process.env.ODRERIR_HOST ?? '').toLowerCase();
/** The one door: the primary host that carries Hlidskjalf's own login. Every app
 *  host redirects its unauthenticated visitors here, with where they were going. */
const PRIMARY_HOST = (process.env.YMIR_PRIMARY_HOST ?? '').toLowerCase();
const ODRERIR_URL = process.env.ODRERIR_URL ?? 'http://127.0.0.1:4322';
/** Every app host the gate fronts: unauthenticated visitors get the login, never
 *  the app. Add a row when an app earns a public hostname. */
const APP_HOSTS: Array<{ host: string; base: string; name: string }> = [
  { host: SMIDJA_HOST, base: SMIDJA_URL, name: 'Smíðja' },
  { host: ODRERIR_HOST, base: ODRERIR_URL, name: 'Óðrerir' },
].filter((a) => a.host !== '');
const DIST = join(ROOT, 'apps/hlidskjalf/dist');

/**
 * Sessions SURVIVE a restart. The cookie used to be a key in a process-local
 * Map, so every API restart silently voided every session — and the boards
 * painted the refused calls as ZEROS: 0 jobs in Nornir, 0/0 watched in Valhalla,
 * while the scheduler ran 33 jobs and 56 daemons were up (2026-10-23, both
 * reported to the Allfather as "dead"). A door that forgets who came in is not
 * a lock, it is a trapdoor.
 *
 * The token is a signed statement (`login.expiry.mac`), not a row in memory:
 * the law that no session is WRITTEN to disk still stands — what lives on disk
 * is the signing key, one machine secret under the hoard's state (0600).
 */
const SESSION_TTL_S = Number(process.env.YMIR_SESSION_TTL_SECONDS ?? 60 * 60 * 24 * 30);
const SESSION_KEY = (() => {
  const fromEnv = process.env.YMIR_SESSION_SECRET;
  if (fromEnv) return fromEnv;
  const path = join(HOARD, 'state', 'gate-session.key');
  try {
    const k = readFileSync(path, 'utf8').trim();
    if (k) return k;
  } catch {
    /* first run on this machine */
  }
  const k = randomBytes(32).toString('hex');
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${k}\n`, { mode: 0o600 });
  } catch {
    /* an unwritable hoard still signs for this process's lifetime */
  }
  return k;
})();
function sessionMac(login: string, exp: number): string {
  return createHmac('sha256', SESSION_KEY).update(`${login}\u0000${exp}`).digest('base64url');
}
/** Mint the cookie's value: who, until when, and a MAC binding both. */
function mintSession(login: string): string {
  const exp = Math.floor(Date.now() / 1000) + SESSION_TTL_S;
  return `${Buffer.from(login, 'utf8').toString('base64url')}.${exp}.${sessionMac(login, exp)}`;
}
/** The login a token vouches for, or null — expired and forged alike are null. */
function readSession(token: string): string | null {
  const [b64, expRaw, mac] = token.split('.');
  if (!b64 || !expRaw || !mac) return null;
  const exp = Number(expRaw);
  if (!Number.isFinite(exp) || exp * 1000 < Date.now()) return null;
  let login = '';
  try {
    login = Buffer.from(b64, 'base64url').toString('utf8');
  } catch {
    return null;
  }
  if (!login) return null;
  const want = Buffer.from(sessionMac(login, exp));
  const got = Buffer.from(mac);
  if (want.length !== got.length || !timingSafeEqual(want, got)) return null;
  return login;
}

/**
 * The token a request carries is the httpOnly `ymir_session` cookie — and nothing
 * else. There is deliberately NO header credential (no `X-Ymir-Session`/`Bearer`)
 * and no stored session: every app must be verified live by this gate rather
 * than read a file that claims a session. The gate is the one authority.
 */
function cookieToken(req: Request): string {
  const c = req.headers.get('cookie') ?? '';
  const m = c.match(/(?:^|;\s*)ymir_session=([^;]+)/);
  return m ? m[1] : '';
}
function isAuthed(req: Request): boolean {
  if (isDesktopSeat(req)) return true;
  return !!readSession(cookieToken(req));
}

/** The peer address per request: Bun's Request has no socket, so it is recorded
 *  at the top of the handler. */
const REQUEST_IP = new WeakMap<Request, string>();

/**
 * The desktop seat (Electron) is local and trusted, so it is never asked to log
 * in: the shell loads this app from 127.0.0.1 and its preload marks every
 * request with `x-ymir-surface: desktop`. The marker alone proves nothing — a
 * web caller could send the header too — so it is honoured ONLY when the request
 * genuinely arrives over loopback, which a remote client never does. The web
 * door keeps its lock.
 */
function isDesktopSeat(req: Request): boolean {
  // A header where the client can set one; a query marker where it cannot —
  // EventSource (the live Runes stream) sends no custom headers.
  const marked =
    (req.headers.get('x-ymir-surface') ?? '') === 'desktop' ||
    new URL(req.url).searchParams.get('surface') === 'desktop';
  if (!marked) return false;
  const ip =
    REQUEST_IP.get(req) ??
    (req as Request & { socket?: { remoteAddress?: string } }).socket?.remoteAddress ??
    '';
  const bare = ip.startsWith('::ffff:') ? ip.slice('::ffff:'.length) : ip;
  return bare === '127.0.0.1' || bare === '::1';
}

/** Who the gate says you are: the desktop seat wears the operator's own name. */
function seatOf(req: Request): string {
  if (isDesktopSeat(req)) {
    const user = (GATE_AUTH || '').split(':')[0];
    return user || 'operator';
  }
  return loginOf(req);
}

/** The login behind a request's session, if any. */
function loginOf(req: Request): string | null {
  return readSession(cookieToken(req));
}

/** Begin a session and hand back the cookie. No session is kept on disk. */
function sessionResponse(login: string): Response {
  const token = mintSession(login);
  return new Response(JSON.stringify({ ok: true, login }), {
    headers: {
      'content-type': 'application/json',
      'set-cookie': `ymir_session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000`,
    },
  });
}

/** The login screen for an app host — same gate, same credentials. */

/** Forward an authed Smíðja-host request to the visualizer on :8437. */
async function proxyApp(req: Request, url: URL, base = SMIDJA_URL, label = 'smidja'): Promise<Response> {
  const headers = new Headers(req.headers);
  headers.delete('host');
  headers.delete('cookie');
  headers.delete('connection');
  const init: RequestInit = { method: req.method, headers, redirect: 'manual' };
  if (req.method !== 'GET' && req.method !== 'HEAD') init.body = await req.arrayBuffer();
  try {
    const up = await fetch(`${base}${url.pathname}${url.search}`, init);
    return new Response(up.body, { status: up.status, headers: up.headers });
  } catch (err) {
    return json({ error: `${label} upstream unreachable: ${(err as Error).message}` }, 502);
  }
}

const STATIC_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.map': 'application/json',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.apk': 'application/vnd.android.package-archive',
};

function serveStatic(pathname: string): Response {
  const rel = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  let file = join(DIST, rel);
  if (!file.startsWith(DIST) || !existsSync(file) || statSync(file).isDirectory()) file = join(DIST, 'index.html');
  const ext = extname(file).toLowerCase();
  const headers: Record<string, string> = { 'content-type': STATIC_TYPES[ext] ?? 'application/octet-stream' };
  if (ext === '.html') headers['cache-control'] = 'no-cache, no-store, must-revalidate';
  if (ext === '.apk') headers['content-disposition'] = 'attachment; filename="ymir.apk"';
  if (ext === '.apk' || ext === '.woff' || ext === '.woff2' || ext === '.ttf') headers['cache-control'] = 'public, max-age=86400';
  try {
    return new Response(readFileSync(file), { headers });
  } catch {
    return new Response('Not found', { status: 404 });
  }
}

/* ---- server -------------------------------------------------------------- */
// Sessions are in-memory only: a gate restart ends them, and nothing on disk can
// revive one. That is the point — no bearer is kept at rest.
const HOST = process.env.HLIDSKJALF_HOST ?? '127.0.0.1';
const server = Bun.serve({
  hostname: HOST,
  port: PORT,
  async fetch(req, srv) {
    const url = new URL(req.url);
    const p = url.pathname;
    // Bun's Request carries no socket; the peer address comes from the server.
    // Recorded per request (a WeakMap, so concurrent requests cannot mix).
    REQUEST_IP.set(req, srv.requestIP(req)?.address ?? '');
    try {
      if (p === '/api/login' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as { username?: string; password?: string };
        const user = b.username ?? '';
        const pass = b.password ?? '';
        // Two ways in: the operator's own credentials (HLIDSKJALF_AUTH), or an
        // account minted with an invite code.
        let login: string | null = null;
        if (GATE_AUTH && `${user}:${pass}` === GATE_AUTH) login = user;
        else if (user && pass) login = await verifyAccount(user, pass);
        if (login) return sessionResponse(login);
        return json({ error: 'invalid credentials' }, 401);
      }
      if (p === '/api/register' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as {
          username?: string;
          password?: string;
          invite?: string;
        };
        const made = await register(b.username ?? '', b.password ?? '', b.invite ?? '');
        if (!made.ok) return json({ error: made.reason }, 403);
        return sessionResponse(made.login);
      }
      /* ---- GitHub: the same gate, a second door ---------------------------- *
       * Sign-in with GitHub never creates access on its own. It names a login,
       * and that login must already hold an account — accounts come from an
       * invite, so the door stays closed to strangers however they arrive. */
      if (p === '/api/auth/github' && req.method === 'GET') {
        const clientId = process.env.GITHUB_CLIENT_ID ?? '';
        const clientSecret = process.env.GITHUB_CLIENT_SECRET ?? '';
        if (!clientId || !clientSecret) {
          return json(
            {
              error:
                'GitHub sign-in is not configured. Set GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET in .env.local (a GitHub OAuth app) and restart the gate.',
            },
            503,
          );
        }
        const state = crypto.randomUUID();
        const redirect = `${url.origin}/api/auth/github/callback`;
        const authorize =
          'https://github.com/login/oauth/authorize' +
          `?client_id=${encodeURIComponent(clientId)}` +
          `&redirect_uri=${encodeURIComponent(redirect)}` +
          '&scope=read:user&state=' +
          encodeURIComponent(state);
        return new Response(JSON.stringify({ url: authorize }), {
          headers: {
            'content-type': 'application/json',
            'set-cookie': `ymir_oauth_state=${state}; Path=/; HttpOnly; SameSite=Lax; Max-Age=600`,
          },
        });
      }
      if (p === '/api/auth/github/callback' && req.method === 'GET') {
        const clientId = process.env.GITHUB_CLIENT_ID ?? '';
        const clientSecret = process.env.GITHUB_CLIENT_SECRET ?? '';
        const code = url.searchParams.get('code') ?? '';
        const state = url.searchParams.get('state') ?? '';
        const expected = (req.headers.get('cookie') ?? '').match(/ymir_oauth_state=([^;]+)/)?.[1] ?? '';
        if (!code) return json({ error: 'GitHub returned no code' }, 400);
        if (!state || state !== expected) return json({ error: 'OAuth state did not match' }, 400);
        const tokenRes = await fetch('https://github.com/login/oauth/access_token', {
          method: 'POST',
          headers: { 'content-type': 'application/json', accept: 'application/json' },
          body: JSON.stringify({ client_id: clientId, client_secret: clientSecret, code }),
        });
        const tok = (await tokenRes.json().catch(() => ({}))) as { access_token?: string };
        if (!tok.access_token) return json({ error: 'GitHub refused the code' }, 502);
        const userRes = await fetch('https://api.github.com/user', {
          headers: {
            authorization: `Bearer ${tok.access_token}`,
            accept: 'application/vnd.github+json',
            'user-agent': 'ymir-gate',
          },
        });
        const gh = (await userRes.json().catch(() => ({}))) as { login?: string };
        const login = (gh.login ?? '').trim().toLowerCase();
        if (!login) return json({ error: 'GitHub returned no login' }, 502);
        if (!findAccount(login)) {
          return json(
            { error: `No account is held for the GitHub login '${login}'. Ask for an invite code, then register.` },
            403,
          );
        }
        return sessionResponse(login);
      }
      if (p === '/api/invites' && req.method === 'GET' && isAuthed(req)) {
        // The operator's own view of who may still be let in.
        return json({
          invites: listInvites().map((i) => ({ ...i, code: i.code })),
          accounts: listAccounts(),
        });
      }
      if (p === '/api/session') {
        const reqHost = (req.headers.get('host') ?? '').toLowerCase().split(':')[0];
        const local = reqHost === 'localhost' || reqHost === '127.0.0.1' || reqHost === '::1' || reqHost === '';
        return json({
          authed: (GATE_AUTH && !local) ? isAuthed(req) : true,
          login: seatOf(req) ?? (voiceAccess(req, REQUEST_IP.get(req) ?? '', true) === null ? 'operator' : null),
          // The login surface shows "create an account" only while a live invite
          // exists — a newcomer with a code can enter, and nobody else can.
          registration: invitesOpen(),
          // GitHub is a second door only when an OAuth app is configured; the
          // login surface hides the button otherwise (it would 503).
          github: !!(process.env.GITHUB_CLIENT_ID && process.env.GITHUB_CLIENT_SECRET),
        });
      }
      if (p === '/api/logout' && req.method === 'POST') {
        // The cookie is cleared client-side; the signed token expires on its own.
        return new Response(JSON.stringify({ ok: true }), {
          headers: { 'content-type': 'application/json', 'set-cookie': 'ymir_session=; Path=/; Max-Age=0' },
        });
      }
      // The Smíðja host rides the same gate: sign in here, then every request
      // is reverse-proxied to the visualizer on :8437.
      const host = (req.headers.get('host') ?? '').toLowerCase().split(':')[0];
      const app = APP_HOSTS.find((a) => a.host === host);
      if (app) {
        if (!isAuthed(req)) {
          // No dead login page: send them to the one login, remembering the app.
          if (p.startsWith('/api/')) return json({ error: 'unauthorized' }, 401);
          const scheme = (req.headers.get('x-forwarded-proto') ?? 'https').split(',')[0];
          const door = PRIMARY_HOST || host;
          return new Response(null, {
            status: 302,
            headers: { location: `${scheme}://${door}/?next=${encodeURIComponent(url.toString())}` },
          });
        }
        return proxyApp(req, url, app.base, app.name);
      }
      // Login is only demanded from outside the machine: a request that arrives
      // on loopback (the local desktop seat) is trusted without a session.
      const reqHost = (req.headers.get('host') ?? '').toLowerCase().split(':')[0];
      const local = reqHost === 'localhost' || reqHost === '127.0.0.1' || reqHost === '::1' || reqHost === '';
      if (GATE_AUTH && !local && p.startsWith('/api/') && !isAuthed(req)) return json({ error: 'unauthorized' }, 401);
      if (p.startsWith('/api/skirnir/voice/')) {
        const login = loginOf(req);
        const owner = isDesktopSeat(req) || !login || login === ((GATE_AUTH || '').split(':')[0] || 'operator');
        const refusal = voiceAccess(req, REQUEST_IP.get(req) ?? '', owner);
        if (refusal) return refusal;
        return voice(req, seatOf(req) ?? 'local-operator');
      }
      if (p === '/api/health') return json({ ok: true, root: ROOT, sessions: orders().length });
      if (p === '/api/mail/accounts') {
        if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);
        return mailDesk('/accounts');
      }
      if (p === '/api/mail/queue') {
        if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);
        return mailDesk('/queue', {
          account: url.searchParams.get('account') ?? '',
          hours: url.searchParams.get('hours') ?? '48',
        });
      }
      if (p === '/api/mail/message') {
        if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);
        return mailDesk('/message', {
          account: url.searchParams.get('account') ?? '',
          id: url.searchParams.get('id') ?? '',
        });
      }
      // Þráðr's status strip (plan 93): the panel asked for a door this gate never had,
      // so it printed "terminal status 404" — an error string where a truth belongs.
      // There is no pty in this process (the backend is a separate errand), so the route
      // reports the seat's real capability instead of pretending to hold a shell.
      if (p === '/api/terminal/status') return json({
        enabled: process.env.YMIR_TERMINAL === '1',
        remoteAllowed: process.env.YMIR_TERMINAL_REMOTE === '1',
        shell: process.env.SHELL || '/bin/bash',
        cwd: ROOT,
        open: 0,
        maxPerUser: Number(process.env.YMIR_TERMINAL_MAX_PER_USER ?? 2),
        idleTimeoutMs: Number(process.env.YMIR_TERMINAL_IDLE_MS ?? 900_000),
        reason: (process.env.YMIR_TERMINAL === '1')
          ? 'enabled, but this gate holds no pty — the terminal backend is plan 93'
          : 'disabled: YMIR_TERMINAL is not 1, and this gate holds no pty',
      });
      if (p === '/api/usage') {
        // What the HARNESSES spent — opencode and pi — not only the smithy's runs.
        // Memoised for a minute: the aggregate is one bounded SQL statement over a
        // 37 GB store, and a panel must not pay for it on every poll.
        return json(await memoAsync('usage', 60_000, async () => {
          try {
            const { execFileSync } = await import('node:child_process');
            const script = new URL('../../../bin/desktop/hlidskjalf-usage.sh', import.meta.url).pathname;
            const out = execFileSync(script, ['--days', process.env.YMIR_USAGE_DAYS ?? '30'], { timeout: 60_000 }).toString().trim();
            return JSON.parse(out);
          } catch (e) {
            return { error: String(e).slice(0, 120) };
          }
        }));
      }
      if (p === '/api/core-four') {
        // THE FOUR DIALS in one read: the model, the window and both compaction
        // thresholds, the prompt surfaces in force, the tool count by source.
        return json(await seatDoor('core-four', 30_000));
      }
      if (p === '/api/pending') {
        // WHAT WAITS ON HIM: open PRs, the wake queue, mail drafts, his own decisions.
        // A short memo, because this is a live question and a stale answer is a wrong one.
        return json(await seatDoor('pending', 15_000));
      }
      if (p === '/api/context') {
        // THIS session's context, as the harness already wrote it: used · window ·
        // remaining · the two thresholds · compactions seen · the verdict.
        return json(await seatDoor('context', 15_000));
      }
      if (p === '/api/plans') {
        // THE LEDGER — the READ source. Skuld stays the WRITE door (plans_create).
        return json(await memoAsync('plans', 30_000, planLedger));
      }
      if (p === '/api/worktrees') return json(await worktrees());
      if (p === '/api/me') return json({ login: loginOf(req) ?? 'operator', realm: 'work' });
      if (p === '/api/workspace') {
        const realm = url.searchParams.get('realm') ?? 'work';
        return json({ realm, path: workspaceRoot(realm) });
      }
      if (p === '/api/agents') {
        // WHO IS STANDING, not who could be. The connector reads herdr's live
        // pane list, so every opencode and pi session appears on the board with
        // its kind, state and task. The roster is the fallback, never the answer.
        try {
          const { execFileSync } = await import('node:child_process');
          const script = new URL('../../../bin/desktop/hlidskjalf-agents.sh', import.meta.url).pathname;
          // cwd is ROOT and ROSTER_DIR is the absolute roster, so the connector's
          // roster path cannot resolve against the wrong directory.
          const out = execFileSync(script, [], {
            timeout: 4000,
            cwd: ROOT,
            env: { ...process.env, ROSTER_DIR: AGENTS_ALT },
          }).toString().trim();
          // An EMPTY array is not data: herdr was absent or no pane answered.
          // Fall through to the roster, exactly as the comment below promises.
          if (out.startsWith('[')) {
            const rows = JSON.parse(out) as unknown;
            if (Array.isArray(rows) && rows.length > 0) {
              return new Response(out, { headers: { 'content-type': 'application/json' } });
            }
          }
        } catch {
          // herdr absent or the connector failed: fall through to the roster
        }
        return json(agents());
      }
      if (p === '/api/tasks') return json(tasks());
      if (p === '/api/orders') return json({ open: orders().filter((o) => o.status !== 'COMPLETED').length, orders: orders() });
      if (p === '/api/runes') return json(runes());
      if (p === '/api/well') return json(await well(url.searchParams.get('q') ?? ''));
      if (p === '/api/well/episode') return json((await wellEpisode(url.searchParams.get('id') ?? '')) ?? { error: 'not found' });
      if (p === '/api/mimir/health') return json(await mimirHealth());
      if (p === '/api/processes') return json(await processes());
      if (p === '/api/ward') return json(wardState());
      // The reviews gate shells out twice (lint + compliance), each with a 60s cap,
      // so an unmemoised poll leaves Glitnir hanging for a minute and reads as a
      // dead surface. One answer per minute is what a human review board needs.
      if (p === '/api/reviews') return json(await memoAsync('reviews', 60_000, reviews));
      if (p === '/api/files') return json(files(url.searchParams.get('realm') ?? 'work'));
      if (p === '/api/file') return json(fileContent(url.searchParams.get('realm') ?? 'work', url.searchParams.get('path') ?? ''));
      if (p === '/api/skills') return json(skills());
      if (p === '/api/runtime') return json(await runtime());
      // A speed-start from the UI. It calls the same launcher the Omarchy key
      // bindings use, so the app is raised when it is already up and started
      // when it is not — one way to raise a Ymir window, not two.
      if (p === '/api/desktop' && req.method === 'POST') {
        const body = (await req.json().catch(() => ({}))) as { view?: string };
        const view = body?.view;
        // odrerir is the fourth hall: its board is read-only, but its WINDOW is an
        // Electron app like the others, so a rune must raise it, never open a tab.
        const VIEWS = ['hlidskjalf', 'smidja', 'sessrumnir', 'odrerir'] as const;
        if (!VIEWS.includes(view as (typeof VIEWS)[number])) {
          return json({ error: 'view must be hlidskjalf, smidja, sessrumnir, or odrerir' }, 400);
        }
        // Hlidskjalf and Smíðja are views of the one Electron shell; Sessrúmnir
        // is its own app with its own launcher.
        const argv = view === 'sessrumnir'
          ? ['bash', join(ROOT, 'bin', 'sessrumnir.sh'), 'start']
          : ['bash', join(ROOT, 'scripts', 'electron.sh'), 'start', '--view', view];
        const proc = Bun.spawn(argv, { stdout: 'pipe', stderr: 'pipe', env: process.env });
        const out = await new Response(proc.stdout).text();
        await proc.exited;
        return json({ view, ok: proc.exitCode === 0, output: out.trim().slice(-400) });
      }
      if (p === '/api/calendar') return json(calendar());
      if (p === '/api/cron') return json(await cron());
      if (p === '/api/cron/start' && req.method === 'POST') return json(await cronAct('start'));
      if (p === '/api/cron/stop' && req.method === 'POST') return json(await cronAct('stop'));
      if (p === '/api/cron/seats') return json(await cronSeats());
      if (p === '/api/loaders') return json(await loaders());
      if (p === '/api/checks') return json(await checks());
      if (p === '/api/smidja/health') return json(smidjaHealth());
      if (p === '/api/smidja/sessions') return json(smidjaSessions());
      if (p === '/api/smidja/decisions') return json(smidjaDecisions());
      if (p === '/api/smidja/stats') return json(smidjaStats());
      if (p === '/api/snotra/live') {
        if (req.method !== 'GET') return json({ error: 'method not allowed' }, 405);
        return json(await liveStatus());
      }
      if (p === '/api/snotra/live/start' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as { slug?: string; topic?: string };
        // The script sanitises the slug itself; the gate does the SAME shaping so
        // the operator is shown the name that will actually be written.
        const slug =
          (b.slug ?? '')
            .trim()
            .replace(/[^a-zA-Z0-9._-]/g, '-')
            .replace(/^-+|-+$/g, '') || 'note';
        const topic = (b.topic ?? '').trim();
        const script = join(ROOT, LIVE_SCRIPT);
        if (!existsSync(script)) return json({ ok: false, error: 'snotra-live.sh is not on this seat' }, 500);
        // A stop that is still draining owns the ear; opening a second one now
        // would race it. The gate KNOWS this — the script's own probe cannot see
        // its own detached child.
        if (liveClosing) return json({ ok: false, error: 'the last book is still closing — wait for it' }, 409);
        // `start` returns as soon as the capture is alive, so a bounded wait is
        // right here (the /api/desktop precedent). `stop` is the slow one.
        const proc = Bun.spawnSync(['timeout', '20', 'bash', script, 'start', slug, ...(topic ? [topic] : [])], {
          cwd: ROOT,
          stdout: 'pipe',
          stderr: 'pipe',
          // THIS BUTTON IS THE SANCTIONED LOCAL-ROOM DOOR (the Allfather's word,
          // 2026-10-31: "we have a button in Hlidskjalf that should activate the
          // mic. that's the main way to the mic"). The script refuses the
          // microphone unless the caller says the room is local, so the gate is
          // the ONE place that says it — and it says it for a room of people
          // physically here, never for an online meeting (that is the bot's job).
          env: { ...process.env, SNOTRA_LOCAL_ROOM: '1' },
        });
        const out = new TextDecoder().decode(proc.stdout ?? new Uint8Array()).trim();
        const err = new TextDecoder().decode(proc.stderr ?? new Uint8Array()).trim();
        if (proc.exitCode !== 0) {
          // ONE EAR AT A TIME: the refusal is the SCRIPT'S OWN sentence (it says
          // which ear is busy), never a generic error invented by the surface.
          const said = (out || err).split('\n').find((l) => l.trim()) ?? 'the live tail refused to open';
          return json({ ok: false, error: said.trim() }, 409);
        }
        return json({ ok: true, slug, said: out });
      }
      if (p === '/api/snotra/live/stop' && req.method === 'POST') {
        const script = join(ROOT, LIVE_SCRIPT);
        if (!existsSync(script)) return json({ closing: false, error: 'snotra-live.sh is not on this seat' }, 500);
        if (liveClosing) return json({ closing: true });
        const before = parseLiveRow(await runAsync(['bash', LIVE_SCRIPT, 'status'], 0));
        if (before.state !== 'listening') {
          // The script's own wording for this door, so the surface never invents one.
          return json({ closing: false, error: 'no live tail is running' }, 409);
        }
        // DETACHED ON PURPOSE. `stop` joins every slice, re-transcribes the
        // recording, asks the rail for a summary, writes the minutes and carves
        // a Rune — MINUTES on a long meeting. A browser waiting on that POST
        // times out and looks broken while the work is fine. Answer now, let the
        // surface poll `closing` until the script has finished.
        const proc = Bun.spawn(['bash', script, 'stop'], { cwd: ROOT, stdout: 'ignore', stderr: 'ignore', env: process.env });
        liveClosing = { since: Date.now(), done: proc.exited.then(() => { liveClosing = null; }) };
        return json({ closing: true });
      }
      if (p.startsWith('/api/smidja/sessions/')) {
        const id = decodeURIComponent(p.slice('/api/smidja/sessions/'.length));
        const detail = smidjaSession(id);
        return detail ? json(detail) : json({ error: `no session ${id}` }, 404);
      }
      if (p === '/api/snotra/meetings' && req.method === 'GET') return json({ meetings: snotraMeetings() });
      if (p === '/api/snotra/meeting' && req.method === 'GET') {
        const id = url.searchParams.get('id') ?? '';
        const m = snotraFind(id);
        if (!m) return json({ error: 'no meeting' }, 404);
        const body = ['minutes.md', 'record.md'].map((f) => join(m.dir, f)).find(existsSync);
        const src = ['record.json', 'meeting.json'].map((f) => join(m.dir, f)).find(existsSync);
        let detail: Record<string, unknown> = {};
        if (src) { try { detail = JSON.parse(readFileSync(src, 'utf8')); } catch { /* broken record */ } }
        return json({ ...m, record: body ? readFileSync(body, 'utf8') : null,
          decisions: (detail as any).decisions ?? [], actions: (detail as any).actions ?? [] });
      }
      if (p === '/api/snotra/draft' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as { id?: string };
        const r = snotraDraft(String(b.id ?? ''));
        return 'error' in r ? json(r, 400) : json(r);
      }
      if (p === '/api/snotra/send' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as { draftId?: string };
        const r = snotraSend(String(b.draftId ?? ''));
        return 'error' in r ? json(r, 400) : json(r);
      }
      if (p === '/api/settings') return json(settings());
      if (p === '/api/workspaces' && req.method === 'GET') return json(workspaces());
      if (p === '/api/workspaces' && req.method === 'POST') {
        const b = (await req.json().catch(() => ({}))) as { name?: string; kind?: string; domains?: string[] | string };
        const name = (b.name ?? '').trim().toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/(^-|-$)/g, '');
        if (!name) return json({ error: 'workspace needs a name' }, 400);
        const kind = b.kind === 'work' ? 'work' : 'personal';
        const domains = Array.isArray(b.domains) ? b.domains.join(',') : b.domains ?? '';
        return json(workspaceProvision(name, kind, domains));
      }
      if (p === '/api/setup/status') return json(await setupStatus());
      if (p === '/api/setup/run' && req.method === 'POST') return json(setupRun());
      if (p === '/api/prompts' && req.method === 'GET') return json(prompts());
      if (p === '/api/prompts' && req.method === 'POST') {
        const body = (await req.json().catch(() => ({}))) as { agent?: string; kind?: string; body?: string };
        if (!body.agent || !body.kind) return json({ error: 'prompt needs agent + kind' }, 400);
        return json(savePrompt(body.agent, body.kind, body.body ?? ''));
      }
      if (p === '/api/stream') return stream();
      if (p === '/api/chat/models') return json(await chatModels());
      if (p === '/api/chat/sessions') return json(chatSessions());
      if (p === '/api/chat/history') return json(chatHistory(url.searchParams.get('session') ?? 'default'));
      if (p === '/api/chat/session' && req.method === 'DELETE') {
        return json(deleteChatSession(url.searchParams.get('session') ?? 'default'));
      }
      if (p === '/api/chat' && req.method === 'POST') {
        const body = (await req.json().catch(() => ({}))) as {
          session?: string;
          content?: string;
          model?: string;
          agents?: string[];
        };
        const content = (body.content ?? '').trim();
        if (!content) return json({ error: 'chat needs content' }, 400);
        return json(await postChat(body.session ?? 'default', content, body.model, body.agents));
      }
      if (p.startsWith('/api/')) return json({ error: `no route ${p}` }, 404);
      return serveStatic(p);
    } catch (err) {
      return json({ error: (err as Error).message }, 500);
    }
  },
});

console.log(`[hlidskjalf] gate api   http://127.0.0.1:${server.port}`);
console.log(`[hlidskjalf] runtime    ${ROOT}`);

/* ---- /api/ward — HIMINBJÖRG, the watchtower ------------------------------- */
// Garmr notices, Vörðr judges, Gná speaks. The tower shows what the hound wrote:
// the state of the two units, the heartbeat (a silent hound is a finding), and the
// newest judgements. It reads files only; it never starts, stops or closes anything.
function wardState() {
  // the home is already resolved once at the top of this file (Rule 07): env ->
  // the recorded choice -> one default. Never a second guess here.
  const home = HOME_DIR;
  const judged = join(home, 'hodd/state/garmr/judged.jsonl');
  const pausedMarker = join(home, 'hodd/state/garmr/PAUSED');
  const heartbeatFile = '/var/log/ymir/garmr/state/hound.heartbeat';
  const findingsFile = '/var/log/ymir/garmr/findings.jsonl';

  const counts: Record<string, number> = { INFO: 0, MEDIUM: 0, HIGH: 0, CRITICAL: 0 };
  const newest: Array<Record<string, unknown>> = [];
  let totalJudged = 0;
  if (existsSync(judged)) {
    const lines = read(judged).split('\n').filter((l) => l.trim().startsWith('{'));
    totalJudged = lines.length;
    for (const line of lines.slice(-2000)) {
      try {
        const row = JSON.parse(line);
        const sev = String(row.severity ?? 'INFO');
        counts[sev] = (counts[sev] ?? 0) + 1;
        if (sev === 'HIGH' || sev === 'CRITICAL') {
          newest.push({
            ts: row.ts ?? '', severity: sev, line: row.line ?? '', title: row.title ?? '',
            comm: row.comm ?? '', pid: row.pid ?? '',
            reasoning: row.reasoning ? { rung: row.reasoning.rung, model: row.reasoning.model } : null,
          });
        }
      } catch { /* a torn line is not a reason to fail the panel */ }
    }
  }

  const beat = existsSync(heartbeatFile) ? read(heartbeatFile).trim() : '';
  const beatAgeSeconds = beat ? Math.max(0, Math.round((Date.now() - Date.parse(beat)) / 1000)) : -1;
  const findingsLines = existsSync(findingsFile)
    ? read(findingsFile).split('\n').filter((l) => l.trim()).length : 0;

  // Skírnir: a bot that stopped answering must be visible, not discovered
  const assistantDir = join(home, 'hodd/state/assistant');
  const beatFile = join(assistantDir, 'telegram.heartbeat');
  const assistantBeat = existsSync(beatFile) ? read(beatFile).trim() : '';
  const beatAge = assistantBeat ? Math.max(0, Math.round((Date.now() - Date.parse(assistantBeat)) / 1000)) : -1;
  let lastAnswer = '';
  let refusalsToday = 0;
  let turnsToday = 0;
  const assistantDb = join(assistantDir, 'assistant.db');
  if (existsSync(assistantDb)) {
    try {
      const db = new Database(assistantDb, { readonly: true });
      const today = new Date().toISOString().slice(0, 10);
      const last = db.query('select ts from turns order by rowid desc limit 1').get() as { ts?: string } | null;
      lastAnswer = last?.ts ?? '';
      const refused = db.query('select count(*) as n from conversations where ts like ? and refused = 1').get(`${today}%`) as { n: number };
      const all = db.query('select count(*) as n from conversations where ts like ?').get(`${today}%`) as { n: number };
      refusalsToday = refused?.n ?? 0;
      turnsToday = all?.n ?? 0;
      db.close();
    } catch { /* the assistant is new: report zero rather than fail the panel */ }
  }
  const assistant = { heartbeat: assistantBeat, heartbeatAgeSeconds: beatAge,
                      live: beatAge >= 0 && beatAge < 300,
                      lastAnswer, refusalsToday, turnsToday };

  return {
    paused: existsSync(pausedMarker),
    heartbeat: beat,
    heartbeatAgeSeconds: beatAgeSeconds,
    silent: beatAgeSeconds === -1 || beatAgeSeconds > 600,
    findings: findingsLines,
    // `judged` is the whole record; bySeverity is the recent window the panel shows.
    // Reporting the window as the total made the tower say "2,000 judged" over a
    // 20,000-line ledger — a small lie in a security surface is still a lie.
    judged: totalJudged,
    bySeverity: counts,
    newest: newest.slice(-25).reverse(),
    assistant,
    door: 'bin/ward/garmr.sh',
  };
}
