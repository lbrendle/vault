import pathlib
import contextlib
import io
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'Sources/VaultApp/Resources/lab-python'))
import vault_kernel as kernel
import vault_packages as packages


class NotebookPackagesTest(unittest.TestCase):
    def test_notebook_pip_commands_and_python_run_in_one_cell(self):
        namespace = {}
        calls = []
        with patch.object(packages, 'install', side_effect=lambda project, args: calls.append(args)):
            kernel.execute_cell('%pip install "ipython==9.12.0"\n!pip install decorator\npip install traitlets\nanswer = 42', '<cell>', namespace)
        self.assertEqual(namespace['answer'], 42)
        self.assertEqual(calls, [['install', 'ipython==9.12.0'], ['install', 'decorator'], ['install', 'traitlets']])

    def test_python_strings_do_not_execute_package_commands(self):
        namespace = {}
        source = "example = '''\n%pip install imaginary\n!pip install imaginary\n'''\ntext = 'pip install imaginary'"
        with patch.object(packages, 'install') as installer:
            kernel.execute_cell(source, '<cell>', namespace)
        installer.assert_not_called()
        self.assertIn('%pip install imaginary', namespace['example'])

    def test_installed_package_is_reused_without_network_or_replacement(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(packages.metadata, 'version', return_value='1.2.3'), patch('pip._internal.cli.main.main') as pip:
            packages.install(pathlib.Path(folder), ['install', 'example>=1.0'])
        pip.assert_not_called()

    def test_install_paths_and_options_cannot_escape_the_project(self):
        with tempfile.TemporaryDirectory() as folder, patch('pip._internal.cli.main.main') as pip:
            for args in [['install','--target','/elsewhere'], ['install','-r','../private.txt'], ['install','example @ https://example.com/script.whl']]:
                with self.assertRaises(ValueError): packages.install(pathlib.Path(folder), args)
        pip.assert_not_called()

    def test_download_timeout_reports_network_failure_and_uses_project_cache(self):
        def failed_download(args):
            print("ERROR: Exception:\npip._vendor.urllib3.exceptions.ReadTimeoutError: Read timed out.")
            return 2
        with tempfile.TemporaryDirectory() as folder, patch.object(packages.metadata, 'version', side_effect=packages.metadata.PackageNotFoundError), patch('pip._internal.cli.main.main', side_effect=failed_download) as pip, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'download timed out'):
                packages.install(pathlib.Path(folder), ['install', 'ipython'])
            args=pip.call_args.args[0]
            self.assertEqual(args[args.index('--cache-dir')+1], str(pathlib.Path(folder)/'.vaultlab'/'pip-cache'))
            self.assertEqual(args[args.index('--timeout')+1], '60')
            self.assertEqual(pip.call_count, 2)

    def test_interrupted_wheel_retries_once_and_recovers(self):
        def result(args):
            print('ERROR: ReadTimeoutError: Read timed out.' if pip.call_count == 1 else 'Successfully installed ipython')
            return 2 if pip.call_count == 1 else 0
        with tempfile.TemporaryDirectory() as folder, patch.object(packages.metadata, 'version', side_effect=packages.metadata.PackageNotFoundError), patch('pip._internal.cli.main.main', side_effect=result) as pip, contextlib.redirect_stdout(io.StringIO()):
            packages.install(pathlib.Path(folder), ['install', 'ipython'])
            self.assertEqual(pip.call_count, 2)
            self.assertEqual(pip.call_args_list[0], pip.call_args_list[1])

    def test_only_package_commands_receive_longer_default_budget(self):
        self.assertEqual(packages.default_timeout('%pip install ipython\nimport IPython', 'cell'), 300)
        self.assertEqual(packages.default_timeout('pip install ipython', 'console'), 300)
        self.assertEqual(packages.default_timeout("example = '''\n%pip install ipython\n'''", 'cell'), 120)
