import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, execFileSync } from "node:child_process";
import {
  createTools,
  figureDispatchArgs,
} from "../.agents/harness/codex/tools.mjs";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
function setup(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "ymir-codex-"));
  fs.mkdirSync(path.join(home, "hodd", "docs"), { recursive: true });
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  return {
    home,
    tools: createTools({
      root,
      home,
      env: { ...process.env, YMIR_BASH: "ymir-test-no-such-bash" },
    }),
  };
}
test("catalog matches the OpenCode model tool surface plus its two command equivalents", (t) => {
  const { tools } = setup(t);
  const source = fs.readFileSync(
    path.join(root, ".agents/harness/opencode/plugins/ymir-tools.ts"),
    "utf8",
  );
  const names = [...source.matchAll(/name: "(ymir_[a-z_]+|subagent)"/g)].map(
    (m) => m[1],
  );
  assert.equal(names.length, 20);
  assert.deepEqual(
    tools
      .list()
      .map((t) => t.name)
      .sort(),
    [...names, "gna_watch_arm", "subagents"].sort(),
  );
});
test("notes preserve bytes, reject invalid input, traversal and credential paths", async (t) => {
  const { home, tools } = setup(t);
  const f = path.join(home, "hodd", "docs", "note.md");
  fs.writeFileSync(f, "previous\n");
  await tools.call("ymir_note", {
    path: "hodd/docs/note.md",
    heading: "Update",
    body: "new bytes",
  });
  assert.match(fs.readFileSync(f, "utf8"), /^previous\n\n---\n/);
  for (const p of [
    "hodd/../../escape.md",
    "C:/escape.md",
    "hodd\\docs\\escape.md",
    "hodd/secrets/key.md",
  ])
    await assert.rejects(
      tools.call("ymir_note", { path: p, heading: "x", body: "y" }),
    );
  await assert.rejects(
    tools.call("ymir_note", {
      path: "hodd/docs/new.md",
      heading: "x",
      body: 2,
    }),
  );
  assert.equal(fs.existsSync(path.join(home, "hodd", "docs", "new.md")), false);
});
test("escaping and dangling directory links are refused", async (t) => {
  const { home, tools } = setup(t);
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), "ymir-outside-"));
  t.after(() => fs.rmSync(outside, { recursive: true, force: true }));
  try {
    fs.symlinkSync(
      outside,
      path.join(home, "hodd", "docs", "outside"),
      process.platform === "win32" ? "junction" : "dir",
    );
  } catch (e) {
    if (process.platform === "win32" && e.code === "EPERM") {
      t.skip(
        "Windows sandbox refuses creation of directory links; run this guard test on Linux CI",
      );
      return;
    }
    throw e;
  }
  await assert.rejects(
    tools.call("ymir_note", {
      path: "hodd/docs/outside/no.md",
      heading: "x",
      body: "y",
    }),
    /symlink/,
  );
  assert.equal(fs.readdirSync(outside).length, 0);
  fs.symlinkSync(
    path.join(outside, "missing"),
    path.join(home, "hodd/docs/dangling"),
    process.platform === "win32" ? "junction" : "dir",
  );
  await assert.rejects(
    tools.call("ymir_note", {
      path: "hodd/docs/dangling/no.md",
      heading: "x",
      body: "y",
    }),
    /symlink/,
  );
});
test("placement never overwrites and copies unless explicitly told to move", async (t) => {
  const { home, tools } = setup(t);
  const source = path.join(home, "hodd", "docs", "source.md");
  fs.writeFileSync(source, "original");
  await tools.call("ymir_place", {
    path: "hodd/docs/dest.md",
    source,
    why: "test",
  });
  assert.equal(fs.readFileSync(source, "utf8"), "original");
  await assert.rejects(
    tools.call("ymir_place", {
      path: "hodd/docs/dest.md",
      source,
      why: "test",
    }),
  );
  assert.equal(
    fs.readFileSync(path.join(home, "hodd/docs/dest.md"), "utf8"),
    "original",
  );
});
test("plan creation refuses absent content, realm selection and missing canonical audit dependencies", async (t) => {
  const { home } = setup(t);
  const tools = createTools({
    root,
    home,
    env: {
      ...process.env,
      YMIR_REALM: "test",
      YMIR_BASH: "ymir-test-no-such-bash",
    },
  });
  const dir = path.join(
    home,
    "svartalfaheim",
    "test",
    "workspace",
    "demo",
    "plans",
  );
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "README.md"),
    "original index\n[retired](42-old.md)\n",
  );
  await assert.rejects(
    tools.call("ymir_plan", {
      slug: "next",
      title: "Next",
      realm: "test",
      project: "demo",
    }),
    /body/,
  );
  await assert.rejects(
    tools.call("ymir_plan", {
      slug: "next",
      title: "Next",
      realm: "test",
      project: "demo",
      body: "actual plan text",
    }),
    /failed/,
  );
  assert.equal(
    fs.readFileSync(path.join(dir, "README.md"), "utf8"),
    "original index\n[retired](42-old.md)\n",
  );
  assert.deepEqual(fs.readdirSync(dir), ["README.md"]);
});
test("shell dependency failure is an error, never empty success", async (t) => {
  const { tools } = setup(t);
  await assert.rejects(tools.call("ymir_heal", {}), /failed/);
});
test("search excludes credential directories and other realms", async (t) => {
  const { home, tools } = setup(t);
  fs.mkdirSync(path.join(home, "hodd/secrets"), { recursive: true });
  fs.writeFileSync(
    path.join(home, "hodd/secrets/searchneedle"),
    "must not surface",
  );
  fs.mkdirSync(path.join(home, "svartalfaheim/other/workspace/demo/docs"), {
    recursive: true,
  });
  fs.writeFileSync(
    path.join(home, "svartalfaheim/other/workspace/demo/docs/searchneedle.md"),
    "must not surface",
  );
  assert.equal(
    await tools.call("ymir_find", { what: "searchneedle", content: true }),
    "nothing matched",
  );
});
test("stdio lifecycle, catalog, invalid arguments and tool failures are valid MCP responses", async (t) => {
  const { home } = setup(t);
  const child = spawn(
    process.execPath,
    [path.join(root, ".agents/harness/codex/server.mjs")],
    {
      env: {
        ...process.env,
        YMIR_ROOT: root,
        YMIR_HOME: home,
        YMIR_BASH: "ymir-test-no-such-bash",
      },
      stdio: ["pipe", "pipe", "pipe"],
    },
  );
  t.after(() => child.kill());
  const replies = new Map();
  let pending = "";
  let error = "";
  child.stderr.on("data", (b) => (error += b));
  child.stdout.on("data", (b) => {
    pending += b;
    let i;
    while ((i = pending.indexOf("\n")) >= 0) {
      const msg = JSON.parse(pending.slice(0, i));
      pending = pending.slice(i + 1);
      replies.set(msg.id, msg);
    }
  });
  let id = 0;
  async function request(method, params) {
    const current = ++id;
    child.stdin.write(
      JSON.stringify({ jsonrpc: "2.0", id: current, method, params }) + "\n",
    );
    const until = Date.now() + 5000;
    while (!replies.has(current) && Date.now() < until)
      await new Promise((r) => setTimeout(r, 10));
    assert.ok(replies.has(current), error || "MCP request timed out");
    return replies.get(current);
  }
  assert.equal(
    (await request("initialize", { protocolVersion: "2025-06-18" })).result
      .serverInfo.name,
    "ymir",
  );
  assert.equal((await request("tools/list")).result.tools.length, 22);
  assert.equal(
    (
      await request("tools/call", {
        name: "ymir_note",
        arguments: { path: "hodd/docs/no.md" },
      })
    ).result.isError,
    true,
  );
  assert.equal(
    (await request("tools/call", { name: "ymir_heal", arguments: {} })).result
      .isError,
    true,
  );
  assert.equal(
    (await request("tools/call", { name: "ymir_layout", arguments: {} })).result
      .isError,
    undefined,
  );
  assert.equal((await request("missing")).error.code, -32601);
  child.stdin.end();
});

test("explicit source reads and moves cannot cross the active realm", async (t) => {
  const { home } = setup(t);
  const tools = createTools({
    root,
    home,
    env: { ...process.env, YMIR_REALM: "one" },
  });
  const other = path.join(home, "svartalfaheim/two/workspace/demo/docs");
  fs.mkdirSync(other, { recursive: true });
  const src = path.join(other, "note.md");
  fs.writeFileSync(src, "private two");
  await assert.rejects(
    tools.call("ymir_place", {
      path: "hodd/docs/import.md",
      source: src,
      why: "not allowed",
      move: true,
    }),
    /realm/,
  );
  await assert.rejects(
    tools.call("ymir_dellingr", {
      path: "svartalfaheim/two/workspace/demo/docs",
    }),
    /realm/,
  );
  assert.equal(fs.readFileSync(src, "utf8"), "private two");
  assert.equal(fs.existsSync(path.join(home, "hodd/docs/import.md")), false);
});
test("specialist dispatch binds the requested figure and explicit acceptance/seat", () => {
  const roster = [{ name: "huginn" }];
  const args = figureDispatchArgs(
    {
      agent: "huginn",
      task: "Inspect the wire",
      done: "Report measured endpoints",
      noSeat: true,
    },
    roster,
    root,
  );
  assert.equal(args[0], "new");
  assert.equal(args[args.indexOf("--figure") + 1], "huginn");
  assert.equal(args[args.indexOf("--done") + 1], "Report measured endpoints");
  assert.ok(args.includes("--no-seat"));
  assert.throws(
    () =>
      figureDispatchArgs({ agent: "huginn", task: "Inspect" }, roster, root),
    /done/,
  );
  assert.throws(
    () =>
      figureDispatchArgs(
        { agent: "huginn", task: "Inspect", done: "Report" },
        roster,
        root,
      ),
    /seat/,
  );
});
let bashWorks = true;
try {
  execFileSync(process.env.YMIR_BASH || "bash", ["--version"], {
    stdio: "ignore",
    windowsHide: true,
  });
} catch {
  bashWorks = false;
}
test(
  "real canonical plan audit accepts full content and rejects a bare skeleton",
  {
    skip: bashWorks
      ? false
      : "Bash unavailable locally; Linux CI must run the canonical plan-audit integration",
  },
  async (t) => {
    const { home } = setup(t);
    const tools = createTools({
        root,
        home,
        env: { ...process.env, YMIR_REALM: "test" },
      }),
      dir = path.join(home, "svartalfaheim/test/workspace/demo/plans");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(
      path.join(dir, "README.md"),
      "# Plans\n\n| Number | Plan | Status |\n|---|---|---|\n| 42 | [Retired](42-old.md) | archived |\n",
    );
    const body =
      '**Status:** opened - **Date:** 2026-11-02\n\n**His words, 2026-11-02:** *"make the thing and prove the thing."*\n\n## 1 - The measured state\n\n```\nmeasured on this box: 3 doors, 1 answering\n```\n\n## 2 - The work\n\nThe first step. Proof: `bin/gates/demo.sh --check` exits 0.\n\n## 3 - The second step\n\nVerified by a smoke run.\n\n## What it refuses\n\nIt refuses to answer zero when it cannot read the shelf.\n\n## Questions for the Allfather\n\n1. Is the shelf correct?\n';
    const args = {
      slug: "next",
      title: "Next",
      realm: "test",
      project: "demo",
      body,
    };
    await tools.call("ymir_plan", args);
    assert.ok(fs.existsSync(path.join(dir, "43-next.md")));
    assert.match(
      fs.readFileSync(path.join(dir, "README.md"), "utf8"),
      /\| 43 \| \[Next\]\(43-next.md\) \| opened \|/,
    );
    await assert.rejects(
      tools.call("ymir_plan", {
        ...args,
        slug: "bad",
        body: "Bare prose, no contract",
      }),
      /audit refused/,
    );
    assert.equal(fs.existsSync(path.join(dir, "44-bad.md")), false);
  },
);

test("realm parent directory cannot expose every realm through grading", async (t) => {
  const { home } = setup(t);
  const tools = createTools({
    root,
    home,
    env: { ...process.env, YMIR_REALM: "one" },
  });
  await assert.rejects(
    tools.call("ymir_dellingr", { path: "svartalfaheim" }),
    /realm/,
  );
});
test("home symlink aliases cannot cross realms or expose credential targets", async (t) => {
  const { home } = setup(t);
  const tools = createTools({
    root,
    home,
    env: { ...process.env, YMIR_REALM: "one" },
  });
  const other = path.join(home, "svartalfaheim/two/workspace/demo/docs");
  fs.mkdirSync(other, { recursive: true });
  fs.writeFileSync(path.join(other, "note.md"), "private two");
  const alias = path.join(home, "hodd/docs/alias");
  try {
    fs.symlinkSync(
      other,
      alias,
      process.platform === "win32" ? "junction" : "dir",
    );
  } catch (e) {
    if (process.platform === "win32" && e.code === "EPERM") {
      t.skip(
        "Windows sandbox refuses directory links; Linux CI exercises alias guards",
      );
      return;
    }
    throw e;
  }
  await assert.rejects(
    tools.call("ymir_dellingr", { path: "hodd/docs/alias" }),
    /realm/,
  );
  await assert.rejects(
    tools.call("ymir_note", {
      path: "hodd/docs/alias/changed.md",
      heading: "bad",
      body: "bad",
    }),
    /realm/,
  );
  assert.equal(fs.existsSync(path.join(other, "changed.md")), false);
  const credentials = path.join(home, "hodd/secrets");
  fs.mkdirSync(credentials, { recursive: true });
  fs.symlinkSync(
    credentials,
    path.join(home, "hodd/docs/credentials-alias"),
    process.platform === "win32" ? "junction" : "dir",
  );
  await assert.rejects(
    tools.call("ymir_note", {
      path: "hodd/docs/credentials-alias/no.md",
      heading: "x",
      body: "y",
    }),
    /credential/,
  );
});
