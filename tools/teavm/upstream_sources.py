"""Materialize patched TeaVM sources from the pinned official submodule."""

from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = Path("org/teavm/classlib/java/util/regex")
# Original and patched hashes make upstream drift and patch errors explicit.
PATCHES = (
    (
        "EOLSet",
        "6c40371df9454227b872cc386874854989a41e89595877fb4742e5a570d66faa",
        "58a2688d5e706bd890644a4513413f1173d8125f7bca3017f21f1ed30bb7c820",
    ),
    (
        "GroupQuantifierSet",
        "01a699d1da43f3c4d5fd74433875587a7f5a53b79e52dad98c69c49bf7431146",
        "e2785963cea67aa94a25b30864e05065a2b9d29f793cb41c2402f7bf6b2631d1",
    ),
    (
        "Lexer",
        "dd8e7d9b348d7105ab6610a8841a86df64ebaea6f96c2f68a38aa6596786b3fb",
        "c90603dcd79b4fbe412eaf14e5ae742e3c0c73fc732d3bda425f5770af471f19",
    ),
    (
        "MultiLineEOLSet",
        "6dc1c597aec8f8b7a722ed1c0c1fd93f17888ece3164cf7f140b8ce827751586",
        "9017c402c19377e55ebabf4ff0c456d50c74f6e370e3cb334a41ed20006a99a7",
    ),
    (
        "Pattern",
        "46eb9166122bf1c0a556c25c6ae8cd97843171768038621782fef52e458babdd",
        "2d5cc9466df9d1d4134682042942aee52023e72d26953ecb0420a50bae1c6265",
    ),
    (
        "RelCompositeGroupQuantifierSet",
        "bf053d520b0da42bd7aae24598067c084f6e3ee4a4c784f6f9f54ac7bf7d815c",
        "c8c6630900966adf9fc16ee2cab5ae19fd77e32e1daf91500fb8fa6b78445c88",
    ),
    (
        "ReluctantGroupQuantifierSet",
        "1b612b91e811e28da25896c5301292e06e5904807a3368ce12b0e661e27888c5",
        "012ad5d10fc09a50fccad0aa35ac47a9c74efbe21f3f11ca2d83fcc7e1ba2c07",
    ),
    (
        "SOLSet",
        "27b3b1f9c64a86526c9ec22e9604a41e24f44533086777008793ec13e94d5965",
        "480264af7325fa12795b3e044dbe72dd287f90f1e6b389b8443f37410ebf18de",
    ),
    (
        "UCISequenceSet",
        "60226fd1c877473844eb13a854a9748dbaecf768056b6cea8631ad034cb2827e",
        "cd8784789436e7881b2e85b92992dd69237d0307de0a5892903311709b8074e3",
    ),
    (
        "UEOLSet",
        "8ef8231c9202ca760f3c4af81b85fe6cf33fafbd74e6c10092cff47e0693639f",
        "d933d7c4cd17c5c13ccd7206dab46645af0b7ce8593040a53b1c68e8fdb447a3",
    ),
    (
        "UMultiLineEOLSet",
        "7add9b179bbda77cf875d7e941fcc4dc562253f456bc56d361b309ca5d743c3c",
        "68cd652da6a65b60762970dfab46952bca7405a15ef1c221b249198c9c976353",
    ),
    (
        "UnicodeCategory",
        "174b21f2fd3c657e77c1e57c41b23f9182ba70b619e1c8f62275438410f03f38",
        "e25f9bce5a29de4d6009c888ea4ce65c61f7d3008fd25b8411ab2b567316e9b3",
    ),
    (
        "UnicodeCategoryScope",
        "ec112071452cc726806d1862f3f4aa87adb53ea1d1e4165961877a8fa4e5f2eb",
        "b3dbff9f2d565b5487eddfbfaef531d5920fb4330335d834948da53a18672e9e",
    ),
)


def apply_patch(original, patch):
    """Apply one unified diff exactly, without offsets or fuzzy matching."""
    source = original.splitlines(keepends=True)
    lines = patch.splitlines(keepends=True)
    if (
        len(lines) < 3
        or not lines[0].startswith("--- ")
        or not lines[1].startswith("+++ ")
    ):
        raise ValueError("Expected a single-file unified diff")
    result = []
    cursor = 0
    index = 2
    while index < len(lines):
        match = re.fullmatch(
            r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@[^\n]*\n", lines[index]
        )
        if not match:
            raise ValueError("Invalid patch hunk")
        old_start, old_count, new_start, new_count = (
            int(match[1]),
            int(match[2] or 1),
            int(match[3]),
            int(match[4] or 1),
        )
        start = old_start - 1 if old_count else old_start
        if start < cursor or start > len(source):
            raise ValueError("Overlapping or invalid patch range")
        result.extend(source[cursor:start])
        cursor = start
        if len(result) != (new_start - 1 if new_count else new_start):
            raise ValueError("Invalid patch output position")
        consumed = produced = 0
        index += 1
        while index < len(lines) and not lines[index].startswith("@@ "):
            line = lines[index]
            if not line or line[0] not in " +-":
                raise ValueError("Unsupported patch line")
            operation, value = line[0], line[1:]
            if operation in " -":
                if cursor >= len(source) or source[cursor] != value:
                    raise ValueError("Patch context differs from pinned upstream")
                cursor += 1
                consumed += 1
            if operation in " +":
                result.append(value)
                produced += 1
            index += 1
        if consumed != old_count or produced != new_count:
            raise ValueError("Patch hunk length differs from header")
    result.extend(source[cursor:])
    return "".join(result)


def prepare_sources(destination, *, root=ROOT):
    """Write generated adapters inside a disposable build source directory."""
    root = Path(root)
    upstream = root / "vendor/teavm/classlib/src/main/java" / PACKAGE
    patches = root / "runtime/teavm/patches/teavm"
    destination = Path(destination) / PACKAGE
    generated = []
    for name, source_hash, output_hash in PATCHES:
        source = upstream / ("T" + name + ".java")
        if not source.exists():
            raise ValueError(
                "TeaVM sources missing; run git submodule update --init vendor/teavm"
            )
        data = source.read_bytes()
        if hashlib.sha256(data).hexdigest() != source_hash:
            raise ValueError("Pinned TeaVM source differs: " + str(source))
        patched = apply_patch(
            data.decode(), (patches / (name + ".patch")).read_text()
        ).encode()
        if hashlib.sha256(patched).hexdigest() != output_hash:
            raise ValueError("Patched TeaVM source differs: " + name)
        destination.mkdir(parents=True, exist_ok=True)
        output = destination / ("Patched" + name + ".java")
        output.write_bytes(patched)
        generated.append(output)
    return generated
