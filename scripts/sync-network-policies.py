#!/usr/bin/env python3
"""After static deployment, carry approved package network policies to current builds.

This trusted deployment command needs D1 credentials; AOT build jobs do not. It
never approves a new package, learns hosts from requests, or transfers artifacts.
"""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "registration", ROOT / "scripts/register-build.py"
)
registration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(registration)


def current_builds(load):
    index = registration.load_static_index(load)
    catalog = None
    current = {}
    for item in index["builds"]:
        manifest = load(item["manifestPath"], 1024 * 1024)
        if not isinstance(manifest, dict) or any(
            manifest.get(key) != item.get(key)
            for key in ("buildId", "packageName", "repoId", "version", "sourceIds")
        ):
            raise ValueError("Static manifest does not match current index")
        if manifest.get("hostScripts") or manifest.get("resources"):
            catalog = (
                catalog if catalog is not None else registration.material_catalog()
            )
        registration.verify_metadata(manifest, material_catalog_override=catalog)
        current[item["packageName"]] = manifest
    return current


def policy_rows(value):
    if (
        not isinstance(value, list)
        or len(value) != 1
        or not isinstance(value[0], dict)
        or value[0].get("success") is not True
        or not isinstance(value[0].get("results"), list)
    ):
        raise ValueError("Invalid Wrangler D1 JSON response")
    rows = value[0]["results"]
    packages = set()
    for row in rows:
        if (
            not isinstance(row, dict)
            or any(
                not isinstance(row.get(key), str)
                for key in (
                    "package_name",
                    "build_id",
                    "bundle_sha256",
                    "allowed_hosts_json",
                )
            )
            or row["package_name"] in packages
        ):
            raise ValueError("Invalid approved network policy row")
        hosts = json.loads(row["allowed_hosts_json"])
        if not isinstance(hosts, list) or not all(
            isinstance(host, str)
            and re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host)
            and "." in host
            and not host.replace(".", "").isdigit()
            and not re.search(
                r"(?:^|\.)(?:localhost|local|internal|home|invalid|test)$", host
            )
            for host in hosts
        ):
            raise ValueError("Invalid approved hostname policy")
        packages.add(row["package_name"])
    return rows


def synchronization_sql(current, approved):
    quote = registration.quote
    statements = []
    for row in approved:
        manifest = current.get(row["package_name"])
        if manifest is None:
            continue
        # Preserve the policy bytes and approval status. A concurrent disable or
        # policy edit aborts the entire transaction instead of overwriting it.
        statements.append(
            "UPDATE extension_builds SET bundle_sha256=CASE WHEN build_id="
            + quote(row["build_id"])
            + " AND bundle_sha256="
            + quote(row["bundle_sha256"])
            + " AND status='verified' AND json(allowed_hosts_json)=json("
            + quote(row["allowed_hosts_json"])
            + ")"
            + " THEN "
            + quote(manifest["bundle"]["sha256"])
            + " ELSE NULL END,build_id="
            + quote(manifest["buildId"])
            + " WHERE package_name="
            + quote(row["package_name"])
            + ";"
        )
    ids = [manifest["buildId"] for manifest in current.values()]
    statements.append(
        "DELETE FROM extension_builds"
        + (
            " WHERE build_id NOT IN ("
            + ",".join(quote(value) for value in sorted(ids))
            + ")"
            if ids
            else ""
        )
        + ";"
    )
    return "\n".join(statements) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--remote", action="store_true")
    destination.add_argument("--local", action="store_true")
    parser.add_argument("--static-root", type=Path)
    parser.add_argument("--persist-to", type=Path)
    args = parser.parse_args()
    if args.local and not args.static_root:
        parser.error("--local requires an explicit --static-root snapshot")
    if args.remote and (args.static_root or args.persist_to):
        parser.error(
            "Local static snapshots/state cannot be used for remote synchronization"
        )
    if args.local:
        load = registration.snapshot_loader(args.static_root)
    else:
        configuration = (ROOT / "apps/api/wrangler.jsonc").read_text()
        origin = re.search(r'"APP_ORIGIN":\s*"([^"\n]+)"', configuration)
        if not origin:
            parser.error("APP_ORIGIN is missing")
        load = registration.deployed_loader(origin[1])
    current = current_builds(load)
    environment = dict(os.environ)
    environment["CLOUDFLARE_SEND_METRICS"] = "false"
    environment.setdefault(
        "WRANGLER_LOG_PATH", str(ROOT / ".local/extensions/network-policy-sync.log")
    )
    target = ["--remote"] if args.remote else ["--local"]
    if args.persist_to:
        target += ["--persist-to", str(args.persist_to.resolve())]

    def execute(arguments):
        return subprocess.check_output(
            ["pnpm", "exec", "wrangler", "d1", "execute", "DB", *target, *arguments],
            cwd=ROOT / "apps/api",
            env=environment,
            text=True,
        )

    approved = policy_rows(
        json.loads(
            execute(
                [
                    "--command",
                    "SELECT package_name,build_id,bundle_sha256,allowed_hosts_json FROM extension_builds WHERE status='verified'",
                    "--json",
                ]
            )
        )
    )
    sql = synchronization_sql(current, approved)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".sql", prefix="karuyomi-policy-sync-", delete=False
    ) as stream:
        stream.write(sql)
        sql_path = Path(stream.name)
    try:
        execute(["--file", str(sql_path), "--yes", "--json"])
    finally:
        sql_path.unlink(missing_ok=True)
    print(
        json.dumps(
            {
                "currentPackages": len(current),
                "inheritedPolicies": sum(
                    row["package_name"] in current for row in approved
                ),
                "newPackagesRemainUnapproved": len(
                    set(current) - {row["package_name"] for row in approved}
                ),
                "destination": "remote" if args.remote else "local",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
