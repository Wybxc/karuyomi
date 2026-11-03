#!/usr/bin/env python3
"""Build one unchanged release9 extension using reviewed host overlays."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime/teavm'
LOCAL = RUNTIME / '.local'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def put_artifact(path, content_type):
    data = path.read_bytes()
    digest = sha(data)
    target = LOCAL / 'artifacts' / digest
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return {'path': '/api/extensions/artifacts/' + digest,
            'sha256': digest, 'size': len(data), 'contentType': content_type}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', help='Pinned package key from upstream/inputs.json')
    parser.add_argument('--baseline', action='store_true', help='Build unchanged release9 host for development comparison only')
    args = parser.parse_args()
    entries = json.loads((RUNTIME / 'upstream/inputs.json').read_text())
    entry = next((e for e in entries if e['key'] == args.package), None)
    if entry is None:
        parser.error('Unknown frozen package')
    provenance = json.loads((RUNTIME / 'upstream-manifest.json').read_text())
    for name, digest in provenance['files'].items():
        if sha((RUNTIME / 'upstream' / name).read_bytes()) != digest:
            raise ValueError('Frozen source was changed: ' + name)
    original = LOCAL / 'materials/public/extensions' / entry['jar']
    if not original.exists():
        parser.error('Original JAR missing. Run scripts/import-teavm.py ARCHIVE --package ' + args.package)
    if sha(original.read_bytes()) != entry['convertedSha256']:
        raise ValueError('Original converted JAR changed')
    material_files = json.loads((RUNTIME / 'upstream-materials.json').read_text())['files']
    for name, digest in material_files.items():
        if sha((LOCAL / 'materials' / name).read_bytes()) != digest:
            raise ValueError('Frozen dependency changed: ' + name)
    java_version = subprocess.run(['java', '-version'], text=True, capture_output=True, check=True).stderr
    if '25.0.4' not in java_version:
        parser.error('This verified toolchain requires JDK 25.0.4; select it with JAVA_HOME/PATH')
    mode = 'baseline' if args.baseline else 'product'
    work = LOCAL / 'work' / (args.package + '-' + mode)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    for name in ['java', 'scripts']:
        shutil.copytree(RUNTIME / 'upstream' / name, work / name)
    shutil.copy(RUNTIME / 'upstream/inputs.json', work / 'inputs.json')
    (work / 'public').mkdir()
    shutil.copytree(LOCAL / 'materials/public/runtime', work / 'public/runtime')
    (work / 'public/extensions').mkdir()
    shutil.copyfile(original, work / 'public/extensions' / original.name)
    if not args.baseline:
        shutil.copytree(RUNTIME / 'java', work / 'java', dirs_exist_ok=True)
    env = dict(os.environ)
    env['TEAVM_BUILD_CACHE'] = str(LOCAL / 'build-cache')
    # The upstream build bootstraps checksum-verified Maven 3.9.11. A system Maven
    # may not silently change this toolchain; use only the pinned cached binary.
    maven = LOCAL / 'build-cache/apache-maven-3.9.11/bin/mvn'
    if maven.exists():
        env['MAVEN'] = str(maven)
    elif shutil.which('mvn'):
        parser.error('Pin Maven 3.9.11 in .local/build-cache before using a system Maven')
    subprocess.run([sys.executable, 'scripts/build.py', args.package], cwd=work, env=env, check=True)
    if sha(original.read_bytes()) != entry['convertedSha256']:
        raise ValueError('Build mutated original input')
    record = json.loads((work / ('results/build-' + args.package + '.json')).read_text())
    bundle = put_artifact(work / 'public/teavm' / args.package / 'app.js', 'text/javascript')
    sources = {}
    for path in sorted((work / 'java').rglob('*')):
        if path.is_file() and 'target' not in path.parts and 'libs' not in path.parts:
            sources[str(path.relative_to(work))] = sha(path.read_bytes())
    working_hash = sha(json.dumps(sources, sort_keys=True, separators=(',', ':')).encode())
    build = {
        'repoId': 'keiyoushi',
        'packageName': entry['packageName'],
        'version': entry['jar'].split('-v', 1)[1].split('-apk', 1)[0],
        'sourceIds': [s['id'] for s in entry['expectedSources']],
        'protocolVersion': 1,
        'hostAbi': 'karuyomi-source-host-v1',
        'runtimeBaseline': 'teavm-0.16.0-js-release9',
        'bridgeVersion': 1,
        'storageSchema': 'release9-v1',
        'bundle': bundle,
        'hostScripts': [],
        'resources': [],
    }
    if not args.baseline:
        for name in ['crypto-bridge.js', 'zstd-bridge.js', 'graphics-bridge.js', 'cache-bridge.js', 'file-bridge.js']:
            build['hostScripts'].append(put_artifact(RUNTIME / 'bridge' / name, 'text/javascript'))
        zstd = put_artifact(LOCAL / 'materials/public/assets/zstd-CV7N7xSg.wasm', 'application/wasm')
        zstd['logicalName'] = 'zstd.wasm'
        build['resources'].append(zstd)
    # Build identity covers bridges/resources and ABI metadata as well as JS.
    # A bridge-only change must not overwrite an already registered build.
    identity_hash = sha(json.dumps(build, sort_keys=True, separators=(',', ':')).encode())
    build_id = 'release9-' + args.package + '-' + mode + '-' + identity_hash[:20]
    build = {'buildId': build_id, **build}
    evidence = {
        'schemaVersion': 1, 'mode': mode, 'package': args.package,
        'originalJarSha256': entry['convertedSha256'],
        'originalApkSha256': entry['apkSha256'],
        'frozenSourceFingerprint': provenance['sourceFingerprint'],
        'workingSourceSha256': working_hash,
        'workingSourceFiles': sources,
        'materialFiles': material_files,
        'toolchain': {'java': java_version.strip(), 'maven': '3.9.11', 'teavm': '0.16.0', 'backend': 'JAVASCRIPT'},
        'build': record, 'manifest': build,
        'boundary': 'Build and input integrity evidence only; Source/browser/product equivalence is not yet proven.',
    }
    if args.baseline:
        # The frozen host lacks the product RPC ABI. It must never produce an
        # installable product manifest or silently become a runtime fallback.
        del evidence['manifest']
        evidence['baselineBundle'] = bundle
        baselines = LOCAL / 'baselines'
        baselines.mkdir(exist_ok=True)
        destination = baselines / (build_id + '.evidence.json')
        destination.write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps({'evidence': str(destination), 'bundle': bundle, 'mode': mode}, indent=2))
        return
    manifests = LOCAL / 'manifests'
    manifests.mkdir(exist_ok=True)
    (manifests / (build_id + '.json')).write_text(json.dumps(build, indent=2) + '\n')
    (manifests / (build_id + '.evidence.json')).write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'manifest': str(manifests / (build_id + '.json')), 'bundle': bundle, 'mode': mode}, indent=2))


if __name__ == '__main__':
    main()
