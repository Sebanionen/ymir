import { useEffect, useRef, useState } from 'react';
import { desktopHeaders } from '../services/api';
import { voiceKeyAction } from '../services/voice-keys';

type Phase = 'idle' | 'permission' | 'listening' | 'transcribing' | 'answering' | 'synthesizing' | 'ready' | 'stopped' | 'error';
type Turn = { phase: Phase; transcript?: string; answer?: string; refused?: boolean; audio?: string; voice?: string; error?: string };
type VoiceStatus = { languages: { id: string; speech: boolean; voice: string }[] };
const labels: Record<Phase, string> = {
  idle: 'Mikrofonen är av', permission: 'Väntar på ditt mikrofontillstånd', listening: 'Lyssnar på din fråga',
  transcribing: 'Mikrofonen är av · tolkar frågan', answering: 'Mikrofonen är av · Skírnir svarar',
  synthesizing: 'Mikrofonen är av · skapar tal', ready: 'Svaret är klart · mikrofonen är av',
  stopped: 'Stoppad · mikrofonen är av', error: 'Kunde inte slutföra · mikrofonen är av',
};

async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`/api/skirnir/voice/${path}`, {
    credentials: 'include', ...init, headers: desktopHeaders(),
  });
  const result = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(result.error ?? `HTTP ${response.status}`);
  return result;
}

export function Skirnir() {
  const [phase, updatePhase] = useState<Phase>('idle');
  const phaseRef = useRef<Phase>('idle');
  function setPhase(value: Phase) { phaseRef.current = value; updatePhase(value); }
  const [language, setLanguage] = useState('en');
  const [consent, setConsent] = useState(false);
  const [connected, setConnected] = useState(false);
  const [connectionFailed, setConnectionFailed] = useState(false);
  const [swedishSpeech, setSwedishSpeech] = useState<boolean | null>(null);
  const swedishAvailability = useRef<boolean | null>(null);
  const refreshVoices = useRef<() => void>(() => {});
  const [voice, setVoice] = useState('');
  const [transcript, setTranscript] = useState('');
  const [answer, setAnswer] = useState('');
  const [refused, setRefused] = useState(false);
  const [error, setError] = useState('');
  const [audio, setAudio] = useState('');
  const [playHint, setPlayHint] = useState('');
  const recorder = useRef<MediaRecorder | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const player = useRef<HTMLAudioElement | null>(null);
  const generation = useRef(0);
  const turn = useRef<string | null>(null);
  const request = useRef<AbortController | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const polling = useRef<ReturnType<typeof setTimeout> | null>(null);
  const audioUrl = useRef('');
  const consentBox = useRef<HTMLInputElement | null>(null);
  const busy = !['idle', 'ready', 'stopped', 'error'].includes(phase);

  function closeTracks() {
    if (timer.current) clearTimeout(timer.current);
    stream.current?.getTracks().forEach((track) => track.stop());
    stream.current = null;
  }

  function cancelLocal() {
    generation.current += 1;
    closeTracks();
    if (recorder.current && recorder.current.state !== 'inactive') {
      recorder.current.onstop = null;
      recorder.current.stop();
    }
    recorder.current = null;
    request.current?.abort();
    if (polling.current) clearTimeout(polling.current);
    player.current?.pause();
  }

  async function stop() {
    const id = turn.current;
    cancelLocal();
    turn.current = null;
    setAudio(''); setPhase('stopped'); setPlayHint('');
    if (id) {
      try { await api(`turns/${id}`, { method: 'DELETE' }); }
      catch { setError('Mikrofonen är av. Backendstoppet kunde inte bekräftas; ladda inte upp en ny fråga ännu.'); }
    }
  }

  useEffect(() => {
    let live = true;
    let reading = false;
    const read = async () => {
      if (reading) return;
      reading = true;
      try {
        const status = await api<VoiceStatus>('status');
        if (live) {
          const available = Boolean(status.languages.find((item) => item.id === 'sv')?.speech);
          swedishAvailability.current = available; setSwedishSpeech(available);
          setConnected(true); setConnectionFailed(false);
        }
      } catch (e) {
        if (live) { setConnectionFailed(true); setError((e as Error).message); }
      } finally { reading = false; }
    };
    const focus = () => { if (document.visibilityState === 'visible') void read(); };
    refreshVoices.current = () => { setError(''); void read(); };
    void read();
    window.addEventListener('focus', focus);
    document.addEventListener('visibilitychange', focus);
    // A private installation can finish after this page opened. Refresh only
    // while speech is unconfirmed, the page is visible and no turn is active.
    const capabilityTimer = setInterval(() => {
      if (swedishAvailability.current !== true && document.visibilityState === 'visible' &&
          ['idle', 'ready', 'stopped', 'error'].includes(phaseRef.current)) void read();
    }, 5000);
    return () => {
      live = false;
      clearInterval(capabilityTimer);
      window.removeEventListener('focus', focus);
      document.removeEventListener('visibilitychange', focus);
      refreshVoices.current = () => {};
      const id = turn.current;
      cancelLocal();
      if (id) void api(`turns/${id}`, { method: 'DELETE', keepalive: true }).catch(() => {});
      if (audioUrl.current) URL.revokeObjectURL(audioUrl.current);
    };
  }, []);

  useEffect(() => {
    if (!audio || !player.current) return;
    void player.current.play().catch(() => setPlayHint('Tryck på Spela upp svaret för att höra det.'));
  }, [audio]);

  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      const target = event.target instanceof HTMLElement ? event.target : null;
      const input = target instanceof HTMLInputElement ? target : null;
      const typing = Boolean(target?.closest('textarea, select, [contenteditable="true"], [role="textbox"]')) ||
        Boolean(input && !['checkbox', 'radio', 'button', 'submit'].includes(input.type));
      const action = voiceKeyAction({ ...event, key: event.key, repeat: event.repeat,
        ctrlKey: event.ctrlKey, altKey: event.altKey, metaKey: event.metaKey, shiftKey: event.shiftKey,
        typing, focused: document.hasFocus(), visible: document.visibilityState === 'visible' }, phaseRef.current);
      if (!action) return;
      event.preventDefault();
      if (action === 'cancel') void stop();
      else if (action === 'finish') finishQuestion();
      else if (!consent) {
        setError('Bekräfta mikrofonvalet först. F8 använder samma samtycke som Börja tala.');
        consentBox.current?.focus();
      } else void start();
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [consent, connected, language]);

  function reset() {
    setError(''); setTranscript(''); setAnswer(''); setRefused(false); setAudio(''); setVoice(''); setPlayHint('');
    if (audioUrl.current) { URL.revokeObjectURL(audioUrl.current); audioUrl.current = ''; }
  }

  async function upload(blob: Blob, token: number) {
    if (generation.current !== token) return;
    const id = crypto.randomUUID();
    turn.current = id;
    const controller = new AbortController();
    request.current = controller;
    setPhase('transcribing');
    const form = new FormData();
    form.set('audio', blob, 'question.audio'); form.set('language', language);
    try {
      await api(`turns/${id}`, { method: 'POST', body: form, signal: controller.signal });
      const poll = async () => {
        if (generation.current !== token) return;
        try {
          const result = await api<Turn>(`turns/${id}`, { signal: controller.signal });
          if (generation.current !== token) return;
          setPhase(result.phase);
          if (result.transcript) setTranscript(result.transcript);
          if (result.answer) { setAnswer(result.answer); setRefused(Boolean(result.refused)); }
          if (result.voice) setVoice(result.voice);
          if (result.error) setError(result.error);
          if (result.phase === 'ready' && result.audio) {
            const bytes = Uint8Array.from(atob(result.audio), (char) => char.charCodeAt(0));
            audioUrl.current = URL.createObjectURL(new Blob([bytes], { type: 'audio/wav' }));
            setAudio(audioUrl.current);
          }
          if (!['ready', 'stopped', 'error'].includes(result.phase)) polling.current = setTimeout(() => void poll(), 600);
        } catch (e) {
          if (generation.current === token) { setPhase('error'); setError((e as Error).message); }
        }
      };
      void poll();
    } catch (e) {
      if (generation.current === token) { setPhase('error'); setError((e as Error).message); }
    }
  }

  function finishQuestion() {
    if (recorder.current?.state === 'recording') recorder.current.stop();
    closeTracks();
  }

  async function start() {
    if (!consent || !connected || !['idle', 'ready', 'stopped', 'error'].includes(phaseRef.current)) return;
    reset();
    const token = ++generation.current;
    setPhase('permission');
    try {
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) throw new Error('Den här webbläsaren saknar lokal ljudinspelning. Använd en aktuell webbläsare på den lokala adressen.');
      const input = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
      if (generation.current !== token) { input.getTracks().forEach((track) => track.stop()); return; }
      stream.current = input;
      const chunks: Blob[] = [];
      const mimeType = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus', 'audio/mp4'].find((type) => MediaRecorder.isTypeSupported(type));
      const recording = new MediaRecorder(input, mimeType ? { mimeType } : undefined);
      recorder.current = recording;
      recording.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
      recording.onstop = () => {
        closeTracks(); recorder.current = null;
        if (generation.current === token) void upload(new Blob(chunks, { type: recording.mimeType }), token);
      };
      recording.onerror = () => { void stop(); setError('Ljudinspelningen avbröts av webbläsaren.'); };
      recording.start();
      setPhase('listening');
      timer.current = setTimeout(finishQuestion, 30_000);
    } catch (e) {
      closeTracks();
      if (generation.current === token) {
        setPhase('error');
        setError((e as Error).name === 'NotAllowedError' ? 'Mikrofontillstånd saknas. Du väljer själv om du vill tillåta det i webbläsaren.' : (e as Error).message);
      }
    }
  }

  return <>
    <div className="stage-head"><div>
      <h1 className="stage-title">Skírnir – Tala</h1>
      <p className="stage-deck">En fråga i taget · godkänd kunskap · lokala röstmotorer</p>
    </div></div>
    <section className="panel" aria-label="Tala med Skírnir" style={{ maxWidth: 840 }}>
      <div className="panel-body" style={{ display: 'grid', gap: 20 }}>
        <div><h2 style={{ marginTop: 0 }}>Tala med Skírnir</h2>
          <p>Tryck på Börja tala, tillåt mikrofonen i webbläsaren och ställ din fråga. Tryck sedan på Avsluta frågan. Mikrofonen stängs innan svaret skapas.</p>
          <p className="muted">Detta är assistenten. Snotras mötesinspelning är en separat funktion. Ljudet används för din fråga och tas bort efter bearbetning; texten följer Skírnirs befintliga privata samtalslogg.</p>
        </div>
        <label>Språk<br /><select aria-label="Språk för tal" value={language} disabled={busy} onChange={(event) => setLanguage(event.target.value)}
          style={{ background: 'var(--ymir-bg-2)', color: 'var(--ymir-text-0)', border: '1px solid var(--ymir-steel-2)', borderRadius: 'var(--ymir-radius)', padding: 8, minHeight: 44, font: 'inherit' }}>
          <option value="en">English · Nicole (USA, kvinna)</option>
          <option value="sv" disabled={swedishSpeech !== true}>{swedishSpeech === null ? 'Svenska · kontrollerar röst…' : swedishSpeech ? 'Svenska · Bengt (sv-SE)' : 'Svenska · röst ej tillgänglig ännu'}</option>
        </select></label>
        <button className="btn btn-sm" style={{ justifySelf: 'start' }} disabled={busy} onClick={() => refreshVoices.current()}>Kontrollera röster</button>
        <p className="muted" style={{ margin: 0 }}>Engelska använder Kokoro Nicole. Svenska använder den separata lokala Bengt-rösten; Kokoro används aldrig som svensk röst. Fakta utan verifierad svensk formulering ger ett ärligt begränsningssvar.</p>
        <label style={{ display: 'flex', alignItems: 'start', gap: 10 }}>
          <input ref={consentBox} type="checkbox" style={{ accentColor: 'var(--ymir-cyan-1)' }} checked={consent} disabled={busy} onChange={(event) => setConsent(event.target.checked)} />
          Jag vill använda mikrofonen för den här frågan. Webbläsaren ber om mitt tillstånd.
        </label>
        <div role="status" aria-live="polite" className="mono" style={{ color: phase === 'listening' ? 'var(--ymir-warn)' : 'var(--ymir-text-1)' }}>
          <span aria-hidden="true">ᛟ </span>{labels[phase]}{!connected ? (connectionFailed ? ' · lokal anslutning saknas' : ' · ansluter lokalt…') : ''}
        </div>
        <p className="muted" style={{ margin: 0 }}><kbd>F8</kbd> börjar tala, nästa <kbd>F8</kbd> avslutar frågan. <kbd>Escape</kbd> avbryter.
          {' '}Gäller bara när den här Skírnir-sidan har fokus, inte när du skriver eller arbetar i en annan app. Samtycke krävs även med F8.</p>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
          <button className="btn btn-primary" style={{ minHeight: 44 }} disabled={!consent || !connected || busy} onClick={() => void start()}>Börja tala</button>
          <button className="btn" style={{ minHeight: 44 }} disabled={phase !== 'listening'} onClick={finishQuestion}>Avsluta frågan</button>
          <button className="btn" style={{ minHeight: 44 }} disabled={phase === 'idle' || phase === 'stopped'} onClick={() => void stop()}>Stoppa</button>
          {connectionFailed && <button className="btn" onClick={() => refreshVoices.current()}>Anslut igen</button>}
        </div>
        {error && <p role="alert" style={{ color: 'var(--ymir-danger)', overflowWrap: 'anywhere' }}>{error}</p>}
        <div><h3>Din fråga</h3><p data-testid="voice-transcript">{transcript || 'Här visas transkriptionen när frågan har tolkats.'}</p></div>
        <div><h3>Skírnirs svar</h3><p data-testid="voice-answer" style={{ whiteSpace: 'pre-wrap' }}>{answer || 'Här visas svaret från Skírnirs befintliga kunskap och svarsspärr.'}</p>
          {answer && refused && <p className="muted">Skírnir markerade svaret som en begränsning eller saknad godkänd fakta.</p>}
        </div>
        {audio && <div><audio ref={player} controls src={audio} aria-label="Skírnirs talade svar" />
          <p className="muted">Röst: {voice === 'af_nicole' ? 'Nicole · amerikansk engelska · kvinna' : voice === 'Microsoft Bengt' ? 'Bengt · svenska (sv-SE)' : voice}</p>
          <p>{playHint}</p><button className="btn" onClick={() => void player.current?.play().catch(() => setPlayHint('Webbläsaren kunde inte spela ljudet.'))}>Spela upp svaret</button></div>}
        <details><summary>Prova med en ljudfil utan mikrofon</summary>
          <p>Välj ett ljudprov på högst 8 MiB. Samma riktiga transkription och svar används.</p>
          <input aria-label="Ljudfil till Skírnir" type="file" accept="audio/*" disabled={!connected || busy}
            onChange={(event) => { const file = event.target.files?.[0]; if (!file) return; reset(); void upload(file, ++generation.current); event.target.value = ''; }} />
        </details>
      </div>
    </section>
  </>;
}
