#!/usr/bin/env python3
"""Check the packaged iOS app, including native Python extension references."""
import pathlib
import plistlib
import sys


def verify(app):
    app = pathlib.Path(app).resolve()
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundlePackageType') != 'APPL':
        raise ValueError('The main bundle must be an application.')
    for folder in ('lab-packages', 'python'):
        if any((app / folder).rglob('*.a')):
            raise ValueError(f'{folder} contains a build-only static library.')
    count = 0
    for framework in (app / 'Frameworks').glob('*.framework'):
        info = plistlib.loads((framework / 'Info.plist').read_bytes())
        if info.get('CFBundlePackageType') != 'FMWK':
            raise ValueError(f'{framework.name} must be a framework, not an application.')
        for origin in framework.glob('*.origin'):
            placeholder = (app / origin.read_text().strip()).resolve()
            if not placeholder.is_relative_to(app):
                raise ValueError(f'{origin.name} escapes the application bundle.')
            binary = (app / placeholder.read_text().strip()).resolve()
            if not binary.is_relative_to(framework.resolve()) or not binary.is_file():
                raise ValueError(f'{placeholder.name} does not point to its packaged native extension.')
            count += 1
    if count == 0:
        raise ValueError('No packaged Python native extensions were found.')
    print(f'Validated {count} native Python extension references and framework bundle types.')


if __name__ == '__main__':
    verify(sys.argv[1])
