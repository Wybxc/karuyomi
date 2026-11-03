#!/usr/bin/env python3
"""Resumable local bootstrap and bounded incremental private-release pipeline."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

from catalog import ROOT, HOST_PATHS, canonical, digest, git, host_fingerprint, host_submodules, scan
from releases import GitHub, download_release, publish_immutable


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(canonical(value) + b'\n')
    os.replace(temporary, path)


def empty_state():
    return {'schemaVersion': 1, 'bootstrap': {'complete': False}, 'attempts': {}, 'active': {}, 'remoteIndexTag': None}


def load_state(path):
    state = read_json(path) if Path(path).exists() else empty_state()
    if state.get('schemaVersion') != 1 or not isinstance(state.get('attempts'), dict) or not isinstance(state.get('active'), dict):
        raise ValueError('Invalid extension checkpoint')
    return state


def ci_environment():
    return os.environ.get('GITHUB_ACTIONS') == 'true' or os.environ.get('CI') == 'true'


def make_plan(catalog, state, limit=12, ci=False, retry_failed=False):
    if ci and state.get('bootstrap', {}).get('complete') is not True:
        raise ValueError('CI bootstrap guard: finish and publish the initial local baseline first')
    if ci and retry_failed:
        raise ValueError('CI cannot retry an unchanged full failure baseline')
    if not 1 <= limit <= (24 if ci else 10000):
        raise ValueError('Invalid batch limit')
    repository_commit = git(ROOT, 'rev-parse', 'HEAD')
    pinned_submodules = host_submodules()
    entries = [{**entry, 'hostRepositoryCommit': repository_commit, 'hostSubmodules': pinned_submodules}
               for entry in catalog['entries']]
    pending = []
    for entry in entries:
        previous = state['attempts'].get(entry['inputFingerprint'])
        if previous is None or (previous['status'] == 'failed' and
                (retry_failed or previous.get('retryable') and previous.get('attempts', 0) < 3)):
            pending.append(entry)
    return {**catalog, 'entries': entries, 'repositoryCommit': repository_commit,
            'selected': pending[:limit], 'pendingCount': len(pending),
            'remainingCount': max(0, len(pending) - limit), 'ci': ci}


def verify_output(directory, descriptor=None):
    directory = Path(directory)
    if directory.is_symlink() or any(file.is_symlink() for file in directory.rglob('*')):
        raise ValueError('Build output must not contain symlinks')
    for name in ['manifest.json', 'validation.json', 'provenance.json']:
        if (directory / name).exists() and (directory / name).stat().st_size > 2 * 1024 * 1024:
            raise ValueError('Oversized build metadata')
    manifest = read_json(directory / 'manifest.json')
    spec = importlib.util.spec_from_file_location('registered_build', ROOT / 'scripts/register-build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    artifacts = module.verify(manifest, directory / 'artifacts')
    if descriptor and (manifest['packageName'] != descriptor['packageName'] or
                       manifest['buildId'] != descriptor['buildId'] or manifest['version'] != descriptor['versionName']):
        raise ValueError('Build output differs from its pinned descriptor')
    validation_path = directory / 'validation.json'
    validation = read_json(validation_path) if validation_path.exists() else {
        'schemaVersion': 1, 'valid': False, 'buildId': manifest['buildId'],
        'manifestSha256': digest((directory / 'manifest.json').read_bytes()),
        'stages': {'artifactIntegrity': 'passed', 'workerInit': 'not_run', 'browserLoad': 'not_run'},
        'failure': {'code': 'browser_not_run', 'message': 'Compilation is not browser compatibility evidence'},
    }
    stages = validation.get('stages', {})
    verified = (validation.get('valid') is True and stages.get('artifactIntegrity') == 'passed' and
                stages.get('workerInit') == 'passed' and stages.get('browserLoad') == 'passed' and
                validation.get('buildId') == manifest['buildId'] and
                validation.get('manifestSha256') == digest((directory / 'manifest.json').read_bytes()))
    validation['runtimeReady'] = verified
    return manifest, artifacts, validation


def release_files(directory, descriptor):
    directory = Path(directory)
    manifest, artifacts, validation = verify_output(directory, descriptor)
    provenance = {'schemaVersion': 1, 'kind': 'source-aot', 'descriptor': descriptor,
                  'manifestSha256': digest((directory / 'manifest.json').read_bytes()),
                  'validationStatus': 'browser_verified' if validation['runtimeReady'] else 'compiled_unverified'}
    files = {sha: directory / 'artifacts' / sha for sha in artifacts}
    files['manifest.json'] = directory / 'manifest.json'
    files['provenance.json'] = canonical(provenance) + b'\n'
    files['validation.json'] = canonical(validation) + b'\n'
    if (directory / 'provenance.json').exists():
        files['build-provenance.json'] = directory / 'provenance.json'
    return files, provenance, validation


def restore_build(api, descriptor, output):
    with tempfile.TemporaryDirectory(prefix='karuyomi-release-') as folder:
        if not download_release(api, descriptor['releaseTag'], folder):
            return False
        folder = Path(folder)
        provenance = read_json(folder / 'provenance.json')
        previous = provenance.get('descriptor', {})
        if provenance.get('kind') != 'source-aot' or any(previous.get(key) != descriptor.get(key) for key in
                ['packageName', 'versionCode', 'inputFingerprint', 'sourceFingerprint', 'hostFingerprint']):
            raise ValueError('Existing release has different source provenance')
        output.mkdir(parents=True, exist_ok=True)
        (output / 'artifacts').mkdir(exist_ok=True)
        for file in folder.iterdir():
            if len(file.name) == 64 and all(c in '0123456789abcdef' for c in file.name):
                shutil.copyfile(file, output / 'artifacts' / file.name)
            elif file.name in {'manifest.json', 'validation.json'}:
                shutil.copyfile(file, output / file.name)
            elif file.name == 'build-provenance.json':
                shutil.copyfile(file, output / 'provenance.json')
        verify_output(output, descriptor)
        write_json(output / 'pipeline-result.json', {'status': 'built', 'restored': True,
                   'descriptor': descriptor, 'releaseDescriptor': previous})
        return True


def build_one(descriptor, output, repository=None):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = {'schemaVersion': 1, 'descriptor': descriptor, 'status': 'failed'}
    try:
        if repository and restore_build(GitHub(repository), descriptor, output):
            return read_json(output / 'pipeline-result.json')
        current, _inputs = host_fingerprint()
        if current != descriptor['hostFingerprint']:
            raise ValueError('Host inputs changed since planning')
        source = ROOT / 'vendor/extensions-source'
        if git(source, 'rev-parse', 'HEAD') != descriptor['upstreamCommit']:
            raise ValueError('Source checkout differs from the planned commit')
        descriptor_path = output / 'descriptor.json'
        write_json(descriptor_path, descriptor)
        with (output / 'build.log').open('w') as log:
            build_environment = {key: value for key, value in os.environ.items()
                                 if key not in {'GH_TOKEN', 'GITHUB_TOKEN'}}
            subprocess.run([sys.executable, str(ROOT / 'scripts/build-extension.py'),
                            '--descriptor', str(descriptor_path), '--output', str(output)],
                           cwd=ROOT, env=build_environment, stdout=log, stderr=subprocess.STDOUT, check=True)
        _manifest, _artifacts, validation = verify_output(output, descriptor)
        write_json(output / 'validation.json', validation)
        result.update(status='built', validationStatus='browser_verified' if validation['runtimeReady'] else 'compiled_unverified')
    except Exception as error:
        # Do not publish build logs, arbitrary upstream stderr or environment.
        result['failure'] = {'stage': 'build', 'code': type(error).__name__, 'message': str(error)[:500]}
        failure_path = output / 'build-result.json'
        if isinstance(error, subprocess.CalledProcessError) and failure_path.is_file():
            failure = read_json(failure_path).get('failure', {})
            if failure.get('stage') in {'upstream', 'host', 'aot', 'complete'}:
                result['failure'] = {'stage': failure['stage'], 'code': str(failure.get('code', 'build_failed'))[:100],
                                     'message': str(failure.get('message', 'Build failed'))[:500]}
        result['retryable'] = isinstance(error, RuntimeError) and str(error).startswith('GitHub')
    write_json(output / 'pipeline-result.json', result)
    return result


def record_result(state, descriptor, result, directory, api=None, target=None):
    key = descriptor['inputFingerprint']
    attempts = state['attempts'].get(key, {}).get('attempts', 0) + 1
    record = {'descriptor': descriptor, 'status': 'failed', 'attempts': attempts, 'retryable': False}
    if result.get('descriptor') != descriptor or result.get('status') != 'built':
        record['failure'] = result.get('failure', {'stage': 'build', 'code': 'missing_result', 'message': 'No matching successful build output'})
        record['retryable'] = result.get('retryable') is True
    elif api is None:
        record['status'] = 'built'
    else:
        try:
            release_descriptor = result.get('releaseDescriptor', descriptor)
            if any(release_descriptor.get(key) != descriptor.get(key) for key in
                   ['packageName', 'versionCode', 'versionName', 'inputFingerprint', 'sourceFingerprint', 'hostFingerprint', 'buildId']):
                raise ValueError('Restored release does not match planned identity')
            files, provenance, validation = release_files(directory, release_descriptor)
            record['descriptor'] = release_descriptor
            record['release'] = publish_immutable(api, descriptor['releaseTag'], files, target)
            record.update(status='published', validationStatus=provenance['validationStatus'], runtimeReady=validation['runtimeReady'])
            state['active'][descriptor['packageName']] = key
        except Exception as error:
            record.update(retryable=isinstance(error, RuntimeError), failure={'stage': 'publish', 'code': type(error).__name__, 'message': str(error)[:500]})
    state['attempts'][key] = record
    return record


def finalize_baseline(state, catalog, local=True):
    if not local or ci_environment():
        raise ValueError('CI cannot create or finalize the initial baseline')
    records = [state['attempts'].get(entry['inputFingerprint']) for entry in catalog['entries']]
    if any(record is None or record['status'] not in {'published', 'failed'} for record in records):
        raise ValueError('Initial baseline still has unattempted or unpublished packages')
    state['bootstrap'] = {'complete': True, 'upstreamCommit': catalog['upstreamCommit'],
                          'catalogFingerprint': catalog['catalogFingerprint'],
                          'published': sum(r['status'] == 'published' for r in records),
                          'failed': sum(r['status'] == 'failed' for r in records),
                          'discoveryFailed': len(catalog['discoveryFailures'])}


def index_payload(state, catalog):
    current = {entry['packageName']: entry for entry in catalog['entries']}
    packages, failures, pending = [], list(catalog['discoveryFailures']), 0
    for package, descriptor in sorted(current.items()):
        record = state['attempts'].get(descriptor['inputFingerprint'])
        if record is None or record['status'] == 'built':
            pending += 1
        elif record['status'] == 'failed':
            failures.append({'packageName': package, 'inputFingerprint': descriptor['inputFingerprint'], 'failure': record['failure']})
        active = state['attempts'].get(state['active'].get(package))
        if active and active['status'] == 'published':
            packages.append({'packageName': package, 'buildId': active['descriptor']['buildId'],
                             'versionName': active['descriptor']['versionName'], 'release': active['release'],
                             'runtimeReady': active['runtimeReady'], 'validationStatus': active['validationStatus'],
                             'inputFingerprint': active['descriptor']['inputFingerprint'],
                             'stale': active['descriptor']['inputFingerprint'] != descriptor['inputFingerprint']})
    return {'schemaVersion': 1, 'upstreamCommit': catalog['upstreamCommit'],
            'catalogFingerprint': catalog['catalogFingerprint'], 'bootstrap': state['bootstrap'],
            'packages': packages, 'failures': failures, 'pending': pending}


def publish_index(api, state, catalog, target):
    latest = api.latest()
    expected = state.get('remoteIndexTag')
    actual = latest['tag_name'] if latest and latest['tag_name'].startswith('extensions-index-') else None
    if expected != actual:
        raise ValueError('Remote index advanced; pull and merge its checkpoint before publishing')
    current = {entry['packageName']: entry['inputFingerprint'] for entry in catalog['entries']}
    state['active'] = {package: key for package, key in state['active'].items() if package in current}
    retained = set(current.values()) | set(state['active'].values())
    state['attempts'] = {key: value for key, value in state['attempts'].items() if key in retained}
    index = index_payload(state, catalog)
    index_bytes = canonical(index) + b'\n'
    snapshot = {key: value for key, value in state.items() if key != 'remoteIndexTag'}
    state_bytes = canonical(snapshot) + b'\n'
    tag = 'extensions-index-' + digest(canonical({'index': digest(index_bytes), 'state': digest(state_bytes)}))[:32]
    publish_immutable(api, tag, {'index.json': index_bytes, 'state.json': state_bytes}, target, latest=True)
    state['remoteIndexTag'] = tag
    return tag


def pull_state(api, path):
    latest = api.latest()
    if not latest or not latest['tag_name'].startswith('extensions-index-'):
        write_json(path, empty_state())
        return
    with tempfile.TemporaryDirectory(prefix='karuyomi-index-') as folder:
        download_release(api, latest['tag_name'], folder)
        state = load_state(Path(folder) / 'state.json')
        state['remoteIndexTag'] = latest['tag_name']
        write_json(path, state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ['plan', 'bootstrap']:
        command = commands.add_parser(name)
        command.add_argument('--source', type=Path, default=ROOT / 'vendor/extensions-source')
        command.add_argument('--state', type=Path, required=True)
        command.add_argument('--output', type=Path, required=True)
        command.add_argument('--limit', type=int, default=12 if name == 'plan' else 10000)
        command.add_argument('--retry-failed', action='store_true')
        command.add_argument('--ci', action='store_true')
        if name == 'bootstrap':
            command.add_argument('--repository', default='Wybxc/karuyomi')
            command.add_argument('--jobs', type=int, default=1)
            command.add_argument('--finalize', action='store_true')
    command = commands.add_parser('build')
    command.add_argument('--plan', type=Path, required=True)
    command.add_argument('--key', required=True)
    command.add_argument('--output', type=Path, required=True)
    command.add_argument('--repository')
    command = commands.add_parser('publish-plan')
    command.add_argument('--plan', type=Path, required=True)
    command.add_argument('--state', type=Path, required=True)
    command.add_argument('--results', type=Path, required=True)
    command.add_argument('--repository', default='Wybxc/karuyomi')
    command = commands.add_parser('pull-state')
    command.add_argument('--state', type=Path, required=True)
    command.add_argument('--repository', default='Wybxc/karuyomi')
    command = commands.add_parser('import-legacy')
    command.add_argument('--manifest', type=Path, required=True)
    command.add_argument('--artifacts', type=Path, required=True)
    command.add_argument('--provenance', type=Path, required=True)
    command.add_argument('--validation', type=Path)
    command.add_argument('--dry-run', action='store_true')
    command.add_argument('--repository', default='Wybxc/karuyomi')
    args = parser.parse_args()
    state_lock = None
    if hasattr(args, 'state'):
        import fcntl
        args.state.parent.mkdir(parents=True, exist_ok=True)
        state_lock = args.state.with_suffix('.lock').open('a')
        try:
            fcntl.flock(state_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error('Another process owns this extension checkpoint')
    if args.command == 'pull-state':
        pull_state(GitHub(args.repository), args.state)
        return
    if args.command == 'import-legacy':
        with tempfile.TemporaryDirectory(prefix='karuyomi-legacy-') as folder:
            folder = Path(folder)
            shutil.copyfile(args.manifest, folder / 'manifest.json')
            (folder / 'artifacts').mkdir()
            source_manifest = read_json(args.manifest)
            for artifact in [source_manifest['bundle'], *source_manifest['hostScripts'], *source_manifest.get('resources', [])]:
                sha = artifact['sha256']
                if len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
                    raise ValueError('Invalid legacy artifact reference')
                shutil.copyfile(args.artifacts / sha, folder / 'artifacts' / sha)
            if args.validation:
                shutil.copyfile(args.validation, folder / 'validation.json')
            manifest, artifacts, validation = verify_output(folder)
            tag = 'legacy-' + manifest['buildId']
            if len(tag) > 200 or not all(c.isalnum() or c in '._-' for c in tag):
                raise ValueError('Invalid legacy build ID')
            provenance = {'schemaVersion': 1, 'kind': 'legacy-frozen',
                          'currentSourceBaseline': False, 'originalProvenance': read_json(args.provenance),
                          'manifestSha256': digest(args.manifest.read_bytes())}
            files = {sha: folder / 'artifacts' / sha for sha in artifacts}
            files.update({'manifest.json': folder / 'manifest.json', 'provenance.json': canonical(provenance) + b'\n',
                          'validation.json': canonical(validation) + b'\n'})
            if args.dry_run:
                print(json.dumps({'tag': tag, 'kind': 'legacy-frozen', 'currentSourceBaseline': False,
                                  'runtimeReady': validation['runtimeReady'], 'assets': sorted(files),
                                  'totalBytes': sum((value.stat().st_size if isinstance(value, Path) else len(value)) for value in files.values())}, indent=2))
            else:
                print(json.dumps(publish_immutable(GitHub(args.repository), tag, files, git(ROOT, 'rev-parse', 'HEAD'))))
        return
    if args.command in {'plan', 'bootstrap'}:
        if args.command == 'bootstrap' and (args.ci or ci_environment()):
            parser.error('Initial full bootstrap is local-only')
        if args.command == 'bootstrap' and git(ROOT, 'status', '--porcelain', '--', *HOST_PATHS):
            parser.error('Commit the reviewed host/toolchain inputs before publishing the initial source baseline')
        host, inputs = host_fingerprint()
        catalog = scan(args.source, host, inputs)
        state = load_state(args.state)
        plan = make_plan(catalog, state, args.limit, args.ci or ci_environment(), args.retry_failed)
        write_json(args.output, plan)
        print(json.dumps({'discovered': len(catalog['entries']), 'discoveryFailures': len(catalog['discoveryFailures']),
                          'selected': len(plan['selected']), 'remaining': plan['remainingCount']}), flush=True)
        if args.command == 'plan':
            return
        if not 1 <= args.jobs <= 4:
            parser.error('--jobs must be between 1 and 4')
        api = GitHub(args.repository)
        builds = args.output.parent / 'builds'
        pool = ThreadPoolExecutor(max_workers=args.jobs)
        try:
            futures = {pool.submit(build_one, entry, builds / entry['inputFingerprint'], args.repository): entry for entry in plan['selected']}
            for future in as_completed(futures):
                descriptor = futures[future]
                record = record_result(state, descriptor, future.result(), builds / descriptor['inputFingerprint'], api, plan['repositoryCommit'])
                write_json(args.state, state)
                print(descriptor['packageName'] + ': ' + record['status'], flush=True)
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
        if args.finalize:
            finalize_baseline(state, catalog)
        publish_index(api, state, catalog, plan['repositoryCommit'])
        write_json(args.state, state)
    elif args.command == 'build':
        plan = read_json(args.plan)
        descriptor = next(e for e in plan['selected'] if e['inputFingerprint'] == args.key)
        result = build_one(descriptor, args.output, args.repository)
        print(json.dumps({'packageName': descriptor['packageName'], 'status': result['status']}))
        if result['status'] != 'built':
            sys.exit(1)
    elif args.command == 'publish-plan':
        plan, state, api = read_json(args.plan), load_state(args.state), GitHub(args.repository)
        for descriptor in plan['selected']:
            matches = list(args.results.rglob('pipeline-result.json'))
            directory = next((p.parent for p in matches if read_json(p).get('descriptor') == descriptor), None)
            result = read_json(directory / 'pipeline-result.json') if directory else {
                'status': 'failed', 'retryable': True,
                'failure': {'stage': 'build', 'code': 'missing_result', 'message': 'No matrix output was produced'},
            }
            record_result(state, descriptor, result, directory, api, plan['repositoryCommit'])
            write_json(args.state, state)
        publish_index(api, state, plan, plan['repositoryCommit'])
        write_json(args.state, state)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError) as error:
        print('extensions: ' + str(error), file=sys.stderr)
        sys.exit(2)
