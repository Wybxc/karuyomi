"""No-network regressions for trusted static-deployment policy synchronization."""

import copy
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from test_register_build import fixture, snapshot

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "policy_sync", ROOT / "scripts/sync-network-policies.py"
)
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)


class PolicySyncTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.folder = Path(self.temporary.name)
        self.manifest = fixture(self.folder)
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        for migration in sorted((ROOT / "apps/api/migrations").glob("*.sql")):
            self.db.executescript(migration.read_text())
        self.insert("example.source", "old", ["example.org"])

    def tearDown(self):
        self.db.close()
        self.temporary.cleanup()

    def insert(self, package, build, hosts, status="verified"):
        self.db.execute(
            "INSERT INTO extension_builds (package_name,build_id,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (?,?,?,?,?,?)",
            (package, build, "a" * 64, status, 1, json.dumps(hosts)),
        )

    def approved(self):
        self.db.row_factory = sqlite3.Row
        rows = [
            dict(row)
            for row in self.db.execute(
                "SELECT package_name,build_id,bundle_sha256,allowed_hosts_json FROM extension_builds WHERE status='verified'"
            )
        ]
        return sync.policy_rows([{"success": True, "results": rows}])

    def run_sync(self, current, approved=None):
        sql = sync.synchronization_sql(
            current, self.approved() if approved is None else approved
        )
        self.db.execute("BEGIN")
        try:
            for statement in sql.split(";\n"):
                if statement.strip():
                    self.db.execute(statement)
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def test_current_build_inherits_approved_policy_without_new_approval(self):
        new_package = {
            **self.manifest,
            "packageName": "new.package",
            "buildId": "new-package-build",
        }
        self.insert("retired.package", "retired", ["retired.example.org"])
        current = {"example.source": self.manifest, "new.package": new_package}
        self.run_sync(current)
        rows = self.db.execute("SELECT * FROM extension_builds").fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["build_id"], self.manifest["buildId"])
        self.assertEqual(rows[0]["bundle_sha256"], self.manifest["bundle"]["sha256"])
        self.assertEqual(json.loads(rows[0]["allowed_hosts_json"]), ["example.org"])
        self.run_sync(current)
        self.assertEqual(
            self.db.execute("SELECT * FROM extension_builds").fetchall(), rows
        )

    def test_disabled_policy_is_not_promoted_or_inherited(self):
        self.db.execute("UPDATE extension_builds SET status='disabled'")
        self.run_sync({"example.source": self.manifest})
        self.assertEqual(
            self.db.execute("SELECT * FROM extension_builds").fetchall(), []
        )
        self.insert(
            "example.source", self.manifest["buildId"], ["example.org"], "disabled"
        )
        self.run_sync({"example.source": self.manifest})
        self.assertEqual(
            self.db.execute("SELECT status FROM extension_builds").fetchone()[0],
            "disabled",
        )

    def test_concurrent_disable_or_policy_edit_aborts_before_retiring_rows(self):
        self.insert("retired.package", "retired", ["retired.example.org"])
        approved = self.approved()
        for column, value in [
            ("status", "disabled"),
            ("allowed_hosts_json", '["changed.example.org"]'),
        ]:
            self.db.execute(
                "UPDATE extension_builds SET status='verified',allowed_hosts_json='[\"example.org\"]' WHERE package_name='example.source'"
            )
            self.db.execute(
                "UPDATE extension_builds SET "
                + column
                + "=? WHERE package_name='example.source'",
                (value,),
            )
            with self.subTest(column=column), self.assertRaises(sqlite3.IntegrityError):
                self.run_sync({"example.source": self.manifest}, approved)
            self.assertEqual(
                self.db.execute(
                    "SELECT build_id FROM extension_builds WHERE package_name='example.source'"
                ).fetchone()[0],
                "old",
            )
            self.assertIsNotNone(
                self.db.execute(
                    "SELECT * FROM extension_builds WHERE package_name='retired.package'"
                ).fetchone()
            )

    def test_empty_current_index_retires_all_approvals(self):
        self.run_sync({})
        self.assertEqual(
            self.db.execute("SELECT * FROM extension_builds").fetchall(), []
        )

    def test_metadata_sync_does_not_require_or_read_bundle_bytes(self):
        snapshot(self.folder, self.manifest)
        (self.folder / (self.manifest["bundle"]["sha256"] + ".gz")).unlink()
        with patch.object(
            sync.registration,
            "verify_gzip",
            side_effect=AssertionError("body transfer"),
        ):
            current = sync.current_builds(
                sync.registration.snapshot_loader(self.folder)
            )
        self.assertEqual(current["example.source"], self.manifest)

    def test_current_manifest_identity_must_match_static_index(self):
        _, _, path = snapshot(self.folder, self.manifest)
        path.write_text(json.dumps({**self.manifest, "buildId": "different"}))
        with self.assertRaisesRegex(ValueError, "does not match"):
            sync.current_builds(sync.registration.snapshot_loader(self.folder))

    def test_malformed_d1_json_and_unapproved_hosts_fail_closed(self):
        for response in [
            {},
            [],
            [{"success": False, "results": []}],
            [{"success": True, "results": [{}]}],
        ]:
            with self.subTest(response=response), self.assertRaises(ValueError):
                sync.policy_rows(response)
        for hosts in [
            ["*.example.org"],
            ["127.0.0.1"],
            ["service.internal"],
            [True],
            "example.org",
        ]:
            rows = copy.deepcopy(self.approved())
            rows[0]["allowed_hosts_json"] = json.dumps(hosts)
            with self.subTest(hosts=hosts), self.assertRaises(ValueError):
                sync.policy_rows([{"success": True, "results": rows}])

    def test_remote_never_accepts_local_snapshot_or_state(self):
        for option in ["--static-root", "--persist-to"]:
            with (
                patch(
                    "sys.argv",
                    ["sync-network-policies.py", "--remote", option, str(self.folder)],
                ),
                patch("sys.stderr"),
                self.assertRaises(SystemExit),
            ):
                sync.main()


if __name__ == "__main__":
    unittest.main()
