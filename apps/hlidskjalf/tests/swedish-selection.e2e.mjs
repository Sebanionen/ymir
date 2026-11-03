// Targeted live preview proof: prerecorded upload only, physical capture blocked.
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
const base = process.env.SKIRNIR_E2E_URL ?? 'http://127.0.0.1:3988';
const fixture = process.env.SKIRNIR_E2E_AUDIO_SV;
const report = process.env.SKIRNIR_E2E_REPORT;
assert(fixture && existsSync(fixture) && report, 'Provide synthetic Swedish WAV and private report directory');
assert(['localhost', '127.0.0.1'].includes(new URL(base).hostname));
mkdirSync(report, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE });
const context = await browser.newContext({ permissions: [], viewport: { width: 1440, height: 1000 } });
await context.addInitScript(() => {
  window.__physicalCaptureAttempts = 0;
  navigator.mediaDevices.getUserMedia = async () => {
    window.__physicalCaptureAttempts++;
    throw new Error('Physical capture forbidden in this test');
  };
});
const page = await context.newPage();
const errors = []; page.on('pageerror', (error) => errors.push(error.message));
let id = '';
page.on('request', (request) => {
  if (request.method() === 'POST' && request.url().includes('/api/skirnir/voice/turns/')) id = request.url().split('/').at(-1);
});
try {
  await page.goto(`${base}/#/skirnir`);
  const stay = page.getByRole('button', { name: 'Stay in Hlidskjalf', exact: true });
  if (await stay.isVisible().catch(() => false)) await stay.click();
  await page.getByRole('heading', { name: 'Skírnir – Tala', exact: true }).waitFor();
  const status = await page.evaluate(async () => (await (await fetch('/api/skirnir/voice/status')).json()));
  assert.equal(status.languages.find((row) => row.id === 'sv')?.speech, true);
  await page.getByRole('button', { name: 'Kontrollera röster', exact: true }).click();
  await page.waitForFunction(() => {
    const option = document.querySelector('select[aria-label="Språk för tal"] option[value="sv"]');
    return option && !option.disabled && option.textContent.includes('Bengt');
  }, undefined, { timeout: 120_000 });
  const option = page.locator('select[aria-label="Språk för tal"] option[value="sv"]');
  const label = await option.innerText();
  assert.equal(await option.isEnabled(), true);
  console.log('PASS real status speech=true and rendered Swedish option enabled');
  await page.keyboard.press('F8');
  assert.equal(await page.evaluate(() => window.__physicalCaptureAttempts), 0);
  console.log('PASS F8 consent gate with physical capture forbidden');
  await page.getByLabel('Språk för tal').selectOption('sv');
  await page.getByText('Prova med en ljudfil utan mikrofon', { exact: true }).click();
  await page.getByLabel('Ljudfil till Skírnir').setInputFiles(fixture);
  await page.waitForFunction(() => {
    const state = document.querySelector('[role="status"]')?.textContent ?? '';
    return state.includes('Svaret är klart') || state.includes('Kunde inte slutföra');
  }, undefined, { timeout: 180_000 });
  if (await page.getByRole('alert').count()) throw new Error(await page.getByRole('alert').innerText());
  const turn = await page.evaluate(async (turnId) => (await (await fetch(`/api/skirnir/voice/turns/${turnId}`)).json()), id);
  assert.equal(turn.phase, 'ready'); assert.equal(turn.voice, 'Microsoft Bengt');
  assert.match(turn.transcript.toLowerCase(), /vad vet du/);
  assert.match(turn.answer, /Jag har \d+ godkända uppgifter/);
  await page.waitForFunction(() => { const player = document.querySelector('audio'); return player && player.readyState >= 2 && player.duration > 0; });
  assert.equal(await option.isEnabled(), true);
  assert.equal(await page.evaluate(() => window.__physicalCaptureAttempts), 0);
  assert.deepEqual(errors, []);
  const evidence = { pass: true, actualPreview: base, renderedLabel: label, renderedSwedishEnabled: true,
    actualStatusSpeech: true, realBackendPhase: turn.phase, voice: turn.voice, answerIsSwedish: true,
    browserDecodedWav: true, physicalCaptureAttempts: 0, uncaughtErrors: errors };
  writeFileSync(join(report, 'rendered-selection-evidence.json'), JSON.stringify(evidence, null, 2));
  await page.screenshot({ path: join(report, 'rendered-swedish-answer.png'), fullPage: true });
  console.log('PASS enabled Swedish selection -> real Whisper/Skirnir/Bengt WAV in browser; physical attempts=0');
} catch (error) {
  writeFileSync(join(report, 'selection-failure.json'), JSON.stringify({ error: String(error), errors }, null, 2));
  await page.screenshot({ path: join(report, 'selection-failure.png'), fullPage: true }).catch(() => {});
  throw error;
} finally { await context.close(); await browser.close(); }
