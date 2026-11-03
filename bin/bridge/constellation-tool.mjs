#!/usr/bin/env node
// constellation-tool.mjs — the machine half of the constellation road.
//
// Cards, keys and tokens, with the ONE agent-card contract
// (packages/contracts/src/agent-card.ts) validating every card: a second
// definition of a card is a second truth. Tokens are EdDSA (ed25519) JWTs —
// short-lived, audience-scoped, skill-scoped — signed by the sending house's own
// key and verified against the public key already in the sender's card.
//
//   node constellation-tool.mjs build    --name --endpoint --skill id:name,… [--description] [--signed] [--out FILE]
//   node constellation-tool.mjs validate FILE
//   node constellation-tool.mjs keygen   --out DIR [--name NAME]
//   node constellation-tool.mjs kid      --pub FILE
//   node constellation-tool.mjs mint     --key FILE --kid K --iss NAME --aud NAME --skill ID[,ID] [--minutes N]
//   node constellation-tool.mjs verify   --pub FILE --token TOKEN [--aud NAME] [--skill ID] [--skew SECONDS]
//   node constellation-tool.mjs signbody --key FILE --body FILE
//   node constellation-tool.mjs verifysig --pub FILE --body FILE --sig BASE64URL
//
// Exit: 0 ok, 1 refusal, 2 usage. Every refusal names the field or check.

import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(here, "../..");

const SECRET_PATTERNS = [
  [/bearer\s+[a-z0-9._~+/=-]{12,}/i, "a bearer credential"],
  [/\b(sk-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})\b/, "a provider key"],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"],
  [/(api[_-]?key|client[_-]?secret|password|passwd|access[_-]?token)\s*[:=]\s*\S+/i, "a secret assignment"],
];

function die(code, message) {
  process.stderr.write(`${message}\n`);
  process.exit(code);
}

function args(argv) {
  const out = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const [k, inline] = a.slice(2).split("=", 2);
    if (inline !== undefined) out[k] = inline;
    else if (argv[i + 1] && !argv[i + 1].startsWith("--")) out[k] = argv[++i];
    else out[k] = "true";
  }
  return out;
}

function b64u(buf) {
  return Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64u(str) {
  return Buffer.from(str.replace(/-/g, "+").replace(/_/g, "/"), "base64");
}

function kidOf(pubPem) {
  const der = createPublicKey(pubPem).export({ type: "spki", format: "der" });
  return createHash("sha256").update(der).digest("hex").slice(0, 16);
}

async function contract() {
  const p = join(ROOT, "packages/contracts/src/agent-card.ts");
  if (!existsSync(p)) die(1, `constellation: the shared agent-card contract was not found at ${p}`);
  return import(pathToFileURL(p).href);
}

function scanSecrets(card) {
  const text = JSON.stringify(card);
  for (const [re, what] of SECRET_PATTERNS) {
    if (re.test(text)) return what;
  }
  return "";
}

function parseSkills(spec) {
  return spec.split(",").map((entry) => {
    const [id, name] = entry.split(":", 2);
    if (!id) die(2, "each --skill must be id or id:name");
    return { id: id.trim(), name: (name || id).trim(), description: `${name || id} offered by this house` };
  });
}

async function buildCard(opts) {
  const { assertAgentCard, A2A_PROTOCOL } = await contract();
  if (!opts.name) die(2, "build: --name is required");
  if (!opts.endpoint) die(2, "build: --endpoint is required");
  if (!opts.skill) die(2, "build: --skill id:name[,…] is required");
  const card = {
    name: opts.name,
    description: opts.description || `${opts.name} — a Ymir hall reachable over A2A for the skills its card declares.`,
    url: opts.endpoint,
    version: opts.version || "1.0.0",
    protocolVersion: opts["protocol-version"] || "1.0",
    protocols: [A2A_PROTOCOL],
    capabilities: { streaming: opts.streaming === "false" ? false : true },
    skills: parseSkills(opts.skill),
    defaultInputModes: ["text/plain"],
    defaultOutputModes: ["text/plain"],
    signed: false,
    publicKey: opts.pub ? readFileSync(opts.pub, "utf8").trim() : "",
    kid: opts.pub && existsSync(opts.pub) ? kidOf(readFileSync(opts.pub, "utf8")) : "",
  };
  card.signed = Boolean(card.publicKey);
  try {
    assertAgentCard(card);
  } catch (err) {
    die(1, `constellation: card refused — ${err.message}`);
  }
  const secret = scanSecrets(card);
  if (secret) die(1, `constellation: card refused — it carries ${secret}. A card is metadata; a secret in it is a leak on a notice board.`);
  return card;
}

function keygen(opts) {
  const out = opts.out || ".";
  mkdirSync(out, { recursive: true });
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const privPem = privateKey.export({ type: "pkcs8", format: "pem" });
  const pubPem = publicKey.export({ type: "spki", format: "pem" });
  const name = opts.name || "house";
  const privPath = join(out, `${name}.ed25519.key`);
  const pubPath = join(out, `${name}.ed25519.pub`);
  writeFileSync(privPath, privPem, { mode: 0o600 });
  writeFileSync(pubPath, pubPem);
  return { privPath, pubPath, kid: kidOf(pubPem) };
}

function mint(opts) {
  for (const k of ["key", "iss", "aud", "skill"]) if (!opts[k]) die(2, `mint: --${k} is required`);
  const priv = createPrivateKey(readFileSync(opts.key));
  const scope = opts.skill.split(",").map((s) => s.trim()).filter(Boolean);
  const now = Math.floor(Date.now() / 1000);
  const minutes = Number(opts.minutes || 5);
  if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 1440) die(2, "mint: --minutes must be 1..1440");
  const header = { alg: "EdDSA", typ: "JWT", kid: opts.kid || kidOf(createPublicKey(priv).export({ type: "spki", format: "pem" })) };
  const payload = {
    iss: opts.iss,
    aud: opts.aud,
    scope,
    iat: now,
    exp: now + minutes * 60,
    jti: createHash("sha256").update(`${opts.iss}:${opts.aud}:${scope.join(",")}:${now}:${Math.random()}`).digest("hex").slice(0, 16),
  };
  const signingInput = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const signature = sign(null, Buffer.from(signingInput), priv);
  return { token: `${signingInput}.${b64u(signature)}`, exp: payload.exp, jti: payload.jti, scope };
}

function verifyToken(opts) {
  if (!opts.pub) die(2, "verify: --pub is required");
  if (!opts.token) die(2, "verify: --token is required");
  const parts = opts.token.split(".");
  if (parts.length !== 3) return { ok: false, check: "shape", why: "a token is three base64url segments" };
  let header;
  let payload;
  try {
    header = JSON.parse(unb64u(parts[0]).toString("utf8"));
    payload = JSON.parse(unb64u(parts[1]).toString("utf8"));
  } catch {
    return { ok: false, check: "shape", why: "header or payload is not JSON" };
  }
  if (header.alg !== "EdDSA") return { ok: false, check: "algorithm", why: `alg ${header.alg} is not EdDSA` };
  const pub = createPublicKey(readFileSync(opts.pub));
  let good = false;
  try {
    good = verify(null, Buffer.from(`${parts[0]}.${parts[1]}`), pub, unb64u(parts[2]));
  } catch {
    good = false;
  }
  if (!good) return { ok: false, check: "signature", why: "the signature does not verify against this key" };
  const kid = kidOf(readFileSync(opts.pub));
  if (header.kid && header.kid !== kid) return { ok: false, check: "key id", why: `token kid ${header.kid} is not this key ${kid}` };
  if (opts.aud && payload.aud !== opts.aud) return { ok: false, check: "audience", why: `token is addressed to ${payload.aud}, not ${opts.aud}` };
  const skew = Number(opts.skew || 60);
  const now = Math.floor(Date.now() / 1000);
  if (typeof payload.exp !== "number" || payload.exp + skew < now) {
    return { ok: false, check: "expiry", why: `token expired at ${new Date((payload.exp || 0) * 1000).toISOString()}` };
  }
  if (opts.skill && !(Array.isArray(payload.scope) && payload.scope.includes(opts.skill))) {
    return { ok: false, check: "scope", why: `scope [${(payload.scope || []).join(",")}] does not name ${opts.skill}` };
  }
  return { ok: true, check: "all", payload };
}

function signBody(opts) {
  if (!opts.key) die(2, "signbody: --key is required");
  if (!opts.body) die(2, "signbody: --body is required");
  const priv = createPrivateKey(readFileSync(opts.key));
  const body = readFileSync(opts.body);
  return { sig: b64u(sign(null, body, priv)), kid: kidOf(createPublicKey(priv).export({ type: "spki", format: "pem" })) };
}

function verifyBody(opts) {
  if (!opts.pub || !opts.body || !opts.sig) die(2, "verifysig: --pub, --body and --sig are required");
  const pub = createPublicKey(readFileSync(opts.pub));
  try {
    return { ok: verify(null, readFileSync(opts.body), pub, unb64u(opts.sig)) };
  } catch (err) {
    return { ok: false, why: err.message };
  }
}

const [command, ...rest] = process.argv.slice(2);
const opts = args(rest);

switch (command) {
  case "build": {
    const card = await buildCard(opts);
    const json = `${JSON.stringify(card, null, 2)}\n`;
    if (opts.out) {
      mkdirSync(dirname(opts.out), { recursive: true });
      writeFileSync(opts.out, json);
      process.stdout.write(`card ${opts.out}\n`);
    } else process.stdout.write(json);
    break;
  }
  case "validate": {
    if (!opts._[0]) die(2, "validate: a card file is required");
    const { assertAgentCard } = await contract();
    let card;
    try {
      card = JSON.parse(readFileSync(opts._[0], "utf8"));
    } catch (err) {
      die(1, `constellation: card refused — not JSON (${err.message})`);
    }
    try {
      assertAgentCard(card);
    } catch (err) {
      die(1, `constellation: card refused — ${err.message}`);
    }
    const secret = scanSecrets(card);
    if (secret) die(1, `constellation: card refused — it carries ${secret}`);
    const skills = (card.skills || []).map((s) => s.id).join(",");
    process.stdout.write(`card[1]{name,url,skills,valid}:\n  "${card.name}","${card.url}","${skills}","true"\n`);
    break;
  }
  case "keygen": {
    const k = keygen(opts);
    process.stdout.write(`key[3]{priv,pub,kid}:\n  "${k.privPath}","${k.pubPath}","${k.kid}"\n`);
    break;
  }
  case "kid": {
    if (!opts.pub) die(2, "kid: --pub is required");
    process.stdout.write(`${kidOf(readFileSync(opts.pub))}\n`);
    break;
  }
  case "mint": {
    const t = mint(opts);
    process.stdout.write(`token[3]{scope,exp,jti}:\n  "${t.scope.join(",")}","${t.exp}","${t.jti}"\n${t.token}\n`);
    break;
  }
  case "verify": {
    const v = verifyToken(opts);
    if (!v.ok) {
      process.stdout.write(`refused[1]{check,why}:\n  "${v.check}","${v.why}"\n`);
      process.exit(1);
    }
    const p = v.payload;
    process.stdout.write(`granted[4]{iss,aud,scope,exp}:\n  "${p.iss}","${p.aud}","${(p.scope || []).join(",")}","${p.exp}"\n`);
    break;
  }
  case "signbody": {
    const s = signBody(opts);
    process.stdout.write(`${s.sig}\n`);
    break;
  }
  case "verifysig": {
    const v = verifyBody(opts);
    if (!v.ok) {
      process.stdout.write(`refused[1]{check,why}:\n  "signature","${v.why || "the signature does not verify"}"\n`);
      process.exit(1);
    }
    process.stdout.write("signature ok\n");
    break;
  }
  default:
    die(2, "usage: constellation-tool.mjs build|validate|keygen|kid|mint|verify|signbody|verifysig …");
}
