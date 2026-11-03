"""Registration conflict/rollback regressions; no cloud credentials or network."""

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "register_build", ROOT / "scripts/register-build.py"
)
register = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(register)


def fixture(folder, content=b"const source = 1;"):
    digest = hashlib.sha256(content).hexdigest()
    (folder / digest).write_bytes(content)
    return {
        **json.loads((ROOT / "packages/contracts/protocol.json").read_text()),
        "bridgeVersion": 1,
        "buildId": "regression-build",
        "packageName": "example.source",
        "repoId": "example",
        "version": "1",
        "storageSchema": "1",
        "sourceIds": ["9223372036854775807"],
        "bundle": {
            "path": "/api/extensions/artifacts/" + digest,
            "sha256": digest,
            "size": len(content),
            "contentType": "application/javascript",
        },
        "hostScripts": [],
    }


class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)
        self.manifest = fixture(self.folder)
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript(
            (ROOT / "apps/api/migrations/0001_many_major_mapleleaf.sql").read_text()
        )

    def tearDown(self):
        self.db.close()
        self.temporary.cleanup()

    def sql(self, manifest=None, hosts=None):
        manifest = manifest or self.manifest
        return register.registration_sql(
            manifest, register.verify(manifest, self.folder), hosts or ["example.org"]
        )

    def execute(self, sql):
        # Mirrors D1's single-file batch transaction. Test the real workerd D1
        # adapter separately; D1 intentionally disallows explicit SQL BEGIN.
        self.db.execute("BEGIN")
        try:
            for statement in sql.split(";\n"):
                if statement.strip():
                    self.db.execute(statement)
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def rows(self, table):
        return self.db.execute("SELECT * FROM " + table).fetchall()

    def test_publish_and_identical_retry_are_idempotent(self):
        self.execute(self.sql())
        before = self.rows("extension_builds")
        self.execute(self.sql())
        self.assertEqual(self.rows("extension_builds"), before)
        self.assertEqual(before[0][3], "verified")
        self.assertEqual(len(self.rows("build_artifacts")), 1)

    def test_legacy_json_whitespace_and_object_key_order_are_equivalent(self):
        self.execute(self.sql())
        value = json.dumps(dict(reversed(list(self.manifest.items()))), indent=2)
        self.db.execute(
            "UPDATE extension_builds SET manifest_json=?,allowed_hosts_json=?",
            (value, '[ "example.org" ]'),
        )
        self.execute(self.sql())
        self.assertEqual(self.rows("extension_builds")[0][3], "verified")

    def test_conflicting_build_never_adds_artifacts_to_verified_build(self):
        self.execute(self.sql())
        before = {
            table: self.rows(table)
            for table in ["extension_builds", "extension_artifacts", "build_artifacts"]
        }
        conflict = fixture(self.folder, b"const source = 2;")
        with self.assertRaises(sqlite3.IntegrityError):
            self.execute(self.sql(conflict))
        self.assertEqual({table: self.rows(table) for table in before}, before)

    def test_network_policy_conflict_fails_without_republishing(self):
        self.execute(self.sql())
        with self.assertRaises(sqlite3.IntegrityError):
            self.execute(self.sql(hosts=["another.example"]))
        self.assertEqual(
            json.loads(self.rows("extension_builds")[0][5]), ["example.org"]
        )

    def test_artifact_metadata_conflict_rolls_back_new_build(self):
        self.execute(self.sql())
        new_build = copy.deepcopy(self.manifest)
        new_build["buildId"] = "second-build"
        new_build["bundle"]["contentType"] = "application/octet-stream"
        with self.assertRaises(sqlite3.IntegrityError):
            self.execute(self.sql(new_build))
        self.assertEqual(len(self.rows("extension_builds")), 1)
        self.assertEqual(len(self.rows("build_artifacts")), 1)

    def test_unexpected_association_cannot_be_silently_published(self):
        self.execute(self.sql())
        self.db.execute(
            "INSERT INTO extension_artifacts VALUES (?,?,?,?)",
            ("b" * 64, "artifacts/" + "b" * 64, 1, "application/javascript"),
        )
        self.db.execute(
            "INSERT INTO build_artifacts VALUES (?,?)",
            (self.manifest["buildId"], "b" * 64),
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.execute(self.sql())

    def test_malformed_or_incompatible_manifest_is_rejected_before_upload(self):
        for key, value in [
            ("sourceIds", []),
            ("bridgeVersion", True),
            ("packageName", ""),
            ("hostScripts", [None]),
            ("resources", [{"logicalName": ""}]),
        ]:
            manifest = copy.deepcopy(self.manifest)
            manifest[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                register.verify(manifest, self.folder)

    def test_conflicting_mime_for_duplicate_hash_is_rejected(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["hostScripts"] = [
            {**manifest["bundle"], "contentType": "application/wasm"}
        ]
        with self.assertRaises(ValueError):
            register.verify(manifest, self.folder)

    def test_shared_materials_are_catalog_checked_without_private_uploads(self):
        catalog = register.material_catalog()
        self.manifest["hostScripts"] = catalog["hostScripts"]
        self.manifest["resources"] = catalog["resources"]
        artifacts = register.verify(self.manifest, self.folder)
        self.assertEqual(list(artifacts), [self.manifest["bundle"]["sha256"]])
        self.execute(self.sql())
        self.assertEqual(len(self.rows("extension_artifacts")), 1)
        self.assertEqual(len(self.rows("build_artifacts")), 1)

    def test_shared_material_hash_size_mime_role_and_name_are_bound(self):
        catalog = register.material_catalog()
        for key, value in [
            ("sha256", "b" * 64),
            ("size", 1),
            ("contentType", "application/wasm"),
        ]:
            manifest = copy.deepcopy(self.manifest)
            manifest["hostScripts"] = [dict(catalog["hostScripts"][0], **{key: value})]
            if key == "sha256":
                manifest["hostScripts"][0]["path"] = "/runtime/materials/" + value
            with self.subTest(key=key), self.assertRaises(ValueError):
                register.verify(manifest, self.folder)
        manifest = copy.deepcopy(self.manifest)
        manifest["hostScripts"] = catalog["resources"]
        with self.assertRaises(ValueError):
            register.verify(manifest, self.folder)
        manifest["hostScripts"] = []
        manifest["resources"] = [
            dict(catalog["resources"][0], logicalName="different.wasm")
        ]
        with self.assertRaises(ValueError):
            register.verify(manifest, self.folder)

    def test_public_bundle_is_rejected_even_if_it_matches_a_material(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["bundle"] = register.material_catalog()["hostScripts"][0]
        with self.assertRaises(ValueError):
            register.verify(manifest, self.folder)

    def test_failed_upload_never_starts_metadata_publication(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["hostScripts"] = [fixture(self.folder, b"const helper = 1;")["bundle"]]
        path = self.folder / "manifest.json"
        path.write_text(json.dumps(manifest))
        calls = []

        def fail_second_upload(arguments, **_kwargs):
            calls.append(arguments)
            if len(calls) == 2:
                raise subprocess.CalledProcessError(1, arguments)

        with (
            patch(
                "sys.argv",
                [
                    "register-build.py",
                    str(path),
                    "--artifacts",
                    str(self.folder),
                    "--local",
                ],
            ),
            patch.object(register.subprocess, "run", side_effect=fail_second_upload),
            patch("builtins.print"),
            self.assertRaises(subprocess.CalledProcessError),
        ):
            register.main()
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call[3] == "r2" for call in calls))


if __name__ == "__main__":
    unittest.main()
