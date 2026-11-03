"""No network or external runtimes: source identities and release safety."""

from pathlib import Path
import copy
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
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
    publish_locator,
    capture_files,
    release_pointer,
    restore_artifacts,
)


def publish(api, tag, files, target, generation=None):
    if generation is None and "provenance.json" in files:
        value = files["provenance.json"]
        value = value.read_bytes() if isinstance(value, Path) else value
        generation = json.loads(value).get("descriptor", {}).get("inputFingerprint")
    return publish_locator(api, tag, generation or "fixture", files, target)


class FakeGitHub:
    def __init__(self):
        self.releases, self.content, self.events = {}, {}, []
        self.latest_tag = None
        self.fail_on_upload = None
        self.next_asset_id = 1

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
            "id": self.next_asset_id,
            "name": name,
            "size": len(data),
            "digest": "sha256:" + catalog.digest(data),
        }
        self.next_asset_id += 1
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

    def find_draft(self, tag):
        release = self.find_release(tag)
        return release if release and release.get("draft") else None

    def make_draft(self, release):
        self.events.append(("hide", release["tag_name"]))
        release["draft"] = True
        return release

    def delete_asset(self, asset):
        self.events.append(("delete", asset["name"]))
        for release in self.releases.values():
            release["assets"] = [
                item for item in release["assets"] if item["id"] != asset["id"]
            ]
        del self.content[asset["id"]]

    def update_pointer(self, release, body, latest=False):
        release["body"] = catalog.canonical({"karuyomiRelease": body}).decode()
        release["name"] = release["tag_name"]
        return self.publish(release, latest)


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
    def test_upload_hashes_each_owned_payload_once_and_reuses_its_receipt(self):
        api = FakeGitHub()
        data = b"one transfer boundary"
        with patch("releases.digest", wraps=catalog.digest) as digest:
            files = capture_files({"bundle.gz": data})
            publish_locator(api, "ext-one-v1", "input-1", files, "main")
        self.assertEqual(sum(call.args[0] == data for call in digest.call_args_list), 1)

    def test_different_host_generation_replaces_one_fixed_locator_only(self):
        api = FakeGitHub()
        tag = catalog.extension_tag("eu.kanade.tachiyomi.extension.en.fixture", 106001)
        first = publish(api, tag, {"bundle.gz": b"one"}, "commit-one", "host-one")
        second = publish(api, tag, {"bundle.gz": b"two"}, "commit-two", "host-two")
        self.assertEqual(tag, "ext-en.fixture-v106001")
        self.assertEqual(first["tag"], second["tag"])
        self.assertNotEqual(first["snapshot"], second["snapshot"])
        self.assertEqual(list(api.releases), [tag])
        self.assertEqual(api.releases[tag]["name"], tag)
        self.assertEqual(
            {item["name"] for item in api.releases[tag]["assets"]},
            {"bundle.gz", "release-manifest.json"},
        )
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(download_release(api, tag, folder, generation="host-one"))
            self.assertEqual(
                download_release(api, tag, folder, generation="host-two")["bundle.gz"],
                b"two",
            )

    def test_manifest_upload_failure_keeps_new_generation_hidden(self):
        api = FakeGitHub()
        first = publish(api, "ext-one-v1", {"bundle.gz": b"one"}, "main", "first")
        api.fail_on_upload = "release-manifest.json"
        with self.assertRaises(RuntimeError):
            publish(api, "ext-one-v1", {"bundle.gz": b"two"}, "main", "second")
        self.assertEqual(release_pointer(api.releases["ext-one-v1"]), first["snapshot"])
        self.assertTrue(api.releases["ext-one-v1"]["draft"])
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(download_release(api, "ext-one-v1", folder))

    def test_stale_writer_and_immutable_locator_fail_without_mutation(self):
        api = FakeGitHub()
        publish(api, "ext-one-v1", {"bundle.gz": b"one"}, "main")
        count = len(api.events)
        with self.assertRaisesRegex(ValueError, "advanced"):
            publish_locator(
                api, "ext-one-v1", "other", {"bundle.gz": b"two"}, "main", expected=None
            )
        api.releases["ext-one-v1"]["immutable"] = True
        with self.assertRaisesRegex(ValueError, "mutable"):
            publish(api, "ext-one-v1", {"bundle.gz": b"two"}, "main")
        self.assertEqual(len(api.events), count)

    def test_stale_pointer_does_not_create_a_replacement_for_a_missing_release(self):
        api = FakeGitHub()
        with self.assertRaisesRegex(ValueError, "advanced"):
            publish_locator(
                api,
                "extensions-index",
                "next",
                {"index.json": b"{}"},
                "main",
                expected={"generation": "deleted-remote-generation"},
            )
        self.assertEqual(api.events, [])

    def test_old_release_format_is_not_silently_accepted(self):
        api = FakeGitHub()
        release = api.create_release("extensions-index", "main")
        api.upload(release, "release-manifest.json", b'{"schemaVersion":1}')
        api.publish(release)
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "current-format"):
                download_release(api, "extensions-index", folder)

    def test_interrupted_draft_resumes_and_published_retry_is_identical(self):
        api = FakeGitHub()
        api.fail_on_upload = "manifest.json"
        files = {"a" * 64: b"bytes", "manifest.json": b"{}"}
        with self.assertRaises(RuntimeError):
            publish(api, "ext-test", files, "main")
        self.assertTrue(api.find_release("ext-test")["draft"])
        publish(api, "ext-test", files, "main")
        count = len(api.content)
        publish(api, "ext-test", files, "main")
        self.assertEqual(len(api.content), count)
        self.assertFalse(api.find_release("ext-test")["draft"])
        self.assertEqual(api.events[-2][2], "release-manifest.json")
        self.assertIsNone(api.latest_tag)

    def test_resume_finds_a_draft_hidden_from_the_published_tag_endpoint(self):
        class DraftGitHub(FakeGitHub):
            def find_release(self, tag):
                release = self.releases.get(tag)
                return release if release and not release["draft"] else None

            def find_draft(self, tag):
                release = self.releases.get(tag)
                return release if release and release["draft"] else None

        api = DraftGitHub()
        api.fail_on_upload = "manifest.json"
        with self.assertRaises(RuntimeError):
            publish(api, "ext-test", {"manifest.json": b"{}"}, "main")
        self.assertIsNone(api.find_release("ext-test"))
        publish(api, "ext-test", {"manifest.json": b"{}"}, "main")
        self.assertEqual(len(api.releases), 1)
        self.assertFalse(api.releases["ext-test"]["draft"])

    def test_replacement_is_hidden_until_all_assets_and_manifest_are_ready(self):
        api = FakeGitHub()
        publish(api, "ext-test", {"manifest.json": b"first"}, "main")
        start = len(api.events)
        api.fail_on_upload = "manifest.json"
        with self.assertRaises(RuntimeError):
            publish(api, "ext-test", {"manifest.json": b"other"}, "main", "changed")
        self.assertEqual(api.events[start], ("hide", "ext-test"))
        self.assertTrue(api.find_release("ext-test")["draft"])
        with tempfile.TemporaryDirectory() as folder:
            self.assertFalse(download_release(api, "ext-test", folder))
        publish(api, "ext-test", {"manifest.json": b"other"}, "main", "changed")
        self.assertFalse(api.find_release("ext-test")["draft"])
        self.assertEqual(
            release_pointer(api.find_release("ext-test"))["generation"], "changed"
        )

    def test_download_checks_all_bytes_and_rejects_extra_asset(self):
        api = FakeGitHub()
        publish(api, "ext-test", {"manifest.json": b"{}"}, "main")
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

    def test_missing_encoding_table_is_rejected(self):
        (self.folder / self.sha).write_bytes(self.data)
        with self.assertRaisesRegex(ValueError, "encoding table"):
            self.restore()


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

    def test_index_is_last_and_state_only_changes_replace_its_fixed_snapshot(self):
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
        self.assertEqual(first, "extensions-index")
        self.assertEqual(first, second)
        self.assertEqual(api.latest_tag, second)
        stale = pipeline.empty_state()
        with self.assertRaisesRegex(ValueError, "advanced"):
            pipeline.publish_index(api, stale, source, "main")

    def test_current_index_does_not_advertise_historical_release_formats(self):
        state, source = pipeline.empty_state(), self.fixture()
        entry = source["entries"][0]
        entry["versionCode"] = 106001
        key, package = entry["inputFingerprint"], entry["packageName"]
        record = {
            "status": "published",
            "descriptor": entry,
            "runtimeReady": False,
            "validationStatus": "compiled_unverified",
            "release": {"tag": "historical-hash-locator"},
        }
        state["attempts"][key], state["active"][package] = record, key
        self.assertEqual(pipeline.index_payload(state, source)["packages"], [])
        record["release"] = {
            "tag": catalog.extension_tag(package, entry["versionCode"]),
            "snapshot": {"generation": key},
        }
        self.assertEqual(len(pipeline.index_payload(state, source)["packages"]), 1)
        self.assertIs(state["attempts"][key], record)

    def test_index_pull_during_replacement_keeps_the_local_checkpoint(self):
        api = FakeGitHub()
        api.create_release("extensions-index", "main")
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            state = pipeline.empty_state()
            state["bootstrap"]["complete"] = True
            pipeline.write_json(path, state)
            before = path.read_bytes()
            with self.assertRaisesRegex(RuntimeError, "retry later"):
                pipeline.pull_state(api, path)
            self.assertEqual(path.read_bytes(), before)


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
            "releaseTag": "ext-example.fixture-v106001",
        }
        (self.output / "artifacts").mkdir()
        (self.output / "artifacts" / self.sha).write_bytes(self.data)
        manifest = {
            **json.loads(
                (catalog.ROOT / "packages/contracts/protocol.json").read_text()
            ),
            "bridgeVersion": 2,
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

    def test_private_non_bundle_material_is_rejected_before_publication(self):
        for role in ["hostScripts", "resources"]:
            with self.subTest(role=role):
                manifest = pipeline.read_json(self.output / "manifest.json")
                artifact = {**manifest["bundle"], "logicalName": "private.js"}
                manifest[role] = [artifact]
                pipeline.write_json(self.output / "manifest.json", manifest)
                with self.assertRaisesRegex(ValueError, "shared runtime materials"):
                    pipeline.verify_output(
                        self.output, self.descriptor, verify_hashes=False
                    )
                api, state = FakeGitHub(), pipeline.empty_state()
                record = pipeline.record_result(
                    state,
                    self.descriptor,
                    {"status": "built", "descriptor": self.descriptor},
                    self.output,
                    api,
                    "main",
                )
                self.assertEqual(record["status"], "failed")
                self.assertEqual(api.releases, {})
                manifest[role] = []
                pipeline.write_json(self.output / "manifest.json", manifest)

    def test_restore_survives_unrelated_upstream_commit_without_rebuilding(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        publish(api, self.descriptor["releaseTag"], files, "main")
        current = {**self.descriptor, "upstreamCommit": "new-unrelated-commit"}
        restored = self.output / "restored"
        result = pipeline.restore_build(api, current, restored)
        self.assertIsInstance(result, pipeline.DownloadedBuildResult)
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
            json.loads(files["manifest.json"])["bundle"]["sha256"],
            self.sha,
        )
        publish(api, self.descriptor["releaseTag"], files, "main")
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
        self.assertEqual((restored / "artifacts" / self.sha).read_bytes(), self.data)
        self.assertEqual(
            pipeline.read_json(restored / "pipeline-result.json")["releaseEncoding"],
            "gzip",
        )

    def test_download_hashes_encoded_and_canonical_bytes_once_each(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        encoded = files[self.sha + ".gz"]
        publish(api, self.descriptor["releaseTag"], files, "main")
        with patch("releases.digest", wraps=catalog.digest) as digest:
            self.assertTrue(
                pipeline.restore_build(api, self.descriptor, self.output / "received")
            )
        for data in [encoded, self.data]:
            self.assertEqual(
                sum(call.args[0] == data for call in digest.call_args_list), 1
            )

    def test_live_download_receipt_adopts_original_compressed_bytes(self):
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
        files = capture_files(dict(files))
        publish(api, self.descriptor["releaseTag"], files, "main")
        before = copy.deepcopy(api.content)
        restored = self.output / "restored"
        result = pipeline.restore_build(api, self.descriptor, restored)
        self.assertIsInstance(result, pipeline.DownloadedBuildResult)
        record = pipeline.record_result(
            pipeline.empty_state(), self.descriptor, result, restored, api, "main"
        )
        self.assertEqual(record["status"], "published")
        self.assertEqual(api.content, before)

    def test_cached_download_after_remote_miss_must_publish_again(self):
        for remote_state in ["deleted", "different_generation"]:
            with self.subTest(remote_state=remote_state):
                api = FakeGitHub()
                files, _provenance, _validation = pipeline.release_files(
                    self.output, self.descriptor
                )
                tag = self.descriptor["releaseTag"]
                old_reference = publish(api, tag, files, "main")
                restored = self.output / remote_state
                self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
                saved = restored / "pipeline-result.json"
                cached = pipeline.read_json(saved)
                # Reproduce a stale checkpoint written before the receipt fix.
                cached["releaseReference"] = old_reference
                pipeline.write_json(saved, cached)
                if remote_state == "deleted":
                    del api.releases[tag]
                else:
                    publish(api, tag, files, "main", "another-input-generation")
                before = len(api.events)
                with patch.object(pipeline, "GitHub", return_value=api):
                    result = pipeline.build_one(
                        self.descriptor, restored, repository="fixture/repo"
                    )
                self.assertEqual(result["status"], "built", result)
                self.assertNotIsInstance(result, pipeline.DownloadedBuildResult)
                for value in [result, pipeline.read_json(saved)]:
                    self.assertNotIn("restored", value)
                    self.assertNotIn("releaseReference", value)
                record = pipeline.record_result(
                    pipeline.empty_state(),
                    self.descriptor,
                    result,
                    restored,
                    api,
                    "main",
                )
                self.assertEqual(record["status"], "published", record)
                self.assertEqual(
                    release_pointer(api.releases[tag])["generation"],
                    self.descriptor["inputFingerprint"],
                )
                self.assertTrue(
                    any(event[0] == "publish" for event in api.events[before:])
                )

    def test_serialized_restore_flags_cannot_skip_publication(self):
        api = FakeGitHub()
        files, _provenance, _validation = pipeline.release_files(
            self.output, self.descriptor
        )
        reference = publish(api, self.descriptor["releaseTag"], files, "main")
        restored = self.output / "restored"
        self.assertTrue(pipeline.restore_build(api, self.descriptor, restored))
        result = pipeline.read_json(restored / "pipeline-result.json")
        result["releaseReference"] = reference
        del api.releases[self.descriptor["releaseTag"]]
        record = pipeline.record_result(
            pipeline.empty_state(), self.descriptor, result, restored, api, "main"
        )
        self.assertEqual(record["status"], "published", record)
        self.assertIn(self.descriptor["releaseTag"], api.releases)

    def test_symlink_in_untrusted_build_output_is_rejected(self):
        (self.output / "provenance.json").unlink()
        (self.output / "provenance.json").symlink_to("/etc/hosts")
        with self.assertRaisesRegex(ValueError, "symlink"):
            pipeline.verify_output(self.output, self.descriptor)


class FrozenRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name).resolve()
        self.checkout = self.folder / "builder"
        self.checkout.mkdir()
        self.git(self.checkout, "init", "-q")
        (self.checkout / "host.txt").write_text("frozen host")
        script = self.checkout / "scripts/build-extension.py"
        script.parent.mkdir()
        script.write_text("""import argparse, hashlib, json, os, pathlib
p=argparse.ArgumentParser()
p.add_argument('--descriptor'); p.add_argument('--output')
a=p.parse_args(); d=json.loads(pathlib.Path(a.descriptor).read_text())
assert 'GH_TOKEN' not in os.environ and 'GITHUB_TOKEN' not in os.environ
assert pathlib.Path.cwd() == pathlib.Path(__file__).resolve().parents[1]
o=pathlib.Path(a.output); (o/'artifacts').mkdir(exist_ok=True)
b=b'const frozen = true;'; h=hashlib.sha256(b).hexdigest()
(o/'artifacts'/h).write_bytes(b)
m={**json.loads((pathlib.Path(__file__).resolve().parents[1]/'protocol.json').read_text()),'bridgeVersion':2,'buildId':d['buildId'],'packageName':d['packageName'],'repoId':'fixture','version':d['versionName'],'storageSchema':'1','sourceIds':['1'],'hostScripts':[],'bundle':{'sha256':h,'path':'/api/extensions/artifacts/'+h,'size':len(b)}}
(o/'manifest.json').write_text(json.dumps(m))
(o/'provenance.json').write_text(json.dumps({'descriptor':d}))
""")
        protocol = (catalog.ROOT / "packages/contracts/protocol.json").read_bytes()
        (self.checkout / "protocol.json").write_bytes(protocol)
        self.git(
            self.checkout,
            "add",
            "host.txt",
            "scripts/build-extension.py",
            "protocol.json",
        )
        self.git(
            self.checkout,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "frozen builder",
        )
        upstream = self.checkout / "vendor/extensions-source"
        upstream.mkdir(parents=True)
        self.git(upstream, "init", "-q")
        (upstream / "source.txt").write_text("frozen source")
        self.git(upstream, "add", "source.txt")
        self.git(
            upstream,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "source",
        )
        inputs = {
            name: catalog.tree_hash(self.checkout, name)
            for name in ["host.txt", "scripts/build-extension.py", "protocol.json"]
        }
        self.descriptor = {
            "schemaVersion": 1,
            "packageName": "example.frozen",
            "buildId": "frozen-build",
            "versionCode": 106001,
            "versionName": "1.6.1",
            "hostRepositoryCommit": self.git(self.checkout, "rev-parse", "HEAD"),
            "hostSubmodules": [],
            "hostInputs": inputs,
            "hostFingerprint": catalog.digest(
                catalog.canonical(
                    {"schemaVersion": 1, "inputs": inputs, "pinnedSubmodules": []}
                )
            ),
            "sourceFingerprint": "s" * 64,
            "inputFingerprint": "f" * 64,
            "upstreamCommit": self.git(upstream, "rev-parse", "HEAD"),
            "releaseTag": "old-internal-plan-field",
        }

    def git(self, root, *args):
        return subprocess.check_output(
            ["git", "-C", str(root), *args], text=True
        ).strip()

    def tearDown(self):
        self.temporary.cleanup()

    def test_runner_uses_frozen_child_and_strips_publish_credentials(self):
        output = self.folder / "delivery"
        with (
            patch.object(
                pipeline,
                "checkout_material_catalog",
                return_value={"hostScripts": [], "resources": []},
            ),
            patch.dict(
                os.environ,
                {"GH_TOKEN": "must-not-reach-builder", "GITHUB_TOKEN": "also-private"},
            ),
        ):
            result = pipeline.build_one(
                self.descriptor, output, build_checkout=self.checkout
            )
            self.assertEqual(result["status"], "built", result)
            with patch.object(
                pipeline.subprocess,
                "run",
                wraps=subprocess.run,
            ) as calls:
                self.assertEqual(
                    pipeline.build_one(
                        self.descriptor, output, build_checkout=self.checkout
                    ),
                    result,
                )
                self.assertFalse(
                    any(
                        len(call.args[0]) > 1
                        and call.args[0][1]
                        == str(self.checkout / "scripts/build-extension.py")
                        for call in calls.call_args_list
                    )
                )
        self.assertEqual(
            self.git(
                self.checkout,
                "status",
                "--porcelain",
                "--",
                *self.descriptor["hostInputs"],
            ),
            "",
        )

    def test_frozen_checkout_rejects_dirty_input_and_wrong_commit(self):
        wrong = {**self.descriptor, "hostRepositoryCommit": "0" * 40}
        with self.assertRaisesRegex(ValueError, "commit"):
            pipeline.validate_build_checkout(self.checkout, wrong)
        (self.checkout / "host.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "clean"):
            pipeline.validate_build_checkout(self.checkout, self.descriptor)

    def test_resume_preserves_every_frozen_descriptor_and_rejects_ci(self):
        plan = {
            "entries": [self.descriptor],
            "repositoryCommit": self.descriptor["hostRepositoryCommit"],
        }
        with patch.object(pipeline, "ci_environment", return_value=False):
            resumed = pipeline.resume_plan(plan, pipeline.empty_state())
        self.assertEqual(resumed["selected"], [self.descriptor])
        self.assertEqual(
            resumed["selected"][0]["releaseTag"], "old-internal-plan-field"
        )
        with patch.object(pipeline, "ci_environment", return_value=True):
            with self.assertRaisesRegex(ValueError, "CI"):
                pipeline.resume_plan(plan, pipeline.empty_state())

    @unittest.skipUnless(hasattr(os, "killpg"), "POSIX process groups required")
    def test_signal_stops_sleeping_builder_tree_before_releasing_checkpoint_lock(self):
        import fcntl

        script = self.checkout / "scripts/build-extension.py"
        script.write_text("""import argparse, json, os, pathlib, signal, subprocess, sys, time
p=argparse.ArgumentParser(); p.add_argument('--descriptor'); p.add_argument('--output')
a=p.parse_args(); output=pathlib.Path(a.output)
child=subprocess.Popen([sys.executable, '-c', '''import pathlib, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
signal.signal(signal.SIGINT, signal.SIG_IGN)
heartbeat=pathlib.Path(sys.argv[1])
while True:
    heartbeat.write_text(str(time.monotonic()))
    time.sleep(0.03)
''', str(output/'heartbeat')])
(output/'pids.json').write_text(json.dumps([os.getpid(), child.pid]))
while True: time.sleep(1)
""")
        self.git(self.checkout, "add", "scripts/build-extension.py")
        self.git(
            self.checkout,
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "sleeping process-tree fixture",
        )
        self.descriptor["hostRepositoryCommit"] = self.git(
            self.checkout, "rev-parse", "HEAD"
        )
        inputs = {
            name: catalog.tree_hash(self.checkout, name)
            for name in self.descriptor["hostInputs"]
        }
        self.descriptor["hostInputs"] = inputs
        self.descriptor["hostFingerprint"] = catalog.digest(
            catalog.canonical(
                {"schemaVersion": 1, "inputs": inputs, "pinnedSubmodules": []}
            )
        )
        pending = {
            **self.descriptor,
            "packageName": "example.pending",
            "inputFingerprint": "e" * 64,
            "buildId": "pending-build",
        }
        plan = {
            "entries": [self.descriptor, pending],
            "repositoryCommit": self.descriptor["hostRepositoryCommit"],
            "discoveryFailures": [],
        }
        plan_path = self.folder / "plan.json"
        pipeline.write_json(plan_path, plan)
        runner = self.folder / "runner.py"
        runner.write_text(
            "import sys\n"
            + "sys.path.insert(0, "
            + repr(str(catalog.ROOT / "tools/extensions"))
            + ")\n"
            + "import pipeline\n"
            + "class OfflineGitHub:\n"
            + "    def find_release(self, tag): return None\n"
            + "    def find_draft(self, tag): return None\n"
            + "pipeline.GitHub=lambda repository: OfflineGitHub()\n"
            + "pipeline.main()\n"
        )
        for number in [signal.SIGINT, signal.SIGTERM]:
            with self.subTest(signal=number):
                run_root = self.folder / str(number)
                state = run_root / "state.json"
                output = run_root / "resume-plan.json"
                delivery = run_root / "builds" / self.descriptor["inputFingerprint"]
                with (self.folder / (str(number) + ".log")).open("w") as log:
                    process = subprocess.Popen(
                        [
                            sys.executable,
                            str(runner),
                            "bootstrap",
                            "--plan",
                            str(plan_path),
                            "--build-checkout",
                            str(self.checkout),
                            "--state",
                            str(state),
                            "--output",
                            str(output),
                            "--jobs",
                            "1",
                        ],
                        stdout=log,
                        stderr=subprocess.STDOUT,
                        env={**os.environ, "CI": "false", "GITHUB_ACTIONS": "false"},
                    )
                    pids = []
                    try:
                        deadline = time.monotonic() + 10
                        while not (delivery / "heartbeat").exists():
                            self.assertIsNone(
                                process.poll(),
                                (self.folder / (str(number) + ".log")).read_text(),
                            )
                            self.assertLess(time.monotonic(), deadline)
                            time.sleep(0.02)
                        pids = pipeline.read_json(delivery / "pids.json")
                        with state.with_suffix(".lock").open("a") as lock:
                            with self.assertRaises(BlockingIOError):
                                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            process.send_signal(number)
                            self.assertEqual(process.wait(timeout=10), 128 + number)
                            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            fcntl.flock(lock, fcntl.LOCK_UN)
                        heartbeat = (delivery / "heartbeat").read_bytes()
                        time.sleep(0.1)
                        self.assertEqual(
                            (delivery / "heartbeat").read_bytes(), heartbeat
                        )
                        for pid in pids:
                            status = subprocess.run(
                                ["ps", "-p", str(pid), "-o", "stat="],
                                capture_output=True,
                                text=True,
                            ).stdout.strip()
                            self.assertTrue(
                                not status or status.startswith("Z"), (pid, status)
                            )
                        self.assertFalse(
                            (
                                run_root
                                / "builds"
                                / pending["inputFingerprint"]
                                / "build.log"
                            ).exists()
                        )
                        self.assertFalse(state.exists())
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                        for pid in pids:
                            try:
                                os.kill(pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass


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
