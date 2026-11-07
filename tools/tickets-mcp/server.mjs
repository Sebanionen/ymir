#!/usr/bin/env node
// skuld v2 — the ticket hall on the official MCP SDK (plan 43 corrective).
// The same store, the same blocking laws, proper bones: McpServer +
// StreamableHTTP transport + zod-anchored tools + a resource. The psql spine
// stays (deps-free, escaped literals) — the SDK is the surface, the pg is the
// floor.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { ledgerPlans, ledgerLine, ledgerRefusal } from "./ledger.mjs";

const DB = process.env.SKULD_PGHOST || "127.0.0.1";
const ROLE = process.env.SKULD_PGROLE || "skuld";
const PASS = process.env.SKULD_PGPASSWORD || "skuld";
const DBN = process.env.SKULD_DBNAME || "skuld";
const OPER = process.env.SKULD_OPERATOR || "brokk";

function q(sql, vars) {
  const out = sql.replace(/:'([a-z_]+)'/g, (m, k) => "'" + String(vars?.[k] ?? "").replace(/'/g, "''") + "'");
  const r = spawnSync("psql", ["-h", DB, "-U", ROLE, "-d", DBN, "-Atc", out],
    { env: { ...process.env, PGPASSWORD: PASS }, encoding: "utf8", maxBuffer: 8 << 20 });
  return { ok: r.status === 0, out: (r.stdout || "").trim(), err: (r.stderr || "").trim() };
}
const rows = (o) => o ? o.split("\n") : [];
const agentOf = () => "brokk"; // the seat's pi names itself; the heart serves one hall at a time
function blockStatus(agent) { const r = q(`SELECT reason FROM blocks WHERE agent = :'a'`, { a: agent }); return rows(r.out)[0] || null; }
function violation(agent, reason) { q(`INSERT INTO blocks (agent, reason) VALUES (:'a', :'r') ON CONFLICT (agent) DO UPDATE SET reason = :'r', created_at = now()`, { a: agent, r: reason }); }
const STATUSES = ["Backlog","Planned","Ready","In Progress","Submitted for Review","In Review","Approved","Done","Changes Requested"];
const MARCH = { "Backlog":["Planned"], "Planned":["Ready"], "Ready":["In Progress"], "In Progress":["Submitted for Review","Changes Requested"], "Submitted for Review":["In Review"], "In Review":["Approved","Changes Requested"], "Approved":["Done"], "Done":[], "Changes Requested":["In Progress"] };

function makeMcp() {
  const server = new McpServer({ name: "skuld", version: "2.0.0" }, {
    capabilities: { tools: {}, resources: { subscribe: false, listChanged: false } }
  });

function blockedResult(agent) {
  const b = blockStatus(agent);
  return b ? `blocked: ${b.split("|")[0]} — an agent that does not make tickets and plans correctly is blocked; the operator clears it (blocks/clear)` : null;
}
// WHICH VERBS THE BLOCK ACTUALLY STOPS — measured 2026-11-06, because the house believed "every
// write" and that was wrong: the block guards THREE verbs, `tickets_create`, `tickets_update` and
// `namespaces_create` (the ones that call this helper). `plans_create`, `plans_update` and
// `comments_post` are NOT guarded, which is why an empty `plans` table was never the block's
// doing — nobody had ever called them. A gate that claims more than it does is worse than no
// gate, so the list is named here and in the plan (210 §10).
function guarded(name, args) {
  const agent = agentOf();
  const bad = blockedResult(agent);
  if (bad && !["blocks_status", "blocks_clear"].includes(name)) return bad;
  return null;
}

server.registerTool("tickets_create", {
  title: "Create a ticket", description: "A registered namespace, title (4+), description (10+), a valid priority. The blocking law is on.",
  inputSchema: { namespace: z.string(), title: z.string(), description: z.string(), priority: z.string().optional(), status: z.string().optional(), labels: z.array(z.string()).optional(), parent: z.number().optional() }
}, async (a) => {
  const agent = agentOf();
  const g = guarded("tickets_create", a);
  if (g) return { content: [{ type: "text", text: g }], isError: true };
  const ns = String(a.namespace || "");
  if (!ns || !rows(q(`SELECT 1 FROM namespaces WHERE name = :'n'`, { n: ns }).out).length) { violation(agent, "tickets/create refused: namespace not registered"); return { content: [{ type: "text", text: `refused: namespace '${ns}' is not on the registry` }], isError: true }; }
  if (String(a.title).trim().length < 4) { violation(agent, "tickets/create refused: title"); return { content: [{ type: "text", text: "refused: a ticket needs a real title (4+ chars)" }], isError: true }; }
  if (String(a.description).trim().length < 10) { violation(agent, "tickets/create refused: description"); return { content: [{ type: "text", text: "refused: a ticket needs a real description (10+ chars)" }], isError: true }; }
  const pri = String(a.priority || "Medium");
  if (!["Low","Medium","High","Critical"].includes(pri)) return { content: [{ type: "text", text: "priority must be Low/Medium/High/Critical" }], isError: true };
  const st = String(a.status || "Ready");
  if (!STATUSES.includes(st)) return { content: [{ type: "text", text: "status must be one of the vocabulary" }], isError: true };
  const labels = (a.labels || []).map(String);
  if (labels.length > 6) return { content: [{ type: "text", text: "at most 6 labels" }], isError: true };
  const r = q(`INSERT INTO tickets (namespace, title, description, priority, status, labels, owner, ticket_no, parent_id)
    VALUES (:'n', :'t', :'d', :'p', :'st', string_to_array(:'l', ','), :'o',
      (SELECT COALESCE(MAX(ticket_no), 0) + 1 FROM tickets WHERE namespace = :'n'),
      NULLIF(:'parent', '')::bigint) RETURNING id, ticket_no`,
    { n: ns, t: String(a.title), d: String(a.description), p: pri, st, l: labels.join(","), o: agent, parent: a.parent ? String(a.parent) : "" });
  if (!r.ok) return { content: [{ type: "text", text: "store error: " + r.err }], isError: true };
  return { content: [{ type: "text", text: `ticket ${ns}/${rows(r.out)[0].split("|")[1]} created (#${rows(r.out)[0].split("|")[0]})` }] };
});

server.registerTool("tickets_list", {
  title: "List tickets", description: "Filter by namespace/status/priority/assignee; the airy numbers + statuses bath.",
  inputSchema: { namespace: z.string().optional(), status: z.string().optional(), priority: z.string().optional() }
}, async (a) => {
  const f = [], v = {};
  if (a.namespace) { f.push("namespace = :'ns'"); v.ns = String(a.namespace); }
  if (a.status) { f.push("status = :'st'"); v.st = String(a.status); }
  if (a.priority) { f.push("priority = :'pr'"); v.pr = String(a.priority); }
  const r = q(`SELECT id, ticket_no, namespace, status, priority, title, COALESCE(assignee, owner, 'hall'), COALESCE(parent_id, 0), LEFT(description, 120)
    FROM tickets ${f.length ? "WHERE " + f.join(" AND ") : ""} ORDER BY id DESC LIMIT 200`, v);
  return { content: [{ type: "text", text: rows(r.out).join("\n") || "(no tickets)" }] };
});

server.registerTool("tickets_get", {
  title: "Read a ticket", description: "The full row of one ticket.",
  inputSchema: { id: z.number() }
}, async (a) => {
  const r = q(`SELECT id, ticket_no, namespace, title, description, priority, status, labels, owner, assignee, created_at FROM tickets WHERE id = :'id'`, { id: String(a.id) });
  const line = rows(r.out)[0];
  return line ? { content: [{ type: "text", text: line }] } : { content: [{ type: "text", text: `no ticket #${a.id}` }], isError: true };
});

server.registerTool("tickets_update", {
  title: "Update a ticket", description: "The legal march (Backlog -> Done through the review gate) + the Done-witness (a description 10+). Violations block.",
  inputSchema: { id: z.number(), status: z.string().optional(), priority: z.string().optional(), labels: z.array(z.string()).optional(), assignee: z.string().optional() }
}, async (a) => {
  const agent = agentOf();
  const g = guarded("tickets_update", a);
  if (g) return { content: [{ type: "text", text: g }], isError: true };
  const cur = rows(q(`SELECT status FROM tickets WHERE id = :'id'`, { id: String(a.id) }).out)[0];
  if (!cur) return { content: [{ type: "text", text: `no ticket #${a.id}` }], isError: true };
  const sets = [], v = { id: String(a.id) };
  if (a.status !== undefined) {
    if (!STATUSES.includes(a.status)) return { content: [{ type: "text", text: "unknown status" }], isError: true };
    if (a.status !== cur && !(MARCH[cur] || []).includes(a.status)) { violation(agent, `illegal march ${cur} -> ${a.status}`); return { content: [{ type: "text", text: `refused: illegal march ${cur} -> ${a.status} (the review gate stands)` }], isError: true }; }
    if (a.status === "Done") {
      const d2 = rows(q(`SELECT description FROM tickets WHERE id = :'id'`, { id: String(a.id) }).out)[0] || "";
      if (d2.trim().length < 10) { violation(agent, "Done-witness refused: no description"); return { content: [{ type: "text", text: "refused: a Done ticket needs a description (10+ chars) — the Done-witness law" }], isError: true }; }
    }
    sets.push("status = :'st'"); v.st = String(a.status);
    if (a.status === "Done") sets.push("closed_at = now()");
  }
  if (a.priority !== undefined) { sets.push("priority = :'pr'"); v.pr = String(a.priority); }
  if (a.labels !== undefined) { sets.push("labels = string_to_array(:'l', ',')"); v.l = a.labels.map(String).join(","); }
  if (a.assignee !== undefined) { sets.push("assignee = :'as'"); v.as = String(a.assignee); }
  if (!sets.length) return { content: [{ type: "text", text: "nothing to update" }], isError: true };
  sets.push("updated_at = now()");
  const r = q(`UPDATE tickets SET ${sets.join(", ")} WHERE id = :'id' RETURNING id`, v);
  return r.ok ? { content: [{ type: "text", text: `ticket #${r.out} updated` }] } : { content: [{ type: "text", text: "store error" }], isError: true };
});

server.registerTool("plans_update", { title: "Approve or ship a plan", description: "The operator walks a plan: approved -> shipped. The reviewer's hand is the Allfather's.",
  inputSchema: { id: z.number(), status: z.string() }
}, async (a) => {
  const agent = agentOf();
  const cur = rows(q(`SELECT status FROM plans WHERE id = :'id'`, { id: String(a.id) }).out)[0];
  if (!cur) return { content: [{ type: "text", text: `no plan #${a.id}` }], isError: true };
  const to = String(a.status);
  const MARCH = { "drafted": ["active", "approved"], "active": ["approved"], "approved": ["shipped"], "shipped": ["done"], "done": [], "superseded": [] };
  if (to !== cur && !(MARCH[cur] || []).includes(to)) return { content: [{ type: "text", text: `illegal plan walk ${cur} -> ${to}` }], isError: true };
  if (to === "approved" && agent !== OPER) return { content: [{ type: "text", text: "the approval is the Allfather's hand" }], isError: true };
  const r = q(`UPDATE plans SET status = :'st', updated_at = now() WHERE id = :'id' RETURNING id`, { id: String(a.id), st: to });
  return r.ok ? { content: [{ type: "text", text: `plan #${r.out} ${to}` }] } : { content: [{ type: "text", text: "store error" }], isError: true };
});
server.registerTool("plans_pending", {
  title: "The awaiting plans",
  description: "The plans whose own first lines say they are proposed, drafted, open or awaiting his word.",
  inputSchema: {}
}, async () => {
  const waiting = ledgerPlans().filter(r => /proposed|drafted|draft|open|awaiting/i.test(r.status));
  if (!waiting.length) return { content: [{ type: "text", text: "(no plans await)" }] };
  return { content: [{ type: "text", text: `plans_awaiting[${waiting.length}]{number,namespace,status,file,title}:\n` + waiting.map(r => "  " + ledgerLine(r)).join("\n") }] };
});

server.registerTool("namespaces_list", { title: "The projects", description: "The registered projects (the slugs and their names) — the pickers fill from here.", inputSchema: {} }, async () => {
  const r = q(`SELECT name, COALESCE(about, name) FROM namespaces ORDER BY name`);
  return { content: [{ type: "text", text: rows(r.out).join("\n") || "(no namespaces)" }] };
});
server.registerTool("namespaces_create", {
  title: "Register a project", description: "The door that registers a namespace — until it exists, tickets_create and plans_create REFUSE ('not on the registry'). A slug (2..40: lower-case letters, digits and '-') and a display name (the 'about'). Registering one that exists is a no-op, not an error.",
  inputSchema: { name: z.string(), about: z.string() }
}, async (a) => {
  const agent = agentOf();
  const g = guarded("namespaces_create", a);
  if (g) return { content: [{ type: "text", text: g }], isError: true };
  const name = String(a.name || "").trim().toLowerCase();
  const about = String(a.about || "").trim();
  if (!/^[a-z0-9][a-z0-9-]{1,39}$/.test(name)) { violation(agent, "namespaces/create refused: slug shape"); return { content: [{ type: "text", text: "refused: a namespace is a SLUG — lower-case letters, digits and '-', 2..40 chars (e.g. odrerir)" }], isError: true }; }
  if (about.length < 2) { violation(agent, "namespaces/create refused: about"); return { content: [{ type: "text", text: "refused: a namespace needs a display name (2+ chars) — it is what the pickers show" }], isError: true }; }
  if (rows(q(`SELECT 1 FROM namespaces WHERE name = :'n'`, { n: name }).out).length) {
    return { content: [{ type: "text", text: `already on the registry: ${name} — nothing to do` }] };
  }
  const r = q(`INSERT INTO namespaces (name, about) VALUES (:'n', :'a') RETURNING name, COALESCE(about, name)`, { n: name, a: about });
  if (!r.ok) return { content: [{ type: "text", text: `store refused: ${String(r.err).split("\n")[0].slice(0, 200)}` }], isError: true };
  return { content: [{ type: "text", text: `registered: ${rows(r.out).join(" ") || name}` }] };
});

server.registerTool("plans_create", {
  title: "Cut a plan — refused here, and told where it goes",
  description: "The ledger is a shelf of files; this door reads it and refuses to grow a second store. The refusal names the one door that writes a plan.",
  inputSchema: { namespace: z.string(), title: z.string(), body: z.string(), tickets: z.array(z.number()).optional() }
}, async () => ({ content: [{ type: "text", text: ledgerRefusal() }], isError: true }));
server.registerTool("plans_list", {
  title: "The plans",
  description: "Every plan on the ledger's shelves, read from the FILES (the truth), filtered by namespace.",
  inputSchema: { namespace: z.string().optional() }
}, async (a) => {
  let plans = ledgerPlans();
  if (a.namespace) plans = plans.filter(r => r.ns === String(a.namespace) || r.ns.startsWith(String(a.namespace) + "/"));
  if (!plans.length) {
    return { content: [{ type: "text", text: `(no plans) — no plan shelf answered under ${path.join(LEDGER_HOME, "svartalfaheim")}; an unreadable home is not an empty shelf` }], isError: true };
  }
  return { content: [{ type: "text", text: `plans[${plans.length}]{number,namespace,status,file,title}:\n` + plans.map(r => "  " + ledgerLine(r)).join("\n") }] };
});
server.registerTool("plans_get", {
  title: "One plan",
  description: "One plan from the ledger: its file, its headline, its status, and its opening body.",
  inputSchema: { id: z.number() }
}, async (a) => {
  const hit = ledgerPlans().filter(r => r.num === Number(a.id));
  if (!hit.length) return { content: [{ type: "text", text: `no plan #${a.id} on the ledger's shelves` }], isError: true };
  const r = hit[0];
  let body = "";
  try { body = fs.readFileSync(r.file, "utf8").split("\n").slice(0, 40).join("\n"); } catch { body = "(unreadable)"; }
  return { content: [{ type: "text", text: `${r.num}|${r.ns}|${r.status}|${r.rel}\n\n${body}` }] };
});

server.registerTool("comments_list", { title: "The thread", description: "A ticket's comments.", inputSchema: { id: z.number() } }, async (a) => {
  const r = q(`SELECT id, author, body, created_at FROM comments WHERE ticket_id = :'id' ORDER BY id`, { id: String(a.id) });
  return { content: [{ type: "text", text: rows(r.out).join("\n") || "(no comments)" }] };
});
server.registerTool("comments_post", { title: "Carve a comment", description: "A word on the ticket.", inputSchema: { id: z.number(), body: z.string() } }, async (a) => {
  const body = String(a.body).trim();
  if (!body || body.length > 2000) return { content: [{ type: "text", text: "a comment needs 1..2000 words" }], isError: true };
  const r = q(`INSERT INTO comments (ticket_id, author, body) VALUES (:'id', :'a', :'b') RETURNING id`, { id: String(a.id), a: agentOf(), b: body });
  return r.ok ? { content: [{ type: "text", text: `comment #${r.out} carved` }] } : { content: [{ type: "text", text: "store error" }], isError: true };
});

server.registerTool("blocks_status", {
  title: "Your block — named, with the remedy on the same line",
  description: "The calling agent's ledger state: clean, or blocked with the reason, which verbs it stops, and who may lift it.",
  inputSchema: {}
}, async () => {
  const agent = agentOf();
  const b = blockStatus(agent);
  if (!b) return { content: [{ type: "text", text: `clean: ${agent} — no block stands` }] };
  const reason = b.split("|")[0];
  return {
    content: [{ type: "text", text:
      `blocked[1]{agent,reason,stops,cleared_by}:\n`
      + `  "${agent}","${reason}","tickets_create · tickets_update · namespaces_create","the operator (SKULD_OPERATOR) — blocks_clear, never the agent itself"\n`
      + `blocked: ${reason} — three verbs are refused until the operator clears it; plans and comments are not among them.` }],
    isError: true
  };
});
server.registerTool("blocks_clear", { title: "The operator's key", description: "Only SKULD_OPERATOR may lift.", inputSchema: { agent: z.string() } }, async (a) => {
  if (agentOf() !== OPER) return { content: [{ type: "text", text: `the operator's door only` }], isError: true };
  q(`DELETE FROM blocks WHERE agent = :'a'`, { a: String(a.agent) });
  return { content: [{ type: "text", text: `block cleared for ${a.agent}` }] };
});

server.resource("the-book", "skuld://book", "the ticket book", async () => {
  const t = rows(q(`SELECT count(*) FROM tickets`).out)[0] || "0";
  const p = rows(q(`SELECT count(*) FROM plans`).out)[0] || "0";
  return { contents: [{ uri: "skuld://book", mimeType: "text/plain", text: `tickets: ${t} · plans: ${p}` }] };
});

  server.registerTool("sync_snapshot", { title: "The whole book", description: "The full export (tickets + plans + statuses + namespaces) for the fleet mirrors — the heart is the primary, the instances pull.", inputSchema: {} }, async () => {
    const t = rows(q(`SELECT id, ticket_no, namespace, status, priority, title, LEFT(description, 200), labels, owner, created_at FROM tickets ORDER BY id`).out);
    const p = rows(q(`SELECT id, namespace, title, status, tickets, created_at FROM plans ORDER BY id`).out);
    const n = rows(q(`SELECT name, COALESCE(about, name) FROM namespaces ORDER BY name`).out);
    return { content: [{ type: "text", text: "tickets\n" + t.join("\n") + "\nplans\n" + p.join("\n") + "\nnamespaces\n" + n.join("\n") }] };
  });

  return server;
}

// — the served mode: StreamableHTTP on PORT (the SDK holds the handshake+session) —
const PORT = parseInt(process.env.PORT || "0", 10);
if (PORT > 0) {
  import("node:http").then(({ default: http }) => {
    const serverHttp = http.createServer(async (req, res) => {
      const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "content-type, accept, mcp-session-id, mcp-protocol-version, mcp-integration-context", "access-control-allow-methods": "POST, OPTIONS, DELETE", "access-control-expose-headers": "mcp-session-id, Mcp-Session-Id" };
      if (req.method === "OPTIONS") { res.writeHead(204, cors).end(); return; }
      if (!["POST", "DELETE"].includes(req.method)) { res.writeHead(405).end(); return; }
      // the documented session-map: one transport per session; the known
      // session re-uses its transport, a fresh one joins by its own connect
      globalThis.__skuldSessions ||= new Map();
      const reqSid = String(req.headers['mcp-session-id'] || '');
      let entry = reqSid ? globalThis.__skuldSessions.get(reqSid) : null;
      if (req.method === 'DELETE' && reqSid) { globalThis.__skuldSessions.delete(reqSid); return; }
      if (!entry) {
        const mcp = makeMcp();
        const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: () => crypto.randomUUID(), onsessioninitialized: (id) => { if (!globalThis.__skuldSessions.has(id)) globalThis.__skuldSessions.set(id, { mcp, transport }); } });
        await mcp.connect(transport);
        entry = { mcp, transport };
        if (!reqSid) globalThis.__skuldSessions.set('boot', entry);
      }
      const transport = entry.transport;
      Object.entries(cors).forEach(([k, v]) => res.setHeader(k, v));
      res.setHeader("content-type", "application/json");
      try {
        const raw = await requestBody(req); let parsed = null; try { parsed = JSON.parse(raw); } catch {}
        await transport.handleRequest(req, res, parsed); }
      catch (e) { res.end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32603, message: String(e) } })); }
    });
    serverHttp.listen(PORT, "0.0.0.0");
  }).catch(e => { process.stderr.write(String(e)); });
}
function requestBody(req) { return new Promise((ok, no) => { let b = ""; req.on("data", c => { b += c; if (b.length > 2 << 20) req.destroy(); }); req.on("end", () => ok(b)); req.on("error", no); }); }