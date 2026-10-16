#!/usr/bin/env python3
"""Restore only checksum-pinned WAV files from the complete release ZIP."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
import zipfile


def digest(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(block)
    return result.hexdigest()


def checked_target(root, relative):
    if not isinstance(relative, str):
        raise ValueError('Media paths must be strings')
    path = PurePosixPath(relative)
    if (path.is_absolute() or '\\' in relative
            or '\0' in relative or '..' in path.parts or str(path) != relative
            or not relative.startswith(('dist/samples/', 'examples/'))
            or path.suffix != '.wav'):
        raise ValueError('Invalid media path: ' + str(relative))
    target = root.joinpath(*path.parts)
    current = root
    for part in path.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError('Refusing symbolic link: ' + relative)
    return target


def restore(root, archive, verify_only=False):
    manifest = json.loads((root / 'release-media.json').read_text())
    if manifest.get('archiveRoot') != 'seed-studio' or manifest.get('version') != '0.29.0':
        raise ValueError('Unsupported media manifest')
    expected = manifest['files']
    if not isinstance(expected, dict) or not expected:
        raise ValueError('Empty or invalid media manifest')
    pending = []
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive entries')
        # Validate the entire input before changing any local file.
        for relative, record in expected.items():
            target = checked_target(root, relative)
            name = 'seed-studio/' + relative
            info = zipped.getinfo(name)
            if info.file_size != record['bytes']:
                raise ValueError('Unexpected size: ' + relative)
            with zipped.open(info) as source:
                if digest(source) != record['sha256']:
                    raise ValueError('Archive checksum mismatch: ' + relative)
            if target.exists():
                with target.open('rb') as source:
                    if digest(source) != record['sha256']:
                        raise ValueError('Refusing to overwrite modified local media: ' + relative)
            else:
                pending.append((relative, target))
        if not verify_only:
            for relative, target in pending:
                checked_target(root, relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                descriptor, temporary = tempfile.mkstemp(prefix='.sprout-media-', dir=target.parent)
                try:
                    with os.fdopen(descriptor, 'wb') as output, zipped.open('seed-studio/' + relative) as source:
                        for block in iter(lambda: source.read(1024 * 1024), b''):
                            output.write(block)
                    # A file created after validation must never be replaced.
                    os.link(temporary, target)
                finally:
                    os.unlink(temporary)
    return {'verified': len(expected), 'restored': 0 if verify_only else len(pending), 'verifyOnly': verify_only}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, help='Path to seed-studio-v0.29.0.zip')
    parser.add_argument('--verify-only', action='store_true', help='Validate without writing files')
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        result = restore(root, options.archive, options.verify_only)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, 'Media restoration failed: ' + str(error) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
