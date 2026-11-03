"""Offline static publication, integrity, state, and frozen-runner regressions."""

from pathlib import Path
import copy
import gzip
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog
import pipeline
import assets

PROTOCOL = json.loads((catalog.ROOT / "packages/contracts/protocol.json").read_text())
MATERIALS = {**PROTOCOL, "hostScripts": [], "resources": []}


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


class EncodingTests(unittest.TestCase):
    def test_deterministic_binary_and_unicode_roundtrip(self):
        raw = bytes(range(256)) * 512 + "漫画 🍵".encode()
        encoded, ref = assets.encode_bundle(raw)
        self.assertEqual((encoded, ref), assets.encode_bundle(raw))
        self.assertEqual(assets.decode_bundle(encoded, ref), raw)
        self.assertEqual(ref["path"], "/extensions/artifacts/" + ref["sha256"] + ".gz")
        self.assertEqual(encoded[4:8], b"\0" * 4)

    def test_encoded_static_asset_limit_is_enforced_before_publication(self):
        with patch.object(assets, "MAX_ENCODED", 1):
            with self.assertRaisesRegex(ValueError, "25 MiB"):
                assets.encode_bundle(b"let x = 1;")

    def test_encoded_and_canonical_domains_checked_once(self):
        raw = b"data" * 100
        encoded, ref = assets.encode_bundle(raw)
        with patch.object(assets, "digest", wraps=catalog.digest) as checks:
            self.assertEqual(assets.decode_bundle(encoded, ref), raw)
        self.assertEqual(
            [call.args[0] for call in checks.call_args_list], [encoded, raw]
        )

    def test_encoded_corruption_and_canonical_substitution_rejected(self):
        encoded, ref = assets.encode_bundle(b"original")
        with self.assertRaisesRegex(ValueError, "Encoded"):
            assets.decode_bundle(encoded[:-1] + b"?", ref)
        other, other_ref = assets.encode_bundle(b"modified")
        other_ref["sha256"] = ref["sha256"]
        with self.assertRaisesRegex(ValueError, "Canonical"):
            assets.decode_bundle(other, other_ref)

    def test_size_bomb_and_truncated_concatenated_trailing_streams_rejected(self):
        encoded, ref = assets.encode_bundle(b"x" * 100000)
        with self.assertRaisesRegex(ValueError, "exceeds"):
            assets.decode_bundle(encoded, {**ref, "size": 100})
        for data in [encoded[:-4], encoded + encoded, encoded + b"trailing"]:
            altered = {
                **ref,
                "encodedSize": len(data),
                "encodedSha256": catalog.digest(data),
            }
            with (
                self.subTest(data=len(data)),
                self.assertRaisesRegex(ValueError, "Truncated|trailing"),
            ):
                assets.decode_bundle(data, altered)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.state_path = self.root / "state.json"
        self.results = self.root / "results"
        self.results.mkdir()
        self.snapshot = self.root / "assets"
        self.patch = patch.object(
            pipeline, "checkout_material_catalog", return_value=MATERIALS
        )
        self.patch.start()
        self.material_patch = patch.object(
            pipeline.verifier(), "material_catalog", return_value=MATERIALS
        )
        self.material_patch.start()

    def tearDown(self):
        self.material_patch.stop()
        self.patch.stop()
        self.temp.cleanup()

    def descriptor(self, package="example.one", key="a", host="h"):
        return {
            "schemaVersion": 1,
            "packageName": package,
            "buildId": "ext-" + package + "-" + key * 32,
            "versionName": "1.6.1",
            "versionCode": 106001,
            "inputFingerprint": key * 64,
            "hostFingerprint": host * 64,
            "sourceFingerprint": "s" * 64,
            "upstreamCommit": "u" * 40,
        }

    def source(self, entries):
        return {
            "entries": entries,
            "upstreamCommit": "u" * 40,
            "hostFingerprint": entries[0]["hostFingerprint"] if entries else "h" * 64,
            "catalogFingerprint": "c" * 64,
            "discoveryFailures": [],
        }

    def plan(self, entries, state=None, selected=None):
        return {
            **self.source(entries),
            "selected": entries if selected is None else selected,
            "baseRevision": (state or pipeline.empty_state())["revision"],
        }

    def output(self, descriptor, failed=False):
        folder = self.results / descriptor["inputFingerprint"]
        folder.mkdir(parents=True, exist_ok=True)
        result = {
            "schemaVersion": 1,
            "descriptor": descriptor,
            "status": "failed" if failed else "built",
        }
        if failed:
            result["failure"] = {
                "stage": "aot",
                "code": "source_failed",
                "message": "Compilation failed",
            }
        else:
            encoded, ref = assets.encode_bundle(
                (
                    "const packageName = " + json.dumps(descriptor["packageName"]) + ";"
                ).encode()
            )
            (folder / "artifacts").mkdir(exist_ok=True)
            (folder / "artifacts" / (ref["sha256"] + ".gz")).write_bytes(encoded)
            manifest = {
                **PROTOCOL,
                "bridgeVersion": 2,
                "buildId": descriptor["buildId"],
                "repoId": "keiyoushi",
                "packageName": descriptor["packageName"],
                "version": descriptor["versionName"],
                "sourceIds": ["1"],
                "storageSchema": "1",
                "bundle": ref,
                "hostScripts": [],
                "resources": [],
            }
            pipeline.write_json(folder / "manifest.json", manifest)
        pipeline.write_json(folder / "pipeline-result.json", result)
        return folder, result

    def prepare(self, plan, state=None, **kwargs):
        return pipeline.prepare_snapshot(
            plan, state or pipeline.empty_state(), self.results, self.snapshot, **kwargs
        )

    def deploy_receipt(self, candidate):
        index_bytes = (self.snapshot / "extensions/index.json").read_bytes()
        return (
            patch.object(pipeline, "remote_state", return_value=candidate),
            patch.object(pipeline, "fetch_bytes", return_value=index_bytes),
        )

    def test_snapshot_contract_only_gzip_and_checkpoint_after_confirmed_deploy(self):
        descriptor = self.descriptor()
        folder, _ = self.output(descriptor)
        with patch.object(pipeline, "ci_environment", return_value=False):
            candidate = self.prepare(self.plan([descriptor]), finalize=True)
        self.assertFalse(self.state_path.exists())
        root = self.snapshot / "extensions"
        index_bytes = (root / "index.json").read_bytes()
        index = json.loads(index_bytes)
        self.assertEqual(candidate["indexSha256"], catalog.digest(index_bytes))
        self.assertTrue(candidate["bootstrap"]["complete"])
        self.assertEqual(index["schemaVersion"], 1)
        self.assertEqual(index["nextCursor"], None)
        self.assertEqual(
            index["builds"][0]["manifestPath"],
            "/extensions/builds/" + descriptor["buildId"] + "/manifest.json",
        )
        self.assertTrue(
            all(file.name.endswith(".gz") for file in (root / "artifacts").iterdir())
        )
        self.assertFalse(
            candidate["attempts"][descriptor["inputFingerprint"]]["runtimeReady"]
        )
        remote, index_receipt = self.deploy_receipt(candidate)
        with remote, index_receipt:
            pipeline.commit_snapshot(
                self.state_path, self.snapshot, "https://example.invalid"
            )
        self.assertEqual(pipeline.load_state(self.state_path), candidate)

    def test_same_failure_not_retried_and_ci_never_bootstraps(self):
        descriptor = self.descriptor()
        state = pipeline.empty_state()
        with (
            patch.object(pipeline, "git", return_value="commit"),
            patch.object(pipeline, "host_submodules", return_value=[]),
        ):
            with self.assertRaisesRegex(ValueError, "bootstrap"):
                pipeline.make_plan(self.source([descriptor]), state, ci=True)
            state["bootstrap"]["complete"] = True
            state["attempts"][descriptor["inputFingerprint"]] = {
                "descriptor": descriptor,
                "status": "failed",
                "retryable": True,
                "attempts": 1,
            }
            self.assertEqual(
                pipeline.make_plan(self.source([descriptor]), state, ci=True)[
                    "selected"
                ],
                [],
            )
            self.assertEqual(
                pipeline.make_plan(self.source([descriptor]), state, retry_failed=True)[
                    "selected"
                ][0]["inputFingerprint"],
                descriptor["inputFingerprint"],
            )
            with self.assertRaisesRegex(ValueError, "retry"):
                pipeline.make_plan(
                    self.source([descriptor]), state, ci=True, retry_failed=True
                )
            with self.assertRaisesRegex(ValueError, "limit"):
                pipeline.make_plan(self.source([descriptor]), state, ci=True, limit=25)

    def test_failed_update_keeps_success_when_host_and_materials_match(self):
        previous = self.descriptor()
        folder, _ = self.output(previous)
        first = self.prepare(self.plan([previous]))
        manifest = pipeline.read_json(folder / "manifest.json")
        encoded = (
            folder / "artifacts" / (manifest["bundle"]["sha256"] + ".gz")
        ).read_bytes()
        update = self.descriptor(key="b")
        self.output(update, failed=True)
        with (
            patch.object(pipeline, "fetch_json", return_value=manifest),
            patch.object(pipeline, "fetch_bytes", return_value=encoded),
        ):
            second = self.prepare(self.plan([update], first), first)
        self.assertEqual(
            second["active"][update["packageName"]], previous["inputFingerprint"]
        )
        self.assertEqual(
            pipeline.read_json(self.snapshot / "extensions/index.json")["builds"][0][
                "buildId"
            ],
            previous["buildId"],
        )
        self.assertEqual(
            second["attempts"][update["inputFingerprint"]]["status"], "failed"
        )

    def test_discovery_failure_retains_an_existing_source_instead_of_retiring_it(self):
        descriptor = {**self.descriptor(), "sourcePath": "src/en/one"}
        folder, _ = self.output(descriptor)
        first = self.prepare(self.plan([descriptor]))
        manifest = pipeline.read_json(folder / "manifest.json")
        encoded = next((folder / "artifacts").iterdir()).read_bytes()
        plan = self.plan([], first)
        plan["discoveryFailures"] = [
            {
                "sourcePath": "src/en/one",
                "status": "discovery_failed",
                "message": "unsupported DSL",
            }
        ]
        with (
            patch.object(pipeline, "fetch_json", return_value=manifest),
            patch.object(pipeline, "fetch_bytes", return_value=encoded),
        ):
            second = self.prepare(plan, first)
        self.assertEqual(
            pipeline.read_json(self.snapshot / "extensions/index.json")["builds"][0][
                "buildId"
            ],
            descriptor["buildId"],
        )
        self.assertTrue(second["attempts"][descriptor["inputFingerprint"]]["stale"])

    def test_failed_rebuild_of_unavailable_success_preserves_record_without_infinite_retry(
        self,
    ):
        descriptor = self.descriptor()
        self.output(descriptor)
        first = self.prepare(self.plan([descriptor]))
        first["attempts"][descriptor["inputFingerprint"]]["available"] = False
        self.output(descriptor, failed=True)
        second = self.prepare(self.plan([descriptor], first), first)
        record = second["attempts"][descriptor["inputFingerprint"]]
        self.assertEqual(record["status"], "published")
        self.assertIn("rebuildFailure", record)
        self.assertFalse(record["available"])
        with (
            patch.object(pipeline, "git", return_value="commit"),
            patch.object(pipeline, "host_submodules", return_value=[]),
        ):
            self.assertEqual(
                pipeline.make_plan(self.source([descriptor]), second)["selected"], []
            )

    def test_old_abi_is_state_only_and_unavailable_not_in_index(self):
        previous = self.descriptor()
        self.output(previous)
        first = self.prepare(self.plan([previous]))
        first["attempts"][previous["inputFingerprint"]]["runtimeIdentity"][
            "hostAbi"
        ] = "old"
        update = self.descriptor(key="b", host="j")
        self.output(update, failed=True)
        with patch.object(
            pipeline,
            "fetch_bytes",
            side_effect=AssertionError("cannot restore removed old ABI"),
        ):
            second = self.prepare(self.plan([update], first), first)
        self.assertEqual(
            pipeline.read_json(self.snapshot / "extensions/index.json")["builds"], []
        )
        self.assertEqual(list((self.snapshot / "extensions/artifacts").iterdir()), [])
        self.assertFalse(second["attempts"][previous["inputFingerprint"]]["available"])
        self.assertEqual(
            second["active"][update["packageName"]], previous["inputFingerprint"]
        )
        with (
            patch.object(pipeline, "git", return_value="commit"),
            patch.object(pipeline, "host_submodules", return_value=[]),
        ):
            restored = pipeline.make_plan(self.source([previous]), second)
        self.assertEqual(len(restored["selected"]), 1)

    def test_success_replaces_previous_build_and_removed_packages_are_pruned(self):
        old, removed = self.descriptor(), self.descriptor("example.removed", "c")
        self.output(old)
        self.output(removed)
        first = self.prepare(self.plan([old, removed]))
        update = self.descriptor(key="b")
        self.output(update)
        second = self.prepare(self.plan([update], first), first)
        self.assertEqual(len(second["active"]), 1)
        self.assertEqual(set(second["attempts"]), {update["inputFingerprint"]})
        self.assertEqual(
            [f.name for f in (self.snapshot / "extensions/builds").iterdir()],
            [update["buildId"]],
        )
        self.assertEqual(
            len(list((self.snapshot / "extensions/artifacts").iterdir())), 1
        )

    def test_missing_or_corrupt_matrix_output_preserves_previous_snapshot(self):
        old = self.descriptor()
        self.output(old)
        first = self.prepare(self.plan([old]))
        before = (self.snapshot / "extensions/build-state.json").read_bytes()
        update = self.descriptor(key="b")
        with self.assertRaisesRegex(ValueError, "Missing matrix"):
            self.prepare(self.plan([update], first), first)
        folder, _ = self.output(update)
        artifact = next((folder / "artifacts").iterdir())
        artifact.write_bytes(b"bad")
        # A failed integrity result may be recorded, but cannot advertise the new build.
        state = copy.deepcopy(first)
        record, content = pipeline.record_result(
            state, update, pipeline.read_json(folder / "pipeline-result.json"), folder
        )
        self.assertEqual(record["status"], "failed")
        self.assertIsNone(content)
        self.assertEqual(
            (self.snapshot / "extensions/build-state.json").read_bytes(), before
        )

    def test_cancellation_does_not_replace_snapshot(self):
        descriptor = self.descriptor()
        self.output(descriptor)
        self.prepare(self.plan([descriptor]))
        before = (self.snapshot / "extensions/build-state.json").read_bytes()
        processes = pipeline.BuilderProcesses()
        processes.cancelled.set()
        with self.assertRaises(pipeline.BuildCancelled):
            self.prepare(self.plan([descriptor]), processes=processes)
        self.assertEqual(
            (self.snapshot / "extensions/build-state.json").read_bytes(), before
        )

    def test_stale_base_and_unconfirmed_deploy_cannot_commit_state(self):
        descriptor = self.descriptor()
        self.output(descriptor)
        candidate = self.prepare(self.plan([descriptor]))
        other = {**candidate, "revision": "b" * 32}
        with patch.object(pipeline, "remote_state", return_value=other):
            with self.assertRaisesRegex(ValueError, "advanced"):
                pipeline.check_base(self.snapshot, "https://example.invalid")
            with self.assertRaisesRegex(ValueError, "not confirmed"):
                pipeline.commit_snapshot(
                    self.state_path, self.snapshot, "https://example.invalid"
                )
        self.assertFalse(self.state_path.exists())

    def test_ci_pull_missing_baseline_or_mixed_index_keeps_existing_state(self):
        pipeline.write_json(self.state_path, pipeline.empty_state())
        original = self.state_path.read_bytes()
        with (
            patch.object(pipeline, "remote_state", return_value=pipeline.empty_state()),
            patch.object(pipeline, "fetch_bytes", return_value=b"{}"),
        ):
            with self.assertRaisesRegex(ValueError, "different snapshots"):
                pipeline.pull_state("https://example.invalid", self.state_path)
        self.assertEqual(self.state_path.read_bytes(), original)
        with patch.object(
            pipeline,
            "fetch_json",
            side_effect=urllib.error.HTTPError(
                "https://example.invalid", 404, "Not Found", {}, None
            ),
        ):
            with self.assertRaisesRegex(ValueError, "unavailable"):
                pipeline.pull_state("https://example.invalid", self.state_path)

    def test_initialization_is_explicit_local_only_and_does_not_hide_invalid_json(self):
        descriptor = self.descriptor()
        self.output(descriptor)
        self.prepare(self.plan([descriptor]))
        invalid = json.JSONDecodeError("bad", "<html>", 0)
        with (
            patch.object(pipeline, "ci_environment", return_value=False),
            patch.object(pipeline, "remote_state", side_effect=invalid),
            patch.object(
                pipeline,
                "fetch_bytes",
                return_value=b"<!doctype html><html>old shell</html>",
            ),
        ):
            with self.assertRaisesRegex(ValueError, "not JSON"):
                pipeline.check_base(self.snapshot, "https://example.invalid")
            pipeline.check_base(
                self.snapshot, "https://example.invalid", initialize=True
            )
        with patch.object(pipeline, "ci_environment", return_value=True):
            with self.assertRaisesRegex(ValueError, "local-only"):
                pipeline.check_base(
                    self.snapshot, "https://example.invalid", initialize=True
                )
        with (
            patch.object(pipeline, "ci_environment", return_value=False),
            patch.object(pipeline, "remote_state", side_effect=invalid),
            patch.object(pipeline, "fetch_bytes", return_value=b"not HTML or JSON"),
        ):
            with self.assertRaisesRegex(ValueError, "arbitrary"):
                pipeline.check_base(
                    self.snapshot, "https://example.invalid", initialize=True
                )

    def test_local_verified_bytes_are_reused_without_second_hash(self):
        descriptor = self.descriptor()
        folder, result = self.output(descriptor)
        manifest, encoded, validation = pipeline.verify_output(folder, descriptor)
        receipt = pipeline.VerifiedBuild(result, manifest, folder, validation)
        with patch.object(
            pipeline,
            "decode_bundle",
            side_effect=AssertionError("duplicate integrity hash"),
        ):
            record, content = pipeline.record_result(
                pipeline.empty_state(), descriptor, receipt, folder
            )
        self.assertEqual(record["status"], "published")
        self.assertEqual((content.manifest, content.payload()), (manifest, encoded))

    def test_finalization_requires_every_input_and_refuses_ci(self):
        descriptor = self.descriptor()
        with self.assertRaisesRegex(ValueError, "unattempted"):
            pipeline.finalize_baseline(
                pipeline.empty_state(), self.source([descriptor])
            )
        with patch.object(pipeline, "ci_environment", return_value=True):
            with self.assertRaisesRegex(ValueError, "CI"):
                pipeline.finalize_baseline(
                    pipeline.empty_state(), self.source([descriptor])
                )


class WorkCleanupTests(unittest.TestCase):
    def test_cleanup_only_after_saved_build_keeps_outputs_and_shared_symlink_target(
        self,
    ):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            local = root / "runtime/teavm/.local"
            shared = local / "build-cache/m2"
            shared.mkdir(parents=True)
            (shared / "keep").write_text("shared")
            descriptor = {"buildId": "one", "inputFingerprint": "a" * 64}
            output = root / "delivery"
            output.mkdir()
            for name in ["extension-work", "extension-cache", "gradle-launcher"]:
                owned = local / name / "one"
                owned.mkdir(parents=True)
                (owned / "keep-until-checkpoint").write_text("owned")
                other = local / name / "other"
                other.mkdir()
                (other / "keep").write_text("other build")
            (local / "extension-cache/one/m2").symlink_to(
                shared, target_is_directory=True
            )
            pipeline.write_json(
                output / "pipeline-result.json",
                {"descriptor": descriptor, "status": "failed"},
            )
            with self.assertRaisesRegex(ValueError, "checkpoint"):
                pipeline.cleanup_built_work(output, descriptor, root)
            pipeline.write_json(
                output / "pipeline-result.json",
                {"descriptor": descriptor, "status": "built"},
            )
            removed = pipeline.cleanup_built_work(output, descriptor, root)
            self.assertEqual(len(removed), 3)
            self.assertTrue((shared / "keep").exists())
            self.assertTrue((output / "pipeline-result.json").exists())
            for name in ["extension-work", "extension-cache", "gradle-launcher"]:
                self.assertFalse((local / name / "one").exists())
                self.assertTrue((local / name / "other/keep").exists())

    def test_unsafe_build_ids_and_linked_parent_cannot_remove_unowned_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            output = root / "delivery"
            output.mkdir()
            for build_id in ["../escape", "/absolute", "", "."]:
                descriptor = {"buildId": build_id}
                pipeline.write_json(
                    output / "pipeline-result.json",
                    {"descriptor": descriptor, "status": "built"},
                )
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    pipeline.cleanup_built_work(output, descriptor, root)
            target = root / "unowned"
            (target / "one").mkdir(parents=True)
            (target / "one/keep").write_text("unowned")
            local = root / "runtime/teavm/.local"
            local.mkdir(parents=True)
            (local / "extension-work").symlink_to(target, target_is_directory=True)
            descriptor = {"buildId": "one"}
            pipeline.write_json(
                output / "pipeline-result.json",
                {"descriptor": descriptor, "status": "built"},
            )
            self.assertEqual(pipeline.cleanup_built_work(output, descriptor, root), [])
            self.assertTrue((target / "one/keep").exists())


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
        script.write_text("""import argparse, gzip, hashlib, json, os, pathlib
p=argparse.ArgumentParser()
p.add_argument('--descriptor'); p.add_argument('--output')
a=p.parse_args(); d=json.loads(pathlib.Path(a.descriptor).read_text())
assert 'GH_TOKEN' not in os.environ and 'GITHUB_TOKEN' not in os.environ
assert pathlib.Path.cwd() == pathlib.Path(__file__).resolve().parents[1]
o=pathlib.Path(a.output); (o/'artifacts').mkdir(exist_ok=True)
b=b'const frozen = true;'; h=hashlib.sha256(b).hexdigest()
e=gzip.compress(b,mtime=0); (o/'artifacts'/(h+'.gz')).write_bytes(e)
m={**json.loads((pathlib.Path(__file__).resolve().parents[1]/'protocol.json').read_text()),'bridgeVersion':2,'buildId':d['buildId'],'packageName':d['packageName'],'repoId':'fixture','version':d['versionName'],'storageSchema':'1','sourceIds':['1'],'hostScripts':[],'bundle':{'sha256':h,'path':'/extensions/artifacts/'+h+'.gz','size':len(b),'contentType':'text/javascript','encoding':'gzip','encodedSha256':hashlib.sha256(e).hexdigest(),'encodedSize':len(e)}}
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
                return_value={**PROTOCOL, "hostScripts": [], "resources": []},
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


if __name__ == "__main__":
    unittest.main()
