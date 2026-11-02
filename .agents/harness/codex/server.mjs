#!/usr/bin/env node
// Ymir's dependency-free Codex stdio MCP adapter. Runtime logic stays in the owner doors.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import readline from "node:readline";
import { createTools, run } from "./tools.mjs";
const dir = path.dirname(fileURLToPath(import.meta.url));
export async function resolveRuntime(env = process.env) {
  let root = env.YMIR_ROOT;
  if (!root && fs.existsSync(path.join(dir, "runtime.json")))
    root = JSON.parse(
      fs.readFileSync(path.join(dir, "runtime.json"), "utf8"),
    ).root;
  if (!root) {
    let p = dir;
    while (path.dirname(p) !== p) {
      if (
        fs.existsSync(path.join(p, "RULES")) &&
        fs.existsSync(path.join(p, "bin", "vault", "hoard-lib.sh"))
      ) {
        root = p;
        break;
      }
      p = path.dirname(p);
    }
  }
  if (!root || !fs.existsSync(path.join(root, "bin", "vault", "hoard-lib.sh")))
    throw Error("YMIR_ROOT must name an installed Ymir runtime");
  let home = env.YMIR_HOME;
  if (!home)
    home = await run(
      env.YMIR_BASH || "bash",
      [
        "-c",
        '. "$1/bin/vault/hoard-lib.sh"; ymir_home_root resolved; printf "%s" "$resolved"',
        "_",
        root,
      ],
      root,
      env,
    );
  if (!home || !fs.statSync(home).isDirectory())
    throw Error("resolved YMIR_HOME is not an existing directory");
  return {
    root,
    home,
    state:
      env.BROKK_STATE_OVERRIDE ||
      env.YMIR_STATE_DIR ||
      path.join(home, "state"),
    env,
  };
}
async function main() {
  const tools = createTools(await resolveRuntime());
  const rpc = async (m) => {
    if (!m || m.jsonrpc !== "2.0" || typeof m.method !== "string")
      return {
        jsonrpc: "2.0",
        id: m?.id ?? null,
        error: { code: -32600, message: "Invalid Request" },
      };
    if (m.id === undefined) return null;
    try {
      let result;
      switch (m.method) {
        case "initialize":
          result = {
            protocolVersion: [
              "2024-11-05",
              "2025-03-26",
              "2025-06-18",
              "2025-11-25",
            ].includes(m.params?.protocolVersion)
              ? m.params.protocolVersion
              : "2025-06-18",
            capabilities: { tools: { listChanged: false } },
            serverInfo: { name: "ymir", version: "0.1.0" },
            instructions:
              "Use existing Ymir gates; private data stays in YMIR_HOME. Pi native UI is not provided.",
          };
          break;
        case "ping":
          result = {};
          break;
        case "tools/list":
          result = { tools: tools.list() };
          break;
        case "tools/call":
          try {
            result = {
              content: [
                {
                  type: "text",
                  text: await tools.call(
                    m.params?.name,
                    m.params?.arguments ?? {},
                  ),
                },
              ],
            };
          } catch (e) {
            result = {
              content: [{ type: "text", text: e.message }],
              isError: true,
            };
          }
          break;
        default:
          return {
            jsonrpc: "2.0",
            id: m.id,
            error: { code: -32601, message: "Method not found" },
          };
      }
      return { jsonrpc: "2.0", id: m.id, result };
    } catch (e) {
      return {
        jsonrpc: "2.0",
        id: m.id,
        error: { code: -32603, message: e.message },
      };
    }
  };
  // Serialize requests: home writes and lifecycle actions cannot race each other.
  let chain = Promise.resolve();
  const input = readline.createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
  });
  input.on("line", (line) => {
    chain = chain
      .then(async () => {
        if (!line.trim()) return;
        let m;
        try {
          m = JSON.parse(line);
        } catch {
          process.stdout.write(
            JSON.stringify({
              jsonrpc: "2.0",
              id: null,
              error: { code: -32700, message: "Parse error" },
            }) + "\n",
          );
          return;
        }
        const reply = await rpc(m);
        if (reply) process.stdout.write(JSON.stringify(reply) + "\n");
      })
      .catch((e) => {
        process.stderr.write(`ymir MCP: ${e.message}\n`);
        process.exitCode = 1;
      });
  });
}
if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
)
  main().catch((e) => {
    process.stderr.write(`ymir MCP startup failed: ${e.message}\n`);
    process.exitCode = 1;
  });
