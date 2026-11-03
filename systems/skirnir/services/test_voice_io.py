"""Failure contracts without a microphone or a live voice engine."""
import importlib.util
import io
import json
import os
import wave
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('voice_io', Path(__file__).with_name('voice-io.py'))
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


class VoiceFailures(unittest.TestCase):
    def test_unicode_answer_survives_windows_utf8_cleaner(self):
        payloads = []
        wav = io.BytesIO()
        with wave.open(wav, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(24000)
            audio.writeframes(b'\0\0' * 24)
        def send(request, **_kwargs):
            payloads.append(json.loads(request.data))
            return io.BytesIO(wav.getvalue())
        def convert(source, target, *_options):
            target.write_bytes(source.read_bytes())
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'speech.wav'
            with patch.dict(os.environ, {'PYTHONIOENCODING': 'utf-8'}), patch.object(sys, 'argv', ['voice-io.py', 'speak', 'Skírnir does not know.', '--output', str(output)]), patch.object(voice, 'open_request', side_effect=send), patch.object(voice, 'convert', side_effect=convert), patch('sys.stdout', new_callable=io.StringIO):
                voice.main()
            self.assertEqual(payloads[0]['input'], 'Skírnir does not know.')
            self.assertGreater(output.stat().st_size, 44)

    def test_swedish_refused_before_network(self):
        with patch.object(sys, 'argv', ['voice-io.py', 'speak', 'Hej', '--lang', 'sv', '--output', 'x.wav']), patch.object(voice, 'open_request') as send:
            with self.assertRaises(SystemExit) as result:
                voice.main()
            self.assertEqual(result.exception.code, 2)
            send.assert_not_called()

    def test_invalid_audio_does_not_replace_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'existing.wav'
            output.write_bytes(b'preserved')
            response = io.BytesIO(b'not a WAV')
            with patch.object(sys, 'argv', ['voice-io.py', 'speak', 'Hello', '--output', str(output)]), patch.object(voice, 'open_request', return_value=response):
                with self.assertRaises(Exception):
                    voice.main()
            self.assertEqual(output.read_bytes(), b'preserved')

    def test_language_is_sent_and_empty_transcript_fails(self):
        def convert(_source, target, *_options):
            target.write_bytes(b'fixture audio')
        def send(request, **_kwargs):
            self.assertIn(b'name="language"\r\n\r\nsv\r\n', request.data)
            return io.BytesIO(b'{"text":""}')
        with patch.object(sys, 'argv', ['voice-io.py', 'transcribe', 'fixture.wav', '--lang', 'sv']), patch.object(voice, 'convert', side_effect=convert), patch.object(voice, 'open_request', side_effect=send):
            with self.assertRaisesRegex(RuntimeError, 'no transcript'):
                voice.main()


if __name__ == '__main__':
    unittest.main()
