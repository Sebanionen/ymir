// just api tokens: write DNA_CLIENT_TOKEN and DNA_CRON_TOKEN into the root .env when missing, short or equal.
// Prints key names only, never a token. --rotate replaces both.
import { join } from "node:path";
import { ensureTokens, repoRoot } from "@dna/sdk/node";

const file = join(repoRoot(), ".env");
const written = ensureTokens(file, { rotate: process.argv.includes("--rotate") });
console.log(
  written.length
    ? `Wrote ${written.join(" and ")} to ${file}`
    : `Both tokens already set in ${file}`,
);
