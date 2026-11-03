export type VoiceKeyInput = { key: string; repeat: boolean; ctrlKey: boolean; altKey: boolean;
  metaKey: boolean; shiftKey: boolean; typing: boolean; focused: boolean; visible: boolean };

/** Only the mounted, focused assistant page owns these keys. No OS hook. */
export function voiceKeyAction(event: VoiceKeyInput, phase: string): 'start' | 'finish' | 'cancel' | null {
  if (event.repeat || event.ctrlKey || event.altKey || event.metaKey || event.shiftKey ||
      event.typing || !event.focused || !event.visible) return null;
  if (event.key === 'Escape' && !['idle', 'stopped'].includes(phase)) return 'cancel';
  if (event.key !== 'F8') return null;
  if (phase === 'listening') return 'finish';
  return ['idle', 'ready', 'stopped', 'error'].includes(phase) ? 'start' : null;
}
