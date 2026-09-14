import importlib
import json
import pathlib
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'Sources/VaultApp/Resources/lab-python'))
from vaultlab import agents


class AssistantTest(unittest.TestCase):
    def test_model_request_round_trip_and_native_error(self):
        requests = []
        def request(payload):
            data = json.loads(payload); requests.append(data)
            if data['method'] == 'list':
                return json.dumps({'models': [{'id': 'local-fixture'}]})
            return json.dumps({'text': 'local reply', 'local': True, 'offline': True})
        with patch.dict(sys.modules, {'_vault_native': types.SimpleNamespace(model=request)}):
            from vaultlab import models
            importlib.reload(models)
            self.assertEqual(models.list()[0]['id'], 'local-fixture')
            self.assertEqual(models.generate('question', model='local-fixture'), 'local reply')
            self.assertEqual(requests[-1]['history'], [{'role': 'user', 'content': 'question'}])
            self.assertEqual(requests[-1]['model_id'], 'local-fixture')
            with self.assertRaises(ValueError): models.chat([{'role': 'system', 'content': 'x'}])
            models._vault_native.model = lambda _: '{"error":"Model needs more memory"}'
            with self.assertRaisesRegex(RuntimeError, 'memory'): models.generate('question')

    def test_agent_permissions_and_iphone_boundary(self):
        args = agents._arguments('codex', 'question; touch unwanted', False)
        self.assertEqual(args[args.index('--sandbox')+1], 'read-only')
        self.assertEqual(args[-1], 'question; touch unwanted')
        self.assertIn('workspace-write', agents._arguments('codex', 'edit', True))
        args = agents._arguments('claude', 'edit', True)
        self.assertNotIn('Bash', args[args.index('--tools')+1].split(','))
        self.assertNotIn('--dangerously-skip-permissions', args)
        with patch.object(sys, 'platform', 'ios'):
            with self.assertRaisesRegex(RuntimeError, 'Mac host'): agents.run('codex', 'hello')

    def test_real_process_output_error_and_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            script = pathlib.Path(folder)/'assistant'
            script.write_text('#!'+sys.executable+'\nimport json, sys, time\n'
                              'prompt=sys.argv[-1]\n'
                              'if prompt=="sleep": time.sleep(10)\n'
                              'if prompt=="fail": print("auth required"); sys.exit(2)\n'
                              'print(json.dumps({"result":prompt}))\n')
            script.chmod(0o700)
            with patch.object(agents, '_executable', return_value=str(script)):
                self.assertEqual(agents.run('claude', 'literal; no shell $(touch nope)'), 'literal; no shell $(touch nope)')
                self.assertIn('hello', agents.run('codex', 'hello'))
                with self.assertRaisesRegex(RuntimeError, 'auth required'): agents.run('codex', 'fail')
                with self.assertRaises(TimeoutError): agents.run('codex', 'sleep', timeout=1)
                self.assertIsNone(agents._active)
                self.assertIn('still usable', agents.run('codex', 'still usable'))
