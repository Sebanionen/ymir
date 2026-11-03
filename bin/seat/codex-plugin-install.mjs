#!/usr/bin/env node
// Valknut's Codex door. Both installation and Gróa use the same deployment/check.
// Only Codex's own CLI mutates its config; unrelated settings remain its concern.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const MARKETPLACE = 'ymir';
const PLUGIN = 'ymir@ymir';

function filesBelow(dir, prefix = '') {
  const files = new Map();
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isSymbolicLink()) throw new Error(`plugin source must not carry a symlink: ${rel}`);
    if (entry.isDirectory()) {
      for (const [key, value] of filesBelow(join(dir, entry.name), rel)) files.set(key, value);
    } else if (entry.isFile()) files.set(rel, readFileSync(join(dir, entry.name)));
  }
  return files;
}

export function expectedPlugin(root = ROOT) {
  const source = join(root, '.agents/harness/codex');
  if (!existsSync(join(source, 'plugin.json'))) throw new Error('Codex plugin source is missing from this Ymir package');
  const files = filesBelow(source);
  files.delete('mcp.json.example');
  files.delete('README.md');
  const manifest = JSON.parse(files.get('plugin.json').toString());
  if (manifest.name !== 'ymir' || typeof manifest.version !== 'string') throw new Error('invalid Ymir Codex plugin manifest');
  // The next MCP process uses the installed Ymir runtime. An already-running
  // Codex session must restart to load changed code and its tool catalog.
  files.set('mcp.json', Buffer.from(JSON.stringify({
    $schema: 'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json',
    mcpServers: { ymir: { type: 'stdio', command: process.execPath,
      args: [join(source, 'server.mjs')], env: { YMIR_ROOT: root } } },
  }, null, 2) + '\n'));
  files.set('runtime.json', Buffer.from(JSON.stringify({ root }, null, 2) + '\n'));
  return { files, version: manifest.version };
}

function sameFiles(dir, expected) {
  if (!existsSync(dir)) return false;
  const actual = filesBelow(dir);
  return actual.size === expected.size && [...expected].every(([name, bytes]) => actual.get(name)?.equals(bytes));
}

function deploy(dir, files) {
  if (sameFiles(dir, files)) return;
  const pending = `${dir}.pending-${process.pid}`;
  const backup = `${dir}.previous-${process.pid}`;
  mkdirSync(pending, { recursive: true });
  try {
    for (const [name, bytes] of files) {
      const path = join(pending, name);
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, bytes);
    }
    if (existsSync(dir)) renameSync(dir, backup);
    try { renameSync(pending, dir); }
    catch (error) { if (existsSync(backup)) renameSync(backup, dir); throw error; }
    if (existsSync(backup)) rmSync(backup, { recursive: true });
  } finally {
    if (existsSync(pending)) rmSync(pending, { recursive: true });
  }
}

export function installCodexPlugin({ check = false, root = ROOT, codexHome = process.env.CODEX_HOME || join(homedir(), '.codex'), codex = 'codex' } = {}) {
  root = resolve(root);
  codexHome = resolve(codexHome);
  const run = (args) => {
    const result = spawnSync(codex, args, { encoding: 'utf8', env: { ...process.env, CODEX_HOME: codexHome }, timeout: 60000, windowsHide: true });
    if (result.error || result.status !== 0) throw new Error(`codex ${args.join(' ')} failed: ${result.error?.message || result.stderr?.trim() || `exit ${result.status}`}`);
    try { return JSON.parse(result.stdout); }
    catch { throw new Error(`codex ${args.join(' ')} did not return JSON; update Codex to a version supporting local plugins`); }
  };
  const { files, version } = expectedPlugin(root);
  const marketRoot = join(codexHome, 'ymir-marketplace');
  const source = join(marketRoot, 'plugins/ymir');
  const catalogFile = join(marketRoot, '.agents/plugins/marketplace.json');
  const catalog = JSON.stringify({ name: MARKETPLACE, interface: { displayName: 'Ymir' }, plugins: [{
    name: 'ymir', source: { source: 'local', path: './plugins/ymir' },
    policy: { installation: 'AVAILABLE', authentication: 'ON_INSTALL' }, category: 'Productivity',
  }] }, null, 2) + '\n';
  const deploymentFile = join(marketRoot, 'deployment.json');
  const installedPath = () => {
    if (!existsSync(deploymentFile)) throw new Error('Codex plugin deployment record is absent; run node bin/seat/codex-plugin-install.mjs');
    const path = JSON.parse(readFileSync(deploymentFile, 'utf8')).installedPath;
    if (typeof path !== 'string' || !isAbsolute(path)) throw new Error('Codex returned no absolute installed plugin path');
    const rel = relative(codexHome, path);
    if (rel === '..' || rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) || isAbsolute(rel)) throw new Error('Codex installed path is outside CODEX_HOME');
    return path;
  };
  const verify = () => {
    if (!sameFiles(source, files) || !existsSync(catalogFile) || readFileSync(catalogFile, 'utf8') !== catalog) throw new Error('Codex plugin source is absent or stale; run node bin/seat/codex-plugin-install.mjs');
    const listed = run(['plugin', 'list', '--marketplace', MARKETPLACE, '--json']);
    const plugin = listed.installed?.find((entry) => entry.pluginId === PLUGIN);
    if (!plugin?.installed || !plugin.enabled || plugin.version !== version || resolve(plugin.source.path) !== source || !sameFiles(installedPath(), files)) throw new Error('Codex plugin is disabled, absent or stale; run node bin/seat/codex-plugin-install.mjs');
  };
  if (check) { verify(); return { state: 'current', plugin: PLUGIN }; }
  mkdirSync(codexHome, { recursive: true });
  deploy(source, files);
  mkdirSync(dirname(catalogFile), { recursive: true });
  if (!existsSync(catalogFile) || readFileSync(catalogFile, 'utf8') !== catalog) writeFileSync(catalogFile, catalog);
  run(['plugin', 'marketplace', 'add', marketRoot, '--json']);
  const prior = run(['plugin', 'list', '--marketplace', MARKETPLACE, '--json']).installed?.find((entry) => entry.pluginId === PLUGIN);
  if (prior?.installed && prior.enabled === false) throw new Error('Ymir was explicitly disabled in Codex; enable it before refreshing (the installer preserves that choice)');
  const installed = run(['plugin', 'add', PLUGIN, '--json']);
  writeFileSync(deploymentFile, JSON.stringify({ installedPath: installed.installedPath }, null, 2) + '\n');
  verify();
  return { state: 'installed', plugin: PLUGIN };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const args = process.argv.slice(2);
    if (args.some((arg) => arg !== '--check')) throw new Error('usage: node bin/seat/codex-plugin-install.mjs [--check]');
    const result = installCodexPlugin({ check: args.includes('--check') });
    console.log(`codex-plugin: ${result.state} (${result.plugin}); restart Codex to load changed tools`);
  } catch (error) { console.error(`codex-plugin: FAIL — ${error.message}`); process.exitCode = 1; }
}
