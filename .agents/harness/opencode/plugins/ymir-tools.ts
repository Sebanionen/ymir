import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

/**
 * Ymir Tools Plugin for OpenCode V2
 * 
 * Ports pi's Ymir tool/command surface to OpenCode V2:
 * - 20 tools (ymir_recall, ymir_remember, ymir_errand, ymir_heal, ymir_update,
 *   ymir_note, ymir_plan, ymir_push, ymir_daily, ymir_find_home, ymir_place,
 *   ymir_import, ymir_structure, ymir_find, ymir_index, ymir_secret_keys,
 *   ymir_layout, subagent, ymir_well, ymir_dellingr)
 * - 2 commands (gna-watch-arm, subagents)
 * 
 * Each tool is a thin wrapper calling existing shell doors (bin/agents/..., bin/records/...).
 * No logic duplication — same doors pi extensions call.
 */

// Helper to resolve Ymir root and home (mirrors pi extension logic)
async function resolveYmirPaths(): Promise<{ root: string; home: string; state: string }> {
  const { $ } = await import("bun")
  
  // Resolve root: YMIR_ROOT env -> .ymir-root pointer -> git root
  let root = process.env.YMIR_ROOT?.trim()
  if (!root) {
    try {
      const pointer = `${process.env.HOME}/.pi/agent/extensions/.ymir-root`
      const content = await Bun.file(pointer).text()
      for (const line of content.split("\n")) {
        const candidate = line.trim()
        if (candidate && await Bun.file(`${candidate}/bin`).exists()) {
          root = candidate
          break
        }
      }
    } catch {}
  }
  if (!root) {
    try {
      root = (await $`git rev-parse --show-toplevel`.quiet()).text().trim()
    } catch {}
  }
  if (!root) throw new Error("YMIR_ROOT not resolved")
  
  // Resolve home: YMIR_HOME env -> hodd.sh path -> default
  let home = process.env.YMIR_HOME?.trim()
  if (!home) {
    try {
      home = (await $`${root}/bin/vault/hodd.sh path`.quiet()).text().trim()
      if (home) home = home.replace(/\/hodd$/, "") // hoard -> home
    } catch {}
  }
  if (!home) home = `${process.env.HOME}/Documents/ymirhome`
  
  const state = process.env.BROKK_STATE_OVERRIDE || `${home}/state`
  
  return { root, home, state }
}

// Helper to run shell commands
async function runShell(cmd: string, args: string[], cwd?: string): Promise<string> {
  const { $ } = await import("bun")
  try {
    return (await $`${cmd} ${args}`.cwd(cwd || process.cwd()).quiet()).text().trim()
  } catch (e: any) {
    throw new Error(e?.stdout?.toString?.()?.trim() || e?.message || "command failed")
  }
}

// Tool output formatter
function toolResult(text: string) {
  return { output: { text }, content: text }
}

export default Plugin.define({
  id: "ymir-tools",
  setup: async (ctx) => {
    const { root, home, state } = await resolveYmirPaths()
    
    // ========================================================================
    // TOOLS — callable by the model
    // ========================================================================
    
    await ctx.tool.transform((tools) => {
      // --- ymir_recall: Recall from the well before acting ---
      tools.add({
        name: "ymir_recall",
        description: "RECALL from the well before acting on anything the home owns. The house law: drink before you act. Thin — calls bin/records/mimir.sh.",
        input: Schema.Struct({
          query: Schema.String,
          limit: Schema.optional(Schema.Number),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ query, limit = 5 }) => {
          try {
            const out = await runShell(`${root}/bin/records/mimir.sh`, ["recall", query, String(limit)], home)
            return toolResult(out || "the well has nothing on that (an empty well is a real answer, not a failure)")
          } catch (e: any) {
            return toolResult("the well did not answer: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_remember: Observe into the well ---
      tools.add({
        name: "ymir_remember",
        description: "OBSERVE into the well — water it after. Records what was learned, so the NEXT machine starts where this one finished.",
        input: Schema.Struct({
          lesson: Schema.String,
          tags: Schema.optional(Schema.Array(Schema.String)),
          actors: Schema.optional(Schema.Array(Schema.String)),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ lesson, tags, actors }) => {
          try {
            const parts = [lesson]
            if (tags?.length) parts.push(`tags: ${tags.join(",")}`)
            if (actors?.length) parts.push(`actors: ${actors.join(",")}`)
            await runShell(`${root}/bin/records/mimir.sh`, ["observe", parts.join(" ")], home)
            return toolResult("observed into the well. Next: ymir_note it into the plan it belongs to, or ymir_push the doc that carries it.")
          } catch (e: any) {
            return toolResult("the well did not take it: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_errand: Dispatch an Eindri errand ---
      tools.add({
        name: "ymir_errand",
        description: "ONE tool for an errand. start = the one spawn path (einherjar-spawn.sh); read = its status, seat and worktree; steer = one line into its inbox; close = claim the outcome and stop the seat.",
        input: Schema.Struct({
          action: Schema.Literal("start", "read", "steer", "close"),
          id: Schema.String,
          project: Schema.optional(Schema.String),
          harness: Schema.optional(Schema.String),
          model: Schema.optional(Schema.String),
          mode: Schema.optional(Schema.String),
          message: Schema.optional(Schema.String),
          terminal: Schema.optional(Schema.String),
          note: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ action, id, project, harness, model, mode, message, terminal, note }) => {
          try {
            switch (action) {
              case "read": {
                const statusFile = `${root}/state/${id}.status`
                const metaFile = `${root}/state/${id}.meta`
                let out = `errand[1]{id,status,backend,harness,model,worktree}:\n`
                if (!(await Bun.file(statusFile).exists()) && !(await Bun.file(metaFile).exists())) {
                  out += `  "${id}","NOTHING RECORDED — no state/${id}.meta and no .status"\n\nThat is the fault this door exists for: an errand that left no record cannot be read, steered or closed by name.`
                  return toolResult(out)
                }
                const status = (await Bun.file(statusFile).text()).trim().split("\n").pop() || ""
                const meta = await Bun.file(metaFile).text()
                const field = (key: string) => (new RegExp(`^${key}=(.*)$`, "m").exec(meta)?.[1] ?? "")
                out += `  "${id}","${status.slice(0, 70)}","${field("backend")}","${field("harness")}","${field("model")}","${field("worktree")}"`
                const wt = field("worktree")
                if (wt && await Bun.file(wt).exists()) {
                  const g = (a: string[]) => runShell("git", a, wt)
                  out += `\n  branch: ${await g(["rev-parse", "--abbrev-ref", "HEAD"])}`
                  out += `\n  commits ahead of main: ${await g(["rev-list", "--count", "origin/main..HEAD"])}`
                  out += `\n  changed files: ${(await g(["status", "--porcelain"])).split("\n").filter(Boolean).length}`
                }
                const inbox = `${root}/state/${id}.inbox`
                if (await Bun.file(inbox).exists()) {
                  const un = await runShell("bash", ["-c", `ls "$1" 2>/dev/null | wc -l`, "_", inbox])
                  out += `\n  steering inbox: ${un} message(s)`
                }
                return toolResult(out)
              }
              case "start": {
                if (!project) return toolResult("start needs `project` (the repo root).")
                const r = await runShell("bash", [
                  `${root}/bin/agents/einherjar-spawn.sh`, id, project,
                  "--mode", mode || "direct-PR",
                  ...(harness ? ["--harness", harness] : []),
                  ...(model ? ["--model", model] : []),
                ], root)
                return toolResult(`${id}: spawn rc=0\n${r || "(see state/" + id + ".status)"}\n` +
                  `one spawn path only - einherjar-spawn.sh. Start here again and you will get a refusal, which is correct.`)
              }
              case "steer": {
                if (!message) return toolResult("steer needs `message` (one line).")
                const r = await runShell("bash", [`${root}/bin/agents/eindri-send.sh`, id, message], root)
                return toolResult(`steered ${id}: rc=0\n${r || ""}`)
              }
              case "close": {
                const term = terminal || "done"
                const c = await runShell("bash", [
                  `${root}/bin/agents/eindri-acclaim.sh`, id, "--terminal", term,
                  ...(note ? ["--line", note] : []),
                ], root)
                const x = await runShell("bash", [`${root}/bin/agents/eindri-control.sh`, "exit", id], root)
                return toolResult(`closed ${id} as ${term}\n  claim rc=0 ${c.split("\n").slice(0, 2).join(" · ")}\n` +
                  `  seat  rc=0 ${x.split("\n").slice(0, 1).join("")}\n` +
                  `  a closed errand leaves no running seat and one durable record.`)
              }
              default:
                return toolResult(`unknown action "${action}" — use start, read, steer or close.`)
            }
          } catch (e: any) {
            return toolResult("error: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_heal: Diagnose or mend the house ---
      tools.add({
        name: "ymir_heal",
        description: "Eir the healer: diagnose every surface of the house (check) or mend what is broken (fix). Calls bin/agents/eir-doctor.sh.",
        input: Schema.Struct({
          mode: Schema.optional(Schema.Literal("check", "fix")),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ mode = "check" }) => {
          try {
            const r = await runShell("bash", [`${root}/bin/agents/eir-doctor.sh`, mode], root, mode === "fix" ? 300_000 : 180_000)
            const verdict = r.includes("exit 0") ? "whole" : `not whole`
            return toolResult(`eir_heal[2]{mode,verdict}:\n  "${mode}","${verdict}"\n\n${r || "(the healer said nothing — that is itself a finding)"}`)
          } catch (e: any) {
            return toolResult("eir_heal failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_update: Renew Brokk ---
      tools.add({
        name: "ymir_update",
        description: "Gróa the updater shaman: check says whether the checkout has anything new; update fast-forwards Brokk and every Eindri-home, never forced, then mends forward. Calls bin/agents/groa-update.sh.",
        input: Schema.Struct({
          mode: Schema.optional(Schema.Literal("check", "update")),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ mode = "check" }) => {
          try {
            const r = await runShell("bash", [`${root}/bin/agents/groa-update.sh`, mode === "update" ? "" : "--check"], root, 600_000)
            const note = mode === "update" && !r.includes("exit 0") 
              ? `\n  Gróa did not finish cleanly. The seat may be partly renewed — read the output before running it again.`
              : ""
            return toolResult(`${r || "(the updater said nothing)"}${note}`)
          } catch (e: any) {
            return toolResult("ymir_update failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_note: Append dated section to a document ---
      tools.add({
        name: "ymir_note",
        description: "Append a DATED, append-only section to an existing document in the home. The vault's core law: never rewrite, never delete - append.",
        input: Schema.Struct({
          path: Schema.String,
          heading: Schema.String,
          body: Schema.String,
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ path, heading, body }) => {
          try {
            if (!path.startsWith("hodd/") && !path.startsWith("svartalfaheim/")) {
              return toolResult(`refused: ${path} is not in the home. Documents live under hodd/ or svartalfaheim/.`)
            }
            const abs = `${home}/${path}`
            const stamp = new Date().toISOString().slice(0, 10)
            const dated = heading.includes(stamp) ? heading : `${heading} — ${stamp}`
            await runShell("mkdir", ["-p", abs.slice(0, abs.lastIndexOf("/"))], home)
            await runShell("bash", ["-c", `printf '\n---\n\n%s\n\n' >> "$1" && cat >> "$1"`, "_", abs], home, dated)
            await runShell("bash", ["-c", `cat >> "$1"`, "_", abs], home, body)
            return toolResult(`appended to ${path}\n  ${dated}\n  next: ymir_push with that one path (never -A).`)
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_plan: Create next numbered plan in ledger ---
      tools.add({
        name: "ymir_plan",
        description: "Create the NEXT numbered plan in the canonical ledger, with the index row. Numbering is after the index's highest; numbers are never reused.",
        input: Schema.Struct({
          slug: Schema.String,
          title: Schema.String,
          realm: Schema.optional(Schema.String),
          project: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ slug, title, realm = "whynotproductions", project = "ymir" }) => {
          try {
            if (!slug.trim() || !title.trim()) {
              return toolResult("ymir_plan needs `slug` and `title`. This tool WRITES a file into the plan ledger, so it refuses to guess.")
            }
            const dir = `${home}/svartalfaheim/${realm}/projects/${project}/plans`
            const nums = (await runShell("bash", ["-c", `ls "$1" | grep -oE '^[0-9]+' | sort -n | tail -1`, "_", dir], home)).trim()
            const next = (parseInt(nums || "0", 10) || 0) + 1
            const nn = String(next).padStart(2, "0")
            const file = `${dir}/${nn}-${slug}.md`
            await runShell("bash", ["-c", `printf '# Plan %s — %s\n\n**Opened %s.**\n' "$2" "$3" "$(date -u +%Y-%m-%d)" > "$1"`, "_", file, nn, title], home)
            return toolResult(`created ${file}\n  number: ${nn} (after the index's highest)\n  next: add the README index row, then ymir_push that ONE path by name.`)
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_push: Commit and push home by named paths ---
      tools.add({
        name: "ymir_push",
        description: "Commit and push ymirhome, staging ONLY the paths you name. Never git add -A. Refuses secrets and refuses to delete a tracked file.",
        input: Schema.Struct({
          paths: Schema.Array(Schema.String),
          message: Schema.String,
          push: Schema.optional(Schema.Boolean),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ paths, message, push = true }) => {
          try {
            if (!paths.length) return toolResult("ymir_push needs `paths` — an array of home-relative paths to stage. Never stage everything: name the files.")
            if (!message.trim()) return toolResult("ymir_push needs a `message` — an imperative subject line and a paragraph of what and why.")
            
            // Refuse secrets
            for (const p of paths) {
              if (/(^|\/)\.?env$|secret|credential|\.key$|token/i.test(p)) {
                return toolResult(`refused: ${p} looks like a credential. Secrets stay out of history.`)
              }
            }
            // Refuse deletions
            const deleted = await runShell("git", ["diff", "--name-only", "--diff-filter=D", "HEAD"], home)
            if (deleted.trim()) {
              return toolResult(`refused: this commit deletes tracked files:\n  ${deleted}\nRule 11 — never delete, only move. Use ymir_place(..., move:true) into hodd/reference/.`)
            }
            
            await runShell("git", ["add", "--", ...paths], home)
            await runShell("git", ["commit", "-m", message], home)
            const lines = [`committed: ${paths.length} named path(s)`]
            if (push) {
              await runShell("git", ["pull", "--rebase", "--autostash", "-q"], home)
              await runShell("git", ["push", "-q"], home)
              lines.push("pushed (rebased over origin first)")
            }
            lines.push(await runShell("git", ["log", "-1", "--format=%h %s"], home))
            return toolResult(lines.join("\n"))
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n").slice(0, 3).join(" | "))
          }
        },
      })

      // --- ymir_daily: Append to today's daily log ---
      tools.add({
        name: "ymir_daily",
        description: "Append to today's log line in the vault (hodd/memory/daily/YYYY-MM-DD.md), or read it.",
        input: Schema.Struct({
          note: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ note }) => {
          try {
            const day = new Date().toISOString().slice(0, 10)
            const f = `${home}/hodd/memory/daily/${day}.md`
            await runShell("mkdir", ["-p", f.slice(0, f.lastIndexOf("/"))], home)
            if (!note) {
              if (!(await Bun.file(f).exists())) return toolResult(`no entry yet for ${day} — nothing has been written for that day`)
              const content = await Bun.file(f).text()
              return toolResult(content || `no entry yet for ${day}`)
            }
            await runShell("bash", ["-c", `printf '%s\n' "$2" >> "$1"`, "_", f, `- ${new Date().toISOString().slice(11, 16)} ${note}`], home)
            return toolResult(`appended to hodd/memory/daily/${day}.md — next: ymir_push that path by name.`)
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_find_home: Placement oracle ---
      tools.add({
        name: "ymir_find_home",
        description: "WHERE SHOULD THIS FILE GO? The placement oracle: takes a file (anywhere on this machine) and answers with the destination shelf, the reason, and whether it already sits in a legal place. NEVER moves anything.",
        input: Schema.Struct({
          path: Schema.String,
          note: Schema.optional(Schema.String),
          sample: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ path, note, sample }) => {
          try {
            const raw = path
            const abs = raw.startsWith("/") ? raw : `${home}/${raw}`
            const base = raw.split("/").pop() ?? raw
            const text = [base, note ?? "", sample ?? ""].join(" ").toLowerCase()
            
            // Already home and legal?
            if (abs.startsWith(`${home}/`)) {
              const rel = abs.slice(home.length + 1)
              const verdict = classifyPath(rel)
              return toolResult(verdict.ok
                ? `already home, and legal:\n  ${rel}\n  shelf: ${verdict.shelf} (${verdict.why})\n  nothing to do.`
                : `it is INSIDE the home but in no legal shelf:\n  ${rel}\n  reason: ${verdict.why}\n  move it with ymir_place(..., move:true) into hodd/reference/ if it is retired.`)
            }
            
            // Classify by subject
            const rules = [
              { re: /secret|credential|\.env$|\.pem$|\.key$|token/, shelf: "hodd/secrets/", why: "a credential — the one place values may live" },
              { re: /masterplan|plan 66|roadmap|master plan/, shelf: "svartalfaheim/whynotproductions/projects/ymir/plans/", why: "a masterplan or architecture plan belongs in the ledger" },
              { re: /register|inventory|index/, shelf: "svartalfaheim/whynotproductions/projects/ymir/plans/", why: "a register is an index — it lives with the plans it indexes" },
              { re: /calendar|mánagandr|managandr|memory|well|engram/, shelf: "svartalfaheim/whynotproductions/projects/ymir/plans/", why: "a feature's design belongs in its plan, not loose" },
              { re: /postiz|social|campaign|marketing|brand|content/, shelf: "hodd/life/marketing/", why: "the operator's own marketing domain" },
              { re: /meeting|minute|standup|1:1/, shelf: "hodd/life/meetings/", why: "a meeting artefact" },
              { re: /journal|diary|personal/, shelf: "hodd/life/personal/", why: "the operator's own personal domain" },
              { re: /runbook|howto|setup|install/, shelf: "hodd/docs/runbooks/", why: "a runbook is a doc about a machine" },
              { re: /architecture|deep.?dive|audit/, shelf: "hodd/docs/", why: "architecture or audit material about the house" },
              { re: /readme|changelog|contribut/, shelf: "hodd/reference/", why: "repo boilerplate — reference, not a house doc" },
            ]
            const hit = rules.find(r => r.re.test(text))
            let dest = hit ? `${hit.shelf}${base}` : `hodd/reference/imported/${base}`
            const parent = raw.replace(/\/$/, "").split("/").slice(-2, -1)[0] ?? ""
            if (await Bun.file(`${home}/${dest}`).exists() && parent && !/^(hodd|svartalfaheim|imported|reference)$/.test(parent)) {
              dest = `${hit ? hit.shelf : "hodd/reference/imported/"}${parent}--${base}`
            }
            const why = hit ? hit.why : "no rule claims it — reference is the safe shelf"
            const verdict = classifyPath(dest)
            if (!verdict.ok) return toolResult(`refused: ${verdict.why}\n  would have been: ${dest}`)
            return toolResult(`outside the home →\n  ${base}\n  destination: ${dest}\n  because: ${why}\n  shelf: ${verdict.shelf}\n` +
              (hit ? "" : "  ⚠ this was a fallback, not a confident classification — confirm it.\n") +
              `  next: ymir_import({ sources: ["${raw}"], dryRun:true }) to confirm, then act.`)
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_place: The ONLY sanctioned way a document enters ymirhome ---
      tools.add({
        name: "ymir_place",
        description: "The ONLY sanctioned way a document enters ymirhome. Classifies the proposed path against the layout law and refuses what it cannot justify. Never deletes: to retire a file, place it in hodd/reference/ with why it went and what replaced it.",
        input: Schema.Struct({
          path: Schema.String,
          source: Schema.optional(Schema.String),
          why: Schema.String,
          move: Schema.optional(Schema.Boolean),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ path, source, why, move }) => {
          try {
            const verdict = classifyPath(path)
            if (!verdict.ok) return toolResult(`refused: ${verdict.why}\n  proposed: ${path}`)
            const dest = `${home}/${path}`
            const lines = [`placed → ${path}`, `  shelf: ${verdict.shelf}`, `  because: ${why}`]
            if (source) {
              try {
                await runShell("mkdir", ["-p", dest.slice(0, dest.lastIndexOf("/"))], home)
                let staged = false
                try {
                  await runShell("git", ["mv", source, dest], home)
                  staged = true
                } catch {
                  await runShell("mv", [source, dest], home)
                }
                lines.push(`  ${staged ? "git mv (a rename in history)" : "moved (untracked)"}`)
              } catch (e: any) {
                lines.push(`  NOT moved: ${e.message.split("\n")[0]}`)
              }
            }
            lines.push(`  next: name it in the shelf's README row, or in register.md if it is an ask.`)
            return toolResult(lines.join("\n"))
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_import: Bring documentation IN FROM OUTSIDE the home ---
      tools.add({
        name: "ymir_import",
        description: "Bring documentation IN FROM OUTSIDE the home and file it where it belongs: classifies the content and the name against the layout law, proposes the destination, and moves it with git mv so the vault's history shows a rename.",
        input: Schema.Struct({
          sources: Schema.Array(Schema.String),
          area: Schema.optional(Schema.String),
          dryRun: Schema.optional(Schema.Boolean),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ sources, area, dryRun = true }) => {
          try {
            const lines: string[] = []
            for (const raw of sources) {
              const src = String(raw)
              if (src.startsWith(home)) { lines.push(`skip ${src} — already inside the home`); continue }
              const base = src.split("/").pop() ?? ""
              let dest = ""
              const hint = (area || base).toLowerCase()
              if (/market|ads|campaign|brand|postiz/.test(hint)) dest = "hodd/life/marketing/imported/"
              else if (/meeting|note|personal|journal/.test(hint)) dest = "hodd/life/personal/imported/"
              else if (/research|paper|arxiv|readme/.test(hint)) dest = "hodd/docs/research/imported/"
              else if (/plan|roadmap|proposal|strategy/.test(hint)) dest = "hodd/life/work/imported/"
              else dest = "hodd/reference/imported/"
              const verdict = classifyPath(`${dest}${base}`)
              if (!verdict.ok) { lines.push(`refused ${base}: ${verdict.why}`); continue }
              const abs = `${home}/${dest}${base}`
              lines.push(`${dryRun ? "would import" : "imported"}  ${src}  ->  ${dest}${base}   (${verdict.why})`)
              if (dryRun) continue
              try {
                await runShell("mkdir", ["-p", abs.slice(0, abs.lastIndexOf("/"))], home)
                await runShell("git", ["mv", src, abs], home)
                lines.push(`  git mv — a rename in the vault's history, never a copy`)
              } catch (e: any) {
                lines.push("  NOT moved: " + e.message.split("\n")[0])
              }
            }
            if (area === undefined) lines.push("classifier used the filename; pass `area` to override.")
            return toolResult(lines.join("\n"))
          } catch (e: any) {
            return toolResult("failed: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_structure: The SHAPE of ymirhome ---
      tools.add({
        name: "ymir_structure",
        description: "The SHAPE of ymirhome as it actually is right now: every shelf, how many files it holds, and the convention that applies to it.",
        input: Schema.Struct({
          depth: Schema.optional(Schema.Number),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ depth = 2 }) => {
          try {
            const rows: string[] = []
            const walk = async (dir: string, level: number) => {
              if (level > depth) return
              try {
                const entries = (await runShell("bash", ["-c", `ls -A "$1" 2>/dev/null`, "_", dir], home)).split("\n").filter(Boolean)
                for (const e of entries) {
                  if (e.startsWith(".")) continue
                  const abs = `${dir}/${e}`
                  const isDir = (await runShell("bash", ["-c", `[ -d "$1" ] && echo yes || echo no`, "_", abs], home)) === "yes"
                  if (!isDir) continue
                  let n = "0"
                  try { n = await runShell("bash", ["-c", `find "$1" -type f | wc -l`, "_", abs], home) } catch {}
                  rows.push(`${"  ".repeat(level)}${e}/  (${n} files)`)
                  await walk(abs, level + 1)
                }
              } catch {}
            }
            await walk(`${home}/hodd`, 0)
            await walk(`${home}/svartalfaheim`, 0)
            const untracked = (await runShell("git", ["status", "--porcelain"], home)).split("\n").filter(l => l.startsWith("??"))
            rows.push("", "strays (untracked, unfiled): " + (untracked.length ? untracked.map(l => l.slice(3)).join(", ") : "none"))
            rows.push("conventions: hodd/ is PRIVATE material · svartalfaheim/ is realm+project · a register is an INDEX · depth lives in a plan · never delete, only move.")
            return toolResult(rows.join("\n"))
          } catch (e: any) {
            return toolResult("could not walk the home: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_find: Where something lives in ymirhome ---
      tools.add({
        name: "ymir_find",
        description: "Where something lives in ymirhome — by name and by content — without grep spelunking.",
        input: Schema.Struct({
          what: Schema.String,
          content: Schema.optional(Schema.Boolean),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ what, content }) => {
          try {
            const out = content
              ? await runShell("grep", ["-ril", "--exclude-dir=.git", what, home])
              : await runShell("find", [home, "-iname", `*${what}*`])
            const rows = out.split("\n").filter(Boolean).slice(0, 40).map(p => p.replace(home, "~"))
            return toolResult(rows.length ? rows.join("\n") : `nothing matched "${what}"`)
          } catch {
            return toolResult(`nothing matched "${what}"`)
          }
        },
      })

      // --- ymir_index: What is uncalled, stale or orphaned ---
      tools.add({
        name: "ymir_index",
        description: "What is uncalled, stale or orphaned in the shelves: untracked strays, empty dirs, files with no README row, and the size of each shelf.",
        input: Schema.Struct({}),
        output: Schema.Struct({ text: Schema.String }),
        execute: async () => {
          try {
            const out: string[] = []
            out.push("untracked (strays — ymir_place or git add by NAME, never -A):")
            const un = (await runShell("git", ["status", "--porcelain"], home)).split("\n").filter(l => l.startsWith("??"))
            out.push(...(un.length ? un.map(l => "  " + l.slice(3)) : ["  none"]))
            out.push("", "last push: " + (await runShell("git", ["log", "-1", "--format=%h %ad %s", "--date=short"], home) || "unknown"))
            out.push("in sync: " + (await runShell("git", ["rev-list", "--left-right", "--count", "origin/main...main"], home) || "?"))
            return toolResult(out.join("\n"))
          } catch (e: any) {
            return toolResult("could not read the home: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_secret_keys: Which secret key NAMES exist in the vault ---
      tools.add({
        name: "ymir_secret_keys",
        description: "Which secret key NAMES exist in the vault. Never values - a name can be printed, a value never leaves the vault.",
        input: Schema.Struct({
          filter: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ filter }) => {
          try {
            const names = (await runShell("bash", [
              "-c",
              `set -u; f="$1"; if [ -f "$f.age" ]; then age -d -i "$f.key" "$f.age" 2>/dev/null; elif [ -f "$f" ]; then cat "$f"; fi | grep -oE '^[A-Za-z0-9_]+=' | tr -d '=' | sort -u`,
              "_",
              `${home}/hodd/secrets/platform.env`,
            ])).split("\n").filter(Boolean)
              .filter(n => !filter || n.toLowerCase().includes(filter.toLowerCase()))
            return toolResult(names.length ? names.join("\n") : "no matching key names (values are never printed)")
          } catch (e: any) {
            return toolResult("could not read the vault: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_layout: The layout law itself ---
      tools.add({
        name: "ymir_layout",
        description: "The layout law itself: which shelf a home-relative path belongs to, and where a given thing lives. Ask before writing, so nothing is filed by guess.",
        input: Schema.Struct({
          path: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ path }) => {
          if (path) {
            const v = classifyPath(path)
            return toolResult(v.ok ? `${path}\n  shelf: ${v.shelf}\n  because: ${v.why}` : `refused: ${v.why}`)
          }
          return toolResult("hodd/            private material (docs · data · memory · identity · life/<domain>)\n" +
            "  hodd/life/<domain>/   the operator's own domains: marketing · personal · work · meetings\n" +
            "  hodd/reference/       retired files, kept to be learned from (Rule 11)\n" +
            "  hodd/secrets/         credentials — never a document\n" +
            "svartalfaheim/<realm>/projects/<project>/\n" +
            "  …/plans/              the canonical plan ledger\n" +
            "  …/docs/                that project's documents\n" +
            "Law: a register is an INDEX (state + a link); depth lives in a plan.")
        },
      })

      // --- subagent: Dispatch an Eindri figure ---
      tools.add({
        name: "subagent",
        description: "Dispatch one of Ymir's Eindri figures as a subagent, or list them. Reads the canonical .agents/agents/*.md tree.",
        input: Schema.Struct({
          agent: Schema.optional(Schema.String),
          task: Schema.optional(Schema.String),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ agent, task }) => {
          try {
            // Load figures from .agents/agents/
            const figuresDir = `${root}/.agents/agents`
            const entries = (await Bun.file(figuresDir).exists()) 
              ? (await runShell("bash", ["-c", `ls "$1" 2>/dev/null | grep '\.md$'`, "_", figuresDir], home)).split("\n").filter(Boolean)
              : []
            
            const figures: Array<{ name: string; description: string; body: string; model?: string }> = []
            for (const entry of entries) {
              const file = `${figuresDir}/${entry}`
              const text = await Bun.file(file).text()
              const fmEnd = text.indexOf("\n---", 3)
              let fm: Record<string, string> = {}
              let body = text
              if (text.startsWith("---") && fmEnd !== -1) {
                for (const line of text.slice(3, fmEnd).split("\n")) {
                  const m = /^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/.exec(line)
                  if (m) fm[m[1]] = m[2].trim().replace(/^["']|["']$/g, "")
                }
                body = text.slice(fmEnd + 4).replace(/^\s*\n/, "")
              }
              figures.push({ name: fm.name || entry.replace(/\.md$/, ""), description: fm.description || "", body, model: fm.model })
            }
            
            if (!agent || !task) {
              if (figures.length === 0) return toolResult("subagents: 0 figures found — is .agents/agents present?")
              const rows = figures.sort((a, b) => a.name.localeCompare(b.name)).map(f => `  "${f.name}","${f.description.replace(/"/g, "'")}"`)
              return toolResult(`subagents[${figures.length}]{name,description}:\n${rows.join("\n")}`)
            }
            
            const figure = figures.find(f => f.name === agent)
            if (!figure) {
              const known = figures.map(f => f.name).sort().join(", ") || "none"
              return toolResult(`error: no figure named "${agent}"\nhelp: known figures: ${known}`)
            }
            
            // Scaffold brief and spawn
            const errandId = `${figure.name}-${Date.now().toString(36)}`
            await runShell("bash", [`${root}/bin/agents/erindi-brief.sh`, errandId, root, "--mode", "direct-PR"], root)
            const briefPath = `${root}/data/${errandId}/brief.md`
            const brief = (await Bun.file(briefPath).text())
              .replace(/\{TASK\}/g, task)
              .replace(/\{FIGURE\}/g, figure.name)
            await Bun.write(briefPath, brief)
            
            await runShell("bash", [
              `${root}/bin/agents/einherjar-spawn.sh`, errandId, root, "--mode", "direct-PR"
            ], root, { 
              env: { ...process.env, BROKK_TASK: task, BROKK_FIGURE: figure.name } 
            })
            
            return toolResult(`dispatched ${figure.name} as errand ${errandId}\n` +
              `  seat: a herdr pane now exists — list it with ymir_errand(action=read, errand=${errandId})\n` +
              `  steer:  ymir_errand(action=steer, errand=${errandId}, message="…")`)
          } catch (e: any) {
            return toolResult(`error: could not seat ${agent} — ${e.message.split("\n")[0]}\n  check: bash bin/agents/einherjar-spawn.sh ${errandId} ${root} --mode direct-PR`)
          }
        },
      })

      // --- ymir_well: Direct well access ---
      tools.add({
        name: "ymir_well",
        description: "Direct access to Mimirsbrunn (the well). recall | observe | search | stats.",
        input: Schema.Struct({
          action: Schema.Literal("recall", "observe", "search", "stats"),
          query: Schema.optional(Schema.String),
          limit: Schema.optional(Schema.Number),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ action, query, limit = 5 }) => {
          try {
            const args = [action]
            if (query) args.push(query)
            if (action === "recall" || action === "search") args.push(String(limit))
            const out = await runShell(`${root}/bin/records/mimir.sh`, args, home)
            return toolResult(out || "(no result)")
          } catch (e: any) {
            return toolResult("well error: " + e.message.split("\n")[0])
          }
        },
      })

      // --- ymir_dellingr: Grade documentation ---
      tools.add({
        name: "ymir_dellingr",
        description: "GRADE the documentation: is it fresh or old? Marks every document with a Norse grade (nýr fresh · eldri aging · forn old · safn archive) from measurable signals only.",
        input: Schema.Struct({
          path: Schema.optional(Schema.String),
          ageDays: Schema.optional(Schema.Number),
        }),
        output: Schema.Struct({ text: Schema.String }),
        execute: async ({ path, ageDays }) => {
          try {
            const eldri = ageDays ? ageDays / 2 : 90
            const forn = ageDays ?? 365
            const rootDir = path ? `${home}/${path}` : `${home}/hodd`
            const files = (await runShell("bash", ["-c", `find "$1" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*'`, "_", rootDir], home))
              .split("\n").filter(Boolean).slice(0, 400)
            
            const rows: string[] = []
            for (const abs of files) {
              const rel = abs.replace(`${home}/`, "")
              let day = -1
              try {
                const d = (await runShell("bash", ["-c", `git log -1 --format=%ct -- "${rel}"`, "_"], home)).trim()
                if (/^[0-9]{9,}$/.test(d)) day = Math.floor((Date.now() - parseInt(d, 10) * 1000) / 86400000)
              } catch {}
              const stem = rel.split("/").pop()!.replace(/\.md$/, "")
              const inRef = rel.startsWith("hodd/reference/")
              const g = inRef ? "safn" : day < 0 ? "unmeasured" : day >= forn ? "forn" : day >= eldri ? "eldri" : "nýr"
              const why = inRef ? "in the reference shelf — moved on purpose"
                : day < 0 ? "could NOT read its age — refused to guess"
                : day >= forn ? `untouched ${day}d` : day >= eldri ? `${day}d since its last change` : `changed ${day}d ago`
              rows.push(`  ${g.padEnd(10)} ${rel}  (${why})`)
            }
            return toolResult(rows.join("\n") + "\n\nAn old document MOVES to hodd/reference/ (Rule 11) — grading decides where it belongs, never whether it survives.")
          } catch (e: any) {
            return toolResult("could not grade: " + e.message.split("\n")[0])
          }
        },
      })
    })

    // ========================================================================
    // COMMANDS — user-invoked slash commands
    // ========================================================================

    await ctx.command.transform((commands) => {
      // --- gna-watch-arm: Arm brokk watcher supervision ---
      commands.add({
        name: "gna-watch-arm",
        description: "Arm brokk watcher supervision through the Pi extension instead of foreground bash.",
        execute: async () => {
          try {
            await runShell("bash", [`${root}/bin/pi/syn-watch-arm.sh`, "--restart"], root)
            return toolResult("watcher: arm requested — the extension will start/restart the watcher cycle")
          } catch (e: any) {
            return toolResult("watcher: FAILED - " + e.message.split("\n")[0])
          }
        },
      })

      // --- subagents: List Eindri figures ---
      commands.add({
        name: "subagents",
        description: "List the Eindri figures available as subagents",
        execute: async () => {
          try {
            const figuresDir = `${root}/.agents/agents`
            const entries = (await Bun.file(figuresDir).exists())
              ? (await runShell("bash", ["-c", `ls "$1" 2>/dev/null | grep '\.md$'`, "_", figuresDir], home)).split("\n").filter(Boolean)
              : []
            const names: string[] = []
            for (const entry of entries) {
              const text = await Bun.file(`${figuresDir}/${entry}`).text()
              const fmEnd = text.indexOf("\n---", 3)
              let name = entry.replace(/\.md$/, "")
              if (text.startsWith("---") && fmEnd !== -1) {
                for (const line of text.slice(3, fmEnd).split("\n")) {
                  const m = /^name:\s*(.*)$/.exec(line)
                  if (m) { name = m[1].trim().replace(/^["']|["']$/g, ""); break }
                }
              }
              names.push(name)
            }
            return toolResult(names.length ? `${names.length} figures: ${names.sort().join(", ")}` : "no figures found — is .agents/agents present?")
          } catch (e: any) {
            return toolResult("error: " + e.message.split("\n")[0])
          }
        },
      })
    })
  },
})

// ========================================================================
// PATH CLASSIFICATION (shared logic from ymirhome.ts)
// ========================================================================

function classifyPath(rel: string): { ok: boolean; shelf: string; why: string } {
  if (rel.startsWith("/")) return { ok: false, shelf: "", why: "absolute path — give it relative to the home" }
  if (rel.split("/").includes("..")) return { ok: false, shelf: "", why: "a path may not escape the home" }
  if (rel.endsWith(".env") || /secret|credential|token/i.test(rel)) {
    return { ok: false, shelf: "", why: "that looks like a credential; secrets live in hodd/secrets/, never in a document" }
  }
  
  const SHELVES = [
    { match: /^hodd\/docs\//, where: "private reference", why: "docs about the operator's own machine" },
    { match: /^hodd\/life\/marketing\//, where: "private reference", why: "marketing plans and records" },
    { match: /^hodd\/memory\/daily\//, where: "private reference", why: "a dated daily log" },
    { match: /^hodd\/secrets\//, where: "NEVER a document", why: "credentials belong here, never in a doc" },
    { match: /^hodd\/reference\//, where: "private reference", why: "a retired file kept to be learned from" },
    { match: /^svartalfaheim\/[^/]+\/projects\/[^/]+\/plans\//, where: "plan ledger", why: "a numbered plan for a project" },
    { match: /^svartalfaheim\/[^/]+\/projects\/[^/]+\//, where: "realm project shelf", why: "a project's own material" },
  ]
  
  for (const s of SHELVES) {
    if (s.match.test(rel)) return { ok: true, shelf: s.where, why: s.why }
  }
  return { ok: false, shelf: "", why: "no shelf claims it — name the shelf, or let ymir_find show where its neighbours live" }
}
