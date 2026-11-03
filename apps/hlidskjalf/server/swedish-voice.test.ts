import { afterEach, expect, test } from 'bun:test';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { swedishCommand, swedishVoice } from './swedish-voice.ts';

const homes: string[] = [];
function fixture() {
  const home = mkdtempSync(join(tmpdir(), 'skirnir-contract-')); homes.push(home);
  const directory = join(home, 'hodd/state/runtime/skirnir-swedish'); mkdirSync(directory, { recursive: true });
  const executable = join(directory, 'test-runtime.exe'); writeFileSync(executable, 'test-only; never executed');
  const script = join(directory, 'recorded-contract-name.ps1'); const body = '# fixture only'; writeFileSync(script, body);
  const manifest = { executable, arguments: ['-NoProfile', '-NonInteractive', '-File', script,
    '-TextPath', '<UTF8 text file>', '-OutputPath', '<output WAV>'],
    script_sha256: createHash('sha256').update(body).digest('hex') };
  const save = () => writeFileSync(join(directory, 'installation.json'), JSON.stringify(manifest));
  save(); return { home, script, manifest, save };
}
afterEach(() => { for (const home of homes.splice(0)) rmSync(home, { recursive: true, force: true }); });
test('recorded executable and arguments select the exact script; only file placeholders are replaced', () => {
  const row = fixture(); const voice = swedishVoice(row.home);
  expect(voice.available).toBe(true);
  expect(swedishCommand(voice, 'question text.txt', 'answer output.wav')).toEqual([
    row.manifest.executable, '-NoProfile', '-NonInteractive', '-File', row.script,
    '-TextPath', 'question text.txt', '-OutputPath', 'answer output.wav']);
});
test('modified script and missing checksum refuse synthesis', () => {
  const row = fixture(); writeFileSync(row.script, '# changed');
  expect(swedishVoice(row.home).available).toBe(false);
  expect(() => swedishCommand(swedishVoice(row.home), 'in.txt', 'out.wav')).toThrow('checksum');
  row.manifest.script_sha256 = ''; row.save();
  expect(swedishVoice(row.home).available).toBe(false);
});
test('unexpected interpreter flags are refused rather than executed', () => {
  const row = fixture(); row.manifest.arguments[2] = '-Command'; row.save();
  expect(swedishVoice(row.home).available).toBe(false);
});
