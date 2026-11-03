#!/usr/bin/env python3
"""Import the audited release9 source subset; binary materials stay local."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'runtime/teavm'
PREFIX = 'teavm-compatibility-v2/'
FINGERPRINT = '06b2e8f9b560f41c60ce6779ee320ac50523780bf5dd24c08dc01a65010fe299'
MANIFEST_HASH = '706d75cc77728ef63e31e14d5629b8ddd9793778de612543c299b222b07b6118'
FREEZE_HASH = 'a0bd0baa35b31a779f734512639ae50d480d5a8bc84e7be359468bba1465369b'
BRIDGES = ('crypto-bridge.js', 'graphics-bridge.js', 'cache-bridge.js', 'file-bridge.js', 'zstd-bridge.js')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_verified(path, data):
    if path.exists() and path.read_bytes() != data:
        raise ValueError(f'Refusing to overwrite changed material: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--package', action='append', default=[], help='Extract the unchanged converted input for this package key')
    parser.add_argument('--sources-only', action='store_true')
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as archive:
        manifest_bytes = archive.read(PREFIX + 'source-snapshots/release9/manifest.json')
        if sha(manifest_bytes) != MANIFEST_HASH:
            raise ValueError('Not the pinned release9 source manifest')
        manifest = json.loads(manifest_bytes)
        if manifest['sha256'] != FINGERPRINT:
            raise ValueError('Release9 source fingerprint mismatch')
        freeze_bytes = archive.read(PREFIX + 'V2-FREEZE.json')
        if sha(freeze_bytes) != FREEZE_HASH:
            raise ValueError('Not the pinned V2 final freeze manifest')
        freeze = json.loads(freeze_bytes)['files']
        entries = {}
        for name in archive.namelist():
            if not name.startswith(PREFIX):
                continue
            rel = name[len(PREFIX):]
            path = PurePosixPath(rel)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Unsafe archive path')
            include = (
                rel.startswith(('java/src/', 'java/compat/', 'reference-host/src/', 'licenses/'))
                or rel in ('java/pom.xml', 'reference-host/pom.xml', 'scripts/build.py', 'scripts/PatchLibraries.java', 'inputs.json', 'NOTICE.md')
                or rel in ['public/' + b for b in BRIDGES]
            )
            if not include or name.endswith('/'):
                continue
            data = archive.read(name)
            expected = manifest['files'].get(rel, freeze.get(rel))
            if expected is None or sha(data) != expected:
                raise ValueError(f'Unverified source: {rel}')
            write_verified(DEST / 'upstream' / rel, data)
            entries[rel] = sha(data)
        provenance = {
            'schemaVersion': 1,
            'candidate': 'release9',
            'sourceFingerprint': FINGERPRINT,
            'sourceManifestSha256': MANIFEST_HASH,
            'sourceArchive': 'teavm-compatibility-v2.zip',
            'files': dict(sorted(entries.items())),
        }
        write_verified(DEST / 'upstream-manifest.json', (json.dumps(provenance, indent=2) + '\n').encode())
        material_hashes = {name: digest for name, digest in sorted(freeze.items())
                           if (name.startswith('public/runtime/') and name.endswith(('.jar', '.json')))
                           or name == 'public/assets/zstd-CV7N7xSg.wasm'}
        write_verified(DEST / 'upstream-materials.json',
                       (json.dumps({'freezeSha256': FREEZE_HASH, 'files': material_hashes}, indent=2) + '\n').encode())
        if not args.sources_only:
            material = DEST / '.local/materials'
            for name in archive.namelist():
                rel = name[len(PREFIX):]
                if (name.startswith(PREFIX + 'public/runtime/') and name.endswith(('.jar', '.json'))) or rel == 'public/assets/zstd-CV7N7xSg.wasm':
                    data = archive.read(name)
                    if sha(data) != freeze.get(rel):
                        raise ValueError(f'Unverified dependency: {rel}')
                    write_verified(material / rel, data)
            inputs = json.loads(archive.read(PREFIX + 'inputs.json'))
            for key in args.package:
                entry = next((e for e in inputs if e['key'] == key), None)
                if entry is None:
                    raise ValueError(f'Unknown package key: {key}')
                rel = 'public/extensions/' + entry['jar']
                data = archive.read(PREFIX + rel)
                if sha(data) != entry['convertedSha256'] or sha(data) != freeze.get(rel):
                    raise ValueError(f'Original JAR hash mismatch: {key}')
                write_verified(material / rel, data)
    print(f'Imported {len(entries)} verified source files; binaries remain in runtime/teavm/.local/')


if __name__ == '__main__':
    main()
