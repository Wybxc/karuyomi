#!/usr/bin/env python3
"""Compile the DTO boundary against original ABI JARs, then run its JVM oracle."""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]
MATERIALS = ROOT / 'runtime/teavm/.local/materials/public/runtime'
OUT = ROOT / 'runtime/teavm/.local/dto-test'
OUT.mkdir(parents=True, exist_ok=True)
CLASSPATH = os.pathsep.join(str(p) for p in sorted(MATERIALS.glob('*.jar')))
if not CLASSPATH:
    raise SystemExit('Import frozen materials first using scripts/import-teavm.py')
subprocess.run(['javac', '--release', '17', '-cp', CLASSPATH, '-d', str(OUT),
    str(ROOT / 'runtime/teavm/java/src/main/java/prototype/HostDto.java'),
    str(ROOT / 'tools/teavm/HostDtoTest.java')], check=True)
subprocess.run(['java', '-cp', str(OUT) + os.pathsep + CLASSPATH,
    'prototype.HostDtoTest'], check=True)
