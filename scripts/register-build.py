#!/usr/bin/env python3
"""Verify a static build and register only its explicit Source network policy.

Static Assets is the sole distribution authority. Remote registration checks the
deployed index; local probes require an explicit controlled static snapshot.
"""

from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import urllib.request
import urllib.parse
import zlib

ROOT = Path(__file__).resolve().parents[1]


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def material_catalog():
    # Metadata comes from the pinned host sources and locked npm packages, never
    # from the build being registered. --print does not read WASM or private seed.
    return json.loads(
        subprocess.check_output(
            [
                "node",
                str(ROOT / "packages/runtime-host/prepare-materials.ts"),
                "--print",
            ],
            cwd=ROOT,
            text=True,
        )
    )


def verify_metadata(manifest, *, material_catalog_override=None):
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
    if type(manifest.get("bridgeVersion")) is not int or manifest["bridgeVersion"] != 2:
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
        bundle = artifact.get("path") == "/extensions/artifacts/" + digest + ".gz"
        shared = artifact.get("path") == "/runtime/materials/" + digest
        if (
            not re.fullmatch("[a-f0-9]{64}", digest)
            or not (bundle or shared)
            or (index == 0 and not bundle)
        ):
            raise ValueError("Invalid artifact reference")
        if index > 0 and not shared:
            raise ValueError(
                "Host scripts and resources must use shared runtime materials"
            )
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
                catalog = (
                    material_catalog_override
                    if material_catalog_override is not None
                    else material_catalog()
                )
            role = (
                "hostScripts" if index <= len(manifest["hostScripts"]) else "resources"
            )
            candidates = catalog[role]
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
            if any(
                key in artifact for key in ("encoding", "encodedSha256", "encodedSize")
            ):
                raise ValueError("Shared runtime materials must be unencoded")
            # Only the bundle is transferred; shared materials belong to the host.
            continue
        if (
            artifact.get("contentType")
            not in ("application/javascript", "text/javascript")
            or artifact.get("encoding") != "gzip"
            or not isinstance(artifact.get("encodedSha256"), str)
            or not re.fullmatch("[a-f0-9]{64}", artifact["encodedSha256"])
            or type(artifact.get("encodedSize")) is not int
            or not 0 < artifact["encodedSize"] <= 25 * 1024 * 1024
        ):
            raise ValueError("Invalid gzip bundle metadata")
        result[digest] = artifact
    if sum(artifact["size"] for artifact in artifacts) > 96 * 1024 * 1024:
        raise ValueError("Build exceeds runtime budget")
    return result


def verify(manifest, folder, *, verify_hashes=True, material_catalog_override=None):
    artifacts = verify_metadata(
        manifest, material_catalog_override=material_catalog_override
    )
    for digest, artifact in artifacts.items():
        file = folder / (digest + ".gz")
        if file.is_symlink() or not file.is_file():
            raise ValueError("Bundle must be a regular gzip file")
        if file.stat().st_size != artifact["encodedSize"]:
            raise ValueError("Encoded bundle size mismatch")
        if verify_hashes:
            verify_gzip(file, artifact)
    return artifacts


def verify_gzip(file, artifact):
    """One transfer read; at most 64KiB decompressed bytes per iteration."""
    encoded_hash = hashlib.sha256()
    raw_hash = hashlib.sha256()
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    encoded_size = raw_size = 0
    try:
        with file.open("rb") as stream:
            while chunk := stream.read(65536):
                encoded_size += len(chunk)
                if encoded_size > artifact["encodedSize"]:
                    raise ValueError("Encoded bundle size mismatch")
                encoded_hash.update(chunk)
                if decoder.eof:
                    raise ValueError("Trailing gzip data")
                pending = chunk
                while pending:
                    raw = decoder.decompress(pending, 65536)
                    pending = decoder.unconsumed_tail
                    raw_size += len(raw)
                    if raw_size > artifact["size"]:
                        raise ValueError("Bundle exceeds canonical size")
                    raw_hash.update(raw)
                    if decoder.unused_data:
                        raise ValueError("Trailing gzip data")
        if not decoder.eof:
            raise ValueError("Truncated gzip bundle")
    except zlib.error as error:
        raise ValueError("Invalid gzip bundle") from error
    if encoded_size != artifact["encodedSize"] or raw_size != artifact["size"]:
        raise ValueError("Bundle size mismatch")
    if encoded_hash.hexdigest() != artifact["encodedSha256"]:
        raise ValueError("Encoded bundle integrity mismatch")
    if raw_hash.hexdigest() != artifact["sha256"]:
        raise ValueError("Canonical bundle integrity mismatch")


def registration_sql(manifest, artifacts, hosts, *, current_build_ids=None):
    # No distribution bytes or manifests live in D1. The deployed current index
    # has already been checked before generating this policy transaction.
    build_id = quote(manifest["buildId"])
    package = quote(manifest["packageName"])
    hosts_json = quote(json.dumps(sorted(set(hosts)), separators=(",", ":")))
    digest = quote(manifest["bundle"]["sha256"])
    retire = ""
    if current_build_ids is not None:
        retire = (
            "DELETE FROM extension_builds WHERE build_id NOT IN ("
            + ",".join(quote(value) for value in sorted(current_build_ids))
            + ");\n"
        )
    return (
        retire
        + "DELETE FROM extension_builds WHERE package_name="
        + package
        + " AND build_id<>"
        + build_id
        + ";\n"
        + "INSERT INTO extension_builds (build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json) VALUES ("
        + ",".join((build_id, package, digest, "'verified'", "unixepoch()", hosts_json))
        + ") ON CONFLICT(build_id) DO UPDATE SET bundle_sha256=CASE WHEN "
        + "extension_builds.package_name=excluded.package_name AND "
        + "extension_builds.bundle_sha256=excluded.bundle_sha256 AND "
        + "json(extension_builds.allowed_hosts_json)=json(excluded.allowed_hosts_json) "
        + "THEN extension_builds.bundle_sha256 ELSE NULL END,status='verified';\n"
    )


def load_static_index(load):
    index = load("/extensions/index.json", 4 * 1024 * 1024)
    if (
        not isinstance(index, dict)
        or type(index.get("schemaVersion")) is not int
        or index["schemaVersion"] != 1
        or index.get("nextCursor") is not None
        or not isinstance(index.get("builds"), list)
        or len(index["builds"]) > 5000
    ):
        raise ValueError("Invalid static extension index")
    packages = set()
    builds = set()
    for item in index["builds"]:
        if (
            not isinstance(item, dict)
            or not isinstance(item.get("buildId"), str)
            or not re.fullmatch(r"[a-zA-Z0-9._-]{1,200}", item["buildId"])
        ):
            raise ValueError("Invalid static build identity")
        package = item.get("packageName")
        if (
            not isinstance(package, str)
            or not package
            or package in packages
            or item["buildId"] in builds
        ):
            raise ValueError(
                "Static index must contain only one current build per package"
            )
        packages.add(package)
        builds.add(item["buildId"])
        if (
            item.get("manifestPath")
            != "/extensions/builds/" + item["buildId"] + "/manifest.json"
        ):
            raise ValueError("Invalid static manifest path")
    return index


def verify_static_authority(manifest, load):
    index = load_static_index(load)
    current = next(
        (
            item
            for item in index["builds"]
            if item["packageName"] == manifest["packageName"]
        ),
        None,
    )
    if current is None or any(
        current.get(key) != manifest[key]
        for key in ("buildId", "packageName", "repoId", "version", "sourceIds")
    ):
        raise ValueError("Build is not current in the static index")
    deployed = load(current["manifestPath"], 1024 * 1024)
    if deployed != manifest:
        raise ValueError("Static manifest differs from supplied build")
    return {item["buildId"] for item in index["builds"]}


def snapshot_loader(root):
    root = root.resolve()

    def load(path, limit):
        file = root / path.lstrip("/")
        if file.is_symlink() or not file.resolve().is_relative_to(root):
            raise ValueError("Invalid static snapshot path")
        with file.open("rb") as stream:
            data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError("Static metadata exceeds limit")
        return json.loads(data)

    return load


def deployed_loader(origin):
    parsed = urllib.parse.urlsplit(origin)
    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.path
        or parsed.query
        or parsed.fragment
        or parsed.username
    ):
        raise ValueError("Static authority requires a configured HTTPS origin")

    def load(path, limit):
        url = origin + path
        request = urllib.request.Request(
            url, headers={"Cache-Control": "no-cache", "Accept": "application/json"}
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            # Static metadata paths must not redirect to a login or other origin.
            if response.url != url:
                raise ValueError("Static metadata redirected")
            data = response.read(limit + 1)
        if len(data) > limit:
            raise ValueError("Static metadata exceeds limit")
        return json.loads(data)

    return load


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
    parser.add_argument(
        "--static-root",
        type=Path,
        help="Controlled static snapshot (local probes only)",
    )
    args = parser.parse_args()
    if args.static_root and not args.local:
        parser.error("--static-root requires --local")
    if args.local and not args.static_root:
        parser.error("--local requires an explicit --static-root snapshot")
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
    current_build_ids = None
    if args.local:
        current_build_ids = verify_static_authority(
            manifest, snapshot_loader(args.static_root)
        )
    elif args.remote:
        configuration = (ROOT / "apps/api/wrangler.jsonc").read_text()
        origin = re.search(r'"APP_ORIGIN":\s*"([^"\n]+)"', configuration)
        if not origin:
            parser.error("APP_ORIGIN is missing")
        current_build_ids = verify_static_authority(
            manifest, deployed_loader(origin[1])
        )
    sql = registration_sql(
        manifest, artifacts, hosts, current_build_ids=current_build_ids
    )
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
