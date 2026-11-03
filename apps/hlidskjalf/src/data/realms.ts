import type { GateId, DomainDef, RealmDef, TaskState, AgentStatus } from '../types';

// Single tenant: the switchable unit is a WORKSPACE (personal | work), not a
// tenant. Domains are knowledge areas inside a workspace. Houses are brands.
export const WORKSPACES: RealmDef[] = [
  {
    id: 'work',
    tenant: 'Work',
    name: 'Work',
    kind: 'work',
    company: 'wayof',
    domains: ['company', 'marketing', 'development', 'life'],
    tint: '#c9973f',
    tint2: '#7d5f2a',
    glyph: 'ᛉ',
  },
  {
    id: 'personal',
    tenant: 'Personal',
    name: 'Personal',
    kind: 'personal',
    domains: ['me', 'life', 'development'],
    tint: '#96a0a8',
    tint2: '#5f686e',
    glyph: 'ᛗ',
  },
];

/** Back-compat alias — the active `realm` id is now a workspace id. */
export const REALMS = WORKSPACES;

export const DOMAIN_LABEL: Record<string, string> = {
  company: 'Company',
  marketing: 'Marketing',
  development: 'Development',
  life: 'Life',
  me: 'Me',
};

export const DOMAINS: Record<string, DomainDef> = {
  ymirlabs: { id: 'ymirlabs', name: 'Ymir Labs', accent: '#c9973f', glyph: 'ᛦ' },
  brokkforge: { id: 'brokkforge', name: 'Brokk Forge', accent: '#f59e0b', glyph: 'ᛒ' },
  runestone: { id: 'runestone', name: 'Runestone Labs', accent: '#f43f5e', glyph: 'ᚱ' },
  muninn: { id: 'muninn', name: 'Muninn Labs', accent: '#8b5cf6', glyph: 'ᛗ' },
  dvalin: { id: 'dvalin', name: 'Dvalin', accent: '#94a3b8', glyph: 'ᛞ' },
  utgard: { id: 'utgard', name: 'Utgard Studios', accent: '#d946ef', glyph: 'ᚢ' },
  askr: { id: 'askr', name: 'Askr', accent: '#34d399', glyph: 'ᚨ' },
  mannheim: { id: 'mannheim', name: 'Mannheim', accent: '#64748b', glyph: 'ᛘ' },
};

export const realmById = (id: string): RealmDef =>
  REALMS.find((r) => r.id === id) ?? REALMS[0];

export interface AccentPreset {
  id: string;
  name: string;
  tint: string | null;
  tint2: string | null;
}

/**
 * Personal accent presets. `realm` follows the tenant tint (the structural
 * default); every other preset lets the operator paint their own seat.
 */
export const ACCENTS: AccentPreset[] = [
  { id: 'realm', name: 'Realm default', tint: null, tint2: null },
  { id: 'azure', name: 'Azure', tint: '#c9973f', tint2: '#0ea5e9' },
  { id: 'indigo', name: 'Indigo', tint: '#818cf8', tint2: '#6366f1' },
  { id: 'violet', name: 'Violet', tint: '#a855f7', tint2: '#7c3aed' },
  { id: 'magenta', name: 'Magenta', tint: '#d946ef', tint2: '#c026d3' },
  { id: 'crimson', name: 'Crimson', tint: '#f43f5e', tint2: '#e11d48' },
  { id: 'ember', name: 'Ember', tint: '#f87171', tint2: '#ef4444' },
  { id: 'orange', name: 'Orange', tint: '#fb923c', tint2: '#f97316' },
  { id: 'amber', name: 'Amber', tint: '#f59e0b', tint2: '#d97706' },
  { id: 'lime', name: 'Lime', tint: '#a3e635', tint2: '#84cc16' },
  { id: 'emerald', name: 'Emerald', tint: '#34d399', tint2: '#10b981' },
  { id: 'teal', name: 'Teal', tint: '#2dd4bf', tint2: '#14b8a6' },
  { id: 'cyan', name: 'Cyan', tint: '#22d3ee', tint2: '#06b6d4' },
  { id: 'steel', name: 'Steel', tint: '#94a3b8', tint2: '#64748b' },
];

/**
 * Resolve a realm definition for any tenant — known realms keep their
 * canonical tint; a freshly provisioned tenant is derived from its house seal.
 */
export function realmDef(
  id: string,
  grant?: { tenant?: string; domain?: string; tint?: string; glyph?: string },
): RealmDef {
  const known = WORKSPACES.find((r) => r.id === id);
  if (known) return known;
  const house = DOMAINS[grant?.domain ?? 'ymirlabs'];
  return {
    id,
    tenant: grant?.tenant ?? id,
    name: grant?.tenant ?? id,
    domain: house.id,
    tint: grant?.tint ?? house.accent,
    tint2: grant?.tint ?? house.accent,
    glyph: grant?.glyph ?? house.glyph,
  };
}

export interface GateDef {
  id: GateId;
  label: string;
  glyph: string;
  hint: string;
}

export const GATES: GateDef[] = [
  { id: 'skirnir', label: 'Skírnir – Tala', glyph: 'ᚨ', hint: 'Assistent · mikrofon med samtycke · lokalt svar' },
  { id: 'fleet', label: 'Fleet', glyph: 'ᚠ', hint: 'Agent Cards · status · A2A graph' },
  { id: 'tasks', label: 'Tasks', glyph: 'ᛏ', hint: 'A2A lifecycle board' },
  { id: 'well', label: 'Well', glyph: 'ᛜ', hint: 'Mimirsbrunn recall · timeline' },
  { id: 'runes', label: 'Runes', glyph: 'ᚱ', hint: 'Append-only ledger' },
  { id: 'reviews', label: 'Reviews', glyph: 'ᛉ', hint: 'Glitnir PR cards' },
  { id: 'processes', label: 'Processes', glyph: 'ᛞ', hint: 'Valhalla supervision' },
  { id: 'files', label: 'Files', glyph: 'ᛊ', hint: 'Skrymir file browser' },
  { id: 'chat', label: 'OmniChat', glyph: 'ᚴ', hint: 'Kaia · orchestration' },
  { id: 'forge', label: 'Forge', glyph: 'ᚨ', hint: 'Create · edit · Eindri & skills' },
  { id: 'runtime', label: 'Runtime', glyph: 'ᛖ', hint: 'Sága digest · session seating' },
  { id: 'cron', label: 'Cron', glyph: 'ᛃ', hint: 'Nornir schedule · job health' },
  { id: 'sessions', label: 'Sessions', glyph: 'ᛋ', hint: 'Smiðja runs · phase progress' },
  { id: 'worktrees', label: 'Worktrees', glyph: 'ᛥ', hint: 'Yggdrasil worktrees · branch · owning agent' },
  { id: 'trace', label: 'Trace', glyph: 'ᛚ', hint: 'Lanes · phases · tool calls' },
  { id: 'decisions', label: 'Decisions', glyph: 'ᚦ', hint: 'Failures grouped · the fix' },
  { id: 'stats', label: 'Stats', glyph: 'ᛗ', hint: 'Tokens · cost · by chain & model' },
  { id: 'managandr', label: 'Mánagandr', glyph: 'ᛅ', hint: 'Read calendar · reckoning · lanes' },
  { id: 'snotra', label: 'Snotra', glyph: 'ᛊ', hint: 'Meetings · record · prepare · approve · send' },
  { id: 'mail', label: 'Gná', glyph: 'ᚷ', hint: 'The one mail desk · needs you · unsure · waiting · done' },
  { id: 'profile', label: 'Profile', glyph: 'ᛝ', hint: 'Personal & company settings' },
];

export const TASK_STATES: TaskState[] = [
  'SUBMITTED',
  'WORKING',
  'INPUT_REQUIRED',
  'AUTH_REQUIRED',
  'COMPLETED',
  'FAILED',
  'REJECTED',
  'CANCELED',
];

export const TERMINAL_STATES: TaskState[] = [
  'COMPLETED',
  'FAILED',
  'REJECTED',
  'CANCELED',
];

export const TASK_STATE_META: Record<
  TaskState,
  { glyph: string; label: string; tone: AgentStatus | 'info' }
> = {
  SUBMITTED: { glyph: 'ᛋ', label: 'Submitted', tone: 'info' },
  WORKING: { glyph: 'ᚹ', label: 'Working', tone: 'info' },
  INPUT_REQUIRED: { glyph: 'ᛁ', label: 'Input required', tone: 'degraded' },
  AUTH_REQUIRED: { glyph: 'ᚨ', label: 'Auth required', tone: 'degraded' },
  COMPLETED: { glyph: 'ᚲ', label: 'Completed', tone: 'nominal' },
  FAILED: { glyph: 'ᚠ', label: 'Failed', tone: 'down' },
  REJECTED: { glyph: 'ᚱ', label: 'Rejected', tone: 'down' },
  CANCELED: { glyph: 'ᛪ', label: 'Canceled', tone: 'degraded' },
};

export const STATUS_META: Record<AgentStatus, { glyph: string; label: string; tone: string }> = {
  nominal: { glyph: 'ᛟ', label: 'NOMINAL', tone: 'ok' },
  degraded: { glyph: 'ᛇ', label: 'DEGRADED', tone: 'warn' },
  down: { glyph: 'ᛪ', label: 'DOWN', tone: 'danger' },
};
