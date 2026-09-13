import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest

spec = importlib.util.spec_from_file_location('starter', Path(__file__).resolve().parents[1] / 'download-model.py')
starter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(starter)
BODY = b'local synthetic model fixture\n' * 2000

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        start = int(self.headers.get('Range', 'bytes=0-')[6:].split('-')[0])
        if self.path == '/no-range':
            start = 0
        self.send_response(206 if start else 200)
        if start:
            self.send_header('Content-Range', f'bytes {start}-{len(BODY)-1}/{len(BODY)}')
        self.send_header('Content-Length', str(len(BODY)-start))
        self.end_headers()
        self.wfile.write(BODY[start:])
    def log_message(self, *_):
        pass

class DownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
    def test_resume_and_servers_without_range(self):
        for endpoint in ('range', 'no-range'):
            with self.subTest(endpoint=endpoint), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / 'model.safetensors'
                target.with_suffix('.safetensors.part').write_bytes(BODY[:119])
                starter.download(f'http://127.0.0.1:{self.server.server_port}/{endpoint}', target, len(BODY), hashlib.sha256(BODY).hexdigest())
                self.assertEqual(target.read_bytes(), BODY)
                self.assertFalse(target.with_suffix('.safetensors.part').exists())
    def test_wrong_checksum_never_publishes_model(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'model.safetensors'
            with self.assertRaisesRegex(ValueError, 'Integrity check failed'):
                starter.download(f'http://127.0.0.1:{self.server.server_port}/range', target, len(BODY), '0'*64)
            self.assertFalse(target.exists())
    def test_valid_existing_file_does_not_access_network(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'model.safetensors'
            target.write_bytes(BODY)
            starter.download('http://127.0.0.1:1/unreachable', target, len(BODY), hashlib.sha256(BODY).hexdigest())
            self.assertEqual(target.read_bytes(), BODY)

if __name__ == '__main__':
    unittest.main()
