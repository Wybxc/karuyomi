#!/usr/bin/env python3
"""Prepare checksum-locked TeaVM runtime materials, Maven and optional Android SDK.

No frozen ZIP or installed system Maven is required. Private Release downloads use
`gh` authentication; --seed permits an already downloaded, identically hashed asset.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import io
import json
import os
import platform
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime/teavm'
LOCAL = RUNTIME / '.local'
LOCK_BYTES = (RUNTIME / 'toolchain-lock.json').read_bytes()
LOCK = json.loads(LOCK_BYTES)


def digest(data, algorithm='sha256'):
    return hashlib.new(algorithm, data).hexdigest()


def safe_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name:
        raise ValueError('Unsafe archive path: ' + name)
    return path


def verify_materials(destination):
    for name, expected in LOCK['seed']['members'].items():
        file = destination / name
        if not file.is_file() or digest(file.read_bytes()) != expected:
            raise ValueError('Runtime material missing or altered: ' + name)


def prepare(seed=None, android=False):
    LOCAL.mkdir(parents=True, exist_ok=True)
    materials = LOCAL / 'runtime-seed'
    try:
        verify_materials(materials)
    except ValueError:
        asset = Path(seed).resolve() if seed else LOCAL / 'downloads' / LOCK['seed']['asset']
        if not asset.exists():
            asset.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['gh', 'release', 'download', LOCK['seed']['tag'], '--repo', LOCK['seed']['repo'], '--pattern', LOCK['seed']['asset'], '--dir', str(asset.parent), '--clobber'], check=True)
        data = asset.read_bytes()
        if digest(data) != LOCK['seed']['sha256'] or len(data) != LOCK['seed']['size']:
            raise ValueError('Runtime seed archive checksum/size mismatch')
        staging = LOCAL / 'runtime-seed.extracting'
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir()
        seen = set()
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for item in archive:
                safe_name(item.name)
                if not item.isfile() or item.name not in LOCK['seed']['members'] or item.name in seen:
                    raise ValueError('Unexpected seed member: ' + item.name)
                payload = archive.extractfile(item).read()
                if digest(payload) != LOCK['seed']['members'][item.name]:
                    raise ValueError('Seed member checksum mismatch: ' + item.name)
                target = staging / item.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
                seen.add(item.name)
        if seen != set(LOCK['seed']['members']):
            raise ValueError('Seed member set is incomplete')
        verify_materials(staging)
        if materials.exists():
            shutil.rmtree(materials)
        staging.rename(materials)
    cache = LOCAL / 'build-cache'
    maven = cache / ('apache-maven-' + LOCK['maven']['version']) / 'bin/mvn'
    if not maven.exists():
        data = urllib.request.urlopen(LOCK['maven']['url'], timeout=120).read()
        if digest(data, 'sha512') != LOCK['maven']['sha512']:
            raise ValueError('Maven checksum mismatch')
        cache.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for item in archive:
                safe_name(item.name)
            archive.extractall(cache, filter='data')
    system = {('Darwin', 'arm64'): 'macos-arm64', ('Linux', 'x86_64'): 'linux-x64'}.get((platform.system(), platform.machine()))
    if system is None:
        raise ValueError('Unsupported build host; use macOS arm64 or Linux x64')
    jdk_entry = LOCK['java']['archives'][system]
    java_home = LOCAL / 'jdks' / jdk_entry['home']
    if not (java_home / 'bin/java').exists():
        download = LOCAL / 'downloads' / jdk_entry['url'].rsplit('/', 1)[1]
        download.parent.mkdir(parents=True, exist_ok=True)
        if not download.exists():
            last_error = None
            for url in [*jdk_entry.get('mirrors', []), jdk_entry['url']]:
                try:
                    payload = urllib.request.urlopen(url, timeout=180).read()
                    if digest(payload) != jdk_entry['sha256']:
                        raise ValueError('JDK download checksum mismatch: ' + url)
                    download.write_bytes(payload)
                    break
                except Exception as error:
                    last_error = error
            else:
                raise RuntimeError('JDK download failed: ' + str(last_error))
        data = download.read_bytes()
        if digest(data) != jdk_entry['sha256']:
            raise ValueError('JDK checksum mismatch')
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            for item in archive:
                safe_name(item.name)
            archive.extractall(LOCAL / 'jdks', filter='data')
    if android:
        sdk = LOCAL / 'android-sdk'
        for key in ['platform', system, 'platform-tools-' + system]:
            entry = LOCK['android']['archives'][key]
            target = sdk / entry['destination']
            marker = target / '.karuyomi-archive-sha1'
            if marker.exists() and marker.read_text() == entry['sha1']:
                continue
            data = urllib.request.urlopen(entry['url'], timeout=120).read()
            if digest(data, 'sha1') != entry['sha1']:
                raise ValueError('Android archive checksum mismatch')
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                prefix = archive.namelist()[0].split('/')[0] + '/'
                for item in archive.infolist():
                    safe_name(item.filename)
                    rel = item.filename.removeprefix(prefix)
                    if item.is_dir() or not rel:
                        continue
                    file = target / rel
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_bytes(archive.read(item))
                    mode = item.external_attr >> 16
                    if mode:
                        file.chmod(mode)
            marker.write_text(entry['sha1'])
        metadata_targets = {'platform': sdk / LOCK['android']['archives']['platform']['destination'] / 'package.xml',
                            'build-tools': sdk / LOCK['android']['archives'][system]['destination'] / 'package.xml',
                            'platform-tools': sdk / 'platform-tools/package.xml',
                            'license': sdk / 'licenses/android-sdk-license'}
        for name, entry in LOCK['android']['metadata'].items():
            payload = (RUNTIME / entry['path']).read_bytes()
            if digest(payload) != entry['sha256']:
                raise ValueError('Android metadata checksum mismatch: ' + name)
            target = metadata_targets[name]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
    result = {'schemaVersion': 1, 'materials': str(materials), 'maven': str(maven), 'androidSdk': str(LOCAL / 'android-sdk'), 'javaHome': str(java_home), 'lockSha256': digest(LOCK_BYTES), 'seedSha256': LOCK['seed']['sha256']}
    (LOCAL / 'prepared-runtime.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=Path)
    parser.add_argument('--android', action='store_true')
    args = parser.parse_args()
    print(json.dumps(prepare(args.seed, args.android), indent=2))
