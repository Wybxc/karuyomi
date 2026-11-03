"""No network or external runtimes: source identities and release safety."""
from pathlib import Path
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.request
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog
import pipeline
from releases import SafeRedirect, download_release, publish_immutable


class FakeGitHub:
    def __init__(self):
        self.releases, self.content, self.events = {}, {}, []
        self.latest_tag = None
        self.fail_on_upload = None

    def find_release(self, tag):
        return self.releases.get(tag)

    def latest(self):
        return self.find_release(self.latest_tag)

    def create_release(self, tag, target):
        release = {'id': len(self.releases) + 1, 'tag_name': tag, 'draft': True, 'html_url': 'https://example.invalid/' + tag, 'assets': []}
        self.releases[tag] = release
        self.events.append(('draft', tag))
        return release

    def assets(self, release):
        return release['assets']

    def upload(self, release, name, data):
        if self.fail_on_upload == name:
            self.fail_on_upload = None
            raise RuntimeError('GitHub simulated interruption')
        self.events.append(('upload', release['tag_name'], name))
        asset = {'id': len(self.content) + 1, 'name': name, 'size': len(data), 'digest': 'sha256:' + catalog.digest(data)}
        release['assets'].append(asset)
        self.content[asset['id']] = data
        return asset

    def download(self, asset):
        return self.content[asset['id']]

    def publish(self, release, latest=False):
        release['draft'] = False
        if latest:
            self.latest_tag = release['tag_name']
        self.events.append(('publish', release['tag_name'], latest))
        return release


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        for name in catalog.SHARED_PATHS:
            if '.' in Path(name).name or name.startswith('gradlew'):
                self.put(name, 'fixed build input\n')
            else:
                self.put(name + '/shared.txt', 'shared input\n')
        self.put('src/en/first/build.gradle.kts', 'keiyoushi {\nversionCode = 2\nlibVersion = "1.6"\ntheme = "theme"\n}\n')
        self.put('src/en/first/src/First.kt', 'class First\n')
        self.put('src/en/second/build.gradle.kts', 'keiyoushi {\nversionCode = 3\nlibVersion = "1.6"\n}\n')
        self.put('lib-multisrc/theme/build.gradle.kts', 'baseVersionCode = 7\nlibVersion = "1.6"\napi(project(":lib:helper"))\n')
        self.put('lib/helper/build.gradle.kts', 'implementation(project(":lib:leaf"))\n')
        self.put('lib/leaf/build.gradle.kts', 'plugins {}\n')
        self.commit()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)

    def commit(self):
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')

    def scan(self, host='0' * 64):
        return catalog.scan(self.root, host)

    def test_version_package_and_transitive_dependencies_match_gradle(self):
        result = self.scan()
        self.assertEqual(result['discoveryFailures'], [])
        first = result['entries'][0]
        self.assertEqual(first['packageName'], 'eu.kanade.tachiyomi.extension.en.first')
        self.assertEqual(first['versionName'], '1.6.9')
        self.assertEqual(first['versionCode'], 106009)
        self.assertEqual(set(first['sourceInputs']), {'src/en/first', 'lib-multisrc/theme', 'lib/helper', 'lib/leaf'})

    def test_same_version_transitive_library_change_invalidates_only_dependents(self):
        before = self.scan()['entries']
        self.put('lib/leaf/Leaf.kt', 'class Changed\n')
        self.commit()
        after = self.scan()['entries']
        self.assertNotEqual(before[0]['inputFingerprint'], after[0]['inputFingerprint'])
        self.assertEqual(before[1]['inputFingerprint'], after[1]['inputFingerprint'])

    def test_shared_build_and_host_changes_invalidate_without_version_bump(self):
        before = self.scan()['entries']
        self.put('core/shared.txt', 'changed shared core\n')
        self.commit()
        after = self.scan()['entries']
        self.assertTrue(all(a['inputFingerprint'] != b['inputFingerprint'] for a, b in zip(before, after)))
        changed_host = self.scan('1' * 64)['entries']
        self.assertTrue(all(a['inputFingerprint'] != b['inputFingerprint'] for a, b in zip(after, changed_host)))

    def test_unrelated_commit_does_not_force_all_extensions_to_rebuild(self):
        before = self.scan()
        self.put('README.md', 'unrelated upstream documentation\n')
        self.commit()
        after = self.scan()
        self.assertNotEqual(before['upstreamCommit'], after['upstreamCommit'])
        self.assertEqual([e['inputFingerprint'] for e in before['entries']], [e['inputFingerprint'] for e in after['entries']])

    def test_unsupported_dsl_isolated_and_dirty_source_refused(self):
        self.put('src/en/first/build.gradle.kts', 'versionCode = 1 + 2\nlibVersion = "1.6"\n')
        with self.assertRaisesRegex(ValueError, 'dirty'):
            self.scan()
        self.commit()
        result = self.scan()
        self.assertEqual(len(result['entries']), 1)
        self.assertEqual(len(result['discoveryFailures']), 1)
        self.assertIn('Unsupported expression', result['discoveryFailures'][0]['message'])

    def test_generated_host_files_do_not_change_fingerprint(self):
        before = catalog.tree_hash(self.root, 'lib')
        self.put('lib/target/classes/Generated.class', 'generated')
        self.put('lib/__pycache__/module.pyc', 'generated')
        self.assertEqual(before, catalog.tree_hash(self.root, 'lib'))


class ReleaseTests(unittest.TestCase):
    def test_interrupted_draft_resumes_and_published_retry_is_identical(self):
        api = FakeGitHub()
        api.fail_on_upload = 'manifest.json'
        files = {'a' * 64: b'bytes', 'manifest.json': b'{}'}
        with self.assertRaises(RuntimeError):
            publish_immutable(api, 'ext-test', files, 'main')
        self.assertTrue(api.find_release('ext-test')['draft'])
        publish_immutable(api, 'ext-test', files, 'main')
        count = len(api.content)
        publish_immutable(api, 'ext-test', files, 'main')
        self.assertEqual(len(api.content), count)
        self.assertFalse(api.find_release('ext-test')['draft'])
        self.assertEqual(api.events[-2][2], 'release-manifest.json')
        self.assertIsNone(api.latest_tag)

    def test_published_content_is_never_clobbered(self):
        api = FakeGitHub()
        publish_immutable(api, 'ext-test', {'manifest.json': b'first'}, 'main')
        before = copy.deepcopy(api.content)
        with self.assertRaisesRegex(ValueError, 'conflict'):
            publish_immutable(api, 'ext-test', {'manifest.json': b'other'}, 'main')
        self.assertEqual(api.content, before)

    def test_download_checks_all_bytes_and_rejects_extra_asset(self):
        api = FakeGitHub()
        publish_immutable(api, 'ext-test', {'manifest.json': b'{}'}, 'main')
        with tempfile.TemporaryDirectory() as folder:
            self.assertTrue(download_release(api, 'ext-test', folder))
            api.content[1] = b'broken'
            with self.assertRaisesRegex(ValueError, 'integrity'):
                download_release(api, 'ext-test', folder)

    def test_redirect_drops_private_token_across_hosts(self):
        request = urllib.request.Request('https://api.github.com/assets/1', headers={'Authorization': 'Bearer secret', 'Cookie': 'secret=1'})
        redirect = SafeRedirect().redirect_request(request, None, 302, 'Found', {}, 'https://release-assets.githubusercontent.com/file')
        self.assertIsNone(redirect.get_header('Authorization'))
        self.assertIsNone(redirect.get_header('Cookie'))
        with self.assertRaises(ValueError):
            SafeRedirect().redirect_request(request, None, 302, 'Found', {}, 'http://example.invalid/file')


class StateTests(unittest.TestCase):
    def fixture(self):
        entries = [{'packageName': 'fixture.' + str(i), 'inputFingerprint': str(i) * 64,
                    'versionName': '1.6.1', 'buildId': 'build-' + str(i)} for i in range(4)]
        return {'entries': entries, 'discoveryFailures': [], 'catalogFingerprint': 'catalog', 'upstreamCommit': 'upstream'}

    def test_ci_refuses_missing_baseline_and_caps_incremental_batches(self):
        state, source = pipeline.empty_state(), self.fixture()
        with self.assertRaisesRegex(ValueError, 'bootstrap guard'):
            pipeline.make_plan(source, state, ci=True)
        state['bootstrap']['complete'] = True
        plan = pipeline.make_plan(source, state, limit=2, ci=True)
        self.assertEqual(len(plan['selected']), 2)
        self.assertEqual(plan['remainingCount'], 2)
        with self.assertRaises(ValueError):
            pipeline.make_plan(source, state, limit=100, ci=True)

    def test_unchanged_failures_do_not_trigger_full_ci_retries(self):
        state, source = pipeline.empty_state(), self.fixture()
        state['bootstrap']['complete'] = True
        for entry in source['entries']:
            state['attempts'][entry['inputFingerprint']] = {'status': 'failed', 'retryable': False}
        self.assertEqual(pipeline.make_plan(source, state, ci=True)['selected'], [])
        self.assertEqual(len(pipeline.make_plan(source, state, retry_failed=True)['selected']), 4)

    def test_baseline_cannot_hide_unattempted_packages_or_claim_all_ready(self):
        state, source = pipeline.empty_state(), self.fixture()
        with self.assertRaisesRegex(ValueError, 'unattempted'):
            pipeline.finalize_baseline(state, source)
        for entry in source['entries']:
            state['attempts'][entry['inputFingerprint']] = {'status': 'failed'}
        with patch.dict(os.environ, {'CI': 'false', 'GITHUB_ACTIONS': 'false'}):
            pipeline.finalize_baseline(state, source)
        self.assertTrue(state['bootstrap']['complete'])
        self.assertEqual(state['bootstrap']['published'], 0)
        self.assertEqual(state['bootstrap']['failed'], 4)
        with patch.dict(os.environ, {'CI': 'true'}), self.assertRaises(ValueError):
            pipeline.finalize_baseline(state, source)

    def test_index_is_last_and_state_only_changes_get_new_immutable_snapshots(self):
        api, state, source = FakeGitHub(), pipeline.empty_state(), self.fixture()
        for entry in source['entries']:
            state['attempts'][entry['inputFingerprint']] = {'status': 'failed', 'failure': {'code': 'unsupported'}}
        first = pipeline.publish_index(api, state, source, 'main')
        self.assertEqual(api.events[-1], ('publish', first, True))
        state['attempts'][source['entries'][0]['inputFingerprint']]['attempts'] = 2
        second = pipeline.publish_index(api, state, source, 'main')
        self.assertNotEqual(first, second)
        self.assertEqual(api.latest_tag, second)
        stale = pipeline.empty_state()
        with self.assertRaisesRegex(ValueError, 'advanced'):
            pipeline.publish_index(api, stale, source, 'main')


class OutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.output = Path(self.temporary.name)
        self.data = b'const fixture = 1;'
        self.sha = catalog.digest(self.data)
        self.descriptor = {'packageName': 'example.fixture', 'buildId': 'fixture-build', 'versionName': '1.6.1',
                           'versionCode': 106001, 'sourceFingerprint': 's' * 64, 'hostFingerprint': 'h' * 64,
                           'inputFingerprint': 'i' * 64, 'upstreamCommit': 'old-commit', 'releaseTag': 'ext-fixture'}
        (self.output / 'artifacts').mkdir()
        (self.output / 'artifacts' / self.sha).write_bytes(self.data)
        manifest = {**json.loads((catalog.ROOT / 'packages/contracts/protocol.json').read_text()),
                    'bridgeVersion': 1, 'buildId': 'fixture-build', 'packageName': 'example.fixture', 'repoId': 'fixture',
                    'version': '1.6.1', 'storageSchema': '1', 'sourceIds': ['9223372036854775807'], 'hostScripts': [],
                    'bundle': {'sha256': self.sha, 'path': '/api/extensions/artifacts/' + self.sha, 'size': len(self.data)}}
        pipeline.write_json(self.output / 'manifest.json', manifest)
        pipeline.write_json(self.output / 'provenance.json', {'origin': 'fixture'})

    def tearDown(self):
        self.temporary.cleanup()

    def test_compilation_is_published_with_runtime_ready_false(self):
        api, state = FakeGitHub(), pipeline.empty_state()
        result = {'status': 'built', 'descriptor': self.descriptor}
        record = pipeline.record_result(state, self.descriptor, result, self.output, api, 'main')
        self.assertEqual(record['status'], 'published')
        self.assertFalse(record['runtimeReady'])
        self.assertEqual(record['validationStatus'], 'compiled_unverified')
        self.assertEqual(state['active']['example.fixture'], 'i' * 64)

    def test_corrupt_output_isolated_without_release_or_active_pointer(self):
        (self.output / 'artifacts' / self.sha).write_bytes(b'corrupt')
        api, state = FakeGitHub(), pipeline.empty_state()
        result = {'status': 'built', 'descriptor': self.descriptor}
        record = pipeline.record_result(state, self.descriptor, result, self.output, api, 'main')
        self.assertEqual(record['status'], 'failed')
        self.assertEqual(api.releases, {})
        self.assertEqual(state['active'], {})

    def test_restore_survives_unrelated_upstream_commit_without_rebuilding(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(self.output, self.descriptor)
        publish_immutable(api, self.descriptor['releaseTag'], files, 'main')
        current = {**self.descriptor, 'upstreamCommit': 'new-unrelated-commit'}
        restored = self.output / 'restored'
        self.assertTrue(pipeline.restore_build(api, current, restored))
        result = pipeline.read_json(restored / 'pipeline-result.json')
        state = pipeline.empty_state()
        record = pipeline.record_result(state, current, result, restored, api, 'main')
        self.assertEqual(record['status'], 'published')
        self.assertEqual(record['descriptor']['upstreamCommit'], 'old-commit')

    def test_symlink_in_untrusted_build_output_is_rejected(self):
        (self.output / 'provenance.json').unlink()
        (self.output / 'provenance.json').symlink_to('/etc/hosts')
        with self.assertRaisesRegex(ValueError, 'symlink'):
            pipeline.verify_output(self.output, self.descriptor)


if __name__ == '__main__':
    unittest.main()
