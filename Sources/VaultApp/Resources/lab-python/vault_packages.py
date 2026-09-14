"""Project-local package installation shared by notebook cells and the console."""
import contextlib
from importlib import metadata
import importlib
import io
from pathlib import Path
import shlex
import sys
import tokenize


def install(project, arguments):
    from pip._internal.cli.main import main
    from pip._vendor.packaging.requirements import Requirement
    if not arguments or arguments[0] != 'install':
        raise ValueError('Use pip install package-name or %pip install package-name in a notebook.')
    requirements, options = [], []
    args = iter(arguments[1:])
    for value in args:
        if value in ('-U', '--upgrade'):
            options.append('--upgrade')
        elif value in ('-q', '--quiet'):
            options.append('--quiet')
        elif value in ('-r', '--requirement'):
            from vault_kernel import safe
            name = next(args, None)
            if not name:
                raise ValueError('Choose a requirements file inside this project.')
            path = safe(project, name)
            if path.stat().st_size > 256 * 1024:
                raise ValueError('The requirements file exceeds 256 KiB.')
            requirements.extend(line.split(' #', 1)[0].strip() for line in path.read_text().splitlines()
                                if line.strip() and not line.lstrip().startswith('#'))
        else:
            requirements.append(value)
    if not requirements:
        raise ValueError('Enter a package name, for example ipython.')
    pending = []
    for value in requirements:
        try:
            requirement = Requirement(value)
        except Exception:
            raise ValueError(f'Unsupported package request: {value}. Use package names and version constraints.') from None
        if requirement.url:
            raise ValueError('Use a package name from the package index; direct URLs and install scripts are not supported.')
        if requirement.marker and not requirement.marker.evaluate():
            continue
        try:
            installed = metadata.version(requirement.name)
        except metadata.PackageNotFoundError:
            installed = None
        if installed and installed in requirement.specifier and not requirement.extras and '--upgrade' not in options:
            print(f'Already available: {requirement.name} {installed}')
        else:
            pending.append(value)
    if not pending:
        return
    site = Path(project) / '.vaultlab' / 'packages'
    cache = Path(project) / '.vaultlab' / 'pip-cache'
    cache.mkdir(parents=True, exist_ok=True)
    command = ['install', '--target', str(site), '--only-binary=:all:',
               '--cache-dir', str(cache), '--timeout', '60', '--retries', '3',
               '--progress-bar', 'off', '--disable-pip-version-check', '--no-compile', *options]
    if sys.platform == 'ios':
        command += ['--platform', 'any', '--implementation', 'py', '--abi', 'none']
    # Pip's connection retries do not cover a timeout midway through a wheel.
    # Retry that transient failure once, reusing completed downloads in the cache.
    for attempt in range(2):
        log = io.StringIO()
        with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            result = main([*command, *pending])
        text = log.getvalue()
        print(text, end='')
        if not result or not download_interrupted(text) or attempt == 1:
            break
        print('Download interrupted. Retrying once with cached downloads…')
    importlib.invalidate_caches()
    if result:
        messages = [line.removeprefix('ERROR:').strip() for line in text.splitlines() if line.startswith('ERROR:')]
        message = messages[-1] if messages else 'Package installation did not complete.'
        if 'ReadTimeoutError' in text or 'Read timed out' in text:
            message = 'The package download timed out. Check your connection and retry; completed downloads are cached in this project.'
        elif 'ConnectionError' in text or 'Network is unreachable' in text or 'NameResolutionError' in text:
            message = 'The package index could not be reached. Check your connection and retry.'
        elif sys.platform == 'ios' and ('No matching distribution' in text or 'Could not find a version' in text):
            message += ' No compatible pure Python wheel was found for this request. Try a compatible version; native packages need an iOS build or a Mac target.'
        raise RuntimeError(message)
    print('Installation complete. Import the package in your next cell.')


def download_interrupted(text):
    return any(error in text for error in ('ReadTimeoutError', 'Read timed out', 'ConnectionError', 'Connection broken', 'IncompleteRead'))


def default_timeout(code, mode):
    if transform_cell(code) != code or (mode == 'console' and code.strip().startswith('pip install ')):
        return 300
    return 120


def transform_cell(code):
    """Translate pip notebook commands while preserving Python string literals."""
    protected = set()
    try:
        for token in tokenize.generate_tokens(io.StringIO(code).readline):
            if token.type == tokenize.STRING:
                protected.update(range(token.start[0] + 1, token.end[0] + 1))
    except (tokenize.TokenError, IndentationError):
        pass
    lines = code.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if index + 1 in protected:
            continue
        body = line.lstrip()
        if body.startswith(('%pip ', '!pip ', 'pip install ')):
            command = body[1:] if body.startswith(('%', '!')) else body
            arguments = shlex.split(command)
            lines[index] = line[:len(line) - len(body)] + f'_vault_pip_install({arguments[1:]!r})\n'
    return ''.join(lines)
