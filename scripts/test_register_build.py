"""Static authority, bounded transfer verification and policy-only D1 tests."""

import copy
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "register_build", ROOT / "scripts/register-build.py"
)
register = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(register)


def fixture(folder, content=b"const source = 1;"):
    digest = hashlib.sha256(content).hexdigest()
    encoded = gzip.compress(content, mtime=0)
    (folder / (digest + ".gz")).write_bytes(encoded)
    return {
        **json.loads((ROOT / "packages/contracts/protocol.json").read_text()),
        "bridgeVersion": 2,
        "buildId": "regression-build",
        "packageName": "example.source",
        "repoId": "example",
        "version": "1",
        "storageSchema": "1",
        "sourceIds": ["9223372036854775807"],
        "bundle": {
            "path": "/extensions/artifacts/" + digest + ".gz",
            "sha256": digest,
            "size": len(content),
            "contentType": "application/javascript",
            "encoding": "gzip",
            "encodedSha256": hashlib.sha256(encoded).hexdigest(),
            "encodedSize": len(encoded),
        },
        "hostScripts": [],
    }


def snapshot(folder, manifest):
    index = {
        "schemaVersion": 1,
        "builds": [
            {
                **{
                    key: manifest[key]
                    for key in (
                        "buildId",
                        "packageName",
                        "repoId",
                        "version",
                        "sourceIds",
                    )
                },
                "manifestPath": "/extensions/builds/"
                + manifest["buildId"]
                + "/manifest.json",
            }
        ],
        "nextCursor": None,
    }
    index_path = folder / "extensions/index.json"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(index))
    manifest_path = folder / index["builds"][0]["manifestPath"].lstrip("/")
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest))
    return index, index_path, manifest_path


class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)
        self.manifest = fixture(self.folder)
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.db.execute("PRAGMA foreign_keys=ON")
        for migration in sorted((ROOT / "apps/api/migrations").glob("*.sql")):
            self.db.executescript(migration.read_text())

    def tearDown(self):
        self.db.close()
        self.temporary.cleanup()

    def sql(self, manifest=None, hosts=None):
        manifest = manifest or self.manifest
        return register.registration_sql(
            manifest, register.verify(manifest, self.folder), hosts or ["example.org"]
        )

    def execute(self, sql):
        self.db.execute("BEGIN")
        try:
            for statement in sql.split(";\n"):
                if statement.strip():
                    self.db.execute(statement)
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def rows(self):
        return self.db.execute(
            "SELECT build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json FROM extension_builds"
        ).fetchall()

    def test_policy_only_idempotent_registration(self):
        self.execute(self.sql())
        before = self.rows()
        self.execute(self.sql())
        self.assertEqual(self.rows(), before)
        self.assertEqual(before[0][3], "verified")
        tables = {
            row[0]
            for row in self.db.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        self.assertNotIn("extension_artifacts", tables)
        self.assertNotIn("build_artifacts", tables)
        self.assertNotIn(
            "manifest_json",
            {row[1] for row in self.db.execute("PRAGMA table_info(extension_builds)")},
        )

    def test_new_current_build_replaces_previous_package_policy(self):
        self.execute(self.sql())
        current = copy.deepcopy(self.manifest)
        current["buildId"] = "next-current"
        self.execute(self.sql(current, ["new.example.org"]))
        self.assertEqual(len(self.rows()), 1)
        self.assertEqual(self.rows()[0][0], "next-current")
        self.assertEqual(json.loads(self.rows()[0][5]), ["new.example.org"])

    def test_build_identity_and_policy_conflicts_rollback_entire_batch(self):
        self.execute(self.sql())
        before = self.rows()
        conflict = fixture(self.folder, b"const source = 2;")
        for manifest, hosts in [
            (conflict, ["example.org"]),
            (self.manifest, ["other.example.org"]),
            ({**self.manifest, "packageName": "other.package"}, ["example.org"]),
        ]:
            with self.subTest(manifest=manifest["packageName"], hosts=hosts):
                with self.assertRaises(sqlite3.IntegrityError):
                    self.execute(
                        "INSERT INTO app_metadata VALUES ('rollback','marker');\n"
                        + self.sql(manifest, hosts)
                    )
                self.assertEqual(self.rows(), before)
                self.assertEqual(
                    self.db.execute("SELECT * FROM app_metadata").fetchall(), []
                )

    def test_migration_retires_old_distribution_rows(self):
        db = sqlite3.connect(":memory:")
        try:
            db.executescript(
                (ROOT / "apps/api/migrations/0001_many_major_mapleleaf.sql").read_text()
            )
            db.execute(
                "INSERT INTO extension_builds VALUES ('old','package','{}','verified',0,'[]')"
            )
            db.executescript(
                (
                    ROOT / "apps/api/migrations/0002_complete_mister_sinister.sql"
                ).read_text()
            )
            self.assertEqual(
                db.execute(
                    "SELECT build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json FROM extension_builds"
                ).fetchall(),
                [],
            )
        finally:
            db.close()

    def test_only_gzip_bundle_file_is_read_and_both_hashes_checked(self):
        self.assertEqual(
            list(register.verify(self.manifest, self.folder)),
            [self.manifest["bundle"]["sha256"]],
        )
        for key in ["sha256", "encodedSha256"]:
            manifest = copy.deepcopy(self.manifest)
            original = self.folder / (manifest["bundle"]["sha256"] + ".gz")
            manifest["bundle"][key] = "a" * 64
            if key == "sha256":
                manifest["bundle"]["path"] = "/extensions/artifacts/" + "a" * 64 + ".gz"
                (self.folder / ("a" * 64 + ".gz")).write_bytes(original.read_bytes())
            with (
                self.subTest(key=key),
                self.assertRaisesRegex(ValueError, "integrity mismatch"),
            ):
                register.verify(manifest, self.folder)

    def test_gzip_truncation_trailing_members_and_bomb_are_bounded(self):
        bundle = self.manifest["bundle"]
        file = self.folder / (bundle["sha256"] + ".gz")
        original = file.read_bytes()
        for data in [
            original[:-1],
            original + b"trailing",
            original + original,
            gzip.compress(b"X" * (4 * 1024 * 1024), mtime=0),
            b"invalid",
        ]:
            file.write_bytes(data)
            bundle["encodedSize"] = len(data)
            bundle["encodedSha256"] = hashlib.sha256(data).hexdigest()
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                register.verify(self.manifest, self.folder)

    def test_valid_large_gzip_uses_bounded_reads(self):
        manifest = fixture(self.folder, bytes(range(256)) * 2048)
        register.verify(manifest, self.folder)
        with patch.object(
            Path, "read_bytes", side_effect=AssertionError("whole artifact read")
        ):
            register.verify(manifest, self.folder)

    def test_schema_only_mode_never_reads_bytes_but_keeps_metadata_and_stat_checks(
        self,
    ):
        with patch.object(
            register,
            "verify_gzip",
            side_effect=AssertionError("redundant verification"),
        ):
            register.verify(self.manifest, self.folder, verify_hashes=False)
        self.manifest["bundle"]["encodedSize"] += 1
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            register.verify(self.manifest, self.folder, verify_hashes=False)

    def test_bad_metadata_symlink_and_raw_artifacts_are_rejected(self):
        for key, value in [
            ("path", "/api/extensions/artifacts/" + self.manifest["bundle"]["sha256"]),
            ("encoding", "br"),
            ("encodedSha256", "a"),
            ("encodedSize", True),
            ("size", 0),
            ("contentType", "application/octet-stream"),
        ]:
            manifest = copy.deepcopy(self.manifest)
            manifest["bundle"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                register.verify(manifest, self.folder)
        file = self.folder / (self.manifest["bundle"]["sha256"] + ".gz")
        target = self.folder / "target"
        file.rename(target)
        file.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "regular"):
            register.verify(self.manifest, self.folder)

    def test_malformed_manifest_rejected(self):
        for key, value in [
            ("sourceIds", []),
            ("bridgeVersion", True),
            ("bridgeVersion", 1),
            ("packageName", ""),
            ("hostScripts", [None]),
            ("resources", [{"logicalName": ""}]),
        ]:
            manifest = copy.deepcopy(self.manifest)
            manifest[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                register.verify(manifest, self.folder)

    def test_shared_materials_match_current_catalog_without_transfer(self):
        catalog = register.material_catalog()
        self.manifest["hostScripts"] = copy.deepcopy(catalog["hostScripts"])
        self.manifest["resources"] = catalog["resources"]
        self.assertEqual(
            len(
                register.verify(
                    self.manifest, self.folder, material_catalog_override=catalog
                )
            ),
            1,
        )
        self.manifest["hostScripts"][0] = {**catalog["hostScripts"][0], "size": 1}
        with self.assertRaisesRegex(ValueError, "shared runtime"):
            register.verify(
                self.manifest, self.folder, material_catalog_override=catalog
            )

    def test_bundle_cannot_be_material_and_material_cannot_be_encoded_bundle(self):
        catalog = register.material_catalog()
        manifest = copy.deepcopy(self.manifest)
        manifest["bundle"] = catalog["hostScripts"][0]
        with self.assertRaises(ValueError):
            register.verify(manifest, self.folder, material_catalog_override=catalog)
        for role in ["hostScripts", "resources"]:
            manifest = copy.deepcopy(self.manifest)
            manifest[role] = [{**manifest["bundle"], "logicalName": "x.js"}]
            with self.assertRaisesRegex(ValueError, "shared runtime"):
                register.verify(manifest, self.folder)
        manifest = copy.deepcopy(self.manifest)
        manifest["hostScripts"] = [{**catalog["hostScripts"][0], "encoding": "gzip"}]
        with self.assertRaisesRegex(ValueError, "unencoded"):
            register.verify(manifest, self.folder, material_catalog_override=catalog)

    def test_current_static_authority_is_required(self):
        index, index_path, manifest_path = snapshot(self.folder, self.manifest)
        load = register.snapshot_loader(self.folder)
        register.verify_static_authority(self.manifest, load)
        for key, value in [
            ("buildId", "old"),
            ("version", "other"),
            ("sourceIds", ["1"]),
            ("manifestPath", "https://other.example/manifest"),
        ]:
            changed = copy.deepcopy(index)
            changed["builds"][0][key] = value
            index_path.write_text(json.dumps(changed))
            with self.subTest(key=key), self.assertRaises(ValueError):
                register.verify_static_authority(self.manifest, load)
        index_path.write_text(json.dumps(index))
        manifest_path.write_text(json.dumps({**self.manifest, "version": "other"}))
        with self.assertRaisesRegex(ValueError, "differs"):
            register.verify_static_authority(self.manifest, load)

    def test_duplicate_static_packages_and_missing_build_are_rejected(self):
        index, index_path, _ = snapshot(self.folder, self.manifest)
        for builds in [[], index["builds"] * 2]:
            index_path.write_text(json.dumps({**index, "builds": builds}))
            with self.assertRaises(ValueError):
                register.verify_static_authority(
                    self.manifest, register.snapshot_loader(self.folder)
                )

    def test_local_cli_registers_only_policy_after_snapshot_check(self):
        _, _, manifest_path = snapshot(self.folder, self.manifest)
        calls = []

        def run(arguments, **_kwargs):
            calls.append(arguments)
            sql = Path(arguments[arguments.index("--file") + 1]).read_text()
            self.assertNotIn("extension_artifacts", sql)
            self.assertNotIn("manifest_json", sql)
            self.execute(sql)

        with (
            patch(
                "sys.argv",
                [
                    "register-build.py",
                    str(manifest_path),
                    "--artifacts",
                    str(self.folder),
                    "--local",
                    "--static-root",
                    str(self.folder),
                    "--allow-host",
                    "example.org",
                ],
            ),
            patch.object(register.subprocess, "run", side_effect=run),
            patch("builtins.print"),
        ):
            register.main()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][3:5], ["d1", "execute"])
        self.assertEqual(len(self.rows()), 1)

    def test_registration_retires_builds_removed_from_current_static_index(self):
        self.execute(self.sql())
        other = {
            **self.manifest,
            "packageName": "removed.package",
            "buildId": "removed",
        }
        self.execute(self.sql(other))
        self.assertEqual(len(self.rows()), 2)
        self.execute(
            register.registration_sql(
                self.manifest,
                {},
                ["example.org"],
                current_build_ids={self.manifest["buildId"]},
            )
        )
        self.assertEqual(len(self.rows()), 1)
        self.assertEqual(self.rows()[0][0], self.manifest["buildId"])

    def test_plan_only_never_writes_or_contacts_deployed_authority(self):
        path = self.folder / "manifest.json"
        path.write_text(json.dumps(self.manifest))
        with (
            patch(
                "sys.argv",
                ["register-build.py", str(path), "--artifacts", str(self.folder)],
            ),
            patch.object(register, "deployed_loader") as load,
            patch.object(register.subprocess, "run") as run,
            patch("builtins.print"),
        ):
            register.main()
        load.assert_not_called()
        run.assert_not_called()

    def test_encoded_asset_cloudflare_limit_is_enforced_before_read(self):
        self.manifest["bundle"]["encodedSize"] = 25 * 1024 * 1024 + 1
        with self.assertRaisesRegex(ValueError, "gzip bundle metadata"):
            register.verify(self.manifest, self.folder, verify_hashes=False)

    def test_remote_cannot_use_local_snapshot_or_register_stale_index(self):
        _, _, manifest_path = snapshot(self.folder, self.manifest)
        with (
            patch(
                "sys.argv",
                [
                    "register-build.py",
                    str(manifest_path),
                    "--remote",
                    "--static-root",
                    str(self.folder),
                ],
            ),
            patch("sys.stderr"),
            self.assertRaises(SystemExit),
        ):
            register.main()
        with (
            patch(
                "sys.argv",
                [
                    "register-build.py",
                    str(manifest_path),
                    "--artifacts",
                    str(self.folder),
                    "--remote",
                ],
            ),
            patch.object(
                register,
                "deployed_loader",
                return_value=lambda _path, _limit: {
                    "schemaVersion": 1,
                    "builds": [],
                    "nextCursor": None,
                },
            ),
            patch.object(register.subprocess, "run") as run,
            self.assertRaisesRegex(ValueError, "not current"),
        ):
            register.main()
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
