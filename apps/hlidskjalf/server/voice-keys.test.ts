import { expect, test } from 'bun:test';
import { voiceKeyAction } from '../src/services/voice-keys';
const key = (value: string, extra = {}) => ({ key: value, repeat: false, ctrlKey: false, altKey: false,
  metaKey: false, shiftKey: false, typing: false, focused: true, visible: true, ...extra });
test('F8 starts, finishes, and never submits twice while processing', () => {
  expect(voiceKeyAction(key('F8'), 'idle')).toBe('start');
  expect(voiceKeyAction(key('F8'), 'listening')).toBe('finish');
  for (const phase of ['permission', 'transcribing', 'answering', 'synthesizing']) expect(voiceKeyAction(key('F8'), phase)).toBeNull();
});
test('repeat, typing, modifiers and another app never take the key', () => {
  for (const state of [{ repeat: true }, { typing: true }, { ctrlKey: true }, { altKey: true },
    { shiftKey: true }, { metaKey: true }, { focused: false }, { visible: false }]) {
    expect(voiceKeyAction(key('F8', state), 'listening')).toBeNull();
  }
});
test('Escape cancels capture, pending permission, backend and playback', () => {
  for (const phase of ['permission', 'listening', 'transcribing', 'answering', 'synthesizing', 'ready']) {
    expect(voiceKeyAction(key('Escape'), phase)).toBe('cancel');
  }
  expect(voiceKeyAction(key('Escape', { typing: true }), 'ready')).toBeNull();
  expect(voiceKeyAction(key('Escape'), 'idle')).toBeNull();
});
