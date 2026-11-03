import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { expectedPlugin, installCodexPlugin } from '../bin/seat/codex-plugin-install.mjs';

const codex = process.env.YMIR_TEST_CODEX || 'codex';
const available = spawnSync(codex, ['plugin', 'add', '--help'], { encoding: 'utf8', windowsHide: true }).status === 0;

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'ymir-codex-install-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const root = join(dir, 'runtime with spaces');
  const source = join(root, '.agents/harness/codex');
  mkdirSync(source, { recursive: true });
  writeFileSync(join(source, 'plugin.json'), JSON.stringify({
    $schema: 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json',
    name: 'ymir', version: '0.1.0', description: 'Ymir local installation contract test',
  }));
  writeFileSync(join(source, 'server.mjs'), '// test public runtime\n');
  const codexHome = join(dir, 'codex');
  return { root, source, codexHome, codex };
}

test('check of an absent installation performs no deployment or config creation', (t) => {
  const f = fixture(t);
  assert.throws(() => installCodexPlugin({ ...f, check: true }), /absent or stale/);
  assert.equal(existsSync(f.codexHome), false);
});

test('generated MCP launches the installed runtime through explicit argv and public root', (t) => {
  const f = fixture(t);
  const { files } = expectedPlugin(f.root);
  const server = JSON.parse(files.get('mcp.json')).mcpServers.ymir;
  assert.equal(server.command, process.execPath);
  assert.deepEqual(server.args, [join(f.source, 'server.mjs')]);
  assert.deepEqual(server.env, { YMIR_ROOT: f.root });
  assert.equal(server.type, 'stdio');
});

test('a failed Codex command is a failed install, never a successful deployment', (t) => {
  const f = fixture(t);
  assert.throws(() => installCodexPlugin({ ...f, codex: join(f.root, 'absent-codex') }), /failed/);
});

test('real Codex installs, checks, preserves user config and refreshes same-version updates', { skip: !available && 'Codex CLI with plugin support is not installed' }, (t) => {
  const f = fixture(t);
  mkdirSync(f.codexHome);
  const config = join(f.codexHome, 'config.toml');
  writeFileSync(config, '# keep this operator setting\nmodel = "operator-choice"\n');
  assert.equal(installCodexPlugin(f).state, 'installed');
  assert.equal(installCodexPlugin({ ...f, check: true }).state, 'current');
  const before = readFileSync(config, 'utf8');
  assert.match(before, /model = "operator-choice"/);
  assert.match(before, /# keep this operator setting/);
  installCodexPlugin(f);
  assert.equal(readFileSync(config, 'utf8'), before, 'reinstall must not rewrite unrelated config');
  const cache = join(f.codexHome, 'plugins/cache/ymir/ymir/0.1.0');
  writeFileSync(join(f.source, 'server.mjs'), '// changed public runtime\n');
  assert.throws(() => installCodexPlugin({ ...f, check: true }), /absent or stale/);
  assert.equal(readFileSync(join(cache, 'server.mjs'), 'utf8'), '// test public runtime\n', '--check must not heal');
  installCodexPlugin(f);
  assert.equal(readFileSync(join(cache, 'server.mjs'), 'utf8'), '// changed public runtime\n');
  assert.equal(installCodexPlugin({ ...f, check: true }).state, 'current');
  const disabled = readFileSync(config, 'utf8').replace('enabled = true', 'enabled = false');
  writeFileSync(config, disabled);
  assert.throws(() => installCodexPlugin(f), /explicitly disabled/);
  assert.equal(readFileSync(config, 'utf8'), disabled, 'update must preserve an explicitly disabled plugin');
});

test('install and update use one Codex deployment door and propagate failure', () => {
  // Wiring contract: catches the regression where a working installer is never
  // reached by Gróa. Real deployment behavior is tested through Codex above.
  const installer = readFileSync(new URL('../bin/engine/ymir-install.sh', import.meta.url), 'utf8');
  const update = readFileSync(new URL('../bin/agents/groa-update.sh', import.meta.url), 'utf8');
  assert.match(installer, /run_step step_codex_plugin/);
  assert.match(installer, /codex-plugin-install\.mjs/);
  assert.match(update, /node "\$ROOT\/bin\/seat\/codex-plugin-install\.mjs" --check \|\| exit 1/);
  assert.match(update, /Codex plugin could not be refreshed[\s\S]*?seat_failed=1/);
});

test('the actual packaged plugin installs and its rendered MCP command lists the shared tools', { skip: !available && 'Codex CLI with plugin support is not installed' }, (t) => {
  const f = fixture(t);
  const root = fileURLToPath(new URL('..', import.meta.url));
  installCodexPlugin({ ...f, root });
  const deployment = JSON.parse(readFileSync(join(f.codexHome, 'ymir-marketplace/deployment.json'), 'utf8'));
  const mcp = JSON.parse(readFileSync(join(deployment.installedPath, 'mcp.json'), 'utf8')).mcpServers.ymir;
  const result = spawnSync(mcp.command, mcp.args, {
    env: { ...process.env, ...mcp.env, YMIR_HOME: f.root }, encoding: 'utf8', windowsHide: true,
    input: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } }) + '\n'
      + JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }) + '\n',
  });
  assert.equal(result.status, 0, result.stderr);
  const messages = result.stdout.trim().split('\n').map((line) => JSON.parse(line));
  assert.equal(messages[0].result.serverInfo.name, 'ymir');
  const names = messages[1].result.tools.map((tool) => tool.name);
  assert.equal(names.length, 22);
  assert.ok(names.includes('ymir_recall'));
  assert.ok(names.includes('ymir_update'));
  assert.ok(names.includes('subagent'));
});
