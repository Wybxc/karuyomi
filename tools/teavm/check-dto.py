#!/usr/bin/env python3
"""Run DTO and bounded HTTP body JVM oracles against original ABI JARs."""

from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MATERIALS = ROOT / "runtime/teavm/.local/runtime-seed/public/runtime"
OUT = ROOT / "runtime/teavm/.local/dto-test"
OUT.mkdir(parents=True, exist_ok=True)
CLASSPATH = os.pathsep.join(str(p) for p in sorted(MATERIALS.glob("*.jar")))
if not CLASSPATH:
    raise SystemExit(
        "Prepare verified runtime materials using scripts/prepare-runtime.py"
    )
subprocess.run(
    [
        "javac",
        "--release",
        "17",
        "-cp",
        CLASSPATH,
        "-d",
        str(OUT),
        str(ROOT / "runtime/teavm/java/src/main/java/prototype/HostDto.java"),
        str(ROOT / "tools/teavm/HostDtoTest.java"),
        str(ROOT / "runtime/teavm/java/src/main/java/prototype/HttpBodySource.java"),
        str(ROOT / "runtime/teavm/java/src/main/java/prototype/HttpRequestSink.java"),
        str(ROOT / "tools/teavm/HttpBodyTest.java"),
    ],
    check=True,
)
subprocess.run(
    ["java", "-cp", str(OUT) + os.pathsep + CLASSPATH, "prototype.HostDtoTest"],
    check=True,
)
subprocess.run(
    ["java", "-cp", str(OUT) + os.pathsep + CLASSPATH, "prototype.HttpBodyTest"],
    check=True,
)
