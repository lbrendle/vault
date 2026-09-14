"""Optional Codex / Claude Code CLI sessions on a Mac, using its saved login.

These are online services by default. They are never used by local model calls.
Use run('codex', 'Explain baseline.py') or edit=True to permit project edits.
On iPad/iPhone select Paired Mac in Vault before running these commands.
"""
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time

_active = None


def _executable(provider):
    if provider not in ('codex', 'claude'):
        raise ValueError('Choose codex or claude')
    if sys.platform == 'ios':
        raise RuntimeError('Codex and Claude Code require a Mac host. Choose Paired Mac (LAN or Tailscale), or use vaultlab.models locally.')
    candidates = [Path.home() / '.local/bin' / provider, Path('/opt/homebrew/bin') / provider,
                  Path('/usr/local/bin') / provider]
    if provider == 'codex':
        candidates = [Path('/Applications/Codex.app/Contents/Resources/codex'),
                      Path('/Applications/ChatGPT.app/Contents/Resources/codex'), *candidates]
    found = shutil.which(provider)
    if found and Path(found).is_absolute():
        candidates.append(Path(found))
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    raise RuntimeError(f'Install {provider} and sign in on your Mac first. Vault uses that existing CLI login.')


def available():
    """Check installed CLIs without contacting either provider or reading credentials."""
    result = {}
    for provider in ('codex', 'claude'):
        try:
            result[provider] = {'installed': True, 'executable': _executable(provider)}
        except RuntimeError as error:
            result[provider] = {'installed': False, 'message': str(error)}
    return result


def _arguments(provider, prompt, edit):
    if provider == 'codex':
        return ['exec', '--sandbox', 'workspace-write' if edit else 'read-only',
                '--skip-git-repo-check', '--ephemeral', '--color', 'never', '--', prompt]
    if provider == 'claude':
        # Claude's file tools do not need a shell permission bypass. Unapproved
        # tools fail instead of waiting on an invisible terminal prompt.
        tools = 'Read,Glob,Grep' + (',Write,Edit,NotebookEdit' if edit else '')
        return ['-p', '--output-format', 'json', '--permission-mode', 'dontAsk',
                '--tools', tools, '--allowedTools', tools, '--no-session-persistence', '--', prompt]
    raise ValueError('Choose codex or claude')


def stop():
    process = _active
    if process is not None and process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def run(provider, prompt, *, edit=False, timeout=300):
    """Return an assistant's response; edit=False restricts its editing tools.

    Authentication stays with the installed CLI. Provider usage may incur cost.
    Claude enables file tools only. Codex also uses its workspace sandbox.
    """
    global _active
    if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 64000:
        raise ValueError('Write a prompt of at most 64,000 characters')
    executable = _executable(provider)
    if _active is not None:
        raise RuntimeError('A coding assistant is already running')
    timeout = max(1, min(600, int(timeout)))
    env = dict(os.environ)
    env['PATH'] = os.pathsep.join([str(Path.home()/'.local/bin'), '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', env.get('PATH', '')])
    # Xcode injection settings must not be inherited by the standalone CLIs.
    env = {k: v for k, v in env.items() if not k.startswith(('DYLD_', 'XCTest', '__XCODE', 'XCInject'))}
    process = subprocess.Popen([executable, *_arguments(provider, prompt, bool(edit))],
                               cwd=Path.cwd(), stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, start_new_session=True)
    _active = process
    output, errors = bytearray(), bytearray()
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, output)
    selector.register(process.stderr, selectors.EVENT_READ, errors)
    started = time.monotonic()
    try:
        while selector.get_map():
            if time.monotonic() - started > timeout:
                raise TimeoutError(f'{provider} exceeded {timeout} seconds')
            for key, _ in selector.select(0.1):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                else:
                    key.data.extend(chunk)
                    if len(output) + len(errors) > 4 * 1024 * 1024:
                        raise RuntimeError('Assistant output exceeded 4 MiB')
        returncode = process.wait(timeout=max(1, timeout - (time.monotonic()-started)))
        text = output.decode('utf-8', errors='replace')
        if returncode:
            raise RuntimeError(f'{provider} exited with status {returncode}: ' + (text or errors.decode('utf-8', errors='replace'))[-12000:])
        if provider == 'claude':
            result = json.loads(text)
            if result.get('is_error'):
                raise RuntimeError(result.get('result') or 'Claude Code could not finish. Check its Mac login and permissions.')
            text = result.get('result', text)
        return text
    finally:
        selector.close()
        stop()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        process.stdout.close(); process.stderr.close()
        _active = None
