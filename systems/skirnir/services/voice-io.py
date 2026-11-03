"""File-only voice adapter for the installed Whisper and Kokoro HTTP engines."""
import argparse
from contextlib import contextmanager
import http.client
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request
import urllib.parse
import uuid
import wave


def setting(name, default):
    value = os.environ.get(name)
    if not value and os.name == 'nt':
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Environment') as key:
                value = winreg.QueryValueEx(key, name)[0]
        except OSError:
            pass
    return value or default


def convert(source, target, *options):
    subprocess.run([setting('FFMPEG_BIN', 'ffmpeg'), '-hide_banner', '-loglevel',
                    'error', '-y', '-i', str(source), *options, str(target)], check=True, timeout=120)


@contextmanager
def open_request(request, timeout=120):
    # Explicit origin connection: no ambient proxy and no urllib Connection: close
    # request. Repeated localhost requests on Windows otherwise reset mid-response.
    url = urllib.parse.urlsplit(request.full_url)
    if url.scheme not in ('http', 'https') or url.username or url.password:
        raise ValueError('Voice URL must be HTTP(S) without inline credentials')
    factory = http.client.HTTPSConnection if url.scheme == 'https' else http.client.HTTPConnection
    connection = factory(url.hostname, url.port, timeout=timeout)
    try:
        target = urllib.parse.urlunsplit(('', '', url.path or '/', url.query, ''))
        connection.request(request.get_method(), target, request.data, dict(request.header_items()))
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError(f'Voice HTTP {response.status}: {response.reason}')
        yield response
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['transcribe', 'speak'])
    parser.add_argument('value', help='input audio path or text')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--lang', default='en')
    args = parser.parse_args()
    if args.action == 'speak' and args.lang != 'en':
        parser.error('This Kokoro adapter supports English only; Swedish speech is unavailable')
    with tempfile.TemporaryDirectory(prefix='skirnir-voice-') as tmp:
        wav = Path(tmp) / 'audio.wav'
        if args.action == 'transcribe':
            convert(args.value, wav, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le')
            boundary = uuid.uuid4().hex
            parts = []
            fields = {'response_format': 'json', 'temperature': '0', 'language': args.lang,
                      'prompt': setting('WHISPER_VOCAB', '')}
            for key, value in fields.items():
                parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
            parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode() + wav.read_bytes() + b'\r\n')
            parts.append(f'--{boundary}--\r\n'.encode())
            request = urllib.request.Request(setting('WHISPER_URL', 'http://127.0.0.1:10300/inference'),
                                             data=b''.join(parts), headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
            with open_request(request) as response:
                text = json.load(response).get('text', '').strip()
            if not text:
                raise RuntimeError('Whisper returned no transcript')
            print(text)
        else:
            if not args.output or args.output.suffix.lower() not in ('.wav', '.ogg'):
                parser.error('speak needs --output with .wav or .ogg')
            # The existing cleaner remains the canonical speech normalisation door.
            cleaner = Path(__file__).with_name('speech-text.py')
            spoken = subprocess.run([sys.executable, str(cleaner)], input=args.value,
                                    text=True, encoding='utf-8', capture_output=True, check=True).stdout.strip()
            payload = json.dumps({'model': 'kokoro', 'input': spoken,
                                  'voice': setting('KOKORO_VOICE', 'af_nicole'),
                                  'lang': 'en-us', 'response_format': 'wav'}).encode()
            request = urllib.request.Request(setting('KOKORO_URL', 'http://127.0.0.1:8765/v1/audio/speech'),
                                             data=payload, headers={'Content-Type': 'application/json'})
            with open_request(request) as response:
                wav.write_bytes(response.read())
            with wave.open(str(wav)) as audio:
                frames = audio.getnframes()
                if frames == 0 or len(audio.readframes(frames)) != frames * audio.getnchannels() * audio.getsampwidth():
                    raise RuntimeError('Kokoro returned empty or truncated WAV')
            # Publish only after decoding succeeded; failed requests leave output untouched.
            if args.output.suffix.lower() == '.wav':
                args.output.write_bytes(wav.read_bytes())
            else:
                encoded = Path(tmp) / 'audio.ogg'
                convert(wav, encoded, '-c:a', 'libopus', '-b:a', '32k', '-ar', '48000', '-ac', '1')
                args.output.write_bytes(encoded.read_bytes())
            print(json.dumps({'audio': str(args.output), 'bytes': args.output.stat().st_size,
                              'language': 'en', 'voice': setting('KOKORO_VOICE', 'af_nicole'), 'road': 'HTTP'}))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'voice: {error}', file=sys.stderr)
        sys.exit(1)
