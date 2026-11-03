"""Bounded, deterministic extension bundle transport for Static Assets."""

from pathlib import Path
import gzip
import io
import json
import urllib.parse
import urllib.request
import zlib

from catalog import digest

MAX_RAW = 64 * 1024 * 1024
MAX_ENCODED = 25 * 1024 * 1024
MAX_METADATA = 32 * 1024 * 1024


def encode_bundle(data, content_type="text/javascript"):
    data = bytes(data)
    if not 0 < len(data) <= MAX_RAW:
        raise ValueError("Invalid canonical bundle size")
    stream = io.BytesIO()
    with gzip.GzipFile(
        filename="", mode="wb", fileobj=stream, compresslevel=9, mtime=0
    ) as archive:
        archive.write(data)
    encoded = stream.getvalue()
    if len(encoded) > MAX_ENCODED:
        raise ValueError("Encoded bundle exceeds Static Assets 25 MiB limit")
    sha = digest(data)
    return encoded, {
        "path": "/extensions/artifacts/" + sha + ".gz",
        "sha256": sha,
        "size": len(data),
        "contentType": content_type,
        "encoding": "gzip",
        "encodedSha256": digest(encoded),
        "encodedSize": len(encoded),
    }


def decode_bundle(encoded, reference):
    """Check each transferred byte domain once; reject concatenated gzip members."""
    size, encoded_size = reference.get("size"), reference.get("encodedSize")
    if (
        type(size) is not int
        or not 0 < size <= MAX_RAW
        or type(encoded_size) is not int
        or not 0 < encoded_size <= MAX_ENCODED
    ):
        raise ValueError("Invalid bundle size")
    if len(encoded) != encoded_size or digest(encoded) != reference.get(
        "encodedSha256"
    ):
        raise ValueError("Encoded bundle integrity mismatch")
    decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        raw = decoder.decompress(encoded, size + 1)
    except zlib.error:
        raise ValueError("Invalid gzip bundle") from None
    if len(raw) > size or decoder.unconsumed_tail:
        raise ValueError("Decoded bundle exceeds canonical size")
    if not decoder.eof or decoder.unused_data:
        raise ValueError("Truncated or trailing gzip bundle")
    if len(raw) != size or digest(raw) != reference.get("sha256"):
        raise ValueError("Canonical bundle integrity mismatch")
    return raw


def origin_url(origin, path):
    parsed = urllib.parse.urlsplit(origin)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise ValueError("Static origin must be an HTTPS origin")
    if (
        not path.startswith("/extensions/")
        or ".." in Path(path).parts
        or "?" in path
        or "#" in path
    ):
        raise ValueError("Invalid static extension path")
    return origin.rstrip("/") + path


def fetch_bytes(origin, path, maximum=MAX_METADATA):
    request = urllib.request.Request(
        origin_url(origin, path), headers={"Accept-Encoding": "identity"}
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.headers.get("Content-Encoding", "identity").lower() != "identity":
            raise ValueError("Static transport must expose the declared gzip bytes")
        data = response.read(maximum + 1)
    if len(data) > maximum:
        raise ValueError("Oversized static response")
    return data


def fetch_json(origin, path):
    return json.loads(fetch_bytes(origin, path))
