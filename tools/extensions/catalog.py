"""Pinned Keiyoushi source-tree discovery; never executes upstream Gradle."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HOST_PATHS = [
    'runtime/teavm/java', 'runtime/teavm/bridge', 'runtime/teavm/patches/teavm', 'runtime/teavm/toolchain', 'runtime/teavm/toolchain-lock.json',
    'scripts/prepare-runtime.py', 'scripts/build-extension.py', 'packages/contracts/protocol.json',
    'packages/runtime-host/materials.mjs', 'packages/runtime-host/prepare-materials.mjs',
    'packages/runtime-host/package.json', 'pnpm-lock.yaml',
    '.gitmodules', 'tools/teavm/build.py', 'tools/teavm/PatchLibraries.java', 'tools/teavm/upstream_sources.py',
]
SHARED_PATHS = ['common', 'core', 'compiler', 'gradle', 'build.gradle.kts',
                'settings.gradle.kts', 'gradle.properties', 'gradlew', 'gradlew.bat']


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(source, *arguments):
    return subprocess.check_output(['git', '-C', str(source), *arguments], text=True).strip()


def tree_hash(root, relative, tracked=None):
    path = root / relative
    if not path.exists():
        raise ValueError('Missing fingerprint input: ' + relative)
    files = [path] if path.is_file() else sorted(p for p in path.rglob('*') if p.is_file())
    records = {}
    for file in files:
        name = file.relative_to(root).as_posix()
        if tracked is not None and name not in tracked:
            continue
        if tracked is None and (any(part in {'.git', '.local', 'target', 'build', '__pycache__', 'node_modules', 'verification', 'probes'} for part in file.relative_to(root).parts)
                                or file.suffix in {'.pyc', '.class'}):
            continue
        if file.is_symlink():
            raise ValueError('Symlink fingerprint input: ' + name)
        records[name] = {'sha256': digest(file.read_bytes()), 'executable': bool(file.stat().st_mode & 0o111)}
    return digest(canonical(records))


def host_submodules(root=ROOT):
    pins = []
    for line in git(root, 'ls-files', '--stage').splitlines():
        metadata, name = line.split('\t', 1)
        if metadata.startswith('160000 ') and name != 'vendor/extensions-source':
            pins.append({'path': name, 'gitlink': metadata.split()[1],
                         'checkout': git(root / name, 'rev-parse', 'HEAD')})
    return pins


def host_fingerprint(root=ROOT):
    inputs = {name: tree_hash(root, name) for name in HOST_PATHS}
    pins = host_submodules(root)
    return digest(canonical({'schemaVersion': 1, 'inputs': inputs, 'pinnedSubmodules': pins})), inputs


def literal(text, name, kind, default=None):
    # Unsupported Kotlin expressions are explicit per-package failures; guessing
    # a version can assign different source bytes the same immutable identity.
    assignments = re.findall(r'^\s*' + re.escape(name) + r'\s*=\s*(.*?)\s*$', text, re.M)
    if not assignments:
        if default is not None:
            return default
        raise ValueError('Missing literal ' + name)
    if len(assignments) != 1:
        raise ValueError('Ambiguous ' + name)
    value = re.sub(r'\s+//.*$', '', assignments[0]).strip()
    pattern = r'\d+' if kind is int else r'"[^"$\n]+"'
    if not re.fullmatch(pattern, value):
        raise ValueError('Unsupported expression for ' + name)
    return int(value) if kind is int else value[1:-1]


def module_text(source, relative):
    text = (source / relative / 'build.gradle.kts').read_text()
    return re.sub(r'/\*.*?\*/|^\s*//[^\n]*', '', text, flags=re.S | re.M)


def dependencies(source, relative):
    pending, seen = [relative], set()
    while pending:
        item = pending.pop()
        if item in seen:
            continue
        seen.add(item)
        text = module_text(source, item)
        refs = re.findall(r'\bproject\(\s*["\'](:[^"\']+)["\']\s*\)', text)
        if len(refs) != len(re.findall(r'\bproject\s*\(', text)):
            raise ValueError('Unsupported dynamic project dependency: ' + item)
        for ref in refs:
            if not re.fullmatch(r':(?:lib|lib-multisrc):[a-zA-Z0-9_-]+', ref):
                raise ValueError('Unsupported project dependency: ' + ref)
            pending.append(ref.lstrip(':').replace(':', '/'))
        theme = literal(text, 'theme', str, '')
        if theme:
            if not re.fullmatch(r'[a-zA-Z0-9_-]+', theme):
                raise ValueError('Invalid theme')
            pending.append('lib-multisrc/' + theme)
    return sorted(seen)


def scan(source, host_hash, host_inputs=None, require_clean=True):
    source = Path(source).resolve()
    commit = git(source, 'rev-parse', 'HEAD')
    if require_clean and git(source, 'status', '--porcelain', '--untracked-files=no'):
        raise ValueError('Upstream tracked files are dirty; refusing unpinned inputs')
    tracked = set(git(source, 'ls-tree', '-r', '--name-only', 'HEAD').splitlines())
    cache = {}

    def hashed(name):
        if name not in cache:
            cache[name] = tree_hash(source, name, tracked)
        return cache[name]

    shared = {name: hashed(name) for name in SHARED_PATHS}
    entries, failures, packages = [], [], set()
    for name in sorted(n for n in tracked if re.fullmatch(r'src/[^/]+/[^/]+/build.gradle.kts', n)):
        relative = str(Path(name).parent)
        try:
            text = module_text(source, relative)
            suffix = literal(text, 'pkgName', str, '.'.join(Path(relative).parts[1:]))
            if not re.fullmatch(r'\w+(?:\.\w+)+', suffix, re.ASCII):
                raise ValueError('Invalid package suffix')
            package = 'eu.kanade.tachiyomi.extension.' + suffix
            if package in packages:
                raise ValueError('Duplicate package name: ' + package)
            declared = literal(text, 'versionCode', int)
            lib = literal(text, 'libVersion', str)
            if not re.fullmatch(r'\d{1,2}\.\d{1,2}', lib):
                raise ValueError('Unsupported libVersion')
            effective = declared
            theme = literal(text, 'theme', str, '')
            if theme:
                theme_text = module_text(source, 'lib-multisrc/' + theme)
                if literal(theme_text, 'libVersion', str) != lib:
                    raise ValueError('Theme libVersion mismatch')
                effective += literal(theme_text, 'baseVersionCode', int)
            version = int(''.join(part.zfill(2) for part in lib.split('.'))) * 1000 + effective
            inputs = {item: hashed(item) for item in dependencies(source, relative)}
            source_hash = digest(canonical({'modules': inputs, 'shared': shared}))
            identity = {'packageName': package, 'versionCode': version,
                        'sourceFingerprint': source_hash, 'hostFingerprint': host_hash}
            fingerprint = digest(canonical(identity))
            slug = re.sub(r'[^a-zA-Z0-9._-]', '-', suffix)[:80]
            entries.append({'schemaVersion': 1, **identity, 'sourcePath': relative,
                            'upstreamCommit': commit, 'declaredVersionCode': declared,
                            'effectiveVersionCode': effective, 'versionName': lib + '.' + str(effective),
                            'sourceInputs': inputs, 'sharedInputs': shared,
                            'hostInputs': host_inputs or {}, 'inputFingerprint': fingerprint,
                            'buildId': 'ext-' + slug + '-' + fingerprint[:32],
                            'releaseTag': 'ext-' + slug + '-v' + str(version) + '-' + fingerprint[:32]})
            packages.add(package)
        except (ValueError, FileNotFoundError) as error:
            failures.append({'sourcePath': relative, 'status': 'discovery_failed', 'message': str(error)})
    if not entries and not failures:
        raise ValueError('No extension modules found in the pinned source tree')
    return {'schemaVersion': 1, 'upstreamCommit': commit, 'hostFingerprint': host_hash,
            'catalogFingerprint': digest(canonical({'entries': [e['inputFingerprint'] for e in entries], 'failures': failures})),
            'entries': entries, 'discoveryFailures': failures}
