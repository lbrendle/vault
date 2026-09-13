#!/usr/bin/env python3
"""Download a pinned starter model; requires only Python 3, never executes model code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import urllib.request

PROJECT = Path(__file__).resolve().parent.parent


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def download(url, target, size, sha256):
    if target.exists() and target.stat().st_size == size and digest(target) == sha256:
        return
    partial = target.with_name(target.name + '.part')
    offset = partial.stat().st_size if partial.exists() else 0
    if offset == size and digest(partial) == sha256:
        partial.replace(target)
        return
    if offset >= size:
        partial.unlink()
        offset = 0
    request = urllib.request.Request(url, headers={'Range': f'bytes={offset}-'} if offset else {})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status == 206:
            match = re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)', response.headers.get('Content-Range', ''))
            if not match or int(match[1]) != offset or int(match[3]) != size:
                raise ValueError('Server returned an unexpected download range')
        elif response.status == 200:
            offset = 0  # Server does not support resuming; start this file again.
        else:
            raise ValueError(f'Download returned HTTP {response.status}')
        with partial.open('ab' if offset else 'wb') as output:
            for chunk in iter(lambda: response.read(1024 * 1024), b''):
                offset += len(chunk)
                if offset > size:
                    raise ValueError('Download exceeds the pinned file size')
                output.write(chunk)
                print(f'\r  {target.name}: {offset / max(size, 1):.0%}', end='', flush=True)
    print()
    if partial.stat().st_size != size or digest(partial) != sha256:
        partial.unlink(missing_ok=True)
        raise ValueError(f'Integrity check failed for {target.name}; run the command again')
    partial.replace(target)


def install(model, root):
    root.mkdir(parents=True, exist_ok=True)
    name = model['repository'].split('/')[-1]
    destination = root / name
    if destination.exists():
        raise ValueError(f'{destination} already exists; refresh Models & chat in Vault')
    staging = root / ('.download-' + name + '-' + model['revision'][:12])
    if staging.is_symlink():
        raise ValueError('Download staging folder must not be a symbolic link')
    staging.mkdir(exist_ok=True)
    remaining = sum(f['bytes'] for f in model['files']) + 64 * 1024 * 1024
    remaining -= sum(p.stat().st_size for p in staging.iterdir() if p.is_file())
    if shutil.disk_usage(root).free < max(0, remaining):
        raise ValueError('Not enough disk space for this model')
    print(f"Installing {model['name']} ({model['precision']}) in {destination}")
    for file in model['files']:
        name = file['name']
        if name in ('.', '..') or Path(name).name != name or '/' in name or '\\' in name:
            raise ValueError('Manifest contains an unsafe filename')
        target = staging / name
        if target.is_symlink() or target.with_name(name + '.part').is_symlink():
            raise ValueError('Model files must not be symbolic links')
        url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{name}"
        download(url, target, file['bytes'], file['sha256'])
    for name in ('LICENSE', 'NOTICE'):
        shutil.copyfile(PROJECT / 'models' / ('Qwen-' + name + '.txt'), staging / name)
    manifest = {**model, 'recommended': model['id'] == 'qwen-large'}
    (staging / 'vault-model.json').write_text(json.dumps(manifest, indent=2) + '\n')
    staging.rename(destination)
    print('Ready. In Vault: Settings → Models & chat → Refresh, then select the model.')
    print('For iPhone/iPad, copy this complete folder into Files and choose Import model folder.')
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', choices=['qwen-small', 'qwen-large', 'all'])
    target = parser.add_mutually_exclusive_group()
    target.add_argument('--destination', type=Path, help='Folder that will contain the complete model folders')
    target.add_argument('--app', action='store_true', help='Install directly into the packaged Mac app model library')
    parser.add_argument('--dry-run', action='store_true', help='Show pinned sources and sizes without downloading')
    args = parser.parse_args()
    root = args.destination or PROJECT / 'models'
    if args.app:
        if sys.platform != 'darwin':
            parser.error('--app is for macOS; use --destination on another system')
        root = Path.home() / 'Library/Application Support/Archii Vault/Models'
    models = json.loads((PROJECT / 'models/starter-models.json').read_text())['models']
    for model in models:
        if args.model not in ('all', model['id']):
            continue
        if args.dry_run:
            print(f"{model['id']}: {model['name']}, {sum(f['bytes'] for f in model['files']) / 1e9:.2f} GB, {model['license']}\n  {model['repository']}@{model['revision']}\n  Destination: {root}")
        else:
            install(model, root)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\nPaused. Run the same command to resume.', file=sys.stderr)
        sys.exit(130)
    except (OSError, ValueError) as error:
        print(f'Could not install model: {error}', file=sys.stderr)
        sys.exit(1)
