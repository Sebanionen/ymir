import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

/** The private installer records the verified PowerShell 7 executable. No
 * account-specific/package path belongs in public code, and 5.1 is no fallback. */
export function swedishVoice(home: string) {
  const directory = process.env.SKIRNIR_SWEDISH_DIR ?? join(home, 'hodd/state/runtime/skirnir-swedish');
  let manifest: { executable?: string; arguments?: string[]; script_sha256?: string } = {};
  try { manifest = JSON.parse(readFileSync(join(directory, 'installation.json'), 'utf8')); } catch { /* unavailable */ }
  const executable = process.env.SKIRNIR_SWEDISH_PWSH ?? manifest.executable ?? '';
  const args = Array.isArray(manifest.arguments) ? [...manifest.arguments] : [];
  const script = process.env.SKIRNIR_SWEDISH_SCRIPT ?? args[3] ?? '';
  const shape = args.length === 8 && args.every((value) => typeof value === 'string') &&
    args[0] === '-NoProfile' && args[1] === '-NonInteractive' && args[2] === '-File' &&
    args[4] === '-TextPath' && args[6] === '-OutputPath';
  const expected = manifest.script_sha256 ?? '';
  let checksum = false;
  try {
    checksum = /^[a-fA-F0-9]{64}$/.test(expected) &&
      createHash('sha256').update(readFileSync(script)).digest('hex') === expected.toLowerCase();
  } catch { /* absent/unreadable script: unavailable, never a fallback */ }
  if (shape) args[3] = script;
  return { executable, script, arguments: args,
    available: Boolean(executable && existsSync(executable) && shape && checksum) };
}

export function swedishCommand(voice: ReturnType<typeof swedishVoice>, text: string, output: string): string[] {
  if (!voice.available) throw new Error('The Swedish voice contract or script checksum is unavailable.');
  const args = [...voice.arguments];
  args[5] = text; args[7] = output;
  return [voice.executable, ...args];
}
