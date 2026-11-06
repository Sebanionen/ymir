-- The whole schema. News domain: sources, cache, items, jev classifications, findings, stories, cards, images, taste,
-- sweeps, source leads, story memberships and release heads. Telemetry follows at the end.

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE requests (
  key TEXT PRIMARY KEY,
  route TEXT NOT NULL,
  status INTEGER NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE sources (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('rss', 'atom', 'hn_front', 'hn_search', 'github_releases', 'web_page')),
  name TEXT NOT NULL,
  url TEXT NOT NULL DEFAULT '',
  query TEXT NOT NULL DEFAULT '',
  weight REAL NOT NULL DEFAULT 1.0,
  interval_min INTEGER NOT NULL DEFAULT 15,
  enabled INTEGER NOT NULL DEFAULT 1,
  fail_count INTEGER NOT NULL DEFAULT 0,
  last_status TEXT,
  last_error TEXT,
  last_fetched_at TEXT,
  etag TEXT,
  last_modified TEXT,
  origin TEXT NOT NULL DEFAULT 'config' CHECK (origin IN ('config', 'user', 'agent', 'upvote')),
  reason TEXT,
  content_hash TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (kind, url, query)
);

CREATE TABLE source_cache (
  id INTEGER PRIMARY KEY,
  source_id INTEGER REFERENCES sources (id) ON DELETE SET NULL,
  url TEXT NOT NULL,
  url_hash TEXT NOT NULL UNIQUE,
  title TEXT,
  author TEXT,
  published_at TEXT,
  excerpt TEXT,
  content_md TEXT,
  image_url TEXT,
  discussion_url TEXT,
  points INTEGER,
  comments INTEGER,
  fetch_via TEXT NOT NULL DEFAULT 'http' CHECK (fetch_via IN ('http', 'firecrawl', 'feed', 'fixture')),
  fetched_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  bytes INTEGER
);

CREATE TABLE sweeps (
  id INTEGER PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE,
  trigger TEXT NOT NULL CHECK (trigger IN ('cron', 'manual', 'test')),
  status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'no_news', 'skipped', 'failed', 'stalled')),
  reason TEXT,
  submission_id INTEGER,
  run_entry_id INTEGER,
  task_id INTEGER,
  search_mode TEXT,
  gathered INTEGER NOT NULL DEFAULT 0,
  kept INTEGER NOT NULL DEFAULT 0,
  duplicates INTEGER NOT NULL DEFAULT 0,
  candidates INTEGER NOT NULL DEFAULT 0,
  presented INTEGER NOT NULL DEFAULT 0,
  summary TEXT,
  firecrawl_credits_used REAL NOT NULL DEFAULT 0,
  firecrawl_credits_left INTEGER,
  phases_json TEXT,
  audit_json TEXT,
  error TEXT,
  max_cards INTEGER,
  started_at TEXT,
  ended_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE items (
  id INTEGER PRIMARY KEY,
  sweep_id INTEGER REFERENCES sweeps (id),
  cache_id INTEGER REFERENCES source_cache (id),
  source_id INTEGER REFERENCES sources (id) ON DELETE SET NULL,
  url TEXT NOT NULL,
  url_hash TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  source_name TEXT,
  published_at TEXT,
  excerpt TEXT,
  image_url TEXT,
  discussion_url TEXT,
  status TEXT NOT NULL DEFAULT 'candidate'
    CHECK (status IN ('candidate', 'rejected', 'duplicate', 'researching', 'classified', 'presented', 'failed')),
  relevance REAL,
  matched_topic TEXT,
  worth REAL,
  novelty REAL,
  attention INTEGER,
  duplicate_of INTEGER REFERENCES items (id),
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  date_source TEXT, -- feed, meta, jsonld, time, url, model or unknown; NULL means never asked
  importance REAL,
  release_key TEXT,
  release_version TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX items_sweep_status ON items (sweep_id, status);
CREATE INDEX items_release_key ON items (release_key);

CREATE TABLE classifications (
  id INTEGER PRIMARY KEY,
  item_id INTEGER REFERENCES items (id),
  command TEXT NOT NULL,
  version INTEGER NOT NULL,
  model TEXT,
  hype INTEGER,
  facts INTEGER,
  signal INTEGER,
  primary_category TEXT,
  labels_json TEXT,
  ranked_json TEXT,
  suspect_combo INTEGER NOT NULL DEFAULT 0,
  answers_json TEXT,
  sweep_id INTEGER REFERENCES sweeps (id),
  tool_call_id TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX classifications_item ON classifications (item_id, command, created_at);

CREATE TABLE findings (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items (id),
  conversation_id INTEGER,
  summary TEXT NOT NULL,
  claims_json TEXT,
  evidence_json TEXT,
  actionability TEXT,
  claim_support_json TEXT,
  created_at TEXT NOT NULL,
  UNIQUE (item_id, conversation_id)
);

CREATE TABLE images (
  id INTEGER PRIMARY KEY,
  origin TEXT NOT NULL CHECK (origin IN ('source', 'generated')),
  status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('ready', 'pending', 'failed')),
  url TEXT,
  file_path TEXT,
  prompt TEXT,
  model TEXT,
  cost_usd REAL,
  error TEXT,
  item_id INTEGER REFERENCES items (id),
  created_at TEXT NOT NULL
);

CREATE TABLE stories (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  dek TEXT,
  body_md TEXT,
  primary_category TEXT,
  hype INTEGER,
  facts INTEGER,
  signal INTEGER,
  image_id INTEGER REFERENCES images (id),
  sweep_id INTEGER REFERENCES sweeps (id),
  tool_call_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT
);
CREATE UNIQUE INDEX stories_tool_call ON stories (tool_call_id) WHERE tool_call_id IS NOT NULL;

CREATE TABLE story_items (
  story_id INTEGER NOT NULL REFERENCES stories (id),
  item_id INTEGER NOT NULL REFERENCES items (id),
  PRIMARY KEY (story_id, item_id)
);
CREATE INDEX story_items_item ON story_items (item_id);

CREATE TABLE cards (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('news', 'story')),
  component TEXT NOT NULL,
  item_id INTEGER REFERENCES items (id),
  story_id INTEGER REFERENCES stories (id),
  image_id INTEGER REFERENCES images (id),
  props_json TEXT NOT NULL,
  hype INTEGER,
  facts INTEGER,
  signal INTEGER,
  primary_category TEXT,
  labels_json TEXT,
  attention INTEGER,
  tool_call_id TEXT NOT NULL UNIQUE,
  conversation_id INTEGER,
  sweep_id INTEGER REFERENCES sweeps (id),
  created_at TEXT NOT NULL
);
CREATE INDEX cards_created ON cards (created_at);

CREATE TABLE feedback (
  id INTEGER PRIMARY KEY,
  card_id INTEGER NOT NULL REFERENCES cards (id),
  signal TEXT CHECK (signal IN ('more', 'less')),
  labels_json TEXT,
  note TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE keywords (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('topic', 'hype', 'facts', 'signal')),
  term TEXT NOT NULL,
  weight REAL NOT NULL DEFAULT 1.0,
  source TEXT NOT NULL DEFAULT 'user' CHECK (source IN ('seed', 'user')),
  enabled INTEGER NOT NULL DEFAULT 1,
  last_searched_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (kind, term)
);

CREATE TABLE taste_questions (
  id INTEGER PRIMARY KEY,
  card_id INTEGER REFERENCES cards (id),
  item_id INTEGER REFERENCES items (id),
  question TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'answered', 'dismissed')),
  answer_labels_json TEXT,
  tool_call_id TEXT NOT NULL UNIQUE,
  conversation_id INTEGER,
  created_at TEXT NOT NULL,
  answered_at TEXT
);

-- One lead per site (host, or github.com/owner/repo). The next sweep offers open leads to the agent, which saves
-- the site as a source with save_source or skips it with a reason.
CREATE TABLE source_leads (
  id INTEGER PRIMARY KEY,
  site TEXT NOT NULL UNIQUE,
  url TEXT NOT NULL,
  title TEXT,
  card_id INTEGER REFERENCES cards (id) ON DELETE SET NULL,
  item_id INTEGER REFERENCES items (id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'saved', 'skipped')),
  note TEXT,
  source_id INTEGER REFERENCES sources (id) ON DELETE SET NULL,
  offered_sweep_id INTEGER REFERENCES sweeps (id) ON DELETE SET NULL,
  created_at TEXT NOT NULL,
  resolved_at TEXT
);
CREATE INDEX source_leads_status ON source_leads (status, created_at);

-- Story membership is assigned before presentation. Coverage and evidence attach to a development without a card.
CREATE TABLE story_memberships (
  item_id INTEGER PRIMARY KEY REFERENCES items (id),
  story_id INTEGER NOT NULL REFERENCES stories (id),
  role TEXT NOT NULL CHECK (role IN ('development', 'coverage', 'evidence')),
  development_id INTEGER NOT NULL REFERENCES items (id)
);
CREATE INDEX story_memberships_story ON story_memberships (story_id);

-- Keep the exact bounded evidence and verdict, keyed by its hash and classifier version, for replay and review.
CREATE TABLE story_decisions (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL REFERENCES items (id),
  other_item_id INTEGER NOT NULL REFERENCES items (id),
  version INTEGER NOT NULL,
  evidence_hash TEXT NOT NULL,
  state_json TEXT NOT NULL,
  answers_json TEXT NOT NULL,
  action TEXT NOT NULL,
  sweep_id INTEGER REFERENCES sweeps (id),
  created_at TEXT NOT NULL,
  UNIQUE (item_id, other_item_id, version, evidence_hash)
);

-- Admission and display are separate: keep the existing card until the newer release actually has a card.
CREATE TABLE release_heads (
  release_key TEXT PRIMARY KEY,
  latest_item_id INTEGER NOT NULL REFERENCES items (id),
  visible_card_id INTEGER REFERENCES cards (id)
);

-- Telemetry: every conversation, run, model response, tool call, jev call, Firecrawl call and hook event.

CREATE TABLE agent_conversations (
  conversation_id INTEGER PRIMARY KEY,
  agent TEXT,
  owner_conversation_id INTEGER,
  owner_task_id INTEGER,
  parent_conversation_id INTEGER,
  sweep_id INTEGER,
  created_at TEXT NOT NULL
);

CREATE TABLE agent_runs (
  run_entry_id INTEGER PRIMARY KEY,
  conversation_id INTEGER NOT NULL,
  request_id TEXT,
  submission_id INTEGER,
  sweep_id INTEGER,
  text TEXT,
  status TEXT NOT NULL DEFAULT 'running',
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  answer_entry_id INTEGER
);
CREATE INDEX agent_runs_conversation ON agent_runs (conversation_id, started_at);

CREATE TABLE generations (
  entry_id INTEGER PRIMARY KEY,
  conversation_id INTEGER NOT NULL,
  run_entry_id INTEGER,
  task_id INTEGER,
  sweep_id INTEGER,
  provider TEXT,
  model TEXT,
  stop_reason TEXT,
  error TEXT,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens INTEGER NOT NULL DEFAULT 0,
  cache_write_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  cost_usd REAL NOT NULL DEFAULT 0,
  context_tokens INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER,
  thinking_chars INTEGER NOT NULL DEFAULT 0,
  text TEXT,
  tool_calls INTEGER NOT NULL DEFAULT 0,
  started_at INTEGER NOT NULL,
  ended_at INTEGER
);
CREATE INDEX generations_run ON generations (run_entry_id);
CREATE INDEX generations_conversation ON generations (conversation_id, started_at);

CREATE TABLE tool_calls (
  id INTEGER PRIMARY KEY,
  generation_entry_id INTEGER NOT NULL,
  call_id TEXT NOT NULL,
  conversation_id INTEGER NOT NULL,
  run_entry_id INTEGER,
  sweep_id INTEGER,
  task_id INTEGER UNIQUE,
  tool_name TEXT NOT NULL,
  args_json TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  is_error INTEGER NOT NULL DEFAULT 0,
  result_text TEXT,
  details_json TEXT,
  result_entry_id INTEGER,
  duration_ms INTEGER,
  started_at INTEGER,
  ended_at INTEGER,
  tool_cost_usd REAL NOT NULL DEFAULT 0,
  UNIQUE (generation_entry_id, call_id)
);
CREATE INDEX tool_calls_conversation ON tool_calls (conversation_id, started_at);
CREATE INDEX tool_calls_sweep ON tool_calls (sweep_id, tool_name);

CREATE TABLE tasks (
  task_id INTEGER PRIMARY KEY,
  conversation_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  owner_task_id INTEGER,
  background INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  outcome TEXT,
  error TEXT,
  started_at INTEGER,
  ended_at INTEGER
);

CREATE TABLE jev_calls (
  id INTEGER PRIMARY KEY,
  command TEXT,
  version INTEGER,
  provider TEXT,
  model TEXT,
  questions INTEGER NOT NULL DEFAULT 0,
  answers_json TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_usd REAL,
  cost_source TEXT,
  elapsed_ms INTEGER,
  attempts INTEGER,
  error TEXT,
  item_id INTEGER,
  sweep_id INTEGER,
  conversation_id INTEGER,
  call_id TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX jev_calls_sweep ON jev_calls (sweep_id);

CREATE TABLE firecrawl_calls (
  id INTEGER PRIMARY KEY,
  endpoint TEXT NOT NULL,
  query TEXT,
  url TEXT,
  status TEXT NOT NULL,
  results INTEGER,
  credits_used REAL,
  credits_source TEXT,
  elapsed_ms INTEGER,
  error TEXT,
  sweep_id INTEGER,
  conversation_id INTEGER,
  call_id TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX firecrawl_calls_day ON firecrawl_calls (created_at);

CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  level TEXT NOT NULL,
  event TEXT NOT NULL,
  conversation_id INTEGER,
  task_id INTEGER,
  call_id TEXT,
  sweep_id INTEGER,
  data_json TEXT
);
CREATE INDEX events_sweep ON events (sweep_id, ts);
CREATE INDEX events_conversation ON events (conversation_id, ts);
