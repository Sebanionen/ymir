import { describe, expect, test } from 'bun:test';
import { createVoiceHandler, voiceAccess } from './voice.ts';
import { tmpdir } from 'node:os';

const base = 'http://127.0.0.1:3989';
function request(method = 'GET', headers: Record<string, string> = {}) {
  return new Request(`${base}/api/skirnir/voice/status`, { method,
    headers: { origin: base, ...headers } });
}

describe('local speech boundary', () => {
  test('remote peer cannot borrow local Host or a session', () => {
    expect(voiceAccess(request(), '203.0.113.2', true)?.status).toBe(403);
  });
  test('forwarded loopback is refused', () => {
    expect(voiceAccess(request('GET', { 'x-forwarded-for': '203.0.113.2' }), '127.0.0.1', true)?.status).toBe(403);
  });
  test('cross-origin mutation and missing origin are refused', () => {
    expect(voiceAccess(request('POST', { origin: 'https://example.invalid' }), '127.0.0.1', true)?.status).toBe(403);
    expect(voiceAccess(new Request(`${base}/api/skirnir/voice/status`, { method: 'POST' }), '127.0.0.1', true)?.status).toBe(403);
  });
  test('non-owner session is refused', () => {
    expect(voiceAccess(request(), '127.0.0.1', false)?.status).toBe(401);
  });
  test('same-origin local owner is admitted', () => {
    expect(voiceAccess(request('POST'), '::ffff:127.0.0.1', true)).toBeNull();
  });
});

describe('turn cancellation and validation without engines', () => {
  const handler = () => createVoiceHandler({ root: tmpdir(), home: tmpdir(), temp: tmpdir() });
  const path = () => `${base}/api/skirnir/voice/turns/${crypto.randomUUID()}`;
  test('stop before upload leaves a tombstone; replay cannot start work', async () => {
    const handle = handler(); const url = path();
    expect((await handle(new Request(url, { method: 'DELETE' }), 'local')).status).toBe(200);
    expect((await handle(new Request(url, { method: 'POST' }), 'local')).status).toBe(409);
    const status = await (await handle(new Request(url), 'local')).json();
    expect(status.phase).toBe('stopped');
    expect((await handle(new Request(url), 'another-session')).status).toBe(404);
  });
  test('oversized and invalid uploads fail before any backend is launched', async () => {
    const handle = handler();
    expect((await handle(new Request(path(), { method: 'POST', headers: { 'content-length': '99999999' } }), 'local')).status).toBe(413);
    const form = new FormData(); form.set('language', 'sv');
    expect((await handle(new Request(path(), { method: 'POST', body: form, headers: { 'content-length': '128' } }), 'local')).status).toBe(400);
  });
});
