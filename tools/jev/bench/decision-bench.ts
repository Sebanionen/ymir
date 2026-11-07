/**
 * decision-bench — measures a llama.cpp rail that serves a native decision GGUF
 * at POST /v1/systemone: one request, one forward pass, no tokens generated.
 * Prints the door proof (one choice question with descriptions) and decisions
 * per second at 3 and 12 options, then the hype/facts/signal command proof.
 *
 *   JEV_LOCAL_API_KEY=... node bench/decision-bench.ts [--out result.json]
 */
import { writeFileSync } from "node:fs";
import { JevClient, JevLedger, loadCommand, rankHfs, runCommand } from "../src/index.ts";
import type { ChoiceQuestion, JevProvider, SystemOneResult } from "../src/index.ts";

const PROVIDER = (process.env.JEV_BACKEND?.trim() || "local") as JevProvider;
const MODEL = process.env.JEV_MODEL?.trim() || (PROVIDER === "mock" ? "mock" : "julia-1@q8_0");
const ENDPOINT = process.env.JEV_LOCAL_URL?.trim() || "http://127.0.0.1:8080/v1/systemone";
const ROUNDS = Number(process.env.JEV_BENCH_ROUNDS ?? 50);
const WARMUP = Number(process.env.JEV_BENCH_WARMUP ?? 2);

const CHARGE_STATE =
  "Customer message: I was charged twice for my order last week and nobody has replied.";

const ROUTE3: Record<string, string> = {
  billing: "A charge, refund, invoice or payment is wrong, duplicated or unexplained",
  shipping: "An order is late, lost, damaged in transit, or has to be returned",
  technical: "A product, account or integration does not work as documented",
};

const QUEUE12: Record<string, string> = {
  billing_duplicate: "The same charge appears twice on the statement",
  billing_refund: "A refund was promised or is overdue",
  billing_invoice: "An invoice, receipt or VAT document is wrong or missing",
  shipping_late: "The parcel is later than the promised delivery window",
  shipping_lost: "The parcel never arrived and no tracking movement is shown",
  shipping_damaged: "The parcel arrived damaged or incomplete",
  shipping_return: "The customer wants to return or exchange an item",
  account_login: "The customer cannot sign in or has lost access to the account",
  account_plan: "The plan, seat count or subscription is not what was bought",
  technical_api: "An API, webhook or integration fails or returns wrong data",
  technical_outage: "The service is down or degraded for everyone",
  legal_gdpr: "A data deletion, export or privacy request",
};

const pct = (xs: number[], q: number) =>
  xs.length ? xs[Math.min(xs.length - 1, Math.floor(q * xs.length))] : 0;

function summarise(latency: number[], elapsedMs: number, answers: number, tokens: number) {
  const sorted = [...latency].sort((a, b) => a - b);
  const mean = latency.reduce((a, b) => a + b, 0) / latency.length;
  const round = (n: number) => Math.round(n * 100) / 100;
  return {
    rounds: latency.length,
    mean_ms: round(mean),
    p50_ms: round(pct(sorted, 0.5)),
    p95_ms: round(pct(sorted, 0.95)),
    min_ms: round(sorted[0]),
    max_ms: round(sorted[sorted.length - 1]),
    decisions_per_second: round(1000 / mean),
    answers_per_second: round((answers / elapsedMs) * 1000),
    mean_input_tokens: round(tokens / latency.length),
    mean_output_tokens: 0,
    wall_ms: round(elapsedMs),
  };
}

async function measure(
  client: JevClient,
  state: string,
  question: ChoiceQuestion,
  rounds: number,
) {
  for (let i = 0; i < WARMUP; i++) await client.systemOne(state, { route: question });
  const latency: number[] = [];
  let answers = 0;
  let tokens = 0;
  let first: SystemOneResult | undefined;
  const started = performance.now();
  for (let i = 0; i < rounds; i++) {
    const t0 = performance.now();
    const result = await client.systemOne(state, { route: question });
    latency.push(performance.now() - t0);
    answers += Object.keys(result.answers).length;
    tokens += result.usage.input_tokens;
    first ??= result;
  }
  const elapsed = performance.now() - started;
  return { summary: summarise(latency, elapsed, answers, tokens), first };
}

const args = process.argv.slice(2);
const outIndex = args.indexOf("--out");
const outPath = outIndex >= 0 ? args[outIndex + 1] : process.env.JEV_BENCH_OUT;

const client = new JevClient({ provider: PROVIDER, model: MODEL, baseUrl: ENDPOINT, timeoutMs: 120_000 });
const ledger = new JevLedger();

const three = await measure(client, CHARGE_STATE, {
  type: "choice",
  instructions: "Which team should handle this customer message?",
  criteria: ROUTE3,
}, ROUNDS);

const twelve = await measure(client, CHARGE_STATE, {
  type: "choice",
  instructions: "Which queue should handle this customer message?",
  criteria: QUEUE12,
}, ROUNDS);

const HFS_DIR = new URL("../prompt_engineering/jev", import.meta.url).pathname;
const hfs = loadCommand("hfs", HFS_DIR);

const HFS_FIXTURES = [
  {
    expect: "hype",
    vars: {
      title: "This new AI agent will replace every engineer by next month, insiders say",
      source: "viral thread",
      excerpt:
        "Insiders claim the secret model is 100x smarter than anything public. No benchmarks or release date, but investors are calling it the biggest game changer in history. AGI is basically here.",
      findings: "",
    },
  },
  {
    expect: "facts",
    vars: {
      title: "llama.cpp b11719: /v1/systemone for native decision models",
      source: "release notes",
      excerpt:
        "Changelog for build b11719: `POST /v1/systemone` answers typed choice, score and noul questions with a native decision GGUF in one forward pass. Measured on an RTX A5000: 82 decisions/s at 3 options.",
      findings: "Read from the server README shipped in the same build.",
    },
  },
];

const HFS_KEYWORDS = {
  hype: ["AGI", "10x", "game changer", "replace every engineer"],
  facts: ["changelog", "release notes", "benchmarks"],
  signal: ["breaking change", "migration", "on-premise"],
};

const hfsProof = [];
for (const fixture of HFS_FIXTURES) {
  const run = await runCommand(
    hfs,
    { ...fixture.vars, section_keywords: HFS_KEYWORDS, taste_examples: [] },
    (state, questions, opts) => client.systemOne(state, questions, opts),
  );
  ledger.record(run.result, { command: hfs.name, version: hfs.version, extra: { expect: fixture.expect } });
  hfsProof.push({
    expect: fixture.expect,
    title: fixture.vars.title,
    answers: run.result.answers,
    rank: rankHfs(run.result.answers, hfs.policy),
    input_tokens: run.result.usage.input_tokens,
    elapsed_ms: run.result.meta.elapsedMs,
  });
}

const proof = {
  measured_at: new Date().toISOString(),
  host: process.env.JEV_HOST || "heimdall",
  gpu: "NVIDIA RTX A5000 Laptop GPU 16384 MiB",
  endpoint: ENDPOINT,
  model: {
    requested: MODEL,
    resolved: three.first?.raw.response.model ?? null,
    provider: three.first?.meta.provider ?? "local",
  },
  door: {
    state: CHARGE_STATE,
    question: { type: "choice", instructions: "Which team should handle this customer message?", criteria: ROUTE3 },
    response: three.first?.raw.response ?? null,
    response_text: three.first?.raw.responseText ?? null,
  },
  bench: {
    options_3: three.summary,
    options_12: twelve.summary,
    option_sets: { options_3: ROUTE3, options_12: QUEUE12 },
  },
  hfs: {
    command: { name: hfs.name, version: hfs.version },
    vocabulary: { categories: hfs.policy, levels: hfs.questions },
    runs: hfsProof,
  },
  ledger: { calls: ledger.calls, questions: ledger.questions, total_usd: ledger.totalUsd },
};

const text = JSON.stringify(proof, null, 2);
if (outPath) writeFileSync(outPath, text + "\n");
console.log(text);
