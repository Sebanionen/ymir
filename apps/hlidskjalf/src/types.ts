import type { AgentInterface } from '../../../packages/contracts/src/index.ts';

// Known realms autocomplete; arbitrary realm ids are allowed so a freshly
// provisioned tenant (first GitHub login) can exist without a rebuild.
export type RealmId = 'work' | 'personal' | (string & {});

export type TenantRole = 'owner' | 'admin' | 'member';

export interface TenantGrant {
  realm: RealmId;
  tenant: string;
  role: TenantRole;
  domain: DomainId;
  tint: string;
  glyph: string;
}

export interface User {
  login: string;
  name: string;
  email: string;
  avatar: string;
}

export interface Session {
  user: User;
  tenants: TenantGrant[];
  /** How the session was established. `github` is OAuth through the gate. */
  method: 'github' | 'gate';
  issuedAt: string;
  /** mock JWS — replaced by Heimdall-issued httpOnly JWT once W0028 lands */
  token: string;
}

export type DomainId =
  | 'ymirlabs'
  | 'brokkforge'
  | 'runestone'
  | 'muninn'
  | 'dvalin'
  | 'utgard'
  | 'askr'
  | 'mannheim';

export type AgentStatus = 'nominal' | 'degraded' | 'down';

export type TaskState =
  | 'SUBMITTED'
  | 'WORKING'
  | 'COMPLETED'
  | 'FAILED'
  | 'REJECTED'
  | 'CANCELED'
  | 'INPUT_REQUIRED'
  | 'AUTH_REQUIRED';

export type GateId =
  | 'skirnir'
  | 'fleet'
  | 'tasks'
  | 'well'
  | 'runes'
  | 'reviews'
  | 'processes'
  | 'files'
  | 'chat'
  | 'forge'
  | 'profile'
  | 'runtime'
  | 'cron'
  | 'sessions'
  | 'worktrees'
  | 'trace'
  | 'decisions'
  | 'stats'
  | 'managandr'
  | 'snotra'
  | 'mail';

export interface SkillDef {
  id: string;
  name: string;
  /** Norse aett prefix (galdr-, mimir-, yggd-, rat-, heimd-, bifr-, val-, skyr-) */
  aett: string;
  description: string;
  capabilities: string[];
  validated: boolean;
  domain: DomainId;
  createdAt: string;
}

export interface AgentCard {
  id: string;
  name: string;
  role: string;
  realm: RealmId;
  domain: DomainId;
  status: AgentStatus;
  capabilities: string[];
  skills: string[];
  interface: AgentInterface;
  model: string;
  uptime: number;
  tasksDone: number;
  /** Live facts from the agent's own pane, when it is genuinely standing. */
  live?: {
    kind: string;
    state: string;
    pane: string;
    workspace: string;
    cwd: string;
    task: string;
  };
  traceability: number;
}

export interface Task {
  id: string;
  title: string;
  state: TaskState;
  realm: RealmId;
  agent: string;
  agentId: string;
  order: string;
  progress: number;
  startedAt: string;
  updatedAt: string;
  artifacts: string[];
  log: string[];
}

export interface RuneEntry {
  id: string;
  ts: string;
  agent: string;
  module: string;
  event: string;
  checksum: string;
  realm: RealmId;
  order: string;
  level: 'info' | 'ok' | 'warn' | 'danger';
}

export interface StreamEvent {
  id: string;
  ts: string;
  kind: 'ratatoskr' | 'rune';
  from: string;
  to?: string;
  taskId?: string;
  state?: TaskState;
  module?: string;
  message: string;
  checksum?: string;
  gate?: GateId;
}

export interface RecallEpisode {
  id: string;
  title: string;
  body: string;
  score: number;
  mode: 'hybrid' | 'cosine' | 'spreading' | 'recent';
  agentScope: string;
  ts: string;
  tags: string[];
}

export interface ProcessInfo {
  id: string;
  name: string;
  daemon: string;
  manager: 'pm2' | 'docker' | 'systemd';
  status: AgentStatus;
  cpu: number;
  mem: number;
  restarts: number;
  uptime: number;
  realm: RealmId | 'platform';
}

export interface PullRequest {
  id: string;
  number: number;
  title: string;
  repo: string;
  author: string;
  realm: RealmId;
  state: 'open' | 'draft' | 'changes' | 'approved' | 'merged';
  mergeable?: string;
  checks: { name: string; state: AgentStatus }[];
  checklist: { label: string; done: boolean }[];
  additions: number;
  deletions: number;
  issue?: string;
  updatedAt: string;
}

/** The Glitnir payload (2026-09-24 audit): real PR cards + the compliance card,
 *  plus a named gh failure — a dead GitHub read is BOARDLY fatal, never silent. */
export interface ReviewsInfo {
  cards: PullRequest[];
  ghError?: string;
}

export interface FileNode {
  name: string;
  type: 'dir' | 'file';
  path: string;
  size?: number;
  updated?: string;
  children?: FileNode[];
}

export interface ChatMessage {
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

export interface RealmDef {
  id: RealmId;
  /** display name of the active workspace (kept as `tenant` for compatibility) */
  tenant: string;
  name?: string;
  kind?: 'work' | 'personal';
  company?: string;
  domains?: TopicId[];
  /** brand label — display only, never isolation */
  domain?: DomainId;
  tint: string;
  tint2: string;
  glyph: string;
}

/** Knowledge domains — the axes a workspace covers. */
export type TopicId = 'company' | 'marketing' | 'development' | 'life' | 'me';

export interface WorkspaceDef {
  id: string;
  name: string;
  kind: 'work' | 'personal';
  company?: string;
  domains: DomainId[];
  tint: string;
  tint2: string;
  glyph: string;
}

export interface DomainDef {
  id: DomainId;
  name: string;
  accent: string;
  glyph: string;
}
