// This test can only capture Chromium's fake device fed by a prerecorded file.
// It never requests a physical microphone or substitutes backend responses.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const base = process.env.SKIRNIR_E2E_URL ?? 'http://127.0.0.1:3988';
const fixture = process.env.SKIRNIR_E2E_AUDIO;
const swedishFixture = process.env.SKIRNIR_E2E_AUDIO_SV;
const report = process.env.SKIRNIR_E2E_REPORT;
assert(fixture && existsSync(fixture), 'Set SKIRNIR_E2E_AUDIO to synthetic prerecorded WAV');
assert(swedishFixture && existsSync(swedishFixture), 'Set SKIRNIR_E2E_AUDIO_SV to genuine synthetic Swedish WAV');
assert(report, 'Set SKIRNIR_E2E_REPORT to a private evidence directory');
assert(['127.0.0.1', 'localhost'].includes(new URL(base).hostname), 'Tests are loopback only');
mkdirSync(report, { recursive: true });
const results = [];
const errors = [];
const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
    `--use-file-for-fake-audio-capture=${fixture}`],
});
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
await context.addInitScript(() => {
  window.__voiceTest = { calls: 0, tracks: [] };
  const original = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  navigator.mediaDevices.getUserMedia = async (...args) => {
    window.__voiceTest.calls++;
    const stream = await original(...args);
    window.__voiceTest.tracks.push(...stream.getTracks());
    return stream;
  };
});
const page = await context.newPage();
page.on('pageerror', (error) => errors.push(error.message));
let uploads = 0;
let latestId = '';
page.on('request', (request) => {
  if (request.method() === 'POST' && request.url().includes('/api/skirnir/voice/turns/')) {
    uploads++; latestId = request.url().split('/').at(-1);
  }
});
const check = (name, details = {}) => { results.push({ name, pass: true, ...details }); console.log(`PASS ${name}`); };
async function ready() {
  await page.waitForFunction(() => {
    const state = document.querySelector('[role="status"]')?.textContent ?? '';
    return state.includes('Svaret är klart') || state.includes('Kunde inte slutföra');
  }, undefined, { timeout: 180_000 });
  const failure = page.getByRole('alert');
  if (await failure.count()) throw new Error(await failure.innerText());
}
async function active() {
  return page.evaluate(async () => (await (await fetch('/api/skirnir/voice/status')).json()).active);
}
try {
  await page.goto(`${base}/#/skirnir`);
  const chooser = page.getByRole('button', { name: 'Stay in Hlidskjalf', exact: true });
  if (await chooser.isVisible({ timeout: 5000 }).catch(() => false)) await chooser.click();
  await page.getByRole('heading', { name: 'Skírnir – Tala', exact: true }).waitFor();
  await page.waitForFunction(() => {
    const value = document.querySelector('[role="status"]')?.textContent ?? '';
    return value && !value.includes('anslutning saknas') && !value.includes('ansluter lokalt');
  }, undefined, { timeout: 120_000 });
  assert.equal(await page.getByRole('button', { name: 'Börja tala', exact: true }).isDisabled(), true);
  assert.equal(await page.evaluate(() => window.__voiceTest.calls), 0);
  check('visible consent-gated button; no capture on page load');
  await page.keyboard.press('F8');
  assert.equal(await page.evaluate(() => window.__voiceTest.calls), 0);
  check('F8 does not bypass visible microphone consent');
  const search = page.getByRole('textbox', { name: 'Workspace-scoped search' });
  await search.fill('typing test'); await page.keyboard.press('F8');
  assert.equal(await page.evaluate(() => window.__voiceTest.calls), 0);
  assert.equal(await search.inputValue(), 'typing test');
  await search.fill('');
  await page.evaluate(() => document.activeElement?.blur());
  check('F8 leaves focused typing alone');
  await page.getByText('Prova med en ljudfil utan mikrofon', { exact: true }).click();
  await page.getByLabel('Ljudfil till Skírnir').setInputFiles(fixture);
  await ready();
  const transcript = await page.getByTestId('voice-transcript').innerText();
  assert.match(transcript.toLowerCase(), /what do you know/);
  assert((await page.getByTestId('voice-answer').innerText()).length > 0);
  await page.waitForFunction(() => { const audio = document.querySelector('audio'); return audio && audio.readyState >= 2 && audio.duration > 0; });
  assert.equal(await page.evaluate(() => window.__voiceTest.calls), 0);
  check('real browser upload -> Whisper -> existing Skirnir -> Kokoro -> playable audio', { transcript });
  const englishVoice = await page.evaluate(async (id) => (await (await fetch(`/api/skirnir/voice/turns/${id}`)).json()).voice, latestId);
  assert.equal(englishVoice, 'af_nicole');
  check('English uses American female Kokoro Nicole af_nicole');
  await page.screenshot({ path: join(report, 'skirnir-answer.png'), fullPage: true });

  await page.getByRole('checkbox').check();
  await page.keyboard.press('F8');
  await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('Lyssnar på din fråga'));
  await page.waitForTimeout(2400);
  await page.evaluate(() => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'F8', repeat: true })));
  assert.match(await page.getByRole('status').innerText(), /Lyssnar/);
  await page.keyboard.press('F8');
  assert.equal(await page.evaluate(() => window.__voiceTest.tracks.every((track) => track.readyState === 'ended')), true);
  await ready();
  check('F8 starts synthetic capture, ignores repeat, then F8 finishes and receives real spoken answer');

  const before = uploads;
  await page.keyboard.press('F8');
  await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('Lyssnar på din fråga'));
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1000);
  assert.equal(await page.evaluate(() => window.__voiceTest.tracks.every((track) => track.readyState === 'ended')), true);
  assert.equal(uploads, before);
  assert.equal(await active(), 0);
  check('Escape while listening releases all synthetic tracks and uploads nothing');

  await page.getByLabel('Ljudfil till Skírnir').setInputFiles(fixture);
  await page.waitForFunction(() => document.querySelector('[role="status"]')?.textContent?.includes('tolkar frågan'));
  await page.keyboard.press('Escape');
  await page.waitForTimeout(1000);
  assert.equal(await active(), 0);
  const stopped = await page.evaluate(async (id) => (await (await fetch(`/api/skirnir/voice/turns/${id}`)).json()).phase, latestId);
  assert.equal(stopped, 'stopped');
  assert.equal(await page.locator('audio').count(), 0);
  check('Escape cancels pending backend work and prevents late playback');

  await page.getByLabel('Språk för tal').selectOption('sv');
  assert.match(await page.getByLabel('Språk för tal').innerText(), /Svenska · Bengt/);
  await page.getByLabel('Ljudfil till Skírnir').setInputFiles(swedishFixture);
  await ready();
  assert.match((await page.getByTestId('voice-transcript').innerText()).toLowerCase(), /vad vet du/);
  assert.match(await page.getByTestId('voice-answer').innerText(), /Jag har \d+ godkända uppgifter/);
  await page.waitForFunction(() => { const audio = document.querySelector('audio'); return audio && audio.readyState >= 2 && audio.duration > 0; });
  const swedishVoice = await page.evaluate(async (id) => (await (await fetch(`/api/skirnir/voice/turns/${id}`)).json()).voice, latestId);
  assert.equal(swedishVoice, 'Microsoft Bengt');
  check('genuine Swedish ASR -> permitted Swedish reply -> Bengt WAV decoded by browser');
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('audio').count(), 0);
  check('Escape stops Swedish playback as well');
  assert.deepEqual(errors, []);
  check('zero uncaught browser errors');
  await page.screenshot({ path: join(report, 'skirnir-swedish-limit.png'), fullPage: true });
  writeFileSync(join(report, 'browser-evidence.json'), JSON.stringify({ syntheticDeviceOnly: true, results, errors }, null, 2));
} catch (error) {
  await page.screenshot({ path: join(report, 'skirnir-failure.png'), fullPage: true }).catch(() => {});
  writeFileSync(join(report, 'browser-failure.json'), JSON.stringify({ results, errors, failure: String(error) }, null, 2));
  throw error;
} finally {
  await context.close(); await browser.close();
}
