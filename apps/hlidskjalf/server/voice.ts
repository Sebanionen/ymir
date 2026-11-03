import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { basename } from 'node:path';
import { swedishCommand, swedishVoice } from './swedish-voice.ts';

type Phase = 'transcribing' | 'answering' | 'synthesizing' | 'ready' | 'stopped' | 'error';
type Turn = { id: string; owner: string; phase: Phase; controller: AbortController;
  transcript?: string; answer?: string; refused?: boolean; audio?: string; voice?: string; error?: string; created: number };
type Options = { root: string; home: string; temp: string; python?: string };
const MAX_AUDIO = 8 * 1024 * 1024;
const ID = /^[a-f0-9-]{36}$/;
function engineUrl(name: string, fallback: string): string {
  const value = process.env[name] ?? fallback;
  const url = new URL(value);
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) ||
      !['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('Assistant voice engines must use local loopback URLs without inline credentials.');
  }
  return value;
}
const whisper = engineUrl('WHISPER_URL', 'http://127.0.0.1:10300/inference');
const kokoro = engineUrl('KOKORO_URL', 'http://127.0.0.1:8765/v1/audio/speech');
const terminal = (turn: Turn) => ['ready', 'stopped', 'error'].includes(turn.phase);
const json = (data: unknown, status = 200) => Response.json(data, {
  status, headers: { 'cache-control': 'no-store' },
});

/** Actual peer and same-origin checks; never trust a Host header as peer proof.
 * Local owner trust is the gate's existing desktop policy, not a new web grant. */
export function voiceAccess(req: Request, peer: string, owner: boolean): Response | null {
  const bare = peer.replace(/^::ffff:/, '');
  const url = new URL(req.url);
  if (!['127.0.0.1', '::1'].includes(bare) ||
      !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) ||
      ['forwarded', 'x-forwarded-for', 'cf-connecting-ip'].some((key) => req.headers.has(key))) {
    return json({ error: 'Assistant speech is available only on the local seat.' }, 403);
  }
  if (!owner) return json({ error: 'The local operator session is required.' }, 401);
  const origin = req.headers.get('origin');
  if ((origin && origin !== url.origin) || req.headers.get('sec-fetch-site') === 'cross-site' ||
      (req.method !== 'GET' && origin !== url.origin)) {
    return json({ error: 'A same-origin request is required.' }, 403);
  }
  return null;
}

async function run(command: string[], options: Options, signal: AbortSignal): Promise<string> {
  signal.throwIfAborted();
  const child = Bun.spawn(command, {
    cwd: options.root, stdout: 'pipe', stderr: 'pipe',
    env: { ...process.env, YMIR_HOME: options.home, PYTHONIOENCODING: 'utf-8',
      SKIRNIR_NO_ESCALATE: '1', WHISPER_URL: whisper, KOKORO_URL: kokoro, KOKORO_VOICE: 'af_nicole' },
  });
  const stop = () => { try { child.kill(); } catch { /* already exited */ } };
  signal.addEventListener('abort', stop, { once: true });
  try {
    const [stdout, stderr, code] = await Promise.all([
      new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited,
    ]);
    signal.throwIfAborted();
    // Do not return stderr: it can contain private runtime paths.
    if (code !== 0) {
      const stage = basename(command.find((part) => /\.(py|ps1)$/.test(part)) ?? 'voice-process');
      const control = stage === 'voice-service.ps1' ? stdout : '';
      await appendFile(join(options.temp, 'errors.log'), JSON.stringify({ stage, code, stderr: stderr.slice(-16000), control }) + '\n').catch(() => {});
      throw new Error('The local voice backend failed. Check its private runtime log.');
    }
    return stdout.trim();
  } finally { signal.removeEventListener('abort', stop); }
}

export function createVoiceHandler(options: Options) {
  const turns = new Map<string, Turn>();
  const python = options.python ?? process.env.SKIRNIR_PYTHON ?? (process.platform === 'win32' ? 'python.exe' : 'python3');
  const services = join(options.root, 'systems/skirnir/services');

  async function processTurn(turn: Turn, file: File, language: string) {
    let temp: string | undefined;
    const timeout = setTimeout(() => turn.controller.abort('timeout'), 180_000);
    const signal = turn.controller.signal;
    try {
      await mkdir(options.temp, { recursive: true });
      temp = await mkdtemp(join(options.temp, 'turn-'));
      if (process.platform === 'win32') {
        await run(['powershell.exe', '-NoProfile', '-NonInteractive', '-File',
          join(services, 'voice-service.ps1'), '-Action', 'start', '-Engine', language === 'en' ? 'all' : 'whisper'], options, signal);
      }
      const input = join(temp, 'question.audio');
      await writeFile(input, Buffer.from(await file.arrayBuffer()));
      signal.throwIfAborted();
      turn.transcript = await run([python, join(services, 'voice-io.py'), 'transcribe', input,
        '--lang', language], options, signal);
      if (!turn.transcript || turn.transcript.length > 4000) throw new Error('The transcript is empty or too long.');
      turn.phase = 'answering';
      // The existing engine owns retrieval, approved knowledge, refusal and audit.
      const result = JSON.parse(await run([python, join(services, 'skirnir.py'),
        '--text', turn.transcript, '--tier', 'owner', '--channel', 'voice-local',
        '--sender', 'local-operator', '--language', language], options, signal)) as { answer?: string; refused?: boolean };
      if (!result.answer) throw new Error('Skirnir returned no permitted answer.');
      turn.answer = result.answer;
      turn.refused = Boolean(result.refused);
      if (language === 'en') {
        turn.phase = 'synthesizing';
        const output = join(temp, 'answer.wav');
        const metadata = JSON.parse(await run([python, join(services, 'voice-io.py'), 'speak', result.answer,
          '--output', output, '--lang', 'en'], options, signal));
        if (metadata.voice !== 'af_nicole') throw new Error('English speech did not use Nicole.');
        turn.voice = 'af_nicole';
        turn.audio = (await readFile(output)).toString('base64');
      } else {
        const voice = swedishVoice(options.home);
        if (!voice.available) throw new Error('Swedish speech is unavailable; no other voice was substituted.');
        turn.phase = 'synthesizing';
        const version = await run([voice.executable, '-NoProfile', '-NonInteractive', '-Command', '$PSVersionTable.PSVersion.ToString()'], options, signal);
        if (version !== '7.6.5') throw new Error('Swedish speech requires the verified PowerShell 7.6.5 runtime.');
        const text = join(temp, 'answer.sv.txt');
        const output = join(temp, 'answer.sv.wav');
        await writeFile(text, result.answer, 'utf8');
        const current = swedishVoice(options.home);
        if (current.executable !== voice.executable) throw new Error('The Swedish interpreter contract changed during this turn.');
        const metadata = JSON.parse(await run(swedishCommand(current, text, output), options, signal));
        if (metadata.voice !== 'Microsoft Bengt' || metadata.culture !== 'sv-SE' || metadata.sample_rate !== 24000 || metadata.channels !== 1 || metadata.bits_per_sample !== 16) throw new Error('The Swedish voice identity or format did not match.');
        turn.voice = 'Microsoft Bengt';
        const bytes = await readFile(output);
        if (bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.length <= 44) throw new Error('Swedish speech returned no valid WAV.');
        turn.audio = bytes.toString('base64');
      }
      signal.throwIfAborted();
      turn.phase = 'ready';
    } catch (error) {
      if (signal.aborted) {
        turn.phase = 'stopped'; turn.audio = undefined;
        if (signal.reason === 'timeout') { turn.phase = 'error'; turn.error = 'The voice turn timed out.'; }
      } else {
        turn.phase = 'error';
        turn.error = error instanceof SyntaxError ? 'The local answer was not valid JSON.' : (error as Error).message;
      }
    } finally {
      clearTimeout(timeout);
      if (temp) await rm(temp, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 }).catch(() => {});
    }
  }

  return async function handle(req: Request, owner: string): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname === '/api/skirnir/voice/status' && req.method === 'GET') {
      return json({ local: true, languages: [{ id: 'en', speech: true, voice: 'af_nicole' },
        { id: 'sv', speech: swedishVoice(options.home).available, voice: 'Microsoft Bengt' }],
        active: [...turns.values()].filter((turn) => turn.owner === owner && !terminal(turn)).length });
    }
    const id = url.pathname.match(/^\/api\/skirnir\/voice\/turns\/([a-f0-9-]+)$/)?.[1];
    if (!id || !ID.test(id)) return json({ error: 'Invalid voice turn.' }, 400);
    for (const [key, turn] of turns) {
      if (terminal(turn) && Date.now() - turn.created > 10 * 60_000) turns.delete(key);
    }
    const existing = turns.get(id);
    if (existing && existing.owner !== owner) return json({ error: 'Voice turn unavailable.' }, 404);
    if (req.method === 'DELETE') {
      // A tombstone also stops an upload that has not finished arriving yet.
      const turn = existing ?? { id, owner, phase: 'stopped', controller: new AbortController(), created: Date.now() };
      turn.controller.abort(); turn.phase = 'stopped'; turn.audio = undefined;
      turns.set(id, turn);
      return json({ stopped: true });
    }
    if (req.method === 'GET') {
      if (!existing) return json({ error: 'Voice turn unavailable.' }, 404);
      return json({ id, phase: existing.phase, transcript: existing.transcript,
        answer: existing.answer, refused: existing.refused, audio: existing.audio, voice: existing.voice, error: existing.error });
    }
    if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);
    if (existing) return json({ error: 'This turn was already used or stopped.' }, 409);
    if ([...turns.values()].some((turn) => turn.owner === owner && !terminal(turn))) {
      return json({ error: 'Stop or finish the current question first.' }, 409);
    }
    const length = Number(req.headers.get('content-length'));
    if (!length || length > MAX_AUDIO + 65536) return json({ error: 'Audio upload must be at most 8 MiB.' }, 413);
    const turn: Turn = { id, owner, phase: 'transcribing', controller: new AbortController(), created: Date.now() };
    turns.set(id, turn);
    try {
      const form = await req.formData();
      const file = form.get('audio');
      const language = String(form.get('language') ?? 'en');
      if (!(file instanceof File) || !file.size || file.size > MAX_AUDIO || !['en', 'sv'].includes(language)) {
        turns.delete(id); return json({ error: 'Choose an audio file and a supported input language.' }, 400);
      }
      if (turn.controller.signal.aborted) return json({ stopped: true }, 409);
      void processTurn(turn, file, language);
      return json({ id, phase: turn.phase }, 202);
    } catch {
      turn.phase = 'error'; turn.error = 'The audio upload could not be read.';
      return json({ error: turn.error }, 400);
    }
  };
}
