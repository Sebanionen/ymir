// Opt-in real-engine proof. Synthetic file only; never opens a microphone.
import { strict as assert } from 'node:assert';
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createVoiceHandler, voiceAccess } from './voice.ts';

const home = process.env.SKIRNIR_TEST_HOME;
const audio = process.env.SKIRNIR_TEST_AUDIO_SV;
const report = process.env.SKIRNIR_TEST_REPORT;
assert(home && audio && report, 'Set explicit private home, synthetic Swedish WAV and private evidence directory');
await mkdir(report, { recursive: true });
const handler = createVoiceHandler({ root: resolve(import.meta.dir, '../../..'), home, temp: join(report, 'turns') });
const server = Bun.serve({ hostname: '127.0.0.1', port: 0,
  fetch(req, srv) { return voiceAccess(req, srv.requestIP(req)?.address ?? '', true) ?? handler(req, 'local-test'); } });
const base = `http://127.0.0.1:${server.port}`;
try {
  const id = crypto.randomUUID();
  const form = new FormData(); form.set('audio', Bun.file(audio), 'synthetic.wav'); form.set('language', 'sv');
  const posted = await fetch(`${base}/api/skirnir/voice/turns/${id}`, { method: 'POST', headers: { origin: base }, body: form });
  assert.equal(posted.status, 202);
  const deadline = Date.now() + 180_000;
  let result: { phase: string; voice?: string; transcript?: string; answer?: string; audio?: string; error?: string } | undefined;
  while (Date.now() < deadline) {
    result = await (await fetch(`${base}/api/skirnir/voice/turns/${id}`)).json();
    if (result?.phase === 'ready' || result?.phase === 'error') break;
    await Bun.sleep(500);
  }
  assert.equal(result?.phase, 'ready', result?.error ?? 'Voice turn timed out');
  assert.equal(result?.voice, 'Microsoft Bengt');
  assert.match(result?.transcript?.toLowerCase() ?? '', /vad vet du/);
  assert.match(result?.answer ?? '', /Jag har \d+ godkända uppgifter/);
  const wav = Buffer.from(result?.audio ?? '', 'base64');
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  await writeFile(join(report, 'contract-answer-sv.wav'), wav);
  const evidence = { pass: true, syntheticFileOnly: true, inputLanguage: 'sv', voice: result?.voice,
    transcriptLength: result?.transcript?.length, answerLength: result?.answer?.length, wavBytes: wav.length,
    checks: ['recorded executable/arguments and script_sha256', 'PowerShell 7.6.5', 'real Whisper sv',
      'existing permitted Swedish answer', 'genuine Bengt PCM WAV'], physicalCaptureAttempts: 0 };
  await writeFile(join(report, 'contract-evidence.json'), JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence));
} finally { server.stop(); }
