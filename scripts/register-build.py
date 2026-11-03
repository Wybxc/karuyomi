#!/usr/bin/env python3
"""Verify every artifact, then register one immutable build locally or remotely.

Without --local/--remote, only prints the reviewed import plan. Network domains
must be explicitly supplied; they are not learned from extension requests.
"""

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def material_catalog():
    # Metadata comes from the pinned host sources, never from the build being
    # registered. --print does not require npm packages or the private JVM seed.
    return json.loads(
        subprocess.check_output(
            [
                "node",
                str(ROOT / "packages/runtime-host/prepare-materials.mjs"),
                "--print",
            ],
            cwd=ROOT,
            text=True,
        )
    )


def verify(manifest, folder):
    if not isinstance(manifest, dict):
        raise ValueError("Invalid build manifest")
    protocol = json.loads((ROOT / "packages/contracts/protocol.json").read_text())
    for key, value in protocol.items():
        if type(manifest.get(key)) is not type(value) or manifest.get(key) != value:
            raise ValueError("Incompatible " + key)
    if not isinstance(manifest.get("buildId"), str) or not re.fullmatch(
        r"[a-zA-Z0-9._-]{1,200}", manifest["buildId"]
    ):
        raise ValueError("Invalid build ID")
    for name, maximum in [
        ("packageName", 200),
        ("repoId", 200),
        ("version", 100),
        ("storageSchema", 100),
    ]:
        value = manifest.get(name)
        if not isinstance(value, str) or not 1 <= len(value) <= maximum:
            raise ValueError("Invalid " + name)
    if type(manifest.get("bridgeVersion")) is not int or manifest["bridgeVersion"] != 1:
        raise ValueError("Incompatible bridgeVersion")
    source_ids = manifest.get("sourceIds")
    if (
        not isinstance(source_ids, list)
        or not 1 <= len(source_ids) <= 500
        or not all(
            isinstance(value, str) and re.fullmatch(r"-?\d+", value, flags=re.ASCII)
            for value in source_ids
        )
    ):
        raise ValueError("Invalid source IDs")
    for name in ["hostScripts", "resources"]:
        values = manifest.get(name, [] if name == "resources" else None)
        if not isinstance(values, list) or len(values) > 16:
            raise ValueError("Invalid " + name)
    for artifact in manifest.get("resources", []):
        if (
            not isinstance(artifact, dict)
            or not isinstance(artifact.get("logicalName"), str)
            or not 1 <= len(artifact["logicalName"]) <= 100
        ):
            raise ValueError("Invalid resource logical name")
    artifacts = [
        manifest.get("bundle"),
        *manifest["hostScripts"],
        *manifest.get("resources", []),
    ]
    result = {}
    seen = {}
    catalog = None
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict) or not isinstance(
            artifact.get("sha256"), str
        ):
            raise ValueError("Invalid artifact")
        digest = artifact["sha256"]
        private = artifact.get("path") == "/api/extensions/artifacts/" + digest
        shared = artifact.get("path") == "/runtime/materials/" + digest
        if (
            not re.fullmatch("[a-f0-9]{64}", digest)
            or not (private or shared)
            or (index == 0 and not private)
        ):
            raise ValueError("Invalid artifact reference")
        if (
            type(artifact.get("size")) is not int
            or not 0 < artifact["size"] <= 64 * 1024 * 1024
        ):
            raise ValueError("Invalid artifact size")
        content_type = artifact.get("contentType", "application/octet-stream")
        if content_type not in (
            "application/javascript",
            "text/javascript",
            "application/wasm",
            "application/octet-stream",
            "application/json",
        ):
            raise ValueError("Unsupported artifact MIME")
        if digest in seen and content_type != seen[digest]:
            raise ValueError("Conflicting MIME for the same artifact")
        seen[digest] = content_type
        if shared:
            if catalog is None:
                catalog = material_catalog()
            role = (
                "hostScripts" if index <= len(manifest["hostScripts"]) else "resources"
            )
            candidates = catalog[role]
            if role == "hostScripts":
                candidates = [*candidates, *catalog.get("compatibility", [])]
            expected = next(
                (value for value in candidates if value["sha256"] == digest), None
            )
            if expected is None or any(
                artifact.get(key) != expected[key]
                for key in ["path", "sha256", "size", "contentType"]
            ):
                raise ValueError("Unknown or incompatible shared runtime material")
            if (
                role == "resources"
                and artifact["logicalName"] != expected["logicalName"]
            ):
                raise ValueError("Shared resource logical name mismatch")
            # Static/app materials are verified against the host catalog, and
            # never uploaded to private R2 or associated in build_artifacts.
            continue
        file = folder / digest
        size = file.stat().st_size
        if not 0 < size <= 64 * 1024 * 1024 or size != artifact["size"]:
            raise ValueError("Artifact size mismatch: " + digest)
        with file.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != digest:
            raise ValueError("Artifact integrity mismatch: " + digest)
        result[digest] = artifact
    if sum(artifact["size"] for artifact in artifacts) > 96 * 1024 * 1024:
        raise ValueError("Build exceeds runtime budget")
    return result


def registration_sql(manifest, artifacts, hosts):
    manifest_json = json.dumps(
        manifest, separators=(",", ":"), ensure_ascii=False, sort_keys=True
    )
    build_id = quote(manifest["buildId"])
    hosts_json = json.dumps(sorted(set(hosts)), separators=(",", ":"))
    # Wrangler --file submits these statements as a D1 transaction. Avoid SQL
    # BEGIN/COMMIT, which D1 rejects. A NOT NULL guard aborts the entire batch on
    # any immutable identity conflict, including existing verified build IDs.
    same_manifest = " AND ".join(
        "NOT EXISTS (SELECT fullkey,type,atom FROM json_tree("
        + first
        + ") EXCEPT "
        + "SELECT fullkey,type,atom FROM json_tree("
        + second
        + "))"
        for first, second in [
            ("extension_builds.manifest_json", "excluded.manifest_json"),
            ("excluded.manifest_json", "extension_builds.manifest_json"),
        ]
    )
    statements = [
        "INSERT INTO extension_builds (build_id,package_name,manifest_json,status,created_at,allowed_hosts_json) VALUES ("
        + ",".join(
            (
                build_id,
                quote(manifest["packageName"]),
                quote(manifest_json),
                quote("disabled"),
                "unixepoch()",
                quote(hosts_json),
            )
        )
        + ") ON CONFLICT(build_id) DO UPDATE SET manifest_json=CASE WHEN "
        + "extension_builds.package_name=excluded.package_name AND "
        + same_manifest
        + " AND json(extension_builds.allowed_hosts_json)=json(excluded.allowed_hosts_json) THEN extension_builds.manifest_json ELSE NULL END;"
    ]
    for digest, artifact in artifacts.items():
        content_type = artifact.get("contentType", "application/octet-stream")
        if content_type not in (
            "application/javascript",
            "text/javascript",
            "application/wasm",
            "application/octet-stream",
            "application/json",
        ):
            raise ValueError("Unsupported artifact MIME")
        statements.append(
            "INSERT INTO extension_artifacts (sha256,object_key,size,content_type) VALUES ("
            + ",".join(
                (
                    quote(digest),
                    quote("artifacts/" + digest),
                    str(artifact["size"]),
                    quote(content_type),
                )
            )
            + ") ON CONFLICT(sha256) DO UPDATE SET object_key=CASE WHEN "
            + "extension_artifacts.object_key=excluded.object_key AND extension_artifacts.size=excluded.size "
            + "AND extension_artifacts.content_type=excluded.content_type THEN extension_artifacts.object_key ELSE NULL END;"
        )
    for digest in artifacts:
        statements.append(
            "INSERT OR IGNORE INTO build_artifacts (build_id,sha256) VALUES ("
            + build_id
            + ","
            + quote(digest)
            + ");"
        )
    # Refuse unexpected prior associations instead of silently succeeding with
    # extra public artifacts (including a previously polluted build).
    statements.append(
        "UPDATE extension_builds SET status='verified', manifest_json=CASE WHEN "
        + "(SELECT count(*) FROM build_artifacts WHERE build_id="
        + build_id
        + ")="
        + str(len(artifacts))
        + " THEN manifest_json ELSE NULL END WHERE build_id="
        + build_id
        + ";"
    )
    return "\n".join(statements) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--artifacts", type=Path, default=ROOT / "runtime/teavm/.local/artifacts"
    )
    parser.add_argument("--allow-host", action="append", default=[])
    destination = parser.add_mutually_exclusive_group()
    destination.add_argument("--local", action="store_true")
    destination.add_argument("--remote", action="store_true")
    parser.add_argument(
        "--persist-to",
        type=Path,
        help="Dedicated Wrangler state directory (requires --local)",
    )
    args = parser.parse_args()
    if args.persist_to and not args.local:
        parser.error("--persist-to requires --local")
    args.artifacts = args.artifacts.resolve()
    manifest = json.loads(args.manifest.read_text())
    artifacts = verify(manifest, args.artifacts)
    hosts = sorted(set(args.allow_host))
    for host in hosts:
        if (
            not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host)
            or "." not in host
            or host.replace(".", "").isdigit()
            or re.search(
                r"(?:^|\.)(?:localhost|local|internal|home|invalid|test)$", host
            )
        ):
            parser.error("Network policy requires explicit public hostnames")
    sql = registration_sql(manifest, artifacts, hosts)
    print(
        json.dumps(
            {
                "buildId": manifest["buildId"],
                "artifacts": len(artifacts),
                "totalBytes": sum(a["size"] for a in artifacts.values()),
                "allowedHosts": hosts,
                "destination": "remote"
                if args.remote
                else "local"
                if args.local
                else "plan-only",
            },
            indent=2,
        ),
        flush=True,
    )
    if not (args.local or args.remote):
        return
    target = "--remote" if args.remote else "--local"
    cwd = ROOT / "apps/api"
    env = dict(os.environ)
    env.setdefault(
        "WRANGLER_LOG_PATH", str(ROOT / "node_modules/.cache/wrangler-import.log")
    )
    env["CLOUDFLARE_SEND_METRICS"] = "false"

    def run(arguments):
        if args.persist_to:
            arguments = [*arguments, "--persist-to", str(args.persist_to.resolve())]
        subprocess.run(
            ["pnpm", "exec", "wrangler", *arguments], cwd=cwd, env=env, check=True
        )

    # Objects are immutable, content-addressed and private. Only after every
    # upload succeeds is the metadata/pointer made visible to authenticated API.
    for digest, artifact in artifacts.items():
        run(
            [
                "r2",
                "object",
                "put",
                "karuyomi-private/artifacts/" + digest,
                target,
                "--file",
                str(args.artifacts / digest),
                "--content-type",
                artifact.get("contentType", "application/octet-stream"),
            ]
        )
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".sql", prefix="karuyomi-register-", delete=False
    ) as stream:
        stream.write(sql)
        sql_path = Path(stream.name)
    try:
        run(["d1", "execute", "DB", target, "--file", str(sql_path), "--yes"])
    finally:
        sql_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
