#!/usr/bin/env python3
"""Collect dependency license texts after npm ci and Xcode package resolution."""
import argparse, json, re
from pathlib import Path

project = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--swift-packages', type=Path, required=True, help='Xcode SourcePackages/checkouts directory')
args = parser.parse_args()
output = project / 'docs/licenses/dependencies'
output.mkdir(parents=True, exist_ok=True)
rows = []

def collect(name, version, root, deep=False):
    safe = re.sub(r'[^A-Za-z0-9._-]', '-', name)
    files = root.rglob('*') if deep else root.iterdir()
    texts = []
    for f in sorted(files):
        if f.is_file() and re.match(r'^(licen[sc]e|copying|notice|copyright)(\.|-|$)', f.name, re.I) and f.stat().st_size < 2_000_000:
            try: text = f.read_text()
            except (UnicodeError, OSError): continue
            texts.append(f'===== {f.relative_to(root)} =====\n\n{text}\n')
    target = output / (safe + '.txt')
    if texts:
        target.write_text('\n'.join(texts))
        rows.append(f'| {name} | {version} | [License and notices](licenses/dependencies/{target.name}) |')
    else:
        rows.append(f'| {name} | {version} | See package metadata; no separate license text shipped |')

lock = json.loads((project / 'web/package-lock.json').read_text())
for path, metadata in sorted(lock['packages'].items()):
    if not path or metadata.get('dev'): continue
    root = project / 'web' / path
    if not root.exists(): continue
    package = json.loads((root / 'package.json').read_text())
    collect(package['name'], package['version'], root)
resolved = json.loads((project / 'native/Package.resolved').read_text())
for pin in resolved['pins']:
    root = args.swift_packages / pin['identity']
    if not root.is_dir(): raise SystemExit(f'Missing checkout: {pin["identity"]}')
    collect(pin['identity'], pin['state'].get('version', pin['state']['revision']), root, deep=True)
(project / 'docs/THIRD_PARTY.md').write_text('''# Third-party software and assets

Vault's own source is Apache-2.0. Each dependency retains its own license. This inventory is generated from the committed npm and Swift resolution files; license texts are reproduced alongside it. Development-only npm packages are not part of this runtime inventory. PDF.js also carries separate resource notices under `docs/licenses` and its distributed `cmaps`, `standard_fonts`, `wasm`, and `iccs` directories.

Qwen starter weights are distributed under their upstream Apache-2.0 licenses. Model revisions, checksums, licenses, and conversion attribution are in `models/`. A checkpoint's presence does not imply endorsement by its publisher.

The Vault icon was created for this project with generative image assistance; theme variants and the leaf wordmark are project artwork. No Obsidian or ChatGPT assets are included. System fonts are requested from the operating system rather than copied from it. Interface glyphs use Lucide (ISC); KaTeX and PDF.js distribute their own licensed fonts.

| Component | Resolved version | License text |
| --- | --- | --- |
''' + '\n'.join(rows) + '\n')
print(f'Collected {len(rows)} dependency entries')
