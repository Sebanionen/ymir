import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import {
  BEGIN,
  cronLine,
  END,
  install,
  managedLine,
  readCrontab,
  uninstall,
} from "../src/crontab.ts";

// A fake crontab on PATH that keeps the table in a temp file.
let dir: string;
let table: string;
let backup: string;
const path = process.env.PATH;
before(() => {
  dir = mkdtempSync(join(tmpdir(), "dna-crontab-"));
  table = join(dir, "table");
  backup = join(dir, "crontab.bak");
  writeFileSync(
    join(dir, "crontab"),
    `#!/bin/bash
T="${table}"
if [ "$1" = "-l" ]; then [ -f "$T" ] && cat "$T" && exit 0; echo "crontab: no crontab for test" >&2; exit 1; fi
if [ "$1" = "-" ]; then cat > "$T"; exit 0; fi
if [ "$1" = "-e" ]; then echo "never" >&2; exit 9; fi
cp "$1" "$T"
`,
  );
  chmodSync(join(dir, "crontab"), 0o755);
  process.env.PATH = `${dir}:${path}`;
});
after(() => {
  process.env.PATH = path;
  rmSync(dir, { recursive: true, force: true });
});

const line = cronLine(
  "*/15 * * * *",
  "/code/apps/dna-server-cron/bin/dna-cron.sh",
  "/nvm/v24/bin/node",
);

test("install on an empty crontab writes one marked line", () => {
  assert.equal(readCrontab(), "");
  assert.equal(
    line,
    "*/15 * * * * DNA_NODE_DIR=/nvm/v24/bin /bin/bash /code/apps/dna-server-cron/bin/dna-cron.sh",
  );
  assert.equal(install(line, backup).changed, true);
  assert.equal(readFileSync(table, "utf8"), `${BEGIN}\n${line}\n${END}\n`);
});

test("install twice leaves one line, and other lines are untouched", () => {
  writeFileSync(
    table,
    `MAILTO=""\n0 3 * * * /usr/local/bin/backup.sh\n${readFileSync(table, "utf8")}`,
  );
  assert.equal(install(line, backup).changed, false);
  const moved = line.replace("*/15", "*/30");
  assert.equal(install(moved, backup).changed, true);
  const text = readFileSync(table, "utf8");
  assert.equal(text.split(BEGIN).length - 1, 1);
  assert.equal(managedLine(text), moved);
  assert.match(text, /^MAILTO=""\n0 3 \* \* \* \/usr\/local\/bin\/backup.sh\n/);
  assert.ok(existsSync(backup), "a backup before every write");
});

test("uninstall removes only the block", () => {
  assert.equal(uninstall(backup).changed, true);
  assert.equal(readFileSync(table, "utf8"), 'MAILTO=""\n0 3 * * * /usr/local/bin/backup.sh\n');
  assert.equal(uninstall(backup).changed, false);
});

test("a schedule needs five fields", () => {
  assert.throws(() => cronLine("*/15 * * *", "/x"), /5 fields/);
});
