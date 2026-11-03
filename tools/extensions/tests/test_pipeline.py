"""No network or external runtimes: source identities and release safety."""

from pathlib import Path
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.request
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog
import pipeline
from releases import (
    SafeRedirect,
    download_release,
    encode_artifact,
    publish_immutable,
    restore_artifacts,
)


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
        release = {
            "id": len(self.releases) + 1,
            "tag_name": tag,
            "draft": True,
            "html_url": "https://example.invalid/" + tag,
            "assets": [],
        }
        self.releases[tag] = release
        self.events.append(("draft", tag))
        return release

    def assets(self, release):
        return release["assets"]

    def upload(self, release, name, data):
        if self.fail_on_upload == name:
            self.fail_on_upload = None
            raise RuntimeError("GitHub simulated interruption")
        self.events.append(("upload", release["tag_name"], name))
        asset = {
            "id": len(self.content) + 1,
            "name": name,
            "size": len(data),
            "digest": "sha256:" + catalog.digest(data),
        }
        release["assets"].append(asset)
        self.content[asset["id"]] = data
        return asset

    def download(self, asset):
        return self.content[asset["id"]]

    def publish(self, release, latest=False):
        release["draft"] = False
        if latest:
            self.latest_tag = release["tag_name"]
        self.events.append(("publish", release["tag_name"], latest))
        return release


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        for name in catalog.SHARED_PATHS:
            if "." in Path(name).name or name.startswith("gradlew"):
                self.put(name, "fixed build input\n")
            else:
                self.put(name + "/shared.txt", "shared input\n")
        self.put(
            "src/en/first/build.gradle.kts",
            'keiyoushi {\nversionCode = 2\nlibVersion = "1.6"\ntheme = "theme"\n}\n',
        )
        self.put("src/en/first/src/First.kt", "class First\n")
        self.put(
            "src/en/second/build.gradle.kts",
            'keiyoushi {\nversionCode = 3\nlibVersion = "1.6"\n}\n',
        )
        self.put(
            "lib-multisrc/theme/build.gradle.kts",
            'baseVersionCode = 7\nlibVersion = "1.6"\napi(project(":lib:helper"))\n',
        )
        self.put(
            "lib/helper/build.gradle.kts", 'implementation(project(":lib:leaf"))\n'
        )
        self.put("lib/leaf/build.gradle.kts", "plugins {}\n")
        self.commit()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-C", str(self.root), *args], text=True
        ).strip()

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)

    def commit(self):
        self.git("add", ".")
        self.git(
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "fixture",
        )

    def scan(self, host="0" * 64):
        return catalog.scan(self.root, host)

    def test_version_package_and_transitive_dependencies_match_gradle(self):
        result = self.scan()
        self.assertEqual(result["discoveryFailures"], [])
        first = result["entries"][0]
        self.assertEqual(first["packageName"], "eu.kanade.tachiyomi.extension.en.first")
        self.assertEqual(first["versionName"], "1.6.9")
        self.assertEqual(first["versionCode"], 106009)
        self.assertEqual(
            set(first["sourceInputs"]),
            {"src/en/first", "lib-multisrc/theme", "lib/helper", "lib/leaf"},
        )

    def test_same_version_transitive_library_change_invalidates_only_dependents(self):
        before = self.scan()["entries"]
        self.put("lib/leaf/Leaf.kt", "class Changed\n")
        self.commit()
        after = self.scan()["entries"]
        self.assertNotEqual(before[0]["inputFingerprint"], after[0]["inputFingerprint"])
        self.assertEqual(before[1]["inputFingerprint"], after[1]["inputFingerprint"])

    def test_shared_build_and_host_changes_invalidate_without_version_bump(self):
        before = self.scan()["entries"]
        self.put("core/shared.txt", "changed shared core\n")
        self.commit()
        after = self.scan()["entries"]
        self.assertTrue(
            all(
                a["inputFingerprint"] != b["inputFingerprint"]
                for a, b in zip(before, after)
            )
        )
        changed_host = self.scan("1" * 64)["entries"]
        self.assertTrue(
            all(
                a["inputFingerprint"] != b["inputFingerprint"]
                for a, b in zip(after, changed_host)
            )
        )

    def test_unrelated_commit_does_not_force_all_extensions_to_rebuild(self):
        before = self.scan()
        self.put("README.md", "unrelated upstream documentation\n")
        self.commit()
        after = self.scan()
        self.assertNotEqual(before["upstreamCommit"], after["upstreamCommit"])
        self.assertEqual(
            [e["inputFingerprint"] for e in before["entries"]],
            [e["inputFingerprint"] for e in after["entries"]],
        )

    def test_unsupported_dsl_isolated_and_dirty_source_refused(self):
        self.put(
            "src/en/first/build.gradle.kts", 'versionCode = 1 + 2\nlibVersion = "1.6"\n'
        )
        with self.assertRaisesRegex(ValueError, "dirty"):
            self.scan()
        self.commit()
        result = self.scan()
        self.assertEqual(len(result["entries"]), 1)
        self.assertEqual(len(result["discoveryFailures"]), 1)
        self.assertIn(
            "Unsupported expression", result["discoveryFailures"][0]["message"]
        )

    def test_generated_host_files_do_not_change_fingerprint(self):
        before = catalog.tree_hash(self.root, "lib")
        self.put("lib/target/classes/Generated.class", "generated")
        self.put("lib/__pycache__/module.pyc", "generated")
        self.assertEqual(before, catalog.tree_hash(self.root, "lib"))


class ReleaseTests(unittest.TestCase):
    def test_interrupted_draft_resumes_and_published_retry_is_identical(self):
        api = FakeGitHub()
        api.fail_on_upload = "manifest.json"
        files = {"a" * 64: b"bytes", "manifest.json": b"{}"}
        with self.assertRaises(RuntimeError):
            publish_immutable(api, "ext-test", files, "main")
        self.assertTrue(api.find_release("ext-test")["draft"])
        publish_immutable(api, "ext-test", files, "main")
        count = len(api.content)
        publish_immutable(api, "ext-test", files, "main")
        self.assertEqual(len(api.content), count)
        self.assertFalse(api.find_release("ext-test")["draft"])
        self.assertEqual(api.events[-2][2], "release-manifest.json")
        self.assertIsNone(api.latest_tag)

    def test_published_content_is_never_clobbered(self):
        api = FakeGitHub()
        publish_immutable(api, "ext-test", {"manifest.json": b"first"}, "main")
        before = copy.deepcopy(api.content)
        with self.assertRaisesRegex(ValueError, "conflict"):
            publish_immutable(api, "ext-test", {"manifest.json": b"other"}, "main")
        self.assertEqual(api.content, before)

    def test_download_checks_all_bytes_and_rejects_extra_asset(self):
        api = FakeGitHub()
        publish_immutable(api, "ext-test", {"manifest.json": b"{}"}, "main")
        with tempfile.TemporaryDirectory() as folder:
            self.assertTrue(download_release(api, "ext-test", folder))
            api.content[1] = b"broken"
            with self.assertRaisesRegex(ValueError, "integrity"):
                download_release(api, "ext-test", folder)

    def test_redirect_drops_private_token_across_hosts(self):
        request = urllib.request.Request(
            "https://api.github.com/assets/1",
            headers={"Authorization": "Bearer secret", "Cookie": "secret=1"},
        )
        redirect = SafeRedirect().redirect_request(
            request,
            None,
            302,
            "Found",
            {},
            "https://release-assets.githubusercontent.com/file",
        )
        self.assertIsNone(redirect.get_header("Authorization"))
        self.assertIsNone(redirect.get_header("Cookie"))
        with self.assertRaises(ValueError):
            SafeRedirect().redirect_request(
                request, None, 302, "Found", {}, "http://example.invalid/file"
            )


class EncodingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)
        self.data = b"\x00\xff" + "中文ページ".encode() + bytes(range(256)) * 64
        self.sha = catalog.digest(self.data)
        self.artifacts = {self.sha: {"sha256": self.sha, "size": len(self.data)}}
        self.encoded, self.entry = encode_artifact(self.sha, self.data)

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, encoded=None, entry=None):
        encoded = self.encoded if encoded is None else encoded
        entry = self.entry if entry is None else entry
        (self.folder / (self.sha + ".gz")).write_bytes(encoded)
        pipeline.write_json(
            self.folder / "artifact-encodings.json",
            {"schemaVersion": 1, "artifacts": [entry]},
        )

    def restore(self):
        return restore_artifacts(
            self.folder, self.folder / "out", self.artifacts, self.sha
        )

    def test_deterministic_gzip_roundtrip_preserves_binary_and_unicode(self):
        self.assertEqual(
            encode_artifact(self.sha, self.data), (self.encoded, self.entry)
        )
        self.assertEqual(self.encoded[4:8], b"\x00" * 4)  # mtime
        self.assertEqual(self.encoded[9], 255)  # OS independent header
        self.write()
        self.assertEqual(self.restore(), "gzip")
        self.assertEqual((self.folder / "out" / self.sha).read_bytes(), self.data)

    def test_transport_corruption_fails_before_decoding(self):
        data = bytearray(self.encoded)
        data[-1] ^= 1
        self.write(bytes(data))
        with self.assertRaisesRegex(ValueError, "Encoded artifact integrity"):
            self.restore()

    def test_valid_transport_cannot_substitute_different_canonical_bytes(self):
        other = b"x" * len(self.data)
        encoded, entry = encode_artifact(catalog.digest(other), other)
        entry.update(sha256=self.sha, asset=self.sha + ".gz")
        self.write(encoded, entry)
        with self.assertRaisesRegex(ValueError, "Canonical artifact integrity"):
            self.restore()

    def test_decompression_stops_at_declared_size(self):
        self.write()
        self.artifacts[self.sha]["size"] = 10
        entry = {**self.entry, "size": 10}
        self.write(entry=entry)
        with self.assertRaisesRegex(ValueError, "exceeds canonical size"):
            self.restore()
        self.assertFalse((self.folder / "out" / self.sha).exists())

    def test_truncated_concatenated_and_trailing_streams_fail_even_with_valid_transport_hash(
        self,
    ):
        for encoded in [
            self.encoded[:-2],
            self.encoded + self.encoded,
            self.encoded + b"trailing",
        ]:
            with self.subTest(size=len(encoded)):
                self.write(
                    encoded,
                    {
                        **self.entry,
                        "encodedSha256": catalog.digest(encoded),
                        "encodedSize": len(encoded),
                    },
                )
                with self.assertRaisesRegex(ValueError, "Truncated or trailing"):
                    self.restore()

    def test_unsafe_asset_and_missing_or_duplicate_bundle_do_not_fall_back_to_raw(self):
        (self.folder / self.sha).write_bytes(self.data)
        self.write(entry={**self.entry, "asset": "../escape"})
        with self.assertRaisesRegex(ValueError, "asset reference"):
            self.restore()
        for entries in [
            [],
            [self.entry, self.entry],
            [{**self.entry, "sha256": "0" * 64}],
        ]:
            with self.subTest(entries=len(entries)):
                pipeline.write_json(
                    self.folder / "artifact-encodings.json",
                    {"schemaVersion": 1, "artifacts": entries},
                )
                with self.assertRaises(ValueError):
                    self.restore()

    def test_original_raw_release_format_remains_supported(self):
        (self.folder / self.sha).write_bytes(self.data)
        self.assertEqual(self.restore(), "identity")
        self.assertEqual((self.folder / "out" / self.sha).read_bytes(), self.data)


class StateTests(unittest.TestCase):
    def fixture(self):
        entries = [
            {
                "packageName": "fixture." + str(i),
                "inputFingerprint": str(i) * 64,
                "versionName": "1.6.1",
                "buildId": "build-" + str(i),
            }
            for i in range(4)
        ]
        return {
            "entries": entries,
            "discoveryFailures": [],
            "catalogFingerprint": "catalog",
            "upstreamCommit": "upstream",
        }

    def test_ci_refuses_missing_baseline_and_caps_incremental_batches(self):
        state, source = pipeline.empty_state(), self.fixture()
        with self.assertRaisesRegex(ValueError, "bootstrap guard"):
            pipeline.make_plan(source, state, ci=True)
        state["bootstrap"]["complete"] = True
        plan = pipeline.make_plan(source, state, limit=2, ci=True)
        self.assertEqual(len(plan["selected"]), 2)
        self.assertEqual(plan["remainingCount"], 2)
        with self.assertRaises(ValueError):
            pipeline.make_plan(source, state, limit=100, ci=True)

    def test_unchanged_failures_do_not_trigger_full_ci_retries(self):
        state, source = pipeline.empty_state(), self.fixture()
        state["bootstrap"]["complete"] = True
        for entry in source["entries"]:
            state["attempts"][entry["inputFingerprint"]] = {
                "status": "failed",
                "retryable": False,
            }
        self.assertEqual(pipeline.make_plan(source, state, ci=True)["selected"], [])
        self.assertEqual(
            len(pipeline.make_plan(source, state, retry_failed=True)["selected"]), 4
        )

    def test_baseline_cannot_hide_unattempted_packages_or_claim_all_ready(self):
        state, source = pipeline.empty_state(), self.fixture()
        with patch.object(pipeline, "ci_environment", return_value=False):
            with self.assertRaisesRegex(ValueError, "unattempted"):
                pipeline.finalize_baseline(state, source)
            for entry in source["entries"]:
                state["attempts"][entry["inputFingerprint"]] = {"status": "failed"}
            pipeline.finalize_baseline(state, source)
        self.assertTrue(state["bootstrap"]["complete"])
        self.assertEqual(state["bootstrap"]["published"], 0)
        self.assertEqual(state["bootstrap"]["failed"], 4)

    def test_ci_environment_cannot_finalize_or_overwrite_baseline(self):
        environments = [
            {"CI": "true", "GITHUB_ACTIONS": "false"},
            {"CI": "false", "GITHUB_ACTIONS": "true"},
            {"CI": "true", "GITHUB_ACTIONS": "true"},
        ]
        for environment in environments:
            for complete in (False, True):
                with (
                    self.subTest(environment=environment, complete=complete),
                    patch.dict(os.environ, environment),
                ):
                    state, source = pipeline.empty_state(), self.fixture()
                    for entry in source["entries"]:
                        state["attempts"][entry["inputFingerprint"]] = {
                            "status": "failed"
                        }
                    state["bootstrap"] = {
                        "complete": complete,
                        "catalogFingerprint": "preserved-baseline",
                    }
                    before = copy.deepcopy(state)
                    self.assertTrue(pipeline.ci_environment())
                    with self.assertRaisesRegex(
                        ValueError, "CI cannot create or finalize"
                    ):
                        pipeline.finalize_baseline(state, source, local=True)
                    self.assertEqual(state, before)

    def test_index_is_last_and_state_only_changes_get_new_immutable_snapshots(self):
        api, state, source = FakeGitHub(), pipeline.empty_state(), self.fixture()
        for entry in source["entries"]:
            state["attempts"][entry["inputFingerprint"]] = {
                "status": "failed",
                "failure": {"code": "unsupported"},
            }
        first = pipeline.publish_index(api, state, source, "main")
        self.assertEqual(api.events[-1], ("publish", first, True))
        state["attempts"][source["entries"][0]["inputFingerprint"]]["attempts"] = 2
        second = pipeline.publish_index(api, state, source, "main")
        self.assertNotEqual(first, second)
        self.assertEqual(api.latest_tag, second)
        stale = pipeline.empty_state()
        with self.assertRaisesRegex(ValueError, "advanced"):
            pipeline.publish_index(api, stale, source, "main")


class OutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.output = Path(self.temporary.name)
        self.data = b"const fixture = 1;"
        self.sha = catalog.digest(self.data)
        self.descriptor = {
            "packageName": "example.fixture",
            "buildId": "fixture-build",
            "versionName": "1.6.1",
            "versionCode": 106001,
            "sourceFingerprint": "s" * 64,
            "hostFingerprint": "h" * 64,
            "inputFingerprint": "i" * 64,
            "upstreamCommit": "old-commit",
            "releaseTag": "ext-fixture",
        }
        (self.output / "artifacts").mkdir()
        (self.output / "artifacts" / self.sha).write_bytes(self.data)
        manifest = {
            **json.loads(
                (catalog.ROOT / "packages/contracts/protocol.json").read_text()
            ),
            "bridgeVersion": 1,
            "buildId": "fixture-build",
            "packageName": "example.fixture",
            "repoId": "fixture",
            "version": "1.6.1",
            "storageSchema": "1",
            "sourceIds": ["9223372036854775807"],
            "hostScripts": [],
            "bundle": {
                "sha256": self.sha,
                "path": "/api/extensions/artifacts/" + self.sha,
                "size": len(self.data),
            },
        }
        pipeline.write_json(self.output / "manifest.json", manifest)
        pipeline.write_json(self.output / "provenance.json", {"origin": "fixture"})

    def tearDown(self):
        self.temporary.cleanup()

    def test_compilation_is_published_with_runtime_ready_false(self):
        api, state = FakeGitHub(), pipeline.empty_state()
        result = {"status": "built", "descriptor": self.descriptor}
        record = pipeline.record_result(
            state, self.descriptor, result, self.output, api, "main"
        )
        self.assertEqual(record["status"], "published")
        self.assertFalse(record["runtimeReady"])
        self.assertEqual(record["validationStatus"], "compiled_unverified")
        self.assertEqual(state["active"]["example.fixture"], "i" * 64)

    def test_corrupt_output_isolated_without_release_or_active_pointer(self):
        (self.output / "artifacts" / self.sha).write_bytes(b"corrupt")
        api, state = FakeGitHub(), pipeline.empty_state()
        result = {"status": "built", "descriptor": self.descriptor}
        record = pipeline.record_result(
            state, self.descriptor, result, self.output, api, "main"
        )
        self.assertEqual(record["status"], "failed")
        self.assertEqual(api.releases, {})
        self.assertEqual(state["active"], {})

    def test_restore_survives_unrelated_upstream_commit_without_rebuilding(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        publish_immutable(api, self.descriptor["releaseTag"], files, "main")
        current = {**self.descriptor, "upstreamCommit": "new-unrelated-commit"}
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, current, restored))
        result = pipeline.read_json(restored / "pipeline-result.json")
        state = pipeline.empty_state()
        record = pipeline.record_result(state, current, result, restored, api, "main")
        self.assertEqual(record["status"], "published")
        self.assertEqual(record["descriptor"]["upstreamCommit"], "old-commit")

    def test_source_release_uses_encoded_bundle_and_canonical_manifest(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        self.assertNotIn(self.sha, files)
        self.assertIn(self.sha + ".gz", files)
        self.assertIn("artifact-encodings.json", files)
        self.assertEqual(
            json.loads(files["manifest.json"].read_bytes())["bundle"]["sha256"],
            self.sha,
        )
        publish_immutable(api, self.descriptor["releaseTag"], files, "main")
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
        self.assertEqual((restored / "artifacts" / self.sha).read_bytes(), self.data)
        self.assertEqual(
            pipeline.read_json(restored / "pipeline-result.json")["releaseEncoding"],
            "gzip",
        )

    def test_already_published_raw_source_release_stays_identical_after_restore(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor, "identity"
        )
        publish_immutable(api, self.descriptor["releaseTag"], files, "main")
        before = copy.deepcopy(api.content)
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
        result = pipeline.read_json(restored / "pipeline-result.json")
        self.assertEqual(result["releaseEncoding"], "identity")
        record = pipeline.record_result(
            pipeline.empty_state(), self.descriptor, result, restored, api, "main"
        )
        self.assertEqual(record["status"], "published")
        self.assertEqual(api.content, before)

    def test_restore_preserves_original_compressed_bytes_for_immutable_retry(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        # Another encoder may use a different valid gzip header or deflate
        # representation; restore must never rewrite a published transport.
        encoded = bytearray(files[self.sha + ".gz"])
        encoded[4] = 1
        files[self.sha + ".gz"] = bytes(encoded)
        table = json.loads(files["artifact-encodings.json"])
        table["artifacts"][0]["encodedSha256"] = catalog.digest(encoded)
        files["artifact-encodings.json"] = catalog.canonical(table) + b"\n"
        publish_immutable(api, self.descriptor["releaseTag"], files, "main")
        before = copy.deepcopy(api.content)
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
        result = pipeline.read_json(restored / "pipeline-result.json")
        record = pipeline.record_result(
            pipeline.empty_state(), self.descriptor, result, restored, api, "main"
        )
        self.assertEqual(record["status"], "published")
        self.assertEqual(api.content, before)

    def test_symlink_in_untrusted_build_output_is_rejected(self):
        (self.output / "provenance.json").unlink()
        (self.output / "provenance.json").symlink_to("/etc/hosts")
        with self.assertRaisesRegex(ValueError, "symlink"):
            pipeline.verify_output(self.output, self.descriptor)


class WorkCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.local = self.root / "runtime/teavm/.local"
        self.build_id = "ext-en.fixture-" + "a" * 32
        self.descriptor = {
            "packageName": "fixture",
            "buildId": self.build_id,
            "inputFingerprint": "a" * 64,
        }
        self.record = {
            "descriptor": self.descriptor,
            "status": "published",
            "release": {"tag": "immutable"},
        }
        self.state = pipeline.empty_state()
        self.state["attempts"]["a" * 64] = self.record
        self.state["active"]["fixture"] = "a" * 64
        self.state_path = self.root / "delivery/state.json"
        self.directories = [
            self.local / name / self.build_id
            for name in ["extension-work", "extension-cache", "gradle-launcher"]
        ]
        self.preserved = []
        for directory in self.directories:
            directory.mkdir(parents=True)
            (directory / "disposable").write_text("work")
            neighbor = directory.with_name(self.build_id + "-other")
            neighbor.mkdir()
            (neighbor / "diagnostic").write_text("retain")
            self.preserved.append(neighbor / "diagnostic")
        self.shared_m2 = self.local / "build-cache/m2"
        self.shared_m2.mkdir(parents=True)
        (self.shared_m2 / "library.jar").write_bytes(b"shared dependency")
        (self.directories[1] / "m2").symlink_to(
            self.shared_m2, target_is_directory=True
        )
        for name in [
            "delivery/artifacts/bundle",
            "delivery/logs/aot.log",
            "runtime/teavm/.local/gradle/cache",
        ]:
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("retain")
            self.preserved.append(file)
        self.root_patch = patch.object(pipeline, "ROOT", self.root)
        self.root_patch.start()
        self.environment_patch = patch.dict(
            os.environ, {"CI": "false", "GITHUB_ACTIONS": "false"}
        )
        self.environment_patch.start()

    def tearDown(self):
        self.environment_patch.stop()
        self.root_patch.stop()
        self.temporary.cleanup()

    def assert_preserved(self):
        self.assertEqual(
            (self.shared_m2 / "library.jar").read_bytes(), b"shared dependency"
        )
        for file in self.preserved:
            self.assertEqual(file.read_text(), "retain")

    def test_saved_publication_cleans_only_exact_work_and_keeps_shared_symlink_target(
        self,
    ):
        pipeline.checkpoint_bootstrap_result(
            self.state_path, self.state, self.descriptor, self.record
        )
        self.assertEqual(pipeline.load_state(self.state_path), self.state)
        for directory in self.directories:
            self.assertFalse(directory.exists())
        self.assert_preserved()
        self.assertEqual(
            pipeline.cleanup_published_work(
                self.state_path, self.descriptor, self.record
            ),
            [],
        )

    def test_failed_or_only_built_outputs_keep_their_diagnostics(self):
        for status in ["failed", "built"]:
            record = {**self.record, "status": status}
            self.state["attempts"]["a" * 64] = record
            self.state["active"].clear()
            pipeline.checkpoint_bootstrap_result(
                self.state_path, self.state, self.descriptor, record
            )
            for directory in self.directories:
                self.assertTrue((directory / "disposable").exists())
        self.assert_preserved()

    def test_failed_checkpoint_write_cannot_trigger_cleanup(self):
        pipeline.write_json(self.state_path, pipeline.empty_state())
        with (
            patch.object(
                pipeline, "write_json", side_effect=PermissionError("checkpoint failed")
            ),
            patch.object(pipeline, "cleanup_published_work") as cleanup,
        ):
            with self.assertRaises(PermissionError):
                pipeline.checkpoint_bootstrap_result(
                    self.state_path, self.state, self.descriptor, self.record
                )
            cleanup.assert_not_called()
        self.assertEqual(pipeline.load_state(self.state_path), pipeline.empty_state())
        self.assertTrue(all(directory.exists() for directory in self.directories))

    def test_missing_or_mismatched_saved_publication_cannot_authorize_cleanup(self):
        for state in [pipeline.empty_state(), {**self.state, "active": {}}]:
            pipeline.write_json(self.state_path, state)
            with self.assertRaisesRegex(ValueError, "checkpoint must be saved"):
                pipeline.cleanup_published_work(
                    self.state_path, self.descriptor, self.record
                )
            self.assertTrue(all(directory.exists() for directory in self.directories))

    def test_top_level_build_symlink_is_unlinked_without_touching_its_target(self):
        shutil.rmtree(self.directories[0])
        self.directories[0].symlink_to(self.shared_m2, target_is_directory=True)
        pipeline.checkpoint_bootstrap_result(
            self.state_path, self.state, self.descriptor, self.record
        )
        self.assertFalse(self.directories[0].is_symlink())
        self.assert_preserved()

    def test_linked_parent_is_not_followed_and_cleanup_failure_keeps_published_status(
        self,
    ):
        parent = self.directories[0].parent
        outside = self.root / "outside"
        parent.rename(outside)
        parent.symlink_to(outside, target_is_directory=True)
        with patch("builtins.print") as warning:
            pipeline.checkpoint_bootstrap_result(
                self.state_path, self.state, self.descriptor, self.record
            )
        self.assertTrue((outside / self.build_id / "disposable").exists())
        self.assertEqual(
            pipeline.load_state(self.state_path)["attempts"]["a" * 64]["status"],
            "published",
        )
        self.assertTrue(warning.called)
        self.assert_preserved()

    def test_unsafe_build_ids_and_ci_cannot_remove_local_work(self):
        pipeline.write_json(self.state_path, self.state)
        for value in ["..", ".", "../extension-work", "/tmp", "x/y", "x\\y", "x\n"]:
            with (
                self.subTest(build_id=value),
                self.assertRaisesRegex(ValueError, "Unsafe build ID"),
            ):
                pipeline.cleanup_published_work(
                    self.state_path, {**self.descriptor, "buildId": value}, self.record
                )
        for variable in ["CI", "GITHUB_ACTIONS"]:
            with patch.dict(os.environ, {variable: "true"}):
                self.assertEqual(
                    pipeline.cleanup_published_work(
                        self.state_path, self.descriptor, self.record
                    ),
                    [],
                )
        self.assertTrue(all(directory.exists() for directory in self.directories))
        self.assert_preserved()


if __name__ == "__main__":
    unittest.main()
