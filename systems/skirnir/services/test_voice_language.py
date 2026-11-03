import os
import tempfile
import unittest
from unittest.mock import patch

fixture = tempfile.TemporaryDirectory()
os.environ['YMIR_HOME'] = fixture.name
os.environ['SKIRNIR_NO_ESCALATE'] = '1'
import skirnir


class SwedishReplies(unittest.TestCase):
    def ask(self, question):
        facts = {'fixture': {'claim': 'A public test fixture.', 'hash': 'fixture-only', 'class': 'public', 'audience': 'public'}}
        with patch.object(skirnir, 'load_digest', return_value=facts), patch.object(skirnir, 'ledger'), \
             patch.object(skirnir, 'escalate', return_value='suppressed'), \
             patch.object(skirnir.subprocess, 'run'):
            return skirnir.answer(question, 'owner', 'voice-local', language='sv')

    def test_inventory_uses_real_filtered_fixture_count(self):
        result = self.ask('Hej, vad vet du?')
        self.assertIn('1 godkända uppgifter', result['answer'])
        self.assertFalse(result['refused'])

    def test_unknown_is_spoken_swedish_refusal_not_invented_translation(self):
        result = self.ask('Vilken färg har månen på torsdag?')
        self.assertIn('godkända kunskap', result['answer'])
        self.assertTrue(result['refused'])

    def test_greeting_is_localized_before_existing_gate(self):
        self.assertEqual(self.ask('Hej')['answer'], 'Hej. Jag lyssnar. Vad vill du veta?')

    def test_voice_does_not_deliver_outbound_requests(self):
        result = self.ask('send this message to someone')
        self.assertIn('skickar, bokar eller ändrar inget', result['answer'])


if __name__ == '__main__':
    unittest.main()
