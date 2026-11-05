import fs from "node:fs";
import { gnaArm } from "./gna-arm.mjs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const exec = promisify(execFile);
const S = { type: "string", minLength: 1 },
  B = { type: "boolean" },
  N = { type: "integer", minimum: 1, maximum: 1000 },
  A = { type: "array", items: S, minItems: 1 };
const E = (...values) => ({ type: "string", enum: values });
const secret =
  /(^|[\\/])\.?env(?:[.\\/]|$)|secret|credential|token|\.(?:key|pem|age)$/i;
const leaf = (s) => {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/.test(s))
    throw Error("expected a plain name");
  return s;
};
export async function run(command, args, cwd, env = process.env) {
  try {
    return (
      await exec(command, args, {
        cwd,
        env,
        timeout: 600000,
        maxBuffer: 4194304,
        windowsHide: true,
      })
    ).stdout.trim();
  } catch (e) {
    throw Error(
      `${path.basename(command)} failed (${e.code ?? "unavailable"}): ${String(e.stderr || e.message).slice(0, 2000)}`,
    );
  }
}
export function validate(value, s, label = "arguments") {
  if (s.type === "object") {
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw Error(`${label} must be object`);
    for (const k of s.required || [])
      if (value[k] === undefined) throw Error(`${label}.${k} is required`);
    for (const [k, v] of Object.entries(value)) {
      if (!s.properties[k]) throw Error(`unknown ${label}.${k}`);
      validate(v, s.properties[k], `${label}.${k}`);
    }
  } else if (s.type === "array") {
    if (!Array.isArray(value) || value.length < (s.minItems || 0))
      throw Error(`${label} must be nonempty array`);
    for (const v of value) validate(v, s.items, label);
  } else if (s.type === "integer") {
    if (!Number.isInteger(value) || value < s.minimum || value > s.maximum)
      throw Error(`${label} integer out of range`);
  } else if (typeof value !== s.type || (s.minLength && !value.trim()))
    throw Error(`${label} must be nonempty ${s.type}`);
  if (s.enum && !s.enum.includes(value))
    throw Error(`${label} must be one of ${s.enum.join(", ")}`);
}
export function createTools({ root, home, state, env = process.env }) {
  root = fs.realpathSync(root);
  home = fs.realpathSync(home);
  state = path.resolve(state || path.join(home, "state"));
  const vars = {
    ...env,
    YMIR_ROOT: root,
    YMIR_HOME: home,
    BROKK_STATE_OVERRIDE: state,
    BROKK_DATA_OVERRIDE:
      env.BROKK_DATA_OVERRIDE || path.join(home, "hodd", "data"),
  };
  const shell = (door, args = [], cwd = root) =>
    run(env.YMIR_BASH || "bash", [path.join(root, door), ...args], cwd, vars);
  // A chosen WSL well is a separate home. Never guess it from a Windows path.
  // Start its supervised service, verify its identity, and execute all memory
  // operations within that Linux home; never fall back to the Windows log.
  const wellShell = async (args) => {
    const configFile = path.join(home, "hodd", "data", "codex-well.json");
    const requiredFile = path.join(home, "hodd", "data", "codex-well.required");
    const present = p => {
      try { fs.lstatSync(p); return true; }
      catch (e) { if (e.code === "ENOENT") return false; throw e; }
    };
    const required = present(requiredFile);
    if (required && !inside(home, fs.realpathSync(requiredFile))) throw Error("well route marker escapes the home");
    if (required && !present(configFile)) throw Error("selected well configuration is missing");
    let config = {};
    if (present(configFile)) {
      if (!inside(home, fs.realpathSync(configFile))) throw Error("well configuration escapes the home");
      try { config = JSON.parse(fs.readFileSync(configFile, "utf8")); }
      catch { throw Error("invalid codex-well.json"); }
      const keys = ["route", "distro", "root", "home", "store", "service", "url"];
      if (!config || Array.isArray(config) || typeof config !== "object" ||
          Object.entries(config).some(([k,v]) => !keys.includes(k) || typeof v !== "string"))
        throw Error("invalid codex-well.json fields");
    }
    const pick = (key, field) => env[key] !== undefined ? env[key] : config[field];
    const configuredRoute = pick("YMIR_CODEX_WELL_ROUTE", "route");
    const route = configuredRoute === undefined ? "local" : configuredRoute;
    if (required && route !== "wsl") throw Error("selected well requires the WSL route");
    if (route === "local") return shell("bin/records/mimir.sh", args, home);
    if (route !== "wsl") throw Error("unsupported YMIR_CODEX_WELL_ROUTE");
    const linuxRoot = pick("YMIR_WSL_WELL_ROOT", "root");
    const linuxHome = pick("YMIR_WSL_WELL_HOME", "home");
    const expectedStore = pick("YMIR_WSL_WELL_STORE", "store");
    for (const [key, value] of Object.entries({YMIR_WSL_WELL_ROOT: linuxRoot, YMIR_WSL_WELL_HOME: linuxHome, YMIR_WSL_WELL_STORE: expectedStore})) {
      if (!value || !path.posix.isAbsolute(value) || value.includes("\0"))
        throw Error(`${key} must name an absolute Linux path`);
    }
    const relativeStore = path.posix.relative(linuxHome, expectedStore);
    if (!relativeStore || relativeStore === ".." || relativeStore.startsWith("../") || path.posix.isAbsolute(relativeStore))
      throw Error("selected store must belong to the selected Linux home");
    const wsl = env.YMIR_WSL || "wsl.exe";
    const distroName = pick("YMIR_WSL_DISTRO", "distro");
    if (!distroName || distroName.includes("\0"))
      throw Error("YMIR_WSL_DISTRO must name the selected Linux distribution");
    const distro = ["-d", distroName];
    const bounded = async (argv) => {
      try { return (await exec(wsl, argv, {env, cwd: home, timeout: 30000, windowsHide: true, maxBuffer: 4194304})).stdout.trim(); }
      catch (e) { throw Error(`WSL well command failed (${e.code ?? "unavailable"}): ${String(e.stderr || e.message).slice(0, 1000)}`); }
    };
    const service = pick("YMIR_WSL_WELL_SERVICE", "service") || "mimir.service";
    if (!/^[A-Za-z0-9_][A-Za-z0-9_.@-]*\.service$/.test(service))
      throw Error("invalid WSL well service name");
    const url = pick("MIMIRSBRUNN_URL", "url") || "http://127.0.0.1:4602";
    const endpoint = new URL(url);
    if (endpoint.protocol !== "http:" || !["127.0.0.1", "localhost", "[::1]"].includes(endpoint.hostname) || endpoint.username || endpoint.password || endpoint.pathname !== "/" || endpoint.search || endpoint.hash)
      throw Error("WSL well URL must be a loopback HTTP origin");
    await bounded([...distro, "--exec", "test", "-d", linuxHome]);
    await bounded([...distro, "--exec", "test", "-f", `${linuxRoot}/bin/records/mimir.sh`]);
    await bounded([...distro, "--exec", "test", "-f", expectedStore]);
    const realHome = await bounded([...distro, "--exec", "realpath", "-e", "--", linuxHome]);
    const realStore = await bounded([...distro, "--exec", "realpath", "-e", "--", expectedStore]);
    const physical = path.posix.relative(realHome, realStore);
    if (!path.posix.isAbsolute(realHome) || !path.posix.isAbsolute(realStore) || !physical || physical === ".." || physical.startsWith("../") || path.posix.isAbsolute(physical))
      throw Error("selected store resolves outside the selected Linux home");
    await bounded([...distro, "--exec", "systemctl", "--user", "start", service]);
    const deadline = Date.now() + 20000;
    let health, error;
    while (Date.now() < deadline) {
      try {
        const response = await bounded([...distro, "--exec", "curl", "-fsS", "--max-time", "2", new URL("/health", endpoint).toString()]);
        health = JSON.parse(response);
        break;
      } catch (e) { error = e; await new Promise(resolve => setTimeout(resolve, 250)); }
    }
    if (!health) throw Error(`WSL well health unavailable: ${error?.message || "timeout"}`);
    if (health.status !== "up" || health.store !== expectedStore)
      throw Error("WSL well store does not match the selected store");
    return bounded([...distro, "--exec", "env", `YMIR_HOME=${linuxHome}`, `ENGRAM_DB=${expectedStore}`,
      `MIMIRSBRUNN_URL=${url}`, "MIMIR_REQUIRE_BRIDGE=1", `MIMIR_EXPECTED_STORE=${expectedStore}`,
      "bash", `${linuxRoot}/bin/records/mimir.sh`, ...args]);
  };
  const git = (args, cwd = home) => run("git", args, cwd, vars);
  const inside = (base, p) => {
    const r = path.relative(base, p);
    return (
      r === "" ||
      (!r.startsWith(".." + path.sep) && r !== ".." && !path.isAbsolute(r))
    );
  };
  function safe(rel, credentials = false) {
    if (
      typeof rel !== "string" ||
      !rel ||
      rel.includes("\\") ||
      rel.includes("\0") ||
      path.isAbsolute(rel) ||
      /^[a-zA-Z]:/.test(rel) ||
      rel.split("/").some((x) => !x || x === "." || x === "..")
    )
      throw Error("path must be home-relative without traversal");
    if (!credentials && secret.test(rel))
      throw Error("credential paths refused");
    const p = path.resolve(home, rel);
    let component = home;
    for (const part of rel.split("/")) {
      component = path.join(component, part);
      let st;
      try {
        st = fs.lstatSync(component);
      } catch (e) {
        if (e.code === "ENOENT") continue;
        throw e;
      }
      if (st.isSymbolicLink()) {
        let resolved;
        try {
          resolved = fs.realpathSync(component);
        } catch {
          throw Error("unresolved symlink refused");
        }
        if (!inside(home, resolved)) throw Error("symlink escapes home");
        const physical = path
          .relative(home, resolved)
          .split(path.sep)
          .join("/");
        if (!credentials && secret.test(physical))
          throw Error("symlink targets credentials");
        const linkedRealm = /^svartalfaheim\/([^/]+)(?:\/|$)/.exec(physical);
        if (
          linkedRealm &&
          (!env.YMIR_REALM || linkedRealm[1] !== env.YMIR_REALM)
        ) {
          throw Error("symlink targets another realm");
        }
      }
    }
    let ancestor = p;
    while (!fs.existsSync(ancestor)) {
      const next = path.dirname(ancestor);
      if (next === ancestor) throw Error("home missing");
      ancestor = next;
    }
    if (!inside(home, fs.realpathSync(ancestor)))
      throw Error("symlink escapes home");
    const realm = /^svartalfaheim\/([^/]+)(?:\/|$)/.exec(rel);
    if (realm && (!env.YMIR_REALM || realm[1] !== env.YMIR_REALM))
      throw Error("set YMIR_REALM to this selected realm first");
    return p;
  }
  function shelf(rel) {
    safe(rel);
    if (/^hodd\/(docs|life|memory|reference|data|identity)\//.test(rel))
      return "private home shelf";
    const m =
      /^svartalfaheim\/([^/]+)\/workspace\/([^/]+)\/(plans|docs)\//.exec(rel);
    if (m) {
      if (!env.YMIR_REALM || m[1] !== env.YMIR_REALM)
        throw Error("set YMIR_REALM to this explicitly selected realm first");
      return m[3] === "plans" ? "canonical plan ledger" : "realm project shelf";
    }
    throw Error("no shelf claims this path");
  }
  function append(rel, text) {
    shelf(rel);
    const p = safe(rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    safe(rel);
    fs.appendFileSync(p, text);
    return `appended to ${rel}`;
  }
  function walk(base, depth = 20, prefix = "") {
    if (depth < 0 || !fs.existsSync(base)) return [];
    const out = [];
    for (const e of fs.readdirSync(base, { withFileTypes: true })) {
      if (
        e.name.startsWith(".") ||
        e.name === "node_modules" ||
        secret.test(e.name) ||
        e.isSymbolicLink()
      )
        continue;
      const r = prefix + e.name;
      if (e.isFile()) out.push(r);
      else if (e.isDirectory())
        out.push(...walk(path.join(base, e.name), depth - 1, r + "/"));
    }
    return out;
  }
  function files() {
    const out = walk(safe("hodd"), 20, "hodd/");
    if (env.YMIR_REALM) {
      const rel = `svartalfaheim/${leaf(env.YMIR_REALM)}/workspace`;
      out.push(...walk(safe(rel), 20, rel + "/"));
    }
    return out;
  }
  function figures() {
    return fs
      .readdirSync(path.join(root, ".agents", "agents"))
      .filter((n) => n.endsWith(".md"))
      .map((n) => {
        const t = fs.readFileSync(
            path.join(root, ".agents", "agents", n),
            "utf8",
          ),
          fm = t.startsWith("---") ? t.slice(3, t.indexOf("\n---", 3)) : "";
        return {
          name: (/^name:\s*(.+)$/m.exec(fm)?.[1] || n.slice(0, -3)).replace(
            /^["']|["']$/g,
            "",
          ),
          description: (/^description:\s*(.+)$/m.exec(fm)?.[1] || "").replace(
            /^["']|["']$/g,
            "",
          ),
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }
  const tools = [];
  const add = (name, description, properties, required, fn) =>
    tools.push({
      name,
      description,
      inputSchema: {
        type: "object",
        properties,
        required,
        additionalProperties: false,
      },
      fn,
    });
  add(
    "ymir_recall",
    "Recall from the shared well before acting.",
    { query: S, limit: N },
    ["query"],
    (a) =>
      wellShell(["recall", a.query, "--k", String(a.limit ?? 5)]),
  );
  add(
    "ymir_remember",
    "Observe a lesson into the shared well.",
    { lesson: S, tags: A, actors: A },
    ["lesson"],
    (a) =>
      wellShell(
        [
          "observe",
          [
            a.lesson,
            a.tags ? `tags: ${a.tags.join(",")}` : "",
            a.actors ? `actors: ${a.actors.join(",")}` : "",
          ]
            .filter(Boolean)
            .join(" "),
        ],
      ),
  );
  add(
    "ymir_errand",
    "Start, read, steer or close an Eindri through the canonical gates.",
    {
      action: E("start", "read", "steer", "close"),
      id: S,
      project: S,
      harness: S,
      model: S,
      mode: E("direct-PR", "local-only", "no-mistakes"),
      message: S,
      terminal: E("done", "paused", "failed", "cancelled"),
      note: S,
    },
    ["action", "id"],
    async (a) => {
      leaf(a.id);
      if (a.action === "read") {
        const rows = ["meta", "status"]
          .filter((x) => fs.existsSync(path.join(state, `${a.id}.${x}`)))
          .map(
            (x) =>
              `${x}:\n${fs.readFileSync(path.join(state, `${a.id}.${x}`), "utf8")}`,
          );
        if (!rows.length) throw Error("no recorded errand");
        return rows.join("\n");
      }
      if (a.action === "start") {
        if (!a.project) throw Error("start requires project");
        return shell("bin/agents/einherjar-spawn.sh", [
          a.id,
          a.project,
          "--mode",
          a.mode || "direct-PR",
          ...(a.harness ? ["--harness", a.harness] : []),
          ...(a.model ? ["--model", a.model] : []),
        ]);
      }
      if (a.action === "steer") {
        if (!a.message) throw Error("steer requires message");
        return shell("bin/agents/eindri-send.sh", [a.id, a.message]);
      }
      const claim = await shell("bin/agents/eindri-acclaim.sh", [
        a.id,
        "--terminal",
        a.terminal || "done",
        ...(a.note ? ["--line", a.note] : []),
      ]);
      return (
        claim +
        "\n" +
        (await shell("bin/agents/eindri-control.sh", ["exit", a.id]))
      );
    },
  );
  add(
    "ymir_heal",
    "Run Eir diagnostics or repairs.",
    { mode: E("check", "fix") },
    [],
    (a) => shell("bin/agents/eir-doctor.sh", [a.mode || "check"]),
  );
  add(
    "ymir_update",
    "Check or update Ymir through Gróa.",
    { mode: E("check", "update") },
    [],
    (a) =>
      shell(
        "bin/agents/groa-update.sh",
        a.mode === "update" ? [] : ["--check"],
      ),
  );
  add(
    "ymir_note",
    "Append a dated section without rewriting previous bytes.",
    { path: S, heading: S, body: S },
    ["path", "heading", "body"],
    (a) =>
      append(
        a.path,
        `\n---\n\n## ${a.heading} — ${new Date().toISOString().slice(0, 10)}\n\n${a.body}\n`,
      ),
  );
  add(
    "ymir_plan",
    "Create a complete plan only after the canonical plan audit passes; realm, project and actual plan body are required.",
    { slug: S, title: S, realm: S, project: S, body: S },
    ["slug", "title", "realm", "project", "body"],
    async (a) => {
      for (const k of ["slug", "realm", "project"]) leaf(a[k]);
      if (!env.YMIR_REALM || a.realm !== env.YMIR_REALM)
        throw Error("set YMIR_REALM to the selected realm first");
      const rel = `svartalfaheim/${a.realm}/workspace/${a.project}/plans`,
        dir = safe(rel);
      if (!fs.statSync(dir).isDirectory())
        throw Error("ledger must already exist");
      const lock = path.join(dir, ".codex-plan.lock"),
        fd = fs.openSync(lock, "wx");
      let staged;
      try {
        const index = safe(rel + "/README.md"),
          text = fs.readFileSync(index, "utf8");
        const nums = [
          ...fs.readdirSync(dir).map((n) => /^(\d+)-/.exec(n)?.[1]),
          ...[...text.matchAll(/(?:\b|\[)(\d+)-[^\s)]+\.md/g)].map((m) => m[1]),
        ]
          .filter(Boolean)
          .map(Number);
        const n = String(Math.max(0, ...nums) + 1).padStart(2, "0"),
          name = `${n}-${a.slug}.md`,
          content = `# Plan ${n} - ${a.title}\n\n${a.body}\n`,
          row = `\n| ${n} | [${a.title.replace(/[\r\n|]/g, " ")}](${name}) | opened |\n`;
        shelf(`${rel}/${name}`);
        staged = fs.mkdtempSync(path.join(dir, ".codex-plan-check-"));
        fs.writeFileSync(path.join(staged, name), content, { flag: "wx" });
        fs.writeFileSync(path.join(staged, "README.md"), row, { flag: "wx" });
        const audit = JSON.parse(
          await shell("bin/gates/plan-audit.sh", ["--json", "--shelf", staged]),
        );
        if (audit.plans !== 1 || audit.gaps !== 0)
          throw Error(
            "canonical plan audit refused: " + JSON.stringify(audit.rows),
          );
        fs.writeFileSync(safe(`${rel}/${name}`), content, { flag: "wx" });
        fs.appendFileSync(index, row);
        return `created ${rel}/${name}; canonical audit passed; appended README index`;
      } finally {
        if (staged) fs.rmSync(staged, { recursive: true, force: true });
        fs.closeSync(fd);
        fs.unlinkSync(lock);
      }
    },
  );
  add(
    "ymir_push",
    "Commit only named home files; refuse secrets, deletions and unrelated staging.",
    { paths: A, message: S, push: B },
    ["paths", "message"],
    async (a) => {
      for (const p of a.paths) {
        shelf(p);
        if (!fs.statSync(safe(p)).isFile())
          throw Error("name individual files");
      }
      const staged = (await git(["diff", "--cached", "--name-only", "-z"]))
        .split("\0")
        .filter(Boolean);
      if (staged.some((p) => !a.paths.includes(p)))
        throw Error("unrelated files already staged");
      if (
        await git([
          "diff",
          "--name-only",
          "--diff-filter=D",
          "HEAD",
          "--",
          ...a.paths,
        ])
      )
        throw Error("tracked deletions refused");
      await git(["add", "--", ...a.paths]);
      await git(["commit", "--only", "-m", a.message, "--", ...a.paths]);
      if (a.push !== false) await git(["push"]);
      return git(["log", "-1", "--format=%h %s"]);
    },
  );
  add(
    "ymir_daily",
    "Read or append the private dated daily log.",
    { note: S },
    [],
    (a) => {
      const rel = `hodd/memory/daily/${new Date().toISOString().slice(0, 10)}.md`;
      if (a.note)
        return append(
          rel,
          `\n- ${new Date().toISOString().slice(11, 16)} ${a.note}\n`,
        );
      return fs.existsSync(safe(rel))
        ? fs.readFileSync(safe(rel), "utf8")
        : "no entry today";
    },
  );
  add(
    "ymir_find_home",
    "Explain placement of an explicit path; never guess the realm.",
    { path: S, note: S, sample: S },
    ["path"],
    (a) => `${a.path}: ${shelf(a.path)}`,
  );
  add(
    "ymir_place",
    "Copy a document to a validated shelf without overwrite; move requires move=true.",
    { path: S, source: S, why: S, move: B },
    ["path", "why"],
    (a) => {
      const s = shelf(a.path);
      if (!a.source) return `valid shelf: ${s}; no file written`;
      const src = fs.realpathSync(path.resolve(a.source));
      if (inside(home, src))
        safe(path.relative(home, src).split(path.sep).join("/"));
      if (secret.test(src)) throw Error("credential sources refused");
      if (!fs.statSync(src).isFile()) throw Error("source must be file");
      const dest = safe(a.path);
      if (src === dest) throw Error("source is destination");
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      safe(a.path);
      fs.copyFileSync(src, dest, fs.constants.COPYFILE_EXCL);
      if (a.move) fs.unlinkSync(src);
      return `${a.move ? "moved" : "copied"} to ${a.path}: ${a.why}`;
    },
  );
  add(
    "ymir_import",
    "Preview outside document imports; apply requires an explicit area and preserves sources.",
    {
      sources: A,
      area: E("marketing", "personal", "work", "research", "reference"),
      dryRun: B,
    },
    ["sources"],
    async (a) => {
      if (a.dryRun === false && !a.area)
        throw Error("apply requires explicit area");
      const base = {
          marketing: "hodd/life/marketing/imported",
          personal: "hodd/life/personal/imported",
          work: "hodd/life/work/imported",
          research: "hodd/docs/research/imported",
          reference: "hodd/reference/imported",
        }[a.area || "reference"],
        rows = [];
      for (const src of a.sources) {
        if (!path.isAbsolute(src)) throw Error("sources must be absolute");
        if (inside(home, fs.realpathSync(src)))
          throw Error("source already belongs to home");
        if (secret.test(src)) throw Error("credential sources refused");
        const rel = `${base}/${path.basename(src)}`;
        shelf(rel);
        rows.push(
          a.dryRun !== false
            ? `would copy ${src} -> ${rel}`
            : await tools
                .find((t) => t.name === "ymir_place")
                .fn({
                  path: rel,
                  source: src,
                  why: `explicit ${a.area} import`,
                  move: false,
                }),
        );
      }
      return rows.join("\n");
    },
  );
  add(
    "ymir_structure",
    "List actual private shelves and the active realm without following symlinks.",
    { depth: { ...N, maximum: 10 } },
    [],
    (a) => {
      const rows = new Map();
      for (const f of files()) {
        const parts = f.split("/");
        for (let i = 1; i < Math.min(parts.length, (a.depth || 2) + 1); i++) {
          const d = parts.slice(0, i).join("/") + "/";
          rows.set(d, (rows.get(d) || 0) + 1);
        }
      }
      return (
        [...rows].map(([d, n]) => `${d} (${n} files)`).join("\n") ||
        "no documents"
      );
    },
  );
  add(
    "ymir_find",
    "Find document names or contents in private shelves and the explicitly active realm.",
    { what: S, content: B },
    ["what"],
    (a) => {
      const q = a.what.toLowerCase();
      return (
        files()
          .filter(
            (f) =>
              f.toLowerCase().includes(q) ||
              (a.content &&
                fs.statSync(safe(f)).size < 1048576 &&
                fs.readFileSync(safe(f), "utf8").toLowerCase().includes(q)),
          )
          .slice(0, 40)
          .join("\n") || "nothing matched"
      );
    },
  );
  add(
    "ymir_index",
    "Report home Git status, last commit and upstream divergence.",
    {},
    [],
    async () =>
      [
        await git(["status", "--porcelain"]),
        await git(["log", "-1", "--format=%h %ad %s", "--date=short"]),
        await git([
          "rev-list",
          "--left-right",
          "--count",
          "@{upstream}...HEAD",
        ]),
      ].join("\n"),
  );
  add(
    "ymir_secret_keys",
    "List variable names only through the canonical vault door; values never leave the shell pipeline.",
    { filter: S },
    [],
    async (a) => {
      const command =
        'set -euo pipefail; bash "$1/bin/vault/hodd.sh" emit secrets/platform.env 2>/dev/null | sed -n "s/^export \\([A-Za-z_][A-Za-z0-9_]*\\)=.*/\\1/p" | sort -u';
      let out;
      try {
        out = await run(
          env.YMIR_BASH || "bash",
          ["-c", command, "_", root],
          root,
          vars,
        );
      } catch {
        throw Error(
          "vault key names unavailable; check the canonical vault door and Bash dependencies",
        );
      }
      return (
        out
          .split("\n")
          .filter(
            (n) =>
              /^[A-Za-z_][A-Za-z0-9_]*$/.test(n) &&
              (!a.filter || n.toLowerCase().includes(a.filter.toLowerCase())),
          )
          .join("\n") || "no matching key names"
      );
    },
  );
  add(
    "ymir_layout",
    "Validate the canonical workspace placement law.",
    { path: S },
    [],
    (a) =>
      a.path
        ? `${a.path}: ${shelf(a.path)}`
        : "hodd/{docs,life,memory,data,identity,reference}/; svartalfaheim/<realm>/workspace/<project>/{plans,docs}/; secrets are not documents",
  );
  add(
    "subagent",
    "List canonical figures or dispatch a named specialist with an explicit mission, acceptance and seat choice.",
    { agent: S, task: S, done: S, project: S, seat: S, noSeat: B },
    [],
    async (a) => {
      const roster = figures();
      if (!a.agent && !a.task) return JSON.stringify(roster);
      const args = figureDispatchArgs(a, roster, root);
      return shell("bin/agents/eindri-dispatch.sh", args);
    },
  );
  add(
    "ymir_well",
    "Call the well: recall or search (hybrid recall), observe, or stats (health).",
    { action: E("recall", "observe", "search", "stats"), query: S, limit: N },
    ["action"],
    (a) => {
      if (a.action !== "stats" && !a.query) throw Error("query required");
      return wellShell(
        [
          a.action === "stats" ? "health" : a.action === "search" ? "recall" : a.action,
          ...(a.query ? [a.query] : []),
          ...(["recall", "search"].includes(a.action)
            ? ["--k", String(a.limit ?? 5)]
            : []),
        ],
      );
    },
  );
  add(
    "ymir_dellingr",
    "Grade docs using measured Git age; missing measurements remain explicit.",
    { path: S, ageDays: N },
    [],
    async (a) => {
      if (
        a.path &&
        !/^hodd(?:\/|$)/.test(a.path) &&
        !(
          env.YMIR_REALM &&
          a.path.startsWith(`svartalfaheim/${leaf(env.YMIR_REALM)}/`)
        )
      ) {
        throw Error(
          "grade hodd or a path within the selected realm, never all realm shelves",
        );
      }
      const base = a.path ? safe(a.path) : safe("hodd"),
        rows = [];
      for (const f of walk(base)
        .filter((f) => f.endsWith(".md"))
        .slice(0, 400)) {
        const rel = path
            .relative(home, path.join(base, f))
            .split(path.sep)
            .join("/"),
          stamp = await git(["log", "-1", "--format=%ct", "--", rel]),
          days = /^\d+$/.test(stamp)
            ? Math.floor((Date.now() - Number(stamp) * 1000) / 86400000)
            : null,
          limit = a.ageDays ?? 365,
          grade = rel.startsWith("hodd/reference/")
            ? "safn"
            : days === null
              ? "unmeasured"
              : days >= limit
                ? "forn"
                : days >= limit / 2
                  ? "eldri"
                  : "nýr";
        rows.push(
          `${grade} ${rel} (${days === null ? "no measured Git age" : days + "d"})`,
        );
      }
      return rows.join("\n") || "no markdown documents";
    },
  );
  add("gna_watch_arm", "Arm or inspect the canonical watcher; Codex native heartbeat owns wake delivery.", { action: E("arm", "status", "poll"), threadId: S }, [], (a) =>
    gnaArm({ root, home, state, env: vars }, a),
  );
  add(
    "subagents",
    "List canonical figures, the OpenCode slash-command equivalent.",
    {},
    [],
    () => JSON.stringify(figures()),
  );
  return {
    list: () => tools.map(({ fn, ...t }) => t),
    async call(name, args = {}) {
      const t = tools.find((t) => t.name === name);
      if (!t) throw Error("unknown tool");
      validate(args, t.inputSchema);
      return String(await t.fn(args));
    },
  };
}

// The specialist is a first-class dispatch argument, never a placeholder in a generic brief.
export function figureDispatchArgs(a, roster, root) {
  if (!a.agent || !a.task || !a.done)
    throw Error("dispatch requires agent, task and done");
  const figure = roster.find((f) => f.name === a.agent);
  if (!figure) throw Error("unknown figure");
  leaf(figure.name);
  if ((!a.seat && a.noSeat !== true) || (a.seat && a.noSeat))
    throw Error("choose seat or explicitly set noSeat=true");
  const id = `${figure.name}-${Date.now().toString(36)}`;
  return [
    "new",
    id,
    a.project || root,
    "--mode",
    "direct-PR",
    "--title",
    a.task,
    "--done",
    a.done,
    "--figure",
    figure.name,
    ...(a.seat ? ["--seat", a.seat] : ["--no-seat"]),
  ];
}
