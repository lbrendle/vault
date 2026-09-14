import json
import pathlib
import sys
import tempfile
import types
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'Sources/VaultApp/Resources/lab-python'))
import vault_kernel as kernel


class LabFilesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.folder = self.root / 'Curriculum' / 'Starter Lab'
        self.folder.mkdir(parents=True)
        self.script = self.folder / 'baseline.py'
        self.script.write_text('answer = 6 * 7\nprint(answer)\n', encoding='utf-8')

    def call(self, method, **args):
        return kernel.dispatch({'method': method, 'root': str(self.root), 'args': {'project': '@/Curriculum/Starter Lab', **args}})

    def test_original_file_and_stale_save(self):
        opened = self.call('labRead', path='baseline.py')
        self.call('labSave', path='baseline.py', content="print('Café 🧠')\n", revision=opened['revision'])
        self.assertEqual(self.script.read_text(encoding='utf-8'), "print('Café 🧠')\n")
        with self.assertRaises(ValueError):
            self.call('labSave', path='baseline.py', content='lost edit', revision=opened['revision'])
        self.assertFalse((self.root / 'Labs/Starter Lab/baseline.py').exists())

    def test_execution_and_records_use_the_same_folder(self):
        previous = sys.modules.get('_vault_native')
        sys.modules['_vault_native'] = types.SimpleNamespace(cancelled=lambda: False)
        try:
            result = self.call('labRun', path='baseline.py', code=self.script.read_text())
            self.assertEqual(result['status'], 'ok')
            self.assertTrue((self.folder / 'runs' / result['id'] / 'record.json').is_file())
        finally:
            if previous is None:
                sys.modules.pop('_vault_native', None)
            else:
                sys.modules['_vault_native'] = previous

    def test_paths_reject_traversal_and_symlink_roots(self):
        with self.assertRaises(ValueError):
            kernel.project_directory(self.root, '@/../outside')
        with tempfile.TemporaryDirectory() as external:
            (self.root / 'Labs').symlink_to(external, target_is_directory=True)
            with self.assertRaises(ValueError):
                kernel.dispatch({'method': 'labProjects', 'root': str(self.root), 'args': {}})

    def test_partial_starter_preserves_edits_and_adds_bundled_notebooks(self):
        labs=self.root/'Labs'; first=labs/'First experiment'; first.mkdir(parents=True)
        (first/'baseline.py').write_text('my existing code')
        kernel.seed_project(labs)
        self.assertEqual((first/'baseline.py').read_text(),'my existing code')
        notebooks=list(first.glob('*.ipynb'))
        self.assertGreaterEqual(len(notebooks),4)
        notebooks[0].write_text('my notebook output')
        kernel.seed_project(labs)
        self.assertEqual(notebooks[0].read_text(),'my notebook output')
