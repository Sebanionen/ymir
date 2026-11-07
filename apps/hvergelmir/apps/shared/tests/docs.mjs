// just test docs: every relative link and image in the READMEs resolves to a file in the repo.
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../../..");
const files = [
  "README.md",
  "apps/shared/packages/dna-sdk/README.md",
  "apps/shared/packages/durable-agent/README.md",
  "apps/shared/packages/jev/README.md",
];
let failures = 0;
for (const file of files) {
  const text = readFileSync(join(root, file), "utf8");
  const refs = [...text.matchAll(/\]\(([^)\s]+)\)|<img[^>]+src="([^"]+)"/g)].map(
    (m) => m[1] ?? m[2],
  );
  for (const ref of refs) {
    if (/^(https?:|mailto:|#)/.test(ref)) continue;
    const path = resolve(dirname(join(root, file)), ref.split("#")[0]);
    if (existsSync(path)) console.log(`PASS ${file}: ${ref}`);
    else {
      console.log(`FAIL ${file}: ${ref} does not exist`);
      failures++;
    }
  }
}
if (failures) process.exit(1);
console.log("ALL DOC LINKS RESOLVE");
