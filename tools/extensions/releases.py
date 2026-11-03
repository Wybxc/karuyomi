"""GitHub private-release transport and resumable fixed-locator publication."""

from pathlib import Path
import gzip
import hashlib
import io
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
import zlib

from catalog import canonical, digest

MAX_ARTIFACT_BYTES = 64 * 1024 * 1024
MAX_ENCODED_BYTES = 65 * 1024 * 1024


def encode_artifact(sha256, data):
    """Encode canonical bytes without a timestamp, filename, or host OS header."""
    data = bytes_of(data)
    if not 0 < len(data) <= MAX_ARTIFACT_BYTES or digest(data) != sha256:
        raise ValueError("Invalid canonical artifact")
    stream = io.BytesIO()
    with gzip.GzipFile(
        filename="", mode="wb", fileobj=stream, compresslevel=9, mtime=0
    ) as archive:
        archive.write(data)
    encoded = stream.getvalue()
    entry = {
        "sha256": sha256,
        "size": len(data),
        "asset": sha256 + ".gz",
        "encoding": "gzip",
        "encodedSha256": digest(encoded),
        "encodedSize": len(encoded),
    }
    return encoded, entry


def restore_artifacts(directory, output, artifacts, bundle_sha, transfer=None):
    """Restore gzip bundle bytes with transport and canonical integrity checks."""
    directory, output = Path(directory), Path(output)
    if set(artifacts) != {bundle_sha}:
        raise ValueError("A release must contain exactly one private bundle")
    table_path = directory / "artifact-encodings.json"
    entries = {}
    if not table_path.is_file():
        raise ValueError("Release lacks its gzip encoding table")
    if table_path.exists():
        if table_path.stat().st_size > 64 * 1024:
            raise ValueError("Oversized artifact encoding table")
        table = json.loads(table_path.read_bytes())
        if (
            not isinstance(table, dict)
            or type(table.get("schemaVersion")) is not int
            or table["schemaVersion"] != 1
            or not isinstance(table.get("artifacts"), list)
        ):
            raise ValueError("Invalid artifact encoding table")
        for entry in table["artifacts"]:
            if not isinstance(entry, dict) or set(entry) != {
                "sha256",
                "size",
                "asset",
                "encoding",
                "encodedSha256",
                "encodedSize",
            }:
                raise ValueError("Invalid artifact encoding entry")
            sha256 = entry["sha256"]
            if sha256 != bundle_sha or sha256 not in artifacts or sha256 in entries:
                raise ValueError("Encoding must identify exactly the private bundle")
            if entry["asset"] != sha256 + ".gz" or entry["encoding"] != "gzip":
                raise ValueError("Invalid encoded asset reference")
            if not isinstance(entry["encodedSha256"], str) or not re.fullmatch(
                "[a-f0-9]{64}", entry["encodedSha256"]
            ):
                raise ValueError("Invalid encoded artifact hash")
            if (
                type(entry["size"]) is not int
                or entry["size"] != artifacts[sha256]["size"]
            ):
                raise ValueError("Canonical artifact size mismatch")
            if (
                type(entry["encodedSize"]) is not int
                or not 0 < entry["encodedSize"] <= MAX_ENCODED_BYTES
            ):
                raise ValueError("Invalid encoded artifact size")
            entries[sha256] = entry
        if set(entries) != {bundle_sha}:
            raise ValueError("Encoding table lacks the private bundle")
    output.mkdir(parents=True, exist_ok=True)
    for sha256, artifact in artifacts.items():
        size = artifact.get("size")
        if (
            not re.fullmatch("[a-f0-9]{64}", sha256)
            or type(size) is not int
            or not 0 < size <= MAX_ARTIFACT_BYTES
        ):
            raise ValueError("Invalid canonical artifact reference")
        entry = entries[sha256]
        file = directory / entry["asset"]
        if file.is_symlink() or file.stat().st_size != entry["encodedSize"]:
            raise ValueError("Downloaded artifact size mismatch")
        name = file.name
        data = transfer[name] if transfer is not None else file.read_bytes()
        actual = (
            transfer.metadata[name]["sha256"] if transfer is not None else digest(data)
        )
        if actual != entry["encodedSha256"]:
            raise ValueError("Encoded artifact integrity mismatch")
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            data = decoder.decompress(data, size + 1)
        except zlib.error:
            raise ValueError("Invalid gzip artifact") from None
        if len(data) > size or decoder.unconsumed_tail:
            raise ValueError("Decoded artifact exceeds canonical size")
        if not decoder.eof or decoder.unused_data:
            raise ValueError("Truncated or trailing gzip artifact")
        if len(data) != size or digest(data) != sha256:
            raise ValueError("Canonical artifact integrity mismatch")
        (output / sha256).write_bytes(data)
    return "gzip"


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        if urllib.parse.urlparse(new_url).scheme != "https":
            raise ValueError("Refusing insecure GitHub redirect")
        result = super().redirect_request(request, fp, code, message, headers, new_url)
        if (
            result is not None
            and urllib.parse.urlparse(request.full_url).netloc
            != urllib.parse.urlparse(new_url).netloc
        ):
            result.remove_header("Authorization")
            result.remove_header("Cookie")
        return result


class GitHub:
    def __init__(self, repository, token=None):
        import re

        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise ValueError("Invalid GitHub repository")
        self.repository = repository
        self.token = (
            token or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        )
        if not self.token:
            raise ValueError("GH_TOKEN is required for private release access")
        self.opener = urllib.request.build_opener(SafeRedirect())
        self._drafts = None

    def request(
        self,
        method,
        path,
        data=None,
        raw=False,
        content_type="application/json",
        missing=False,
    ):
        url = path if path.startswith("https:") else "https://api.github.com" + path
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.netloc not in {
            "api.github.com",
            "uploads.github.com",
        }:
            raise ValueError("Invalid GitHub API endpoint")
        body = (
            data
            if isinstance(data, bytes)
            else canonical(data)
            if data is not None
            else None
        )
        request = urllib.request.Request(
            url,
            data=body,
            method=method,
            headers={
                "Authorization": "Bearer " + self.token,
                "User-Agent": "karuyomi-extension-publisher",
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": content_type,
                "Accept": "application/octet-stream"
                if raw
                else "application/vnd.github+json",
            },
        )
        try:
            with self.opener.open(request, timeout=120) as response:
                content = response.read(128 * 1024 * 1024 + 1)
                if len(content) > 128 * 1024 * 1024:
                    raise ValueError("GitHub asset exceeds transport budget")
                return content if raw else json.loads(content) if content else None
        except urllib.error.HTTPError as error:
            if missing and error.code == 404:
                return None
            # Never print credentials, signed download query strings or bodies.
            raise RuntimeError(
                f"GitHub {method} {parsed.path}: HTTP {error.code}"
            ) from None
        except urllib.error.URLError:
            raise RuntimeError("GitHub transport unavailable") from None

    def find_release(self, tag):
        return self.request(
            "GET",
            f"/repos/{self.repository}/releases/tags/{urllib.parse.quote(tag, safe='')}",
            missing=True,
        )

    def latest(self):
        return self.request(
            "GET", f"/repos/{self.repository}/releases/latest", missing=True
        )

    def find_draft(self, tag):
        if self._drafts is None:
            self._drafts = {}
            page = 1
            while True:
                items = self.request(
                    "GET", f"/repos/{self.repository}/releases?per_page=100&page={page}"
                )
                self._drafts.update(
                    {item["tag_name"]: item for item in items if item.get("draft")}
                )
                if len(items) < 100:
                    break
                page += 1
        return self._drafts.get(tag)

    def create_release(self, tag, target):
        return self.request(
            "POST",
            f"/repos/{self.repository}/releases",
            {
                "tag_name": tag,
                "target_commitish": target,
                "name": tag,
                "draft": True,
                "make_latest": "false",
            },
        )

    def assets(self, release):
        values, page = [], 1
        while True:
            items = self.request(
                "GET",
                f"/repos/{self.repository}/releases/{release['id']}/assets?per_page=100&page={page}",
            )
            values.extend(items)
            if len(items) < 100:
                return values
            page += 1

    def upload(self, release, name, data):
        url = release["upload_url"].split("{", 1)[0]
        expected = f"/repos/{self.repository}/releases/{release['id']}/assets"
        if urllib.parse.urlparse(url).path != expected:
            raise ValueError("Unexpected release upload endpoint")
        return self.request(
            "POST",
            url + "?name=" + urllib.parse.quote(name, safe=""),
            data,
            content_type="application/octet-stream",
        )

    def download(self, asset):
        # Use the authenticated API URL, never a private browser_download_url.
        return self.request(
            "GET", f"/repos/{self.repository}/releases/assets/{asset['id']}", raw=True
        )

    def publish(self, release, latest=False):
        return self.request(
            "PATCH",
            f"/repos/{self.repository}/releases/{release['id']}",
            {
                "draft": False,
                "make_latest": "true" if latest else "false",
            },
        )

    def update_pointer(self, release, body, latest=False):
        return self.request(
            "PATCH",
            f"/repos/{self.repository}/releases/{release['id']}",
            {
                "name": release["tag_name"],
                "body": canonical({"karuyomiRelease": body}).decode(),
                "draft": False,
                "make_latest": "true" if latest else "false",
            },
        )

    def make_draft(self, release):
        return self.request(
            "PATCH",
            f"/repos/{self.repository}/releases/{release['id']}",
            {"draft": True},
        )

    def delete_asset(self, asset):
        self.request(
            "DELETE", f"/repos/{self.repository}/releases/assets/{asset['id']}"
        )


def bytes_of(value):
    return value.read_bytes() if isinstance(value, Path) else value


class TransferFiles(dict):
    """Owned transfer bytes and their once-computed integrity metadata.

    This receipt is process-local, never deserialized from build output JSON.
    """

    def __init__(self, files, known=None):
        super().__init__()
        self.metadata = {}
        self.reference = None
        for name, value in files.items():
            data = bytes_of(value)
            self[name] = data
            previous = (known or {}).get(name)
            if previous is not None and not isinstance(value, bytes):
                raise ValueError("Precomputed digests require owned bytes")
            self.metadata[name] = previous or {
                "sha256": digest(data),
                "size": len(data),
            }
            if self.metadata[name]["size"] != len(data):
                raise ValueError("Transfer receipt size mismatch")


def capture_files(files, known=None):
    return files if isinstance(files, TransferFiles) else TransferFiles(files, known)


def release_pointer(release):
    try:
        body = json.loads(release.get("body") or "null")
    except (TypeError, ValueError):
        return None
    pointer = body.get("karuyomiRelease") if isinstance(body, dict) else None
    if pointer is None:
        return None
    if (
        not isinstance(pointer, dict)
        or pointer.get("schemaVersion") != 2
        or not isinstance(pointer.get("generation"), str)
        or not re.fullmatch(r"[a-zA-Z0-9._-]{1,200}", pointer["generation"])
        or type(pointer.get("manifestAssetId")) is not int
        or pointer["manifestAssetId"] <= 0
        or not re.fullmatch(r"[a-f0-9]{64}", str(pointer.get("manifestSha256")))
    ):
        raise ValueError("Invalid release generation pointer")
    return pointer


def _check_asset(api, asset, expected, name):
    if asset["size"] != expected["size"]:
        raise ValueError("Release asset size conflict: " + name)
    actual = asset.get("digest")
    if actual is None:
        actual = "sha256:" + digest(api.download(asset))
    if actual != "sha256:" + expected["sha256"]:
        raise ValueError("Release asset hash conflict: " + name)


_UNSET = object()


def publish_locator(api, tag, generation, files, target, latest=False, expected=_UNSET):
    """Hide the locator as a draft, replace assets, then publish it last.

    Readers may temporarily find the locator unavailable during replacement.
    A single publisher is required: GitHub release updates have no CAS API.
    """
    if not re.fullmatch(r"[a-zA-Z0-9._-]{1,200}", generation):
        raise ValueError("Invalid release generation")
    files = capture_files(files)
    if "release-manifest.json" in files or any(
        not re.fullmatch(r"[a-zA-Z0-9._-]+", name) or name in {".", ".."}
        for name in files
    ):
        raise ValueError("Invalid release asset name")
    release = api.find_release(tag) or api.find_draft(tag)
    previous = release_pointer(release) if release else None
    if expected is not _UNSET and previous != expected:
        raise ValueError("Remote release advanced; pull its checkpoint first")
    if release and release.get("immutable"):
        raise ValueError("Fixed release locator requires a mutable release")
    if release is None:
        release = api.create_release(tag, target)
    manifest = (
        canonical(
            {
                "schemaVersion": 2,
                "tag": tag,
                "generation": generation,
                "files": files.metadata,
            }
        )
        + b"\n"
    )
    metadata = {"size": len(manifest), "sha256": digest(manifest)}
    wanted = {**files, "release-manifest.json": manifest}
    checks = {**files.metadata, "release-manifest.json": metadata}
    assets = {asset["name"]: asset for asset in api.assets(release)}
    same = set(assets) == set(wanted) and all(
        assets[name]["size"] == checks[name]["size"]
        and assets[name].get("digest") == "sha256:" + checks[name]["sha256"]
        for name in wanted
    )
    if not same:
        if not release.get("draft"):
            release = api.make_draft(release)
        # Remove the old commit marker before changing any of its data assets.
        if "release-manifest.json" in assets:
            api.delete_asset(assets.pop("release-manifest.json"))
        for name, asset in list(assets.items()):
            if (
                name not in wanted
                or asset["size"] != checks[name]["size"]
                or asset.get("digest") != "sha256:" + checks[name]["sha256"]
            ):
                api.delete_asset(asset)
                del assets[name]
        for name, data in wanted.items():
            asset = assets.get(name) or api.upload(release, name, data)
            _check_asset(api, asset, checks[name], name)
            assets[name] = asset
    pointer = {
        "schemaVersion": 2,
        "generation": generation,
        "manifestAssetId": assets["release-manifest.json"]["id"],
        "manifestSha256": metadata["sha256"],
    }
    if previous != pointer or release.get("draft") or latest:
        release = api.update_pointer(release, pointer, latest=latest)
    return {
        "tag": tag,
        "url": release.get("html_url"),
        "releaseManifestSha256": metadata["sha256"],
        "snapshot": pointer,
    }


def download_release(api, tag, directory, generation=None):
    release = api.find_release(tag)
    if not release or release.get("draft"):
        return False
    pointer = release_pointer(release)
    if pointer is None:
        raise ValueError("Release lacks current-format pointer: " + tag)
    if generation is not None and pointer["generation"] != generation:
        return False
    assets = {asset["name"]: asset for asset in api.assets(release)}
    asset = assets.get("release-manifest.json")
    if asset is None or asset["id"] != pointer["manifestAssetId"]:
        raise ValueError("Release generation manifest is missing")
    manifest_bytes = api.download(asset)
    if digest(manifest_bytes) != pointer["manifestSha256"]:
        raise ValueError("Downloaded release manifest integrity mismatch")
    manifest = json.loads(manifest_bytes)
    if (
        manifest.get("schemaVersion") != 2
        or manifest.get("tag") != tag
        or manifest.get("generation") != pointer["generation"]
        or not isinstance(manifest.get("files"), dict)
        or set(assets) != set(manifest["files"]) | {"release-manifest.json"}
    ):
        raise ValueError("Release manifest mismatch: " + tag)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    received, metadata = {}, {}
    for name, item in manifest["files"].items():
        if not re.fullmatch(r"[a-zA-Z0-9._-]+", name) or name in {".", ".."}:
            raise ValueError("Unsafe asset name")
        data = api.download(assets[name])
        if len(data) != item["size"] or digest(data) != item["sha256"]:
            raise ValueError("Downloaded asset integrity mismatch: " + name)
        (directory / name).write_bytes(data)
        received[name], metadata[name] = data, item
    (directory / "release-manifest.json").write_bytes(manifest_bytes)
    result = TransferFiles(received, metadata)
    result.reference = {
        "tag": tag,
        "url": release.get("html_url"),
        "releaseManifestSha256": pointer["manifestSha256"],
        "snapshot": pointer,
    }
    return result
