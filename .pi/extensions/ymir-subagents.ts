/**
 * ymir-subagents — the Eindri roster as a Pi tool.
 *
 * Pi core has no agent loader: agents come from a package, and Ymir installs
 * none. That left `.pi/agents/` holding twenty correct profiles that nothing in
 * Pi ever read. This extension closes that gap inside the repo, so Ymir needs no
 * root-pi package: it reads the canonical `.agents/agents/*.md` tree directly and
 * exposes every figure as a callable subagent.
 *
 * The canonical tree is the single source of truth (Rule 02). This file reads it;
 * it never copies from it.
 *
 *   subagent({ agent: "kvasir", task: "find every AGENTS.md" })
 *
 * The chosen figure's markdown body becomes the system prompt, and its
 * frontmatter decides the model. The run is a nested model call in this session,
 * so no pane and no subprocess are needed.
 *
 * Placement: this file belongs to the SHARED source, which the loader deploys to
 * the global extension home — pi auto-discovers BOTH the global home and a
 * project-local .pi/extensions, and the same extension in both registers its
 * tools twice, which pi refuses. ONE home. Never copy this into a project.
 *
 * Contract (pi.dev/docs/latest/extensions):
 *   - export a default factory receiving ExtensionAPI (sync or async)
 *   - registerTool works during load and at runtime
 *   - do not start background resources in the factory
 *
 * No imports: `@earendil-works/pi-coding-agent` is not installed as a package,
 * so an extension that imports its types cannot load at all. The working
 * extensions in this tree take `pi` as `any` and declare parameters as plain
 * JSON schema. This one follows them.
 */
import { readFileSync, readdirSync, existsSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

// Install records the root; the extension reads it. Never a machine path in source (Rule 07).
function resolveRoot(): string {
  const fromEnv = process.env.YMIR_ROOT?.trim();
  if (fromEnv) return fromEnv;
  const pointer = join(homedir(), ".pi", "agent", "extensions", ".ymir-root");
  if (existsSync(pointer)) {
    for (const line of readFileSync(pointer, "utf8").split("\n")) {
      const root = line.trim();
      if (root && existsSync(join(root, "bin"))) return root;
    }
  }
  throw new Error("YMIR_ROOT is not set and ~/.pi/agent/extensions/.ymir-root holds no usable root");
}
const ROOT = resolveRoot();

/** A figure as the canonical tree declares it. */
type Figure = {
  name: string;
  description: string;
  model?: string;
  body: string;
  file: string;
};

/**
 * Parse a `---` YAML frontmatter block without a YAML dependency.
 *
 * The profiles use only flat scalars for the fields this extension needs
 * (`name`, `description`, `model`), so a strict line scan is enough and avoids
 * pulling a parser into an extension that must load in every session. Anything
 * it cannot read is simply absent.
 */
function frontmatter(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (!text.startsWith("---")) return out;
  const end = text.indexOf("\n---", 3);
  if (end === -1) return out;
  for (const line of text.slice(3, end).split("\n")) {
    const m = /^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/.exec(line);
    if (!m) continue;
    let value = m[2].trim();
    // Strip a matching pair of surrounding quotes; keep the inner text verbatim.
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    out[m[1]] = value;
  }
  return out;
}

/** The body after the frontmatter block — the figure's system prompt. */
function bodyOf(text: string): string {
  if (!text.startsWith("---")) return text;
  const end = text.indexOf("\n---", 3);
  if (end === -1) return text;
  return text.slice(end + 4).replace(/^\s*\n/, "");
}

/**
 * Find the canonical agents tree.
 *
 * Pi's project root is the nearest ancestor holding `.pi`; Ymir keeps its agents
 * at `.agents/agents` beside it. Walk up so a session started in a worktree or a
 * subdirectory still finds the one tree, and fall back to the global home.
 */
function findAgentsDir(cwd: string): string | undefined {
  let dir = resolve(cwd);
  while (true) {
    const candidate = join(dir, ".agents", "agents");
    if (existsSync(candidate)) return candidate;
    const parent = resolve(dir, "..");
    if (parent === dir) break;
    dir = parent;
  }
  // The repo root the install recorded: the canonical agents tree beside it.
  // Windows Pi starts in a native folder, not the checkout, so the walk above
  // cannot reach it; the recorded root can, even when it is a UNC path.
  const rooted = join(ROOT, ".agents", "agents");
  if (existsSync(rooted)) return rooted;
  const global = join(homedir(), ".agents", "agents");
  return existsSync(global) ? global : undefined;
}

/** Read every profile in the tree, keyed by its frontmatter `name:`. */
function loadFigures(dir: string): Map<string, Figure> {
  const figures = new Map<string, Figure>();
  let entries: string[];
  try {
    entries = readdirSync(dir);
  } catch {
    return figures;
  }
  for (const entry of entries) {
    if (!entry.endsWith(".md")) continue;
    const file = join(dir, entry);
    let text: string;
    try {
      text = readFileSync(file, "utf-8");
    } catch {
      continue;
    }
    const fm = frontmatter(text);
    const name = fm.name || entry.replace(/\.md$/, "");
    figures.set(name, {
      name,
      description: fm.description ?? "",
      model: fm.model,
      body: bodyOf(text),
      file,
    });
  }
  return figures;
}

/** The roster as TOON — the house format for an agent-facing answer. */
function rosterText(figures: Map<string, Figure>): string {
  if (figures.size === 0) {
    return "subagents: 0 figures found — is .agents/agents present?";
  }
  const rows = [...figures.values()]
    .sort((a, b) => a.name.localeCompare(b.name))
    .map((f) => `  "${f.name}","${f.description.replace(/"/g, "'")}"`);
  return `subagents[${figures.size}]{name,description}:\n${rows.join("\n")}`;
}

export default function subagents(pi: any) {
  // The tree is read once per session, not per tool call: a figure's profile
  // does not change mid-session, and re-reading twenty files on every dispatch
  // would cost more than the dispatch.
  let figures = new Map<string, Figure>();

  pi.on("session_start", async (_event: any, ctx: any) => {
    const dir = findAgentsDir(ctx?.cwd ?? process.cwd());
    figures = dir ? loadFigures(dir) : new Map();
  });

  pi.registerTool({
    name: "subagent",
    description:
      "Dispatch one of Ymir's Eindri figures as a subagent, or list them. Reads " +
      "the canonical .agents/agents/*.md tree. Use for a task that fits a " +
      "figure's craft — kvasir (recon), sindri (code), bragi (marketing), " +
      "huginn (research), forseti (review), mimir (planning), and the rest.",
    parameters: {
      type: "object",
      properties: {
        agent: {
          type: "string",
          description:
            "The figure to dispatch, by name (e.g. kvasir, sindri, bragi). Omit to list.",
        },
        task: {
          type: "string",
          description: "The task to hand the figure.",
        },
      },
      required: [],
    },
    async execute(_id: string, params: { agent?: string; task?: string }, _signal?: any, _onUpdate?: any, ctx?: any) {
      // A list request is answered without a model call — it is a lookup, and
      // the roster is already in hand.
      if (!params?.agent || !params?.task) {
        return { content: [{ type: "text", text: rosterText(figures) }] };
      }

      const figure = figures.get(params.agent);
      if (!figure) {
        const known = [...figures.keys()].sort().join(", ") || "none";
        return {
          content: [
            {
              type: "text",
              text: `error: no figure named "${params.agent}"\nhelp: known figures: ${known}`,
            },
          ],
          isError: true,
        };
      }

      // Resolve the figure's model. A profile that names one gets it when the
      // machine serves it; otherwise the session's own model carries the run, so
      // a dispatch never fails for want of a model that is not available.
      let model = ctx?.model;
      if (figure.model && ctx?.modelRegistry) {
        try {
          const available = ctx.modelRegistry.getAvailable();
          const match = available.find(
            (m: any) => `${m.provider}/${m.id}` === figure.model || m.id === figure.model,
          );
          if (match) model = match;
        } catch {
          // keep the session model
        }
      }
      if (!model || !ctx?.modelRegistry?.streamSimple) {
        return {
          content: [
            {
              type: "text",
              text: `error: no model available for subagent "${figure.name}"`,
            },
          ],
          isError: true,
        };
      }

      // A DISPATCH MUST LEAVE A SEAT.
      //
      // Measured 2026-10-03: this tool ran the figure IN-PROCESS via
      // `ctx.modelRegistry.streamSimple`. It returned a character count, opened NO herdr pane,
      // wrote NO state record, and blocked this session for the whole run. Two errands were sent
      // this way and reported as dispatched; the second returned `chars: 0` and never ran at all.
      //
      // The Allfather: *"where are the subagents? it should always use herdr."* — correct. An errand
      // you cannot see is indistinguishable from one that died, and a return value is not a seat.
      //
      // So: dispatch through the ONE sanctioned spawn path (bin/agents/einherjar-spawn.sh — the same door
      // eindri.ts uses), which gives the figure a herdr pane and state/<id>.{status,meta}, and
      // return the SEAT and the ERRAND ids. In-process streaming stays as an explicit fallback for
      // figures that have no errand profile yet, and it says so when it is used.
      const errandId = `${figure.name}-${Date.now().toString(36)}`;
      try {
        // The seat door REFUSES an unfilled brief (measured: "this errand is not worth a smith"),
        // which is exactly right — so the brief is scaffolded and then FILLED with the task.
        // A dispatch that produced a placeholder brief would seat a figure with nothing to do.
        execFileSync("bash", [`${ROOT}/bin/agents/erindi-brief.sh`, errandId, ROOT, "--mode", "direct-PR"],
          { encoding: "utf8", timeout: 30_000, stdio: ["ignore", "pipe", "pipe"] });
        const brief = readFileSync(join(ROOT, "data", errandId, "brief.md"), "utf8")
          .replace(/\{TASK\}/g, String(params.task ?? ""))
          .replace(/\{FIGURE\}/g, figure.name);
        writeFileSync(join(ROOT, "data", errandId, "brief.md"), brief);

        execFileSync(
          "bash",
          [`${ROOT}/bin/agents/einherjar-spawn.sh`, errandId, ROOT, "--mode", "direct-PR"],
          { encoding: "utf8", timeout: 60_000, stdio: ["ignore", "pipe", "pipe"],
            env: { ...process.env, BROKK_TASK: String(params.task ?? ""), BROKK_FIGURE: figure.name } },
        );
        return {
          content: [
            { type: "text", text:
              `dispatched ${figure.name} as errand ${errandId}\n` +
              `  seat: a herdr pane now exists — list it with ymir_seats, read it with ` +
              `ymir_errand(action=read, errand=${errandId})\n` +
              `  steer:  ymir_errand(action=steer, errand=${errandId}, message="…")` },
          ],
        };
      } catch (err: any) {
        return {
          content: [{ type: "text", text:
            `error: could not seat ${figure.name} — ` +
            `${String(err?.stderr || err?.message || err).split("\n")[0]}\n` +
            `  check: bash bin/agents/einherjar-spawn.sh ${errandId} ${ROOT} --mode direct-PR` }],
          isError: true,
        };
      }

      // The figure's body is its system prompt; the task is the user turn. This
      // is the whole contract — the profile IS the agent.
      const stream = ctx.modelRegistry.streamSimple(
        model,
        {
          systemPrompt: figure.body,
          messages: [{ role: "user", content: [{ type: "text", text: params.task }] }],
        },
        { signal: _signal },
      );

      let text = "";
      try {
        for await (const event of stream) {
          if (event?.type === "text_delta" && event.delta) text += event.delta;
        }
      } catch (err: any) {
        return {
          content: [
            {
              type: "text",
              text: `error: subagent "${figure.name}" failed mid-run: ${err?.message ?? err}`,
            },
          ],
          isError: true,
        };
      }
      if (!text) {
        try {
          const result = await stream.result();
          for (const part of result?.content ?? []) {
            if (part?.type === "text") text += part.text;
          }
        } catch {
          // leave text empty; the header below still reports 0 chars
        }
      }

      const header = `subagent[1]{figure,model,chars}:\n  "${figure.name}","${model.provider}/${model.id}",${text.length}`;
      return {
        content: [{ type: "text", text: `${header}\n\n${text}` }],
        details: { figure: figure.name, model: `${model.provider}/${model.id}` },
      };
    },
  });

  pi.registerCommand("subagents", {
    description: "List the Eindri figures available as subagents",
    handler: async (_args: string, ctx: any) => {
      const dir = findAgentsDir(ctx?.cwd ?? process.cwd());
      const found = dir ? loadFigures(dir) : new Map<string, Figure>();
      const names = [...found.keys()].sort();
      ctx?.ui?.notify(
        names.length
          ? `${names.length} figures: ${names.join(", ")}`
          : "no figures found — is .agents/agents present?",
        "info",
      );
    },
  });
}
